//
//  YggdrasilVPNApp.swift
//  YggdrasilVPN
//
//  Modern SwiftUI app for Yggdrasil mesh network
//

import SwiftUI

@main
struct YggdrasilVPNApp: App {
    @StateObject private var vpnManager = VPNManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vpnManager)
        }
    }
}
