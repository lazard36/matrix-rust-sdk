//
//  AddPeerView.swift
//  YggdrasilVPN
//
//  View for adding new peers to the configuration
//

import SwiftUI

struct AddPeerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vpnManager: VPNManager

    @State private var peerURI: String = ""
    @State private var selectedProtocol: PeerProtocol = .tls
    @State private var host: String = ""
    @State private var port: String = "443"
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var useManualEntry = false

    enum PeerProtocol: String, CaseIterable {
        case tls = "tls"
        case tcp = "tcp"
        case quic = "quic"

        var defaultPort: String {
            switch self {
            case .tls, .tcp: return "443"
            case .quic: return "443"
            }
        }
    }

    var constructedURI: String {
        guard !host.isEmpty else { return "" }
        let portString = port.isEmpty ? selectedProtocol.defaultPort : port
        return "\(selectedProtocol.rawValue)://\(host):\(portString)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Entry Mode", selection: $useManualEntry) {
                        Text("Paste URI").tag(false)
                        Text("Manual Entry").tag(true)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Mode")
                }

                if useManualEntry {
                    Section {
                        Picker("Protocol", selection: $selectedProtocol) {
                            ForEach(PeerProtocol.allCases, id: \.self) { proto in
                                Text(proto.rawValue.uppercased()).tag(proto)
                            }
                        }

                        TextField("Host (e.g., peer.example.com)", text: $host)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)

                        TextField("Port", text: $port)
                            .keyboardType(.numberPad)
                    } header: {
                        Text("Peer Details")
                    } footer: {
                        if !constructedURI.isEmpty {
                            Text("URI: \(constructedURI)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        TextField("tls://peer.example.com:443", text: $peerURI)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    } header: {
                        Text("Peer URI")
                    } footer: {
                        Text("Enter a peer URI in the format: protocol://host:port")
                    }
                }

                Section {
                    PublicPeersView(onSelect: { uri in
                        peerURI = uri
                        useManualEntry = false
                    })
                } header: {
                    Text("Public Peers")
                } footer: {
                    Text("Select from known public peers or enter a custom peer above.")
                }
            }
            .navigationTitle("Add Peer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addPeer()
                    }
                    .disabled(useManualEntry ? host.isEmpty : peerURI.isEmpty)
                }
            }
            .alert("Invalid Peer", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func addPeer() {
        let uri = useManualEntry ? constructedURI : peerURI.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !uri.isEmpty else {
            errorMessage = "Please enter a peer URI."
            showingError = true
            return
        }

        // Basic validation
        let validPrefixes = ["tls://", "tcp://", "quic://"]
        guard validPrefixes.contains(where: { uri.lowercased().hasPrefix($0) }) else {
            errorMessage = "Peer URI must start with tls://, tcp://, or quic://"
            showingError = true
            return
        }

        // Check for duplicates
        if vpnManager.configuredPeers.contains(uri) {
            errorMessage = "This peer is already configured."
            showingError = true
            return
        }

        vpnManager.addPeer(uri)
        dismiss()
    }
}

// MARK: - Public Peers View

struct PublicPeersView: View {
    let onSelect: (String) -> Void

    // Common public peers - users can update these
    let publicPeers: [(region: String, peers: [String])] = [
        ("Europe", [
            "tls://ygg.mkg20001.io:443",
            "tls://vpn.ltha.de:443",
            "tls://ygg.yt:443"
        ]),
        ("North America", [
            "tls://ygg-ny.incognet.io:443",
            "tls://ygg.leftist.network:443"
        ]),
        ("Asia-Pacific", [
            "tls://ygg.ap.nym.re:443"
        ])
    ]

    var body: some View {
        ForEach(publicPeers, id: \.region) { region in
            DisclosureGroup(region.region) {
                ForEach(region.peers, id: \.self) { peer in
                    Button {
                        onSelect(peer)
                    } label: {
                        Text(peer)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }
}

#Preview {
    AddPeerView()
        .environmentObject(VPNManager.shared)
}
