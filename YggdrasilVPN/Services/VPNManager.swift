//
//  VPNManager.swift
//  YggdrasilVPN
//
//  Manages VPN connection state and configuration
//

import Foundation
import NetworkExtension
import Combine

@MainActor
final class VPNManager: ObservableObject {
    static let shared = VPNManager()

    // MARK: - Published Properties

    @Published private(set) var status: NEVPNStatus = .disconnected
    @Published private(set) var ipv6Address: String?
    @Published private(set) var subnet: String?
    @Published private(set) var connectedPeersCount: Int = 0
    @Published private(set) var activePeers: [String] = []
    @Published private(set) var configuredPeers: [String] = []

    // MARK: - Private Properties

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var pollTimer: Timer?
    private let appGroup = "group.ua.eliah.yggdrasil"
    private let bundleIdentifier = "ua.eliah.yggdrasil.network-extension"

    // MARK: - Computed Properties

    var isConnected: Bool {
        status == .connected
    }

    var isTransitioning: Bool {
        status == .connecting || status == .disconnecting || status == .reasserting
    }

    var statusDescription: String {
        switch status {
        case .invalid:
            return "Invalid"
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .reasserting:
            return "Reconnecting..."
        case .disconnecting:
            return "Disconnecting..."
        @unknown default:
            return "Unknown"
        }
    }

    // MARK: - Initialization

    private init() {
        setupNotificationObserver()
    }

    deinit {
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        pollTimer?.invalidate()
    }

    // MARK: - Public Methods

    func loadConfiguration() {
        Task {
            await loadOrCreateManager()
            loadPeersFromStorage()
        }
    }

    func connect() async {
        guard let manager = manager else {
            await loadOrCreateManager()
            guard self.manager != nil else { return }
            await connect()
            return
        }

        do {
            // Save configuration before connecting
            try await saveConfiguration()

            // Start VPN tunnel
            try manager.connection.startVPNTunnel()
        } catch {
            print("Failed to start VPN: \(error)")
        }
    }

    func disconnect() async {
        manager?.connection.stopVPNTunnel()
    }

    func addPeer(_ peer: String) {
        guard !configuredPeers.contains(peer) else { return }
        configuredPeers.append(peer)
        savePeersToStorage()

        // Update VPN configuration if connected
        Task {
            try? await saveConfiguration()
        }
    }

    func removePeers(at offsets: IndexSet) {
        configuredPeers.remove(atOffsets: offsets)
        savePeersToStorage()

        Task {
            try? await saveConfiguration()
        }
    }

    func resetConfiguration() {
        configuredPeers.removeAll()
        savePeersToStorage()
        clearStatus()

        Task {
            try? await saveConfiguration()
        }
    }

    func exportConfiguration() -> Data? {
        let config = buildConfiguration()
        return try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
    }

    func importConfiguration(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let peers = json["Peers"] as? [String] else {
            return
        }

        configuredPeers = peers
        savePeersToStorage()

        Task {
            try? await saveConfiguration()
        }
    }

    // MARK: - Private Methods

    private func loadOrCreateManager() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()

            if let existing = managers.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == bundleIdentifier
            }) {
                self.manager = existing
            } else {
                self.manager = createNewManager()
                try await self.manager?.saveToPreferences()
                try await self.manager?.loadFromPreferences()
            }

            updateStatus()
        } catch {
            print("Failed to load VPN configuration: \(error)")
        }
    }

    private func createNewManager() -> NETunnelProviderManager {
        let manager = NETunnelProviderManager()

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = bundleIdentifier
        proto.serverAddress = "Yggdrasil"
        proto.providerConfiguration = [:]

        manager.protocolConfiguration = proto
        manager.localizedDescription = "Yggdrasil"
        manager.isEnabled = true

        return manager
    }

    private func saveConfiguration() async throws {
        guard let manager = manager else { return }

        let config = buildConfiguration()
        let jsonData = try JSONSerialization.data(withJSONObject: config)

        if let proto = manager.protocolConfiguration as? NETunnelProviderProtocol {
            proto.providerConfiguration = ["json": jsonData]
            manager.protocolConfiguration = proto
        }

        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
    }

    private func buildConfiguration() -> [String: Any] {
        var config: [String: Any] = [:]

        // Peers configuration
        config["Peers"] = configuredPeers

        // Interface configuration
        config["IfName"] = "tun0"

        // Listen configuration (empty for mobile)
        config["Listen"] = [String]()

        // Multicast configuration
        config["MulticastInterfaces"] = [String]()

        return config
    }

    private func setupNotificationObserver() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }

    private func updateStatus() {
        guard let connection = manager?.connection else {
            status = .disconnected
            return
        }

        status = connection.status

        if status == .connected {
            startPolling()
        } else {
            stopPolling()
            if status == .disconnected {
                clearStatus()
            }
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollStatus()
            }
        }
        // Initial poll
        Task {
            await pollStatus()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollStatus() async {
        guard let session = manager?.connection as? NETunnelProviderSession else { return }

        // Request address
        await sendIPCMessage("address", to: session) { [weak self] response in
            if let address = response as? String {
                Task { @MainActor in
                    self?.ipv6Address = address
                }
            }
        }

        // Request subnet
        await sendIPCMessage("subnet", to: session) { [weak self] response in
            if let subnet = response as? String {
                Task { @MainActor in
                    self?.subnet = subnet
                }
            }
        }

        // Request peers
        await sendIPCMessage("peers", to: session) { [weak self] response in
            if let peersData = response as? Data,
               let peers = try? JSONSerialization.jsonObject(with: peersData) as? [[String: Any]] {
                Task { @MainActor in
                    self?.connectedPeersCount = peers.count
                    self?.activePeers = peers.compactMap { $0["Remote"] as? String }
                }
            }
        }
    }

    private func sendIPCMessage(_ message: String, to session: NETunnelProviderSession, handler: @escaping (Any?) -> Void) async {
        do {
            try session.sendProviderMessage(message.data(using: .utf8)!) { response in
                handler(response)
            }
        } catch {
            print("IPC error: \(error)")
            handler(nil)
        }
    }

    private func clearStatus() {
        ipv6Address = nil
        subnet = nil
        connectedPeersCount = 0
        activePeers = []
    }

    // MARK: - Storage

    private var peersStorageKey: String { "configured_peers" }

    private func savePeersToStorage() {
        if let userDefaults = UserDefaults(suiteName: appGroup) {
            userDefaults.set(configuredPeers, forKey: peersStorageKey)
        } else {
            UserDefaults.standard.set(configuredPeers, forKey: peersStorageKey)
        }
    }

    private func loadPeersFromStorage() {
        let defaults = UserDefaults(suiteName: appGroup) ?? UserDefaults.standard
        configuredPeers = defaults.stringArray(forKey: peersStorageKey) ?? []
    }
}
