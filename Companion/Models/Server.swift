import Foundation
import IdentifiedCollections
import MCP

struct Server: Identifiable, Hashable, Equatable, Codable, Sendable {
    let id: String
    var name: String
    
    enum Configuration: Hashable, Sendable {
        case stdio(StdioConfig)
        case sse(SSEConfig)
        case streamableHTTP(StreamableHTTPConfig)

        struct StdioConfig: Hashable, Codable, Sendable {
            var command: String
            var args: [String]?
            var env: [String: String]?
        }

        struct SSEConfig: Hashable, Codable, Sendable {
            var type: String = "sse"
            var url: String
            var note: String?
        }

        struct StreamableHTTPConfig: Hashable, Codable, Sendable {
            var type: String = "streamable-http"
            var url: String
            var note: String?
        }
        
        init(stdio command: String, arguments: [String] = []) {
            self = .stdio(StdioConfig(command: command, args: arguments, env: nil))
        }

        init(http url: String) {
            self = .streamableHTTP(StreamableHTTPConfig(url: url))
        }

        var displayValue: String {
            switch self {
            case .stdio(let config):
                let args = config.args?.joined(separator: " ") ?? ""
                return args.isEmpty ? config.command : "\(config.command) \(args)"
            case .sse(let config):
                return config.url
            case .streamableHTTP(let config):
                return config.url
            }
        }

        var command: String? {
            if case .stdio(let config) = self {
                return config.command
            }
            return nil
        }

        var arguments: [String]? {
            if case .stdio(let config) = self {
                return config.args
            }
            return nil
        }

        var url: String? {
            switch self {
            case .stdio:
                return nil
            case .sse(let config):
                return config.url
            case .streamableHTTP(let config):
                return config.url
            }
        }
    }
    var configuration: Configuration
    
    enum Status: Hashable, Equatable, Codable, Sendable {
        case disconnected
        case connecting
        case connected
        case error(String)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }

        var displayText: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting..."
            case .connected: return "Connected"
            case .error(let message): return "Error: \(message)"
            }
        }
    }
    var status: Server.Status = .disconnected
    
    var availableTools: [MCP.Tool] = []
    var availablePrompts: [MCP.Prompt] = []
    var availableResources: [MCP.Resource] = []
    var resourceTemplates: [MCP.Resource.Template] = []

    // Server information from MCP initialization
    var serverInfo: MCP.Server.Info?
    var protocolVersion: String?
    var capabilities: MCP.Server.Capabilities?
    var instructions: String?

    init(id: String? = nil, name: String, configuration: Configuration) {
        self.id = id ?? "\(name)|\(configuration)".sha256Hash
        self.name = name
        self.configuration = configuration
    }
}

// MARK: - Codable

extension Server.Configuration: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try to decode as a dictionary to check for type field
        if let object = try? container.decode([String: Value].self) {
            if case .string(let type) = object["type"] {
                switch type {
                case "sse":
                    let config = try container.decode(SSEConfig.self)
                    self = .sse(config)
                case "streamable-http":
                    let config = try container.decode(StreamableHTTPConfig.self)
                    self = .streamableHTTP(config)
                default:
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Unknown transport type: \(type)"
                    )
                }
            } else {
                // No type field, assume stdio
                let config = try container.decode(StdioConfig.self)
                self = .stdio(config)
            }
        } else {
            // Fallback to stdio if we can't decode as dictionary
            let config = try container.decode(StdioConfig.self)
            self = .stdio(config)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .stdio(let config):
            try container.encode(config)
        case .sse(let config):
            try container.encode(config)
        case .streamableHTTP(let config):
            try container.encode(config)
        }
    }
}


