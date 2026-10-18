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

// MARK: - Server events

/// Notifications a connected server sends to the client.
///
/// `ServerStore` handles these to refresh lists,
/// append log messages, and mark resources as updated.
enum ServerEvent: Sendable {
    case toolsListChanged(serverID: String)
    case promptsListChanged(serverID: String)
    case resourcesListChanged(serverID: String)
    case resourceUpdated(serverID: String, uri: String)
    case logMessage(serverID: String, message: ServerLogMessage)
    case elicitationCompleted(serverID: String, elicitationId: String)
}

/// Progress for a long-running tool call.
struct ToolProgress: Sendable {
    var progress: Double
    var total: Double?
    var message: String?

    var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(max(progress / total, 0), 1)
    }
}

// MARK: - Connection protocol

/// Owns live MCP connections, keyed by server ID.
///
/// A connection type does not keep a server list.
/// `ServerStore` is the only source of truth for servers;
/// it asks the connection type to connect, disconnect, and call.
/// Tests can substitute a fake that conforms to this protocol.
protocol ServerConnecting: Sendable {
    func setEventHandler(_ handler: (@Sendable (ServerEvent) -> Void)?) async

    func connect(_ server: Server) async throws -> ServerConnectionResult
    func disconnect(serverID: String) async
    func testConnection(_ server: Server) async throws
    func ping(serverID: String) async throws

    func listTools(serverID: String) async throws -> [MCP.Tool]
    func listPrompts(serverID: String) async throws -> [MCP.Prompt]
    func listResources(serverID: String) async throws -> [MCP.Resource]
    func listResourceTemplates(serverID: String) async throws -> [MCP.Resource.Template]

    func callTool(
        serverID: String,
        name: String,
        arguments: [String: Value],
        progressHandler: (@Sendable (ToolProgress) -> Void)?
    ) async throws -> MCP.CallTool.Result
    func getPrompt(serverID: String, name: String, arguments: [String: String]) async throws
        -> MCP.GetPrompt.Result
    func readResource(serverID: String, uri: String) async throws -> MCP.ReadResource.Result

    func setLoggingLevel(serverID: String, level: MCP.LogLevel) async throws
    func completePromptArgument(
        serverID: String, promptName: String, argumentName: String,
        argumentValue: String, context: [String: String]?
    ) async throws -> MCP.Complete.Result.Completion
    func completeResourceArgument(
        serverID: String, resourceURI: String, argumentName: String,
        argumentValue: String, context: [String: String]?
    ) async throws -> MCP.Complete.Result.Completion
    func subscribeToResource(serverID: String, uri: String) async throws
    func unsubscribeFromResource(serverID: String, uri: String) async throws
    func notifyRootsChanged(serverID: String) async
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
        var progressHandlers: [MCP.ProgressToken: @Sendable (ToolProgress) -> Void] = [:]
        var isConnected = false

        init(client: MCP.Client, transport: any MCP.Transport) {
            self.client = client
            self.transport = transport
        }
    }

    private var connections: [String: LiveConnection] = [:]
    private var eventHandler: (@Sendable (ServerEvent) -> Void)?

    private let featureHandler: (any ClientFeatureHandling)?
    private let keychain: KeychainStore
    private let settingsStore: ServerSettingsStore

    init(
        featureHandler: (any ClientFeatureHandling)? = nil,
        keychain: KeychainStore = KeychainStore(),
        settingsStore: ServerSettingsStore = ServerSettingsStore()
    ) {
        self.featureHandler = featureHandler
        self.keychain = keychain
        self.settingsStore = settingsStore
    }

    func setEventHandler(_ handler: (@Sendable (ServerEvent) -> Void)?) {
        eventHandler = handler
    }

    private func emit(_ event: ServerEvent) {
        eventHandler?(event)
    }

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

    func ping(serverID: String) async throws {
        let connection = try liveConnection(serverID)
        try await connection.client.ping()
    }

    func listTools(serverID: String) async throws -> [MCP.Tool] {
        let connection = try liveConnection(serverID)
        let tools = try await fetchAllTools(connection.client)
        connection.tools = tools
        return tools
    }

    func listPrompts(serverID: String) async throws -> [MCP.Prompt] {
        let connection = try liveConnection(serverID)
        let prompts = try await fetchAllPrompts(connection.client)
        connection.prompts = prompts
        return prompts
    }

    func listResources(serverID: String) async throws -> [MCP.Resource] {
        let connection = try liveConnection(serverID)
        let resources = try await fetchAllResources(connection.client)
        connection.resources = resources
        return resources
    }

    func listResourceTemplates(serverID: String) async throws -> [MCP.Resource.Template] {
        let connection = try liveConnection(serverID)
        let templates = try await fetchAllResourceTemplates(connection.client)
        connection.resourceTemplates = templates
        return templates
    }

    func callTool(
        serverID: String,
        name: String,
        arguments: [String: Value],
        progressHandler: (@Sendable (ToolProgress) -> Void)?
    ) async throws -> MCP.CallTool.Result {
        let connection = try liveConnection(serverID)
        guard connection.tools.contains(where: { $0.name == name }) else {
            throw ServerConnectionError.toolNotFound(name)
        }

        let token = MCP.ProgressToken.unique()
        if let progressHandler {
            connection.progressHandlers[token] = progressHandler
        }
        defer { connection.progressHandlers[token] = nil }

        let client = connection.client
        let context: MCP.RequestContext<MCP.CallTool.Result> = try await client.callTool(
            name: name,
            arguments: arguments,
            meta: MCP.Metadata(progressToken: token)
        )

        return try await withTaskCancellationHandler {
            try await context.value
        } onCancel: {
            let requestID = context.requestID
            Task {
                try? await client.cancelRequest(requestID, reason: "Cancelled by user")
            }
        }
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

    func setLoggingLevel(serverID: String, level: MCP.LogLevel) async throws {
        let connection = try liveConnection(serverID)
        try await connection.client.setLoggingLevel(level)
    }

    func completePromptArgument(
        serverID: String, promptName: String, argumentName: String,
        argumentValue: String, context: [String: String]?
    ) async throws -> MCP.Complete.Result.Completion {
        let connection = try liveConnection(serverID)
        return try await connection.client.complete(
            promptName: promptName,
            argumentName: argumentName,
            argumentValue: argumentValue,
            context: context
        )
    }

    func completeResourceArgument(
        serverID: String, resourceURI: String, argumentName: String,
        argumentValue: String, context: [String: String]?
    ) async throws -> MCP.Complete.Result.Completion {
        let connection = try liveConnection(serverID)
        return try await connection.client.complete(
            resourceURI: resourceURI,
            argumentName: argumentName,
            argumentValue: argumentValue,
            context: context
        )
    }

    func subscribeToResource(serverID: String, uri: String) async throws {
        let connection = try liveConnection(serverID)
        try await connection.client.subscribeToResource(uri: uri)
    }

    func unsubscribeFromResource(serverID: String, uri: String) async throws {
        let connection = try liveConnection(serverID)
        // The SDK has no unsubscribe helper and the parameters type has no
        // public initializer, so Companion builds it by decoding JSON
        // and sends the request through the generic `send` API.
        let data = try JSONEncoder().encode(["uri": uri])
        let parameters = try JSONDecoder().decode(
            MCP.ResourceUnsubscribe.Parameters.self, from: data)
        let context = try await connection.client.send(
            MCP.ResourceUnsubscribe.request(parameters))
        _ = try await context.value
    }

    func notifyRootsChanged(serverID: String) async {
        guard let connection = connections[serverID], connection.isConnected else { return }
        try? await connection.client.notifyRootsChanged()
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

    private func forwardProgress(serverID: String, parameters: MCP.ProgressNotification.Parameters) {
        guard let connection = connections[serverID],
            let handler = connection.progressHandlers[parameters.progressToken]
        else { return }
        handler(
            ToolProgress(
                progress: parameters.progress,
                total: parameters.total,
                message: parameters.message
            ))
    }

    // MARK: Pagination

    private func fetchAllTools(_ client: MCP.Client) async throws -> [MCP.Tool] {
        try await fetchAllPages { cursor in
            let (tools, nextCursor) = try await client.listTools(cursor: cursor)
            return (tools, nextCursor)
        }
    }

    private func fetchAllPrompts(_ client: MCP.Client) async throws -> [MCP.Prompt] {
        try await fetchAllPages { cursor in
            let (prompts, nextCursor) = try await client.listPrompts(cursor: cursor)
            return (prompts, nextCursor)
        }
    }

    private func fetchAllResources(_ client: MCP.Client) async throws -> [MCP.Resource] {
        try await fetchAllPages { cursor in
            let (resources, nextCursor) = try await client.listResources(cursor: cursor)
            return (resources, nextCursor)
        }
    }

    private func fetchAllResourceTemplates(_ client: MCP.Client) async throws
        -> [MCP.Resource.Template]
    {
        try await fetchAllPages { cursor in
            let (templates, nextCursor) = try await client.listResourceTemplates(cursor: cursor)
            return (templates, nextCursor)
        }
    }

    /// Follows `nextCursor` until the server stops sending one.
    /// The page cap and repeated-cursor check protect against
    /// servers that loop forever.
    private func fetchAllPages<Item: Sendable>(
        _ fetchPage: (String?) async throws -> (items: [Item], nextCursor: String?)
    ) async throws -> [Item] {
        var all: [Item] = []
        var cursor: String?
        var seenCursors: Set<String> = []
        var pages = 0

        repeat {
            let (items, nextCursor) = try await fetchPage(cursor)
            all += items
            pages += 1

            guard let nextCursor, pages < 100, !seenCursors.contains(nextCursor) else {
                break
            }
            seenCursors.insert(nextCursor)
            cursor = nextCursor
        } while cursor != nil

        return all
    }

    // MARK: Connection setup

    /// Registers handlers for server notifications and,
    /// when a feature handler exists, for roots, sampling,
    /// and elicitation requests from the server.
    private func registerHandlers(client: MCP.Client, server: Server) async {
        let serverID = server.id
        let serverName = server.name

        if let featureHandler {
            await client.withRootsHandler {
                await featureHandler.roots(forServerNamed: serverName)
            }
            await client.withSamplingHandler { parameters in
                try await featureHandler.handleSampling(
                    serverName: serverName, parameters: parameters)
            }
            await client.withElicitationHandler { parameters in
                try await featureHandler.handleElicitation(
                    serverName: serverName, parameters: parameters)
            }
        }

        await client.onNotification(MCP.ToolListChangedNotification.self) { [weak self] _ in
            await self?.emit(.toolsListChanged(serverID: serverID))
        }
        await client.onNotification(MCP.PromptListChangedNotification.self) { [weak self] _ in
            await self?.emit(.promptsListChanged(serverID: serverID))
        }
        await client.onNotification(MCP.ResourceListChangedNotification.self) { [weak self] _ in
            await self?.emit(.resourcesListChanged(serverID: serverID))
        }
        await client.onNotification(MCP.ResourceUpdatedNotification.self) { [weak self] message in
            await self?.emit(
                .resourceUpdated(serverID: serverID, uri: message.params.uri))
        }
        await client.onNotification(MCP.LogMessageNotification.self) { [weak self] message in
            let logMessage = ServerLogMessage(
                level: message.params.level,
                logger: message.params.logger,
                data: message.params.data
            )
            await self?.emit(.logMessage(serverID: serverID, message: logMessage))
        }
        await client.onNotification(MCP.ProgressNotification.self) { [weak self] message in
            await self?.forwardProgress(serverID: serverID, parameters: message.params)
        }
        await client.onNotification(MCP.ElicitationCompleteNotification.self) {
            [weak self] message in
            await self?.emit(
                .elicitationCompleted(
                    serverID: serverID, elicitationId: message.params.elicitationId))
        }
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

        let capabilities: MCP.Client.Capabilities =
            featureHandler == nil
            ? MCP.Client.Capabilities()
            : MCP.Client.Capabilities(
                sampling: MCP.Client.Capabilities.Sampling(),
                elicitation: MCP.Client.Capabilities.Elicitation(
                    form: MCP.Client.Capabilities.Elicitation.Form(),
                    url: MCP.Client.Capabilities.Elicitation.URL()
                ),
                roots: MCP.Client.Capabilities.Roots(listChanged: true)
            )
        let client = MCP.Client(
            name: name,
            version: version,
            title: "Companion",
            description: "A utility for testing and debugging MCP servers",
            capabilities: capabilities
        )

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

                if let customEnv = server.configuration.env {
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

            let headers = server.configuration.headers ?? [:]
            let bearerToken = keychain.string(
                for: KeychainStore.bearerTokenAccount(serverName: server.name))
            let authorizer = oauthAuthorizer(for: server)

            transport = HTTPClientTransport(
                endpoint: url,
                configuration: config,
                authorizer: authorizer,
                requestModifier: { request in
                    var modified = request
                    for (field, value) in headers {
                        modified.setValue(value, forHTTPHeaderField: field)
                    }
                    if let bearerToken,
                        modified.value(forHTTPHeaderField: "Authorization") == nil
                    {
                        modified.setValue(
                            "Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
                    }
                    return modified
                }
            )
            connection = LiveConnection(client: client, transport: transport)
        }

        await registerHandlers(client: client, server: server)

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

            if initResult.capabilities.logging != nil {
                try? await client.setLoggingLevel(AppSettings.defaultLogLevel())
            }

            if initResult.capabilities.tools != nil {
                do {
                    let tools = try await fetchAllTools(client)
                    result.tools = tools
                    connection.tools = tools
                } catch {
                    Logger.connection.error(
                        "Failed to fetch tools: \(error.localizedDescription, privacy: .public)")
                }
            }

            if initResult.capabilities.prompts != nil {
                do {
                    let prompts = try await fetchAllPrompts(client)
                    result.prompts = prompts
                    connection.prompts = prompts
                } catch {
                    Logger.connection.error(
                        "Failed to fetch prompts: \(error.localizedDescription, privacy: .public)")
                }
            }

            if initResult.capabilities.resources != nil {
                do {
                    let resources = try await fetchAllResources(client)
                    result.resources = resources
                    connection.resources = resources
                } catch {
                    Logger.connection.error(
                        "Failed to fetch resources: \(error.localizedDescription, privacy: .public)")
                }

                do {
                    let templates = try await fetchAllResourceTemplates(client)
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

    /// Builds an OAuth authorizer when the server settings enable OAuth.
    /// With no saved client secret, the SDK registers the client
    /// dynamically when the authorization server supports it.
    private func oauthAuthorizer(for server: Server) -> (any HTTPClientAuthorizer)? {
        let settings = settingsStore.settings(forServerNamed: server.name)
        guard settings.useOAuth else { return nil }

        let tokenStorage = KeychainTokenStorage(keychain: keychain, serverName: server.name)
        let clientID =
            settings.oauthClientID
            ?? tokenStorage.load()?.clientID
            ?? ""
        let clientSecret = keychain.string(
            for: KeychainStore.oauthClientSecretAccount(serverName: server.name))

        let authentication: OAuthConfiguration.TokenEndpointAuthentication
        if let clientSecret, !clientSecret.isEmpty {
            authentication = .clientSecretBasic(
                clientID: clientID, clientSecret: clientSecret)
        } else {
            authentication = .none(clientID: clientID)
        }

        let configuration = OAuthConfiguration(
            grantType: .authorizationCode,
            authentication: authentication,
            authorizationRedirectURI: OAuthBrowserPresenter.redirectURI,
            clientName: "Companion",
            authorizationDelegate: OAuthBrowserPresenter()
        )
        return OAuthAuthorizer(configuration: configuration, tokenStorage: tokenStorage)
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
