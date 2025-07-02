import ComposableArchitecture
import Foundation

struct ConfigFile {
    typealias Entry = Server.Configuration

    var entries: [String: Entry]

    init(entries: [String: Entry]) {
        self.entries = entries
    }

    static let empty = ConfigFile(entries: [:])

    var servers: [Server] {
        entries.map { (name, serverConfig) in
            // Generate deterministic hash based on name and configuration
            let stableId = "\(name)|\(serverConfig)".sha256Hash

            return Companion.Server(id: stableId, name: name, configuration: serverConfig)
        }
    }

    init(servers: [Server]) {
        var serversDict: [String: Entry] = [:]

        for server in servers {
            serversDict[server.name] = server.configuration
        }

        self.entries = serversDict
    }
}

// MARK: Shared

extension SharedKey where Self == FileStorageKey<ConfigFile> {
    static var serversConfig: Self {
        fileStorage(
            .applicationSupportDirectory
                .appending(
                    component: Bundle.main.bundleIdentifier ?? "com.loopwork.Companion"
                ).appending(component: "servers.json")
        )
    }
}

// MARK: Codable

extension ConfigFile: Codable {
    private enum CodingKeys: String, CodingKey {
        case entries = "mcpServers"
    }
}
