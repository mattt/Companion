import Foundation
import MCP
import os

#if canImport(System)
    import System
#else
    @preconcurrency import SystemPackage
#endif

// MARK: - Connection result

struct ServerConnectionResult: Sendable {
    var serverInfo: MCP.Server.Info
    var protocolVersion: String
    var capabilities: MCP.Server.Capabilities
    var instructions: String?
    var tools: [MCP.Tool]
    var prompts: [MCP.Prompt]
    var resources: [MCP.Resource]
    var resourceTemplates: [MCP.Resource.Template]
}

// MARK: - Connection protocol

/// Owns live MCP connections, keyed by server ID.
///
/// A connection type does not keep a server list.
/// `ServerStore` is the only source of truth for servers;
/// it asks the connection type to connect, disconnect, and call.
/// Tests can substitute a fake that conforms to this protocol.
protocol ServerConnecting: Sendable {
    func connect(_ server: Server) async throws -> ServerConnectionResult
    func disconnect(serverID: String) async
    func testConnection(_ server: Server) async throws

    func listTools(serverID: String) async throws -> [MCP.Tool]
    func listPrompts(serverID: String) async throws -> [MCP.Prompt]
    func listResources(serverID: String) async throws -> [MCP.Resource]
    func listResourceTemplates(serverID: String) async throws -> [MCP.Resource.Template]

    func callTool(serverID: String, name: String, arguments: [String: Value]) async throws
        -> MCP.CallTool.Result
    func getPrompt(serverID: String, name: String, arguments: [String: String]) async throws
        -> MCP.GetPrompt.Result
    func readResource(serverID: String, uri: String) async throws -> MCP.ReadResource.Result
}

// MARK: - Live implementation

actor MCPServerConnections: ServerConnecting {
    private final class LiveConnection {
        let client: MCP.Client
        let transport: any MCP.Transport
        #if os(macOS)
            var process: Process?
        #endif
        var tools: [MCP.Tool] = []
        var prompts: [MCP.Prompt] = []
        var resources: [MCP.Resource] = []
        var resourceTemplates: [MCP.Resource.Template] = []
        var isConnected = false

        init(client: MCP.Client, transport: any MCP.Transport) {
            self.client = client
            self.transport = transport
        }
    }

    private var connections: [String: LiveConnection] = [:]

    func connect(_ server: Server) async throws -> ServerConnectionResult {
        let (connection, result) = try await performConnection(server)

        do {
            try Task.checkCancellation()
        } catch {
            await tearDown(connection)
            throw error
        }

        if let existing = connections[server.id] {
            await tearDown(existing)
        }
        connections[server.id] = connection
        return result
    }

    func disconnect(serverID: String) async {
        guard let connection = connections.removeValue(forKey: serverID) else { return }
        await tearDown(connection)
        Logger.connection.info("Disconnected server \(serverID, privacy: .public)")
    }

    func testConnection(_ server: Server) async throws {
        let (connection, _) = try await performConnection(server)
        await tearDown(connection)
    }

    func listTools(serverID: String) async throws -> [MCP.Tool] {
        let connection = try liveConnection(serverID)
        let (tools, _) = try await connection.client.listTools()
        connection.tools = tools
        return tools
    }

    func listPrompts(serverID: String) async throws -> [MCP.Prompt] {
        let connection = try liveConnection(serverID)
        let (prompts, _) = try await connection.client.listPrompts()
        connection.prompts = prompts
        return prompts
    }

    func listResources(serverID: String) async throws -> [MCP.Resource] {
        let connection = try liveConnection(serverID)
        let (resources, _) = try await connection.client.listResources()
        connection.resources = resources
        return resources
    }

    func listResourceTemplates(serverID: String) async throws -> [MCP.Resource.Template] {
        let connection = try liveConnection(serverID)
        let (templates, _) = try await connection.client.listResourceTemplates()
        connection.resourceTemplates = templates
        return templates
    }

    func callTool(serverID: String, name: String, arguments: [String: Value]) async throws
        -> MCP.CallTool.Result
    {
        let connection = try liveConnection(serverID)
        guard connection.tools.contains(where: { $0.name == name }) else {
            throw ServerConnectionError.toolNotFound(name)
        }
        let (content, isError) = try await connection.client.callTool(
            name: name,
            arguments: arguments
        )
        return MCP.CallTool.Result(content: content, isError: isError)
    }

    func getPrompt(serverID: String, name: String, arguments: [String: String]) async throws
        -> MCP.GetPrompt.Result
    {
        let connection = try liveConnection(serverID)
        guard connection.prompts.contains(where: { $0.name == name }) else {
            throw ServerConnectionError.promptNotFound(name)
        }
        let (description, messages) = try await connection.client.getPrompt(
            name: name,
            arguments: arguments
        )
        return MCP.GetPrompt.Result(description: description, messages: messages)
    }

    func readResource(serverID: String, uri: String) async throws -> MCP.ReadResource.Result {
        let connection = try liveConnection(serverID)
        let contents = try await connection.client.readResource(uri: uri)
        return MCP.ReadResource.Result(contents: contents)
    }

    // MARK: Private

    private func liveConnection(_ serverID: String) throws -> LiveConnection {
        guard let connection = connections[serverID], connection.isConnected else {
            throw ServerConnectionError.notConnected
        }
        return connection
    }

    private func tearDown(_ connection: LiveConnection) async {
        connection.isConnected = false
        await connection.client.disconnect()
        await connection.transport.disconnect()
        #if os(macOS)
            if let process = connection.process, process.isRunning {
                process.terminate()
            }
        #endif
    }

    /// Creates a client and transport for the server configuration,
    /// performs the MCP handshake, and fetches the initial lists.
    /// A failure to fetch one list does not fail the connection.
    private func performConnection(_ server: Server) async throws
        -> (LiveConnection, ServerConnectionResult)
    {
        Logger.connection.info("Connecting to server '\(server.name, privacy: .public)'")

        let name = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "Companion"
        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let client = MCP.Client(name: name, version: version)

        let transport: any MCP.Transport
        let connection: LiveConnection

        switch server.configuration.transportType {
        case .stdio:
            #if os(macOS)
                let command = server.configuration.command ?? ""
                let args = server.configuration.arguments ?? []
                var env = ProcessInfo.processInfo.environment

                let homePath = FileManager.default.homeDirectoryForCurrentUser.path
                env["PATH"] = [
                    "/opt/homebrew/opt/postgresql@17/bin",
                    "/opt/homebrew/bin",
                    "/opt/homebrew/sbin",
                    "/opt/homebrew/opt/asdf/libexec/bin",
                    "/usr/local/bin",
                    "/usr/bin",
                    "/bin",
                    "/usr/sbin",
                    "/sbin",
                    "/usr/local/sbin",
                    "/opt/local/bin",
                    "/opt/local/sbin",
                    "\(homePath)/.local/bin",
                    "\(homePath)/.cargo/bin",
                    "\(homePath)/.asdf/shims",
                    "\(homePath)/.pyenv/shims",
                    "\(homePath)/.rbenv/shims",
                    "\(homePath)/.bun/bin",
                ].joined(separator: ":")

                if case .stdio(let stdioConfig) = server.configuration,
                    let customEnv = stdioConfig.env
                {
                    for (key, value) in customEnv {
                        env[key] = value
                    }
                }

                let shellCommand =
                    args.isEmpty ? command : "\(command) \(args.joined(separator: " "))"

                let process = Process()
                let stdInPipe = Pipe()
                let stdOutPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", shellCommand]
                process.environment = env
                process.currentDirectoryURL = URL(
                    fileURLWithPath: FileManager.default.currentDirectoryPath)
                process.standardInput = stdInPipe
                process.standardOutput = stdOutPipe
                process.standardError = Pipe()

                let input = FileDescriptor(
                    rawValue: stdOutPipe.fileHandleForReading.fileDescriptor)
                let output = FileDescriptor(
                    rawValue: stdInPipe.fileHandleForWriting.fileDescriptor)

                transport = StdioTransport(input: input, output: output)
                connection = LiveConnection(client: client, transport: transport)
                connection.process = process

                try process.run()
            #else
                throw ServerConnectionError.stdioNotSupported
            #endif

        case .http:
            let urlString = server.configuration.url ?? ""
            guard let url = URL(string: urlString) else {
                throw ServerConnectionError.invalidURL(urlString)
            }

            let config: URLSessionConfiguration = .ephemeral
            #if !os(macOS)
                config.multipathServiceType = .none
            #endif
            transport = HTTPClientTransport(endpoint: url, configuration: config)
            connection = LiveConnection(client: client, transport: transport)
        }

        do {
            let initResult = try await client.connect(transport: transport)
            connection.isConnected = true

            var result = ServerConnectionResult(
                serverInfo: initResult.serverInfo,
                protocolVersion: initResult.protocolVersion,
                capabilities: initResult.capabilities,
                instructions: initResult.instructions,
                tools: [],
                prompts: [],
                resources: [],
                resourceTemplates: []
            )

            if initResult.capabilities.tools != nil {
                do {
                    let (tools, _) = try await client.listTools()
                    result.tools = tools
                    connection.tools = tools
                } catch {
                    Logger.connection.error(
                        "Failed to fetch tools: \(error.localizedDescription, privacy: .public)")
                }
            }

            if initResult.capabilities.prompts != nil {
                do {
                    let (prompts, _) = try await client.listPrompts()
                    result.prompts = prompts
                    connection.prompts = prompts
                } catch {
                    Logger.connection.error(
                        "Failed to fetch prompts: \(error.localizedDescription, privacy: .public)")
                }
            }

            if initResult.capabilities.resources != nil {
                do {
                    let (resources, _) = try await client.listResources()
                    result.resources = resources
                    connection.resources = resources
                } catch {
                    Logger.connection.error(
                        "Failed to fetch resources: \(error.localizedDescription, privacy: .public)")
                }

                do {
                    let (templates, _) = try await client.listResourceTemplates()
                    result.resourceTemplates = templates
                    connection.resourceTemplates = templates
                } catch {
                    Logger.connection.error(
                        "Failed to fetch resource templates: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }

            Logger.connection.info(
                "Connected to '\(server.name, privacy: .public)': \(result.tools.count) tools, \(result.prompts.count) prompts, \(result.resources.count) resources"
            )
            return (connection, result)
        } catch {
            Logger.connection.error(
                "Connection failed for '\(server.name, privacy: .public)': \(error.localizedDescription, privacy: .public)"
            )
            await tearDown(connection)
            throw error
        }
    }
}

// MARK: - Errors

enum ServerConnectionError: Swift.Error, LocalizedError {
    case notConnected
    case toolNotFound(String)
    case promptNotFound(String)
    case stdioNotSupported
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to server"
        case .toolNotFound(let name):
            return "Tool \(name) not found"
        case .promptNotFound(let name):
            return "Prompt \(name) not found"
        case .stdioNotSupported:
            return "STDIO transport is not supported on this platform"
        case .invalidURL(let urlString):
            return "Invalid URL: \(urlString)"
        }
    }
}
