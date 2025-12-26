# Yggdrasil VPN for iOS

A modern SwiftUI-based iOS app for connecting to the [Yggdrasil mesh network](https://yggdrasil-network.github.io/).

## Features

- Simple on/off toggle for VPN connection
- Display your Yggdrasil IPv6 address with one-tap copy
- Configure and manage peers list
- Select from known public peers or add custom peers
- Modern iOS 17+ SwiftUI interface
- Network Extension (VPN profile) architecture

## Requirements

- iOS 17.0 or later
- Xcode 15.0 or later
- Apple Developer account (for Network Extension entitlements)
- Yggdrasil.xcframework (built from yggdrasil-go)

## Project Structure

```
YggdrasilVPN/
├── YggdrasilVPN/                    # Main iOS app
│   ├── YggdrasilVPNApp.swift        # App entry point
│   ├── Views/
│   │   ├── ContentView.swift        # Main UI with toggle, status, peers
│   │   ├── AddPeerView.swift        # Add peer sheet
│   │   └── SettingsView.swift       # Settings and configuration
│   ├── Services/
│   │   └── VPNManager.swift         # VPN connection management
│   ├── Models/
│   │   └── YggdrasilConfiguration.swift
│   ├── Assets.xcassets/
│   ├── Info.plist
│   └── YggdrasilVPN.entitlements
├── YggdrasilNetworkExtension/       # Network Extension target
│   ├── PacketTunnelProvider.swift   # VPN tunnel implementation
│   ├── Info.plist
│   └── YggdrasilNetworkExtension.entitlements
└── YggdrasilVPN.xcodeproj/
```

## Setup Instructions

### 1. Build Yggdrasil Framework

```bash
# Install Go 1.22+ and gomobile
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init

# Clone and build yggdrasil-go
git clone https://github.com/yggdrasil-network/yggdrasil-go
cd yggdrasil-go
./build -i

# Copy the framework to the project
cp -r Yggdrasil.xcframework /path/to/YggdrasilVPN/
```

### 2. Configure Signing

1. Open `YggdrasilVPN.xcodeproj` in Xcode
2. Select the project in the navigator
3. For each target (YggdrasilVPN and YggdrasilNetworkExtension):
   - Set your Development Team
   - Ensure "Automatically manage signing" is enabled
4. Update the App Group identifier if needed in:
   - `YggdrasilVPN/YggdrasilVPN.entitlements`
   - `YggdrasilNetworkExtension/YggdrasilNetworkExtension.entitlements`
   - `YggdrasilVPN/Services/VPNManager.swift` (appGroup constant)
   - `YggdrasilNetworkExtension/PacketTunnelProvider.swift` (UserDefaults suite)

### 3. Add Yggdrasil Framework

1. Drag `Yggdrasil.xcframework` into the Xcode project
2. Add it to both targets (app and extension)
3. Ensure it's set to "Embed & Sign" for the app target

### 4. Build and Run

1. Select a physical iOS device (Network Extensions don't work in Simulator)
2. Build and run the app
3. The first connection will prompt for VPN permission

## Bundle Identifiers

- App: `ua.eliah.yggdrasil`
- Extension: `ua.eliah.yggdrasil.network-extension`
- App Group: `group.ua.eliah.yggdrasil`

## Entitlements Required

The app requires the following entitlements (already configured):

- `com.apple.developer.networking.networkextension` (packet-tunnel-provider)
- `com.apple.developer.networking.vpn.api` (allow-vpn)
- `com.apple.security.application-groups`
- `com.apple.developer.networking.multicast` (extension only)

## License

MIT License
