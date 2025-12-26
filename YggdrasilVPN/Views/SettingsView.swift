//
//  SettingsView.swift
//  YggdrasilVPN
//
//  Settings and configuration view
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vpnManager: VPNManager

    @AppStorage("autoConnect") private var autoConnect = false
    @AppStorage("connectOnWiFi") private var connectOnWiFi = true
    @AppStorage("connectOnCellular") private var connectOnCellular = false

    @State private var showingResetAlert = false
    @State private var showingExportSheet = false

    var body: some View {
        NavigationStack {
            List {
                // Auto-connect Section
                Section {
                    Toggle("Auto-connect on Launch", isOn: $autoConnect)

                    Toggle("Connect on WiFi", isOn: $connectOnWiFi)

                    Toggle("Connect on Cellular", isOn: $connectOnCellular)
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Configure automatic connection behavior.")
                }

                // Configuration Section
                Section {
                    NavigationLink {
                        ConfigurationEditorView()
                    } label: {
                        Label("Advanced Configuration", systemImage: "doc.text")
                    }

                    Button {
                        showingExportSheet = true
                    } label: {
                        Label("Export Configuration", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Configuration")
                }

                // Info Section
                Section {
                    LabeledContent("App Version", value: appVersion)
                    LabeledContent("Build", value: buildNumber)

                    Link(destination: URL(string: "https://yggdrasil-network.github.io/")!) {
                        Label("Yggdrasil Documentation", systemImage: "book")
                    }

                    Link(destination: URL(string: "https://github.com/yggdrasil-network/public-peers")!) {
                        Label("Public Peers List", systemImage: "globe")
                    }
                } header: {
                    Text("About")
                }

                // Danger Zone
                Section {
                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        Label("Reset Configuration", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Reset")
                } footer: {
                    Text("This will remove all peers and reset to default configuration.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Reset Configuration?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    vpnManager.resetConfiguration()
                }
            } message: {
                Text("This will remove all peers and reset the configuration to defaults. This cannot be undone.")
            }
            .sheet(isPresented: $showingExportSheet) {
                if let configData = vpnManager.exportConfiguration(),
                   let configString = String(data: configData, encoding: .utf8) {
                    ShareSheet(items: [configString])
                }
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - Configuration Editor View

struct ConfigurationEditorView: View {
    @EnvironmentObject var vpnManager: VPNManager
    @State private var configText: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var hasChanges = false

    var body: some View {
        VStack {
            TextEditor(text: $configText)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: configText) { _, _ in
                    hasChanges = true
                }
        }
        .padding()
        .navigationTitle("Configuration")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveConfiguration()
                }
                .disabled(!hasChanges)
            }
        }
        .onAppear {
            loadConfiguration()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    private func loadConfiguration() {
        if let data = vpnManager.exportConfiguration(),
           let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            configText = prettyString
        } else {
            configText = "{}"
        }
        hasChanges = false
    }

    private func saveConfiguration() {
        guard let data = configText.data(using: .utf8) else {
            errorMessage = "Invalid text encoding"
            showingError = true
            return
        }

        do {
            // Validate JSON
            _ = try JSONSerialization.jsonObject(with: data)
            vpnManager.importConfiguration(data)
            hasChanges = false
        } catch {
            errorMessage = "Invalid JSON: \(error.localizedDescription)"
            showingError = true
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SettingsView()
        .environmentObject(VPNManager.shared)
}
