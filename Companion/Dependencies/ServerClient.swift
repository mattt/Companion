import ComposableArchitecture
import Dependencies
import Foundation
import JSONSchema
import MCP

#if canImport(System)
    import System
#else
    @preconcurrency import SystemPackage
#endif

#if os(macOS)
    // Process is only available on macOS, not iOS
#endif

// Debug MCP SDK availability
private func debugMCPSDK() {
    print("ServerClient: MCP SDK imported successfully")
    print("ServerClient: Available types:")
    print("  - MCP.Client: \(type(of: MCP.Client.self))")
    print("  - StdioTransport: \(type(of: StdioTransport.self))")
    print("  - HTTPClientTransport: \(type(of: HTTPClientTransport.self))")
}

// Timeout helper
private func withThrowingTimeout<T>(seconds: Int, operation: @escaping () async throws -> T)
    async throws -> T
{
    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            do {
                return try await operation()
            } catch {
                print("ServerClient: Operation failed in timeout wrapper: \(error)")
                throw error
            }
        }

        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            print("ServerClient: Timeout reached after \(seconds) seconds")
            throw MCPError.connectionTimeout
        }

        guard let result = try await group.next() else {
            print("ServerClient: No result from task group")
            throw MCPError.connectionTimeout
        }

        group.cancelAll()
        return result
    }
}

struct ServerClient {
    var connect: @Sendable (Server) async throws -> Void
    var disconnect: @Sendable (String, Bool) async throws -> Void
    var testConnection: @Sendable (Server) async throws -> Void
    var fetchTools: @Sendable (String) async throws -> [Tool]
    var fetchPrompts: @Sendable (String) async throws -> [Prompt]
    var fetchResources: @Sendable (String) async throws -> [Resource]
    var fetchResourceTemplates: @Sendable (String) async throws -> [Resource.Template]
    var pollTools: @Sendable (String) async throws -> AsyncThrowingStream<[Tool], Swift.Error>
    var callTool: @Sendable (String, String, [String: Value]) async throws -> MCP.CallTool.Result
    var getPrompt: @Sendable (String, String, [String: Value]) async throws -> MCP.GetPrompt.Result
    var readResource: @Sendable (String, String) async throws -> MCP.ReadResource.Result
    var getServers: @Sendable () async -> IdentifiedArrayOf<Server>
    var addServer: @Sendable (Server) async -> Void
    var updateServer: @Sendable (Server) async -> Void
    var removeServer: @Sendable (String) async -> Void
    var observeServers: @Sendable () async -> AsyncStream<IdentifiedArrayOf<Server>>
}

// MARK: - Dependency Registration

extension ServerClient: DependencyKey {
    static var liveValue: ServerClient {
        let clientManager = ServerClientManagerActor()

        return Self(
            connect: { server in
                try await clientManager.connect(server)
            },

            disconnect: { serverId, notify in
                try await clientManager.disconnect(serverId, notify: notify)
            },

            testConnection: { server in
                try await clientManager.testConnection(server)
            },

            fetchTools: { serverId in
                try await clientManager.fetchTools(serverId)
            },

            fetchPrompts: { serverId in
                try await clientManager.fetchPrompts(serverId)
            },

            fetchResources: { serverId in
                try await clientManager.fetchResources(serverId)
            },

            fetchResourceTemplates: { serverId in
                try await clientManager.fetchResourceTemplates(serverId)
            },

            pollTools: { serverId in
                await clientManager.pollTools(serverId)
            },

            callTool: { serverId, toolName, arguments in
                try await clientManager.callTool(serverId, toolName, arguments)
            },

            getPrompt: { serverId, promptName, arguments in
                try await clientManager.getPrompt(serverId, promptName, arguments)
            },

            readResource: { serverId, resourceUri in
                try await clientManager.readResource(serverId, resourceUri)
            },

            getServers: {
                await clientManager.getServers()
            },

            addServer: { server in
                await clientManager.addServer(server)
            },

            updateServer: { server in
                await clientManager.updateServer(server)
            },

            removeServer: { serverId in
                await clientManager.removeServer(serverId)
            },

            observeServers: {
                await clientManager.observeServers()
            }
        )
    }

    static let testValue = Self(
        connect: { server in
            print("TEST: Connecting to server \(server.name)")
            try await Task.sleep(for: .seconds(1))
            print("TEST: Connected to server \(server.name)")
        },
        disconnect: { serverId, notify in
            print("TEST: Disconnecting server \(serverId), notify: \(notify)")
        },
        testConnection: { server in
            print("TEST: Testing connection to server \(server.name)")
            try await Task.sleep(for: .seconds(2))
            print("TEST: Connection test successful for server \(server.name)")
        },
        fetchTools: { _ in
            print("TEST: Fetching tools")
            return []
        },
        fetchPrompts: { _ in
            print("TEST: Fetching prompts")
            return []
        },
        fetchResources: { _ in
            print("TEST: Fetching resources")
            return []
        },
        fetchResourceTemplates: { _ in
            print("TEST: Fetching resource templates")
            return []
        },
        pollTools: { _ in AsyncThrowingStream { $0.finish() } },
        callTool: { serverId, toolName, arguments in
            print(
                "TEST: Calling tool \(toolName) on server \(serverId) with arguments: \(arguments)")
            return MCP.CallTool.Result(content: [.text("Test tool call result")], isError: false)
        },
        getPrompt: { serverId, promptName, arguments in
            print(
                "TEST: Getting prompt \(promptName) on server \(serverId) with arguments: \(arguments)"
            )
            return MCP.GetPrompt.Result(description: "Test prompt description", messages: [])
        },
        readResource: { serverId, resourceUri in
            print("TEST: Reading resource \(resourceUri) on server \(serverId)")
            return MCP.ReadResource.Result(contents: [])
        },
        getServers: {
            print("TEST: Getting servers")
            return IdentifiedArrayOf()
        },
        addServer: { server in
            print("TEST: Adding server \(server.name)")
        },
        updateServer: { server in
            print("TEST: Updating server \(server.name)")
        },
        removeServer: { serverId in
            print("TEST: Removing server \(serverId)")
        },
        observeServers: {
            AsyncStream { continuation in
                print("TEST: Observing servers")
                continuation.yield(IdentifiedArrayOf())
                continuation.finish()
            }
        }
    )
}

extension DependencyValues {
    var serverClient: ServerClient {
        get { self[ServerClient.self] }
        set { self[ServerClient.self] = newValue }
    }
}

// MARK: - Implementation

@globalActor private actor ServerClientManagerActor {
    static let shared = ServerClientManagerActor()

    private final class ServerConnection {
        let server: Server
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
        var pollingTask: Task<Void, Never>?

        init(server: Server, client: MCP.Client, transport: any MCP.Transport) {
            self.server = server
            self.client = client
            self.transport = transport
        }

        deinit {
            pollingTask?.cancel()
        }
    }

    private var connections: [String: ServerConnection] = [:]
    @Shared(.serversConfig) private var config: ConfigFile = .empty
    private var serversContinuation: AsyncStream<IdentifiedArrayOf<Server>>.Continuation?

    // Runtime server state (ephemeral)
    private var servers: IdentifiedArrayOf<Server> = []

    // Merge persistent config with runtime state
    private func loadServers() {
        let configServers = config.servers

        // Merge with existing runtime state, preserving connections and runtime data
        var mergedServers: [Server] = []

        for configServer in configServers {
            // Try to find existing server by ID (config generates stable IDs)
            if let existingServer = servers[id: configServer.id] {
                // Update config but preserve runtime state
                var updatedServer = existingServer
                updatedServer.name = configServer.name
                updatedServer.configuration = configServer.configuration
                mergedServers.append(updatedServer)
            } else {
                // New server from config - use it as-is since config provides stable ID
                mergedServers.append(configServer)
            }
        }

        servers = IdentifiedArrayOf(uniqueElements: mergedServers)
    }

    // Save only configuration to persistent storage
    private func saveServerConfigs() {
        let configServers = servers.map { server in
            // Create clean config server without runtime state
            Server(id: server.id, name: server.name, configuration: server.configuration)
        }

        $config.withLock { config in
            config = ConfigFile(servers: configServers)
        }
    }

    // Data structure to hold connection results
    private struct ConnectionData {
        let connection: ServerConnection
        let initResult: MCP.Initialize.Result
        let tools: [MCP.Tool]
        let prompts: [MCP.Prompt]
        let resources: [MCP.Resource]
        let resourceTemplates: [MCP.Resource.Template]
    }

    init() {
        // Load servers from config into runtime state
        loadServers()
    }

    func connect(_ server: Server) async throws {
        // Use the core connection logic and then persist the server
        let connectionData = try await performConnection(server)

        // Check for cancellation before proceeding
        try Task.checkCancellation()

        // Store the connection and add to persistent server list
        connections[server.id] = connectionData.connection

        // Store server in our list with connecting status first
        var updatedServer = server
        updatedServer.status = .connecting
        if servers[id: server.id] != nil {
            print("ServerClient: Updating existing server to connecting status")
            servers[id: server.id] = updatedServer
        } else {
            print("ServerClient: Adding new server with connecting status")
            servers.append(updatedServer)
        }
        notifyServersChanged()

        // Check for cancellation before final update
        try Task.checkCancellation()

        // Update with connected status and data
        updatedServer.status = .connected
        updatedServer.availableTools = connectionData.tools
        updatedServer.availablePrompts = connectionData.prompts
        updatedServer.availableResources = connectionData.resources
        updatedServer.resourceTemplates = connectionData.resourceTemplates
        updatedServer.serverInfo = connectionData.initResult.serverInfo
        updatedServer.protocolVersion = connectionData.initResult.protocolVersion
        updatedServer.capabilities = connectionData.initResult.capabilities
        updatedServer.instructions = connectionData.initResult.instructions
        servers[id: server.id] = updatedServer
        print(
            "ServerClient: Server '\(server.name)' marked as connected with \(connectionData.tools.count) tools, \(connectionData.prompts.count) prompts, \(connectionData.resources.count) resources"
        )
        notifyServersChanged()

        // Start polling for tool changes if server supports it
        if connectionData.initResult.capabilities.tools?.listChanged == true {
            startToolPolling(serverId: server.id)
        }
    }

    // Core connection logic shared by both connect and testConnection
    private func performConnection(_ server: Server) async throws -> ConnectionData {
        debugMCPSDK()
        print(
            "ServerClient: Attempting to connect to server '\(server.name)' with configuration: \(server.configuration)"
        )

        // Create client
        let name = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "Companion"
        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        print("ServerClient: Creating MCP client with name: '\(name)', version: '\(version)'")
        let client = MCP.Client(name: name, version: version)
        print("ServerClient: MCP client created successfully")

        // Declare transport and connection vars before switch
        let transport: any MCP.Transport
        var connection: ServerConnection  // Will be initialized within the switch

        // Configure transport and initialize connection based on type
        switch server.configuration.transportType {
        case .stdio:
            #if os(macOS)
                let command = server.configuration.command ?? ""
                let args = server.configuration.arguments ?? []
                var env = ProcessInfo.processInfo.environment

                // Set custom PATH for homebrew, standard locations, and common dev tools
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

                // Apply any custom environment variables from server config
                if case .stdio(let stdioConfig) = server.configuration,
                    let customEnv = stdioConfig.env
                {
                    for (key, value) in customEnv {
                        env[key] = value
                    }
                }

                // Use shell wrapper to properly resolve PATH
                let shellCommand =
                    args.isEmpty ? command : "\(command) \(args.joined(separator: " "))"

                print("ServerClient: Setting up STDIO transport")
                print("ServerClient: Shell command: \(shellCommand)")
                print("ServerClient: Environment PATH: \(env["PATH"] ?? "nil")")

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

                let input = FileDescriptor(rawValue: stdOutPipe.fileHandleForReading.fileDescriptor)
                let output = FileDescriptor(rawValue: stdInPipe.fileHandleForWriting.fileDescriptor)

                transport = StdioTransport(input: input, output: output)

                connection = ServerConnection(server: server, client: client, transport: transport)
                connection.process = process

                // Launch the process *after* setting up connection object
                print("ServerClient: Launching process...")
                try process.run()
                print("ServerClient: Process launched successfully")
            #else
                print("ServerClient: STDIO transport not supported on iOS")
                throw MCPError.stdioNotSupported
            #endif

        case .http:
            let urlString = server.configuration.url ?? ""
            guard let url = URL(string: urlString) else {
                throw MCPError.invalidURL(urlString)
            }

            print("ServerClient: Setting up HTTP transport to \(url)")

            // Basic connectivity check for HTTP endpoints
            do {
                print("ServerClient: Testing HTTP endpoint connectivity...")
                let (_, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse {
                    print(
                        "ServerClient: HTTP endpoint responded with status: \(httpResponse.statusCode)"
                    )
                }
            } catch {
                print("ServerClient: HTTP endpoint test failed: \(error.localizedDescription)")
                // Continue anyway - the MCP connection might still work
            }

            // Configure URLSession to disable multipath to avoid QUIC connection issues on iOS
            let config: URLSessionConfiguration = .ephemeral
            #if !os(macOS)
                config.multipathServiceType = .none
            #endif
            transport = HTTPClientTransport(endpoint: url, configuration: config)
            connection = ServerConnection(server: server, client: client, transport: transport)
            print("ServerClient: HTTP transport configured")
        }

        // Connect to the server and perform initial setup (common logic)
        do {
            print("ServerClient: About to call client.connect(transport:) for \(server.name)...")

            // Try without timeout first to see what happens
            print("ServerClient: Attempting connection WITHOUT timeout to debug...")
            let initResult = try await client.connect(transport: transport)
            print("ServerClient: client.connect() returned successfully with result: \(initResult)")
            print("ServerClient: MCP client connected successfully!")
            print("ServerClient: InitResult capabilities: \(initResult.capabilities)")

            // Mark connection as connected
            connection.isConnected = true

            // Initialize variables to store fetched data
            var mcpTools: [MCP.Tool] = []
            var mcpPrompts: [MCP.Prompt] = []
            var mcpResources: [MCP.Resource] = []
            var mcpResourceTemplates: [MCP.Resource.Template] = []

            // Fetch initial data - don't fail connection if individual fetches fail
            if initResult.capabilities.tools != nil {
                do {
                    print("ServerClient: Fetching tools...")
                    let (tools, _) = try await client.listTools()
                    mcpTools = tools
                    connection.tools = tools
                    print("ServerClient: Found \(tools.count) tools")
                } catch {
                    print("ServerClient: Failed to fetch tools: \(error.localizedDescription)")
                }
            } else {
                print("Tools not supported, skipping")
            }

            if initResult.capabilities.prompts != nil {
                do {
                    print("ServerClient: Fetching prompts...")
                    let (prompts, _) = try await client.listPrompts()
                    mcpPrompts = prompts
                    connection.prompts = prompts
                    print("ServerClient: Found \(prompts.count) prompts")
                } catch {
                    print("ServerClient: Failed to fetch prompts: \(error.localizedDescription)")
                }
            } else {
                print("Prompts not supported, skipping")
            }

            if initResult.capabilities.resources != nil {
                do {
                    print("ServerClient: Fetching resources...")
                    let (resources, _) = try await client.listResources()
                    mcpResources = resources
                    connection.resources = resources
                    print("ServerClient: Found \(resources.count) resources")
                } catch {
                    print("ServerClient: Failed to fetch resources: \(error.localizedDescription)")
                }

                do {
                    print("ServerClient: Fetching resource templates...")
                    let (resourceTemplates, _) = try await client.listResourceTemplates()
                    mcpResourceTemplates = resourceTemplates
                    connection.resourceTemplates = resourceTemplates
                    print("ServerClient: Found \(resourceTemplates.count) resource templates")
                } catch {
                    print(
                        "ServerClient: Failed to fetch resource templates: \(error.localizedDescription)"
                    )
                }
            } else {
                print("Resources not supported, skipping")
            }

            print("ServerClient: Connection completed successfully for '\(server.name)'")

            return ConnectionData(
                connection: connection,
                initResult: initResult,
                tools: mcpTools,
                prompts: mcpPrompts,
                resources: mcpResources,
                resourceTemplates: mcpResourceTemplates
            )
        } catch {
            print(
                "ServerClient: Connection failed for server '\(server.name)': \(error.localizedDescription)"
            )

            // Clean up transport and terminate process if it was started
            await transport.disconnect()
            #if os(macOS)
                if let process = connection.process, process.isRunning {
                    process.terminate()
                }
            #endif
            throw error
        }
    }

    func disconnect(_ serverId: String, notify: Bool = true) async throws {
        print("ServerClient: Disconnecting server \(serverId)")

        // Update server status to disconnected before actual disconnection
        if notify, let server = servers[id: serverId] {
            var updatedServer = server
            updatedServer.status = .disconnected
            servers[id: serverId] = updatedServer
            notifyServersChanged()
        }

        // Cancel any ongoing polling task before removing the connection
        if let connection = connections[serverId] {
            connection.pollingTask?.cancel()
            connection.pollingTask = nil
        }

        // Remove the connection
        connections.removeValue(forKey: serverId)

        // Update server status and clear runtime data
        if notify, let server = servers[id: serverId] {
            var updatedServer = server
            updatedServer.status = .disconnected
            updatedServer.availableTools = []
            updatedServer.availablePrompts = []
            updatedServer.availableResources = []
            updatedServer.resourceTemplates = []
            servers[id: serverId] = updatedServer
            notifyServersChanged()
        }

        print("ServerClient: Server \(serverId) disconnected")
    }

    func testConnection(_ server: Server) async throws {
        print("ServerClient: Testing connection using performConnection method...")

        // Use the internal performConnection method directly without affecting servers list
        do {
            let connectionData = try await performConnection(server)
            print("ServerClient: Test connection successful, cleaning up...")

            // Clean up the connection without affecting persistent servers
            connections.removeValue(forKey: server.id)
            await connectionData.connection.transport.disconnect()
            #if os(macOS)
                if let process = connectionData.connection.process, process.isRunning {
                    process.terminate()
                }
            #endif

            print("ServerClient: Test connection successful and cleaned up")
        } catch {
            print("ServerClient: Test connection failed: \(error)")
            // Clean up any partial connection state
            connections.removeValue(forKey: server.id)
            throw error
        }
    }

    func callTool(_ serverId: String, _ toolName: String, _ arguments: [String: Value]) async throws
        -> MCP.CallTool.Result
    {
        print("ServerClient: Calling tool '\(toolName)' on server \(serverId)")
        print("  Arguments: \(arguments)")

        guard let connection = connections[serverId] else {
            print("  ERROR: Server connection not found")
            throw MCPError.notConnected
        }

        guard connection.isConnected else {
            print("  ERROR: Server not connected")
            throw MCPError.notConnected
        }

        // Verify the tool exists on this server
        guard connection.tools.contains(where: { $0.name == toolName }) else {
            print("  ERROR: Tool '\(toolName)' not found on server")
            throw MCPError.toolNotFound(toolName)
        }

        do {
            // Call the tool on the MCP server
            print("  Calling tool on server...")
            let (content, isError) = try await connection.client.callTool(
                name: toolName,
                arguments: arguments
            )

            print("  Tool call returned, processing result...")

            return MCP.CallTool.Result(content: content, isError: isError)

        } catch {
            print("  Exception during tool call: \(error.localizedDescription)")
            throw error
        }
    }

    func getPrompt(_ serverId: String, _ promptName: String, _ arguments: [String: Value])
        async throws -> MCP.GetPrompt.Result
    {
        print("ServerClient: Getting prompt '\(promptName)' on server \(serverId)")
        print("  Arguments: \(arguments)")

        guard let connection = connections[serverId] else {
            print("  ERROR: Server connection not found")
            throw MCPError.notConnected
        }

        guard connection.isConnected else {
            print("  ERROR: Server not connected")
            throw MCPError.notConnected
        }

        // Verify the prompt exists on this server
        guard connection.prompts.contains(where: { $0.name == promptName }) else {
            print("  ERROR: Prompt '\(promptName)' not found on server")
            throw MCPError.promptNotFound(promptName)
        }

        do {
            // Get the prompt from the MCP server
            print("  Getting prompt from server...")
            let (description, messages) = try await connection.client.getPrompt(
                name: promptName,
                arguments: arguments
            )

            print("  Prompt call returned, processing result...")
            print("  Description: \(description ?? "nil")")
            print("  Messages count: \(messages.count)")

            return MCP.GetPrompt.Result(description: description, messages: messages)

        } catch {
            print("  Exception during prompt call: \(error.localizedDescription)")
            throw error
        }
    }

    func readResource(_ serverId: String, _ resourceUri: String) async throws
        -> MCP.ReadResource.Result
    {
        print("ServerClient: Reading resource '\(resourceUri)' on server \(serverId)")

        guard let connection = connections[serverId] else {
            print("  ERROR: Server connection not found")
            throw MCPError.notConnected
        }

        guard connection.isConnected else {
            print("  ERROR: Server not connected")
            throw MCPError.notConnected
        }

        // Verify the resource exists on this server
        guard connection.resources.contains(where: { $0.uri == resourceUri }) else {
            print("  ERROR: Resource '\(resourceUri)' not found on server")
            throw MCPError.resourceNotFound(resourceUri)
        }

        do {
            // Read the resource from the MCP server
            print("  Reading resource from server...")
            let contents = try await connection.client.readResource(uri: resourceUri)

            print("  Resource read returned, processing result...")
            print("  Contents count: \(contents.count)")

            return MCP.ReadResource.Result(contents: contents)

        } catch {
            print("  Exception during resource read: \(error.localizedDescription)")
            throw error
        }
    }

    func fetchTools(_ serverId: String) async throws -> [Tool] {
        guard let connection = connections[serverId] else {
            throw MCPError.notConnected
        }

        // Get tools from MCP server
        let (mcpTools, _) = try await connection.client.listTools()

        // Update stored tools
        connection.tools = mcpTools

        // Update server in the list
        if servers[id: serverId] != nil {
            servers[id: serverId]?.availableTools = mcpTools
            notifyServersChanged()
        }

        return mcpTools
    }

    func pollTools(_ serverId: String) -> AsyncThrowingStream<[Tool], Swift.Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let connection = connections[serverId] else {
                    continuation.finish(throwing: MCPError.notConnected)
                    return
                }

                // Cancel any existing polling task
                connection.pollingTask?.cancel()

                // Create new polling task
                connection.pollingTask = Task {
                    while !Task.isCancelled {
                        do {
                            let tools = try await fetchTools(serverId)
                            continuation.yield(tools)
                            try await Task.sleep(for: .seconds(30))
                        } catch {
                            if !Task.isCancelled {
                                continuation.finish(throwing: error)
                            } else {
                                continuation.finish()
                            }
                            break
                        }
                    }
                }

                continuation.onTermination = { _ in
                    connection.pollingTask?.cancel()
                }
            }
        }
    }

    private func startToolPolling(serverId: String) {
        guard let connection = connections[serverId] else { return }

        // Cancel any existing polling task
        connection.pollingTask?.cancel()

        // Create new polling task
        connection.pollingTask = Task {
            while !Task.isCancelled {
                do {
                    // Wait for a while before polling
                    try await Task.sleep(for: .seconds(30))

                    // Poll for tools
                    let (mcpTools, _) = try await connection.client.listTools()

                    // If tools have changed, update server
                    if mcpTools != connection.tools {
                        connection.tools = mcpTools

                        // Update server's available tools
                        if servers[id: serverId] != nil {
                            servers[id: serverId]?.availableTools = mcpTools
                            notifyServersChanged()
                        }
                    }
                } catch {
                    // Handle error silently - we'll just try again next time
                    if !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(60))  // Wait longer after an error
                    } else {
                        break
                    }
                }
            }
        }
    }

    func fetchPrompts(_ serverId: String) async throws -> [Prompt] {
        guard let connection = connections[serverId] else {
            throw MCPError.notConnected
        }

        // Get prompts from MCP server
        let (mcpPrompts, _) = try await connection.client.listPrompts()

        // Update stored prompts
        connection.prompts = mcpPrompts

        // Update server in the list
        if servers[id: serverId] != nil {
            servers[id: serverId]?.availablePrompts = mcpPrompts
            notifyServersChanged()
        }

        return mcpPrompts
    }

    func fetchResources(_ serverId: String) async throws -> [Resource] {
        guard let connection = connections[serverId] else {
            throw MCPError.notConnected
        }

        // Get resources from MCP server
        let (mcpResources, _) = try await connection.client.listResources()

        // Update stored resources
        connection.resources = mcpResources

        // Update server in the list
        if servers[id: serverId] != nil {
            servers[id: serverId]?.availableResources = mcpResources
            notifyServersChanged()
        }

        return mcpResources
    }

    func fetchResourceTemplates(_ serverId: String) async throws -> [Resource.Template] {
        guard let connection = connections[serverId] else {
            throw MCPError.notConnected
        }

        // Get resource templates from MCP server
        let (mcpResourceTemplates, _) = try await connection.client.listResourceTemplates()

        // Update stored resource templates
        connection.resourceTemplates = mcpResourceTemplates

        // Update server in the list
        if servers[id: serverId] != nil {
            servers[id: serverId]?.resourceTemplates = mcpResourceTemplates
            notifyServersChanged()
        }

        return mcpResourceTemplates
    }

    func getServers() async -> IdentifiedArrayOf<Server> {
        return servers
    }

    func addServer(_ server: Server) async {
        print("ServerClient: Adding server '\(server.name)' with status: \(server.status)")
        servers.append(server)
        print("ServerClient: Server added. Total servers: \(servers.count)")

        // Save to persistent storage
        saveServerConfigs()
        notifyServersChanged()
    }

    func updateServer(_ server: Server) async {
        print("ServerClient: Updating server '\(server.name)' with status: \(server.status)")

        // Disconnect if currently connected and configuration changed
        if let existingServer = servers[id: server.id],
            existingServer.configuration != server.configuration,
            connections[server.id] != nil
        {
            print("ServerClient: Configuration changed, disconnecting before update")
            try? await disconnect(server.id)
        }

        // Update the server in our list
        servers[id: server.id] = server
        print("ServerClient: Server updated. Total servers: \(servers.count)")

        // Save to persistent storage
        saveServerConfigs()
        notifyServersChanged()
    }

    func removeServer(_ serverId: String) async {
        // Disconnect if connected but skip notification to avoid flash
        try? await disconnect(serverId, notify: false)

        // Remove from servers list
        servers.removeAll { $0.id == serverId }

        // Save to persistent storage and notify once
        saveServerConfigs()
        notifyServersChanged()
    }

    func observeServers() async -> AsyncStream<IdentifiedArrayOf<Server>> {
        AsyncStream { continuation in
            Task { @MainActor in
                await self.setServersContinuation(continuation)
                continuation.yield(await self.getServers())
            }

            continuation.onTermination = { _ in
                Task { @MainActor in
                    await self.clearServersContinuation()
                }
            }
        }
    }

    private func setServersContinuation(
        _ continuation: AsyncStream<IdentifiedArrayOf<Server>>.Continuation
    ) {
        serversContinuation = continuation
    }

    private func clearServersContinuation() {
        serversContinuation = nil
    }

    private func notifyServersChanged() {
        print("ServerClient: Notifying servers changed. Total servers: \(servers.count)")
        for server in servers {
            print(
                "  - \(server.name): \(server.status) (\(server.availableTools.count) tools, \(server.availablePrompts.count) prompts)"
            )
        }
        serversContinuation?.yield(servers)
        print("ServerClient: Server change notification sent")
    }
}

// MARK: - Custom Errors

enum MCPError: Swift.Error, LocalizedError {
    case notConnected
    case alreadyConnected
    case toolNotFound(String)
    case promptNotFound(String)
    case resourceNotFound(String)
    case connectionTimeout
    case stdioNotSupported
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to server"
        case .alreadyConnected:
            return "Already connected to server"
        case .toolNotFound(let name):
            return "Tool \(name) not found"
        case .promptNotFound(let name):
            return "Prompt \(name) not found"
        case .resourceNotFound(let name):
            return "Resource \(name) not found"
        case .connectionTimeout:
            return "Connection timed out after 30 seconds"
        case .stdioNotSupported:
            return "STDIO transport is not supported on iOS"
        case .invalidURL(let urlString):
            return "Invalid URL: \(urlString)"
        }
    }
}
