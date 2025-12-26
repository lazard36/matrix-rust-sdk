//
//  PacketTunnelProvider.swift
//  YggdrasilNetworkExtension
//
//  Yggdrasil packet tunnel provider for iOS VPN
//

import NetworkExtension
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {

    // MARK: - Properties

    private var yggdrasil: Yggdrasil?
    private let logger = Logger(subsystem: "ua.eliah.yggdrasil.network-extension", category: "tunnel")

    // MARK: - Tunnel Lifecycle

    override func startTunnel(options: [String : NSObject]? = nil) async throws {
        logger.info("Starting Yggdrasil tunnel")

        // Get configuration from protocol
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let providerConfig = proto.providerConfiguration,
              let jsonData = providerConfig["json"] as? Data else {
            logger.error("No configuration found")
            throw NEVPNError(.configurationInvalid)
        }

        // Parse configuration
        guard let config = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            logger.error("Failed to parse configuration JSON")
            throw NEVPNError(.configurationInvalid)
        }

        // Initialize Yggdrasil
        do {
            try await startYggdrasil(with: config)
            logger.info("Yggdrasil tunnel started successfully")
        } catch {
            logger.error("Failed to start Yggdrasil: \(error.localizedDescription)")
            throw error
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        logger.info("Stopping Yggdrasil tunnel with reason: \(String(describing: reason))")

        yggdrasil?.stop()
        yggdrasil = nil

        logger.info("Yggdrasil tunnel stopped")
    }

    // MARK: - Yggdrasil Management

    private func startYggdrasil(with config: [String: Any]) async throws {
        // Initialize Yggdrasil instance
        yggdrasil = Yggdrasil()

        // Generate or load configuration
        var yggConfig: String
        if let existingConfig = loadStoredConfiguration() {
            yggConfig = existingConfig
        } else {
            guard let generated = yggdrasil?.generateConfigJSON() else {
                throw NSError(domain: "YggdrasilError", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to generate configuration"
                ])
            }
            yggConfig = generated
            saveConfiguration(generated)
        }

        // Merge user configuration (peers, etc.)
        yggConfig = mergeConfiguration(base: yggConfig, overlay: config)

        // Start Yggdrasil
        guard let error = yggdrasil?.startJSON(yggConfig) else {
            throw NSError(domain: "YggdrasilError", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Unknown error starting Yggdrasil"
            ])
        }

        if !error.isEmpty {
            throw NSError(domain: "YggdrasilError", code: 3, userInfo: [
                NSLocalizedDescriptionKey: error
            ])
        }

        // Get network settings from Yggdrasil
        guard let address = yggdrasil?.getAddressString(),
              let subnet = yggdrasil?.getSubnetString(),
              let mtu = yggdrasil?.getMTU() else {
            throw NSError(domain: "YggdrasilError", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Failed to get network settings"
            ])
        }

        // Configure network settings
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "fd00::1")

        // IPv6 Settings
        let ipv6Settings = NEIPv6Settings(addresses: [address], networkPrefixLengths: [7])
        ipv6Settings.includedRoutes = [NEIPv6Route(destinationAddress: "0200::", networkPrefixLength: 7)]
        settings.ipv6Settings = ipv6Settings

        // MTU
        settings.mtu = NSNumber(value: mtu)

        // Apply settings
        try await setTunnelNetworkSettings(settings)

        // Start packet reading
        startPacketFlow()
    }

    private func mergeConfiguration(base: String, overlay: [String: Any]) -> String {
        guard var baseConfig = try? JSONSerialization.jsonObject(with: base.data(using: .utf8)!) as? [String: Any] else {
            return base
        }

        // Merge peers
        if let peers = overlay["Peers"] as? [String] {
            baseConfig["Peers"] = peers
        }

        // Merge other settings
        if let listen = overlay["Listen"] as? [String] {
            baseConfig["Listen"] = listen
        }

        if let multicast = overlay["MulticastInterfaces"] as? [[String: Any]] {
            baseConfig["MulticastInterfaces"] = multicast
        }

        guard let mergedData = try? JSONSerialization.data(withJSONObject: baseConfig),
              let mergedString = String(data: mergedData, encoding: .utf8) else {
            return base
        }

        return mergedString
    }

    // MARK: - Packet Flow

    private func startPacketFlow() {
        guard let yggdrasil = yggdrasil else { return }

        // Get file descriptor for TUN device
        guard let fd = getTunnelFileDescriptor() else {
            logger.error("Failed to get tunnel file descriptor")
            return
        }

        // Pass file descriptor to Yggdrasil
        yggdrasil.setTUN(fd)

        logger.info("Packet flow started with file descriptor: \(fd)")
    }

    private func getTunnelFileDescriptor() -> Int32? {
        var buf = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        var len = socklen_t(buf.count)

        for fd: Int32 in 0...1024 {
            var addr = sockaddr_ctl()
            var addrLen = socklen_t(MemoryLayout.size(ofValue: addr))

            if getpeername(fd, UnsafeMutableRawPointer(&addr).assumingMemoryBound(to: sockaddr.self), &addrLen) == 0 {
                if addr.sc_family == AF_SYSTEM {
                    if getsockopt(fd, SYSPROTO_CONTROL, 2, &buf, &len) == 0 {
                        let name = String(cString: buf)
                        if name == "com.apple.net.utun_control" {
                            return fd
                        }
                    }
                }
            }
        }

        return nil
    }

    // MARK: - IPC Message Handling

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        guard let message = String(data: messageData, encoding: .utf8) else {
            completionHandler?(nil)
            return
        }

        logger.debug("Received IPC message: \(message)")

        switch message {
        case "address":
            let address = yggdrasil?.getAddressString() ?? ""
            completionHandler?(address.data(using: .utf8))

        case "subnet":
            let subnet = yggdrasil?.getSubnetString() ?? ""
            completionHandler?(subnet.data(using: .utf8))

        case "coords":
            let coords = yggdrasil?.getCoordsString() ?? ""
            completionHandler?(coords.data(using: .utf8))

        case "peers":
            let peersJSON = yggdrasil?.getPeersJSON() ?? "[]"
            completionHandler?(peersJSON.data(using: .utf8))

        case "dht":
            let dhtJSON = yggdrasil?.getDHTJSON() ?? "[]"
            completionHandler?(dhtJSON.data(using: .utf8))

        case "self":
            let selfJSON = yggdrasil?.getSelfJSON() ?? "{}"
            completionHandler?(selfJSON.data(using: .utf8))

        default:
            completionHandler?(nil)
        }
    }

    // MARK: - Configuration Storage

    private var configurationKey: String { "yggdrasil_config" }

    private func loadStoredConfiguration() -> String? {
        let defaults = UserDefaults(suiteName: "group.ua.eliah.yggdrasil")
        return defaults?.string(forKey: configurationKey)
    }

    private func saveConfiguration(_ config: String) {
        let defaults = UserDefaults(suiteName: "group.ua.eliah.yggdrasil")
        defaults?.set(config, forKey: configurationKey)
    }

    // MARK: - Sleep/Wake

    override func sleep(completionHandler: @escaping () -> Void) {
        logger.info("System going to sleep")
        completionHandler()
    }

    override func wake() {
        logger.info("System waking up")
    }
}

// MARK: - Yggdrasil Protocol

/// Protocol for Yggdrasil framework interface
/// The actual implementation comes from Yggdrasil.xcframework
@objc protocol YggdrasilProtocol {
    func generateConfigJSON() -> String
    func startJSON(_ config: String) -> String
    func stop()
    func getAddressString() -> String
    func getSubnetString() -> String
    func getCoordsString() -> String
    func getMTU() -> Int
    func setTUN(_ fd: Int32)
    func getPeersJSON() -> String
    func getDHTJSON() -> String
    func getSelfJSON() -> String
}

/// Placeholder class for Yggdrasil - will be replaced by the actual framework
class Yggdrasil: NSObject {
    func generateConfigJSON() -> String? {
        // This is a placeholder - actual implementation from Yggdrasil.xcframework
        return "{\"Peers\":[]}"
    }

    func startJSON(_ config: String) -> String? {
        // Placeholder - returns empty string on success
        return ""
    }

    func stop() {
        // Placeholder
    }

    func getAddressString() -> String? {
        return nil
    }

    func getSubnetString() -> String? {
        return nil
    }

    func getCoordsString() -> String? {
        return nil
    }

    func getMTU() -> Int? {
        return 65535
    }

    func setTUN(_ fd: Int32) {
        // Placeholder
    }

    func getPeersJSON() -> String? {
        return "[]"
    }

    func getDHTJSON() -> String? {
        return "[]"
    }

    func getSelfJSON() -> String? {
        return "{}"
    }
}
