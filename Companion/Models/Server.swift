import Foundation
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
            var headers: [String: String]?
            var note: String?
        }

        struct StreamableHTTPConfig: Hashable, Codable, Sendable {
            var type: String = "streamable-http"
            var url: String
            var headers: [String: String]?
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

        var headers: [String: String]? {
            switch self {
            case .stdio:
                return nil
            case .sse(let config):
                return config.headers
            case .streamableHTTP(let config):
                return config.headers
            }
        }

        var env: [String: String]? {
            if case .stdio(let config) = self {
                return config.env
            }
            return nil
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

    // Runtime UI state (not persisted; ConfigFile stores name + configuration only)
    var isConnecting: Bool = false
    var isLoadingData: Bool = false
    var errorMessage: String?

    var availableTools: [MCP.Tool] = []
    var availablePrompts: [MCP.Prompt] = []
    var availableResources: [MCP.Resource] = []
    var availableResourceTemplates: [MCP.Resource.Template] = []

    // Server information from MCP initialization
    var serverInfo: MCP.Server.Info?
    var protocolVersion: String?
    var capabilities: MCP.Server.Capabilities?
    var instructions: String?

    // Runtime state for logging and subscriptions (not persisted)
    var logMessages: [ServerLogMessage] = []
    var logLevel: MCP.LogLevel = .debug
    var subscribedResourceURIs: Set<String> = []
    var updatedResourceURIs: Set<String> = []

    init(id: String? = nil, name: String, configuration: Configuration) {
        self.id = id ?? "\(name)|\(configuration)".sha256Hash
        self.name = name
        self.configuration = configuration
    }
}

// MARK: - Log messages

/// A log message received from a server through `notifications/message`.
struct ServerLogMessage: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var date: Date = Date()
    var level: MCP.LogLevel
    var logger: String?
    var data: MCP.Value

    /// A short text representation of the log data.
    var text: String {
        switch data {
        case .string(let string):
            return string
        default:
            guard let encoded = try? JSONEncoder().encode(data),
                let string = String(data: encoded, encoding: .utf8)
            else {
                return "\(data)"
            }
            return string
        }
    }
}

// MARK: - Codable

extension Server {
    private enum CodingKeys: String, CodingKey {
        case id, name, configuration, status
        case isConnecting, isLoadingData, errorMessage
        case availableTools, availablePrompts, availableResources, availableResourceTemplates
        case serverInfo, protocolVersion, capabilities, instructions
        case logMessages, logLevel, subscribedResourceURIs, updatedResourceURIs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        configuration = try container.decode(Configuration.self, forKey: .configuration)
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .disconnected
        isConnecting = try container.decodeIfPresent(Bool.self, forKey: .isConnecting) ?? false
        isLoadingData = try container.decodeIfPresent(Bool.self, forKey: .isLoadingData) ?? false
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        availableTools =
            try container.decodeIfPresent([MCP.Tool].self, forKey: .availableTools) ?? []
        availablePrompts =
            try container.decodeIfPresent([MCP.Prompt].self, forKey: .availablePrompts) ?? []
        availableResources =
            try container.decodeIfPresent([MCP.Resource].self, forKey: .availableResources) ?? []
        availableResourceTemplates =
            try container.decodeIfPresent(
                [MCP.Resource.Template].self, forKey: .availableResourceTemplates) ?? []
        serverInfo = try container.decodeIfPresent(MCP.Server.Info.self, forKey: .serverInfo)
        protocolVersion = try container.decodeIfPresent(String.self, forKey: .protocolVersion)
        capabilities = try container.decodeIfPresent(
            MCP.Server.Capabilities.self, forKey: .capabilities)
        instructions = try container.decodeIfPresent(String.self, forKey: .instructions)
        logMessages =
            try container.decodeIfPresent([ServerLogMessage].self, forKey: .logMessages) ?? []
        logLevel = try container.decodeIfPresent(MCP.LogLevel.self, forKey: .logLevel) ?? .debug
        subscribedResourceURIs =
            try container.decodeIfPresent(Set<String>.self, forKey: .subscribedResourceURIs) ?? []
        updatedResourceURIs =
            try container.decodeIfPresent(Set<String>.self, forKey: .updatedResourceURIs) ?? []
    }
}

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


