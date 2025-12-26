//
//  ContentView.swift
//  YggdrasilVPN
//
//  Main content view with VPN toggle, IPv6 display, and peers configuration
//

import SwiftUI
import NetworkExtension

struct ContentView: View {
    @EnvironmentObject var vpnManager: VPNManager
    @State private var showingAddPeer = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                // Connection Section
                Section {
                    VPNToggleView()
                } header: {
                    Text("Connection")
                }

                // Status Section
                Section {
                    StatusInfoView()
                } header: {
                    Text("Status")
                }

                // Peers Section
                Section {
                    PeersListView(showingAddPeer: $showingAddPeer)
                } header: {
                    Text("Peers")
                } footer: {
                    Text("Add peers to connect to the Yggdrasil network. At least one peer is required.")
                }
            }
            .navigationTitle("Yggdrasil")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingAddPeer) {
                AddPeerView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .onAppear {
                vpnManager.loadConfiguration()
            }
        }
    }
}

// MARK: - VPN Toggle View

struct VPNToggleView: View {
    @EnvironmentObject var vpnManager: VPNManager

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("VPN")
                    .font(.headline)
                Text(vpnManager.statusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { vpnManager.isConnected },
                set: { newValue in
                    Task {
                        if newValue {
                            await vpnManager.connect()
                        } else {
                            await vpnManager.disconnect()
                        }
                    }
                }
            ))
            .labelsHidden()
            .disabled(vpnManager.isTransitioning)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Status Info View

struct StatusInfoView: View {
    @EnvironmentObject var vpnManager: VPNManager
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // IPv6 Address
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("IPv6 Address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(vpnManager.ipv6Address ?? "Not connected")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(vpnManager.ipv6Address != nil ? .primary : .secondary)
                }

                Spacer()

                if let address = vpnManager.ipv6Address {
                    Button {
                        UIPasteboard.general.string = address
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(copied ? .green : .accentColor)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Divider()

            // Subnet
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Subnet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(vpnManager.subnet ?? "—")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(vpnManager.subnet != nil ? .primary : .secondary)
                }
                Spacer()
            }

            Divider()

            // Connected Peers Count
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected Peers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(vpnManager.connectedPeersCount)")
                        .font(.body)
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Peers List View

struct PeersListView: View {
    @EnvironmentObject var vpnManager: VPNManager
    @Binding var showingAddPeer: Bool

    var body: some View {
        ForEach(vpnManager.configuredPeers, id: \.self) { peer in
            PeerRowView(peer: peer)
        }
        .onDelete { indexSet in
            vpnManager.removePeers(at: indexSet)
        }

        Button {
            showingAddPeer = true
        } label: {
            Label("Add Peer", systemImage: "plus.circle.fill")
        }
    }
}

struct PeerRowView: View {
    let peer: String
    @EnvironmentObject var vpnManager: VPNManager

    var isConnected: Bool {
        vpnManager.activePeers.contains { $0.contains(peerHost) }
    }

    var peerHost: String {
        // Extract host from URI like tls://host:port or tcp://host:port
        let withoutScheme = peer.replacingOccurrences(of: "tls://", with: "")
            .replacingOccurrences(of: "tcp://", with: "")
            .replacingOccurrences(of: "quic://", with: "")
        return withoutScheme.components(separatedBy: ":").first ?? peer
    }

    var body: some View {
        HStack {
            Circle()
                .fill(isConnected ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)

            Text(peer)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(VPNManager.shared)
}
