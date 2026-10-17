import Foundation

struct ConfigFile {
    typealias Entry = Server.Configuration

    var entries: [String: Entry]

    init(entries: [String: Entry]) {
        self.entries = entries
    }

    static let empty = ConfigFile(entries: [:])

    var servers: [Server] {
        entries
            .sorted { $0.key < $1.key }
            .map { (name, serverConfig) in
                let stableId = "\(name)|\(serverConfig)".sha256Hash
                return Server(id: stableId, name: name, configuration: serverConfig)
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

// MARK: Codable

extension ConfigFile: Codable {
    private enum CodingKeys: String, CodingKey {
        case entries = "mcpServers"
    }
}

// MARK: - Persistence

protocol ServerConfigStoring: Sendable {
    func load() throws -> ConfigFile
    func save(_ config: ConfigFile) throws
}

struct FileServerConfigStore: ServerConfigStoring {
    let fileURL: URL

    init(fileURL: URL = FileServerConfigStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(
                component: Bundle.main.bundleIdentifier ?? "me.mattt.Companion"
            )
            .appending(component: "servers.json")
    }

    func load() throws -> ConfigFile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(ConfigFile.self, from: data)
    }

    func save(_ config: ConfigFile) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: [.atomic])
    }
}
