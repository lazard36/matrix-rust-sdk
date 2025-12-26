//
//  YggdrasilConfiguration.swift
//  YggdrasilVPN
//
//  Yggdrasil configuration model
//

import Foundation

/// Represents the Yggdrasil configuration
struct YggdrasilConfiguration: Codable {
    var peers: [String]
    var listen: [String]
    var adminListen: String?
    var multicastInterfaces: [MulticastInterface]
    var allowedPublicKeys: [String]
    var ifName: String
    var ifMTU: Int
    var nodeInfo: [String: String]?
    var nodeInfoPrivacy: Bool

    enum CodingKeys: String, CodingKey {
        case peers = "Peers"
        case listen = "Listen"
        case adminListen = "AdminListen"
        case multicastInterfaces = "MulticastInterfaces"
        case allowedPublicKeys = "AllowedPublicKeys"
        case ifName = "IfName"
        case ifMTU = "IfMTU"
        case nodeInfo = "NodeInfo"
        case nodeInfoPrivacy = "NodeInfoPrivacy"
    }

    init() {
        peers = []
        listen = []
        adminListen = nil
        multicastInterfaces = []
        allowedPublicKeys = []
        ifName = "tun0"
        ifMTU = 65535
        nodeInfo = nil
        nodeInfoPrivacy = false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        peers = try container.decodeIfPresent([String].self, forKey: .peers) ?? []
        listen = try container.decodeIfPresent([String].self, forKey: .listen) ?? []
        adminListen = try container.decodeIfPresent(String.self, forKey: .adminListen)
        multicastInterfaces = try container.decodeIfPresent([MulticastInterface].self, forKey: .multicastInterfaces) ?? []
        allowedPublicKeys = try container.decodeIfPresent([String].self, forKey: .allowedPublicKeys) ?? []
        ifName = try container.decodeIfPresent(String.self, forKey: .ifName) ?? "tun0"
        ifMTU = try container.decodeIfPresent(Int.self, forKey: .ifMTU) ?? 65535
        nodeInfo = try container.decodeIfPresent([String: String].self, forKey: .nodeInfo)
        nodeInfoPrivacy = try container.decodeIfPresent(Bool.self, forKey: .nodeInfoPrivacy) ?? false
    }
}

/// Multicast interface configuration
struct MulticastInterface: Codable {
    var regex: String
    var beacon: Bool
    var listen: Bool
    var port: Int
    var priority: Int

    enum CodingKeys: String, CodingKey {
        case regex = "Regex"
        case beacon = "Beacon"
        case listen = "Listen"
        case port = "Port"
        case priority = "Priority"
    }

    init(regex: String = ".*", beacon: Bool = true, listen: Bool = true, port: Int = 0, priority: Int = 0) {
        self.regex = regex
        self.beacon = beacon
        self.listen = listen
        self.port = port
        self.priority = priority
    }
}

/// Peer connection status
struct PeerInfo: Codable, Identifiable {
    var id: String { remote }

    let remote: String
    let up: Bool
    let inbound: Bool
    let address: String?
    let coords: [Int]?
    let bytesReceived: Int?
    let bytesSent: Int?
    let uptime: Double?

    enum CodingKeys: String, CodingKey {
        case remote = "Remote"
        case up = "Up"
        case inbound = "Inbound"
        case address = "Address"
        case coords = "Coords"
        case bytesReceived = "BytesRecvd"
        case bytesSent = "BytesSent"
        case uptime = "Uptime"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        remote = try container.decode(String.self, forKey: .remote)
        up = try container.decodeIfPresent(Bool.self, forKey: .up) ?? false
        inbound = try container.decodeIfPresent(Bool.self, forKey: .inbound) ?? false
        address = try container.decodeIfPresent(String.self, forKey: .address)
        coords = try container.decodeIfPresent([Int].self, forKey: .coords)
        bytesReceived = try container.decodeIfPresent(Int.self, forKey: .bytesReceived)
        bytesSent = try container.decodeIfPresent(Int.self, forKey: .bytesSent)
        uptime = try container.decodeIfPresent(Double.self, forKey: .uptime)
    }
}

/// Self information from Yggdrasil
struct SelfInfo: Codable {
    let address: String
    let subnet: String
    let coords: [Int]
    let publicKey: String

    enum CodingKeys: String, CodingKey {
        case address = "Address"
        case subnet = "Subnet"
        case coords = "Coords"
        case publicKey = "PublicKey"
    }
}
