import Foundation
import Testing

@testable import Companion

struct ConfigFileTests {
    private static let sampleJSON = """
        {
          "mcpServers": {
            "Everything": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-everything"],
              "env": { "DEBUG": "1" }
            },
            "Legacy SSE": {
              "type": "sse",
              "url": "https://example.com/sse"
            },
            "Remote": {
              "type": "streamable-http",
              "url": "https://example.com/mcp"
            }
          }
        }
        """

    @Test func decodesSampleServersJSON() throws {
        let config = try JSONDecoder().decode(
            ConfigFile.self, from: Data(Self.sampleJSON.utf8)
        )

        let servers = config.servers
        #expect(servers.count == 3)
        #expect(servers.map(\.name) == ["Everything", "Legacy SSE", "Remote"])

        let everything = try #require(servers.first { $0.name == "Everything" })
        #expect(everything.configuration.command == "npx")
        #expect(
            everything.configuration.arguments
                == ["-y", "@modelcontextprotocol/server-everything"])

        let sse = try #require(servers.first { $0.name == "Legacy SSE" })
        #expect(sse.configuration.url == "https://example.com/sse")

        let remote = try #require(servers.first { $0.name == "Remote" })
        #expect(remote.configuration.url == "https://example.com/mcp")
    }

    @Test func serverIDsAreStableAcrossDecodes() throws {
        let first = try JSONDecoder().decode(
            ConfigFile.self, from: Data(Self.sampleJSON.utf8))
        let second = try JSONDecoder().decode(
            ConfigFile.self, from: Data(Self.sampleJSON.utf8))

        #expect(first.servers.map(\.id) == second.servers.map(\.id))
    }

    @Test func roundTripsThroughEncoder() throws {
        let servers = [
            Server(name: "Local", configuration: .init(stdio: "python3", arguments: ["-m", "srv"])),
            Server(name: "Remote", configuration: .init(http: "https://example.com/mcp")),
        ]
        let config = ConfigFile(servers: servers)

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ConfigFile.self, from: data)

        #expect(decoded.servers.map(\.id) == config.servers.map(\.id))
        #expect(decoded.servers.map(\.name) == ["Local", "Remote"])
    }

    @Test func fileStoreSavesAndLoads() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(component: UUID().uuidString)
        let fileURL = directory.appending(component: "servers.json")
        let store = FileServerConfigStore(fileURL: fileURL)

        #expect(try store.load().entries.isEmpty)

        let config = ConfigFile(servers: [
            Server(name: "Local", configuration: .init(stdio: "node"))
        ])
        try store.save(config)

        let loaded = try store.load()
        #expect(loaded.servers.map(\.name) == ["Local"])
        #expect(loaded.servers.first?.configuration.command == "node")

        try FileManager.default.removeItem(at: directory)
    }
}
