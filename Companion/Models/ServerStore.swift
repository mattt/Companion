import Foundation
import MCP
import os

/// The single source of truth for servers and their runtime state.
///
/// Views read `servers`, `selection`, and `sheet` from the environment
/// and call the methods on this type to add, edit, remove, connect,
/// disconnect, and refresh servers. Connection work is delegated to a
/// `ServerConnecting` value, so tests can pass in a fake. Persistence is
/// delegated to a `ServerConfigStoring` value.
@MainActor
@Observable
final class ServerStore {
    private(set) var servers: [Server] = []
    var selection: SidebarSelection?
    var sheet: Sheet?

    enum Sheet: Identifiable {
        case addServer
        case editServer(Server)

        var id: String {
            switch self {
            case .addServer:
                return "addServer"
            case .editServer(let server):
                return "editServer-\(server.id)"
            }
        }
    }

    private let connection: any ServerConnecting
    private let configStore: any ServerConfigStoring
    private let settingsStore: ServerSettingsStore
    private let keychain: KeychainStore

    /// Queues sampling and elicitation requests from servers for the UI.
    let featureCoordinator: ClientFeatureCoordinator

    /// One task per server, so cancelling one server's work
    /// does not affect any other server.
    private var connectTasks: [String: Task<Void, Never>] = [:]
    private var refreshTasks: [String: Task<Void, Never>] = [:]
    private var listRefreshTasks: [String: Task<Void, Never>] = [:]

    init(
        connection: (any ServerConnecting)? = nil,
        configStore: any ServerConfigStoring = FileServerConfigStore(),
        featureCoordinator: ClientFeatureCoordinator = ClientFeatureCoordinator(),
        settingsStore: ServerSettingsStore = ServerSettingsStore(),
        keychain: KeychainStore = KeychainStore()
    ) {
        self.featureCoordinator = featureCoordinator
        self.connection =
            connection ?? MCPServerConnections(featureHandler: featureCoordinator)
        self.configStore = configStore
        self.settingsStore = settingsStore
        self.keychain = keychain

        do {
            servers = try configStore.load().servers
        } catch {
            Logger.persistence.error(
                "Failed to load servers: \(error.localizedDescription, privacy: .public)")
            servers = []
        }

        let liveConnection = self.connection
        Task { [weak self] in
            await liveConnection.setEventHandler { [weak self] event in
                let store = self
                Task { @MainActor in
                    store?.handleServerEvent(event)
                }
            }
        }
    }

    // MARK: - Lookup

    func server(id: String) -> Server? {
        servers.first { $0.id == id }
    }

    private func index(of serverID: String) -> Int? {
        servers.firstIndex { $0.id == serverID }
    }

    // MARK: - Presentation

    func presentAddServer() {
        sheet = .addServer
    }

    func presentEditServer(_ server: Server) {
        sheet = .editServer(server)
    }

    // MARK: - Add, update, remove

    func addServer(name: String, configuration: Server.Configuration) {
        let server = Server(name: name, configuration: configuration)
        servers.append(server)
        save()
        selection = .server(server)
        connect(serverID: server.id)
    }

    func addExampleServer() {
        addServer(
            name: "Everything",
            configuration: .init(
                stdio: "npx",
                arguments: ["-y", "@modelcontextprotocol/server-everything"]
            )
        )
    }

    func updateServer(id: String, name: String, configuration: Server.Configuration) {
        guard let idx = index(of: id) else { return }
        let oldName = servers[idx].name
        let configurationChanged = servers[idx].configuration != configuration
        let wasConnected = servers[idx].status.isConnected

        servers[idx].name = name
        servers[idx].configuration = configuration
        save()

        if oldName != name {
            settingsStore.rename(from: oldName, to: name)
            keychain.rename(
                from: KeychainStore.bearerTokenAccount(serverName: oldName),
                to: KeychainStore.bearerTokenAccount(serverName: name))
            keychain.rename(
                from: KeychainStore.oauthClientSecretAccount(serverName: oldName),
                to: KeychainStore.oauthClientSecretAccount(serverName: name))
            keychain.rename(
                from: KeychainStore.oauthTokenAccount(serverName: oldName),
                to: KeychainStore.oauthTokenAccount(serverName: name))
        }

        if configurationChanged {
            Task {
                await connection.disconnect(serverID: id)
                if let i = index(of: id) {
                    servers[i].status = .disconnected
                    servers[i].availableTools = []
                    servers[i].availablePrompts = []
                    servers[i].availableResources = []
                    servers[i].availableResourceTemplates = []
                }
                connect(serverID: id)
            }
        } else if !wasConnected {
            connect(serverID: id)
        }
    }

    func removeServer(id: String) {
        connectTasks[id]?.cancel()
        connectTasks[id] = nil
        refreshTasks[id]?.cancel()
        refreshTasks[id] = nil
        for key in listRefreshTasks.keys where key.hasPrefix("\(id):") {
            listRefreshTasks[key]?.cancel()
            listRefreshTasks[key] = nil
        }

        if let name = server(id: id)?.name {
            featureCoordinator.cancelPendingRequests(serverName: name)
            settingsStore.removeSettings(forServerNamed: name)
            keychain.delete(account: KeychainStore.bearerTokenAccount(serverName: name))
            keychain.delete(
                account: KeychainStore.oauthClientSecretAccount(serverName: name))
            keychain.delete(account: KeychainStore.oauthTokenAccount(serverName: name))
        }

        if selection?.serverId == id {
            selection = nil
        }
        servers.removeAll { $0.id == id }
        save()

        Task {
            await connection.disconnect(serverID: id)
        }
    }

    // MARK: - Connect, disconnect, refresh

    func connect(serverID: String) {
        guard let idx = index(of: serverID) else { return }
        guard !servers[idx].status.isConnected, connectTasks[serverID] == nil else { return }

        let server = servers[idx]
        servers[idx].isConnecting = true
        servers[idx].status = .connecting
        servers[idx].errorMessage = nil

        connectTasks[serverID] = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await connection.connect(server)
                guard !Task.isCancelled, let i = index(of: serverID) else {
                    await connection.disconnect(serverID: serverID)
                    finishConnect(serverID: serverID)
                    return
                }
                servers[i].status = .connected
                servers[i].availableTools = result.tools
                servers[i].availablePrompts = result.prompts
                servers[i].availableResources = result.resources
                servers[i].availableResourceTemplates = result.resourceTemplates
                servers[i].serverInfo = result.serverInfo
                servers[i].protocolVersion = result.protocolVersion
                servers[i].capabilities = result.capabilities
                servers[i].instructions = result.instructions
                servers[i].logLevel = AppSettings.defaultLogLevel()
                servers[i].errorMessage = nil
                finishConnect(serverID: serverID)
            } catch is CancellationError {
                if let i = index(of: serverID) {
                    servers[i].status = .disconnected
                    servers[i].errorMessage = nil
                }
                finishConnect(serverID: serverID)
            } catch {
                if let i = index(of: serverID) {
                    servers[i].status = .error(error.localizedDescription)
                    servers[i].errorMessage = error.localizedDescription
                }
                finishConnect(serverID: serverID)
            }
        }
    }

    private func finishConnect(serverID: String) {
        if let i = index(of: serverID) {
            servers[i].isConnecting = false
        }
        connectTasks[serverID] = nil
    }

    func cancelConnect(serverID: String) {
        connectTasks[serverID]?.cancel()
    }

    func disconnect(serverID: String) {
        connectTasks[serverID]?.cancel()
        connectTasks[serverID] = nil
        refreshTasks[serverID]?.cancel()
        refreshTasks[serverID] = nil
        for key in listRefreshTasks.keys where key.hasPrefix("\(serverID):") {
            listRefreshTasks[key]?.cancel()
            listRefreshTasks[key] = nil
        }

        if let name = server(id: serverID)?.name {
            featureCoordinator.cancelPendingRequests(serverName: name)
        }

        if let i = index(of: serverID) {
            servers[i].isConnecting = false
            servers[i].isLoadingData = false
            servers[i].status = .disconnected
            servers[i].availableTools = []
            servers[i].availablePrompts = []
            servers[i].availableResources = []
            servers[i].availableResourceTemplates = []
            servers[i].subscribedResourceURIs = []
            servers[i].updatedResourceURIs = []
            servers[i].errorMessage = nil
        }

        Task {
            await connection.disconnect(serverID: serverID)
        }
    }

    /// Connects every server that is not already connected or connecting.
    func connectAllServers() {
        for server in servers where !server.status.isConnected && !server.isConnecting {
            connect(serverID: server.id)
        }
    }

    /// Deletes every saved secret: sampling API keys,
    /// bearer tokens, and OAuth client secrets and tokens.
    func clearAllSecrets() {
        for provider in SamplingProvider.allCases where provider.needsAPIKey {
            keychain.delete(
                account: KeychainStore.apiKeyAccount(provider: provider.rawValue))
        }
        for server in servers {
            keychain.delete(
                account: KeychainStore.bearerTokenAccount(serverName: server.name))
            keychain.delete(
                account: KeychainStore.oauthClientSecretAccount(serverName: server.name))
            keychain.delete(
                account: KeychainStore.oauthTokenAccount(serverName: server.name))
        }
    }

    func restart(serverID: String) {
        Task {
            await connection.disconnect(serverID: serverID)
            if let i = index(of: serverID) {
                servers[i].status = .disconnected
            }
            connect(serverID: serverID)
        }
    }

    func refresh(serverID: String) {
        guard let idx = index(of: serverID), servers[idx].status.isConnected else { return }
        guard refreshTasks[serverID] == nil else { return }

        servers[idx].isLoadingData = true
        servers[idx].errorMessage = nil

        refreshTasks[serverID] = Task { [weak self] in
            guard let self else { return }
            do {
                async let tools = connection.listTools(serverID: serverID)
                async let prompts = connection.listPrompts(serverID: serverID)
                async let resources = connection.listResources(serverID: serverID)
                async let templates = connection.listResourceTemplates(serverID: serverID)
                let (fetchedTools, fetchedPrompts, fetchedResources, fetchedTemplates) =
                    try await (tools, prompts, resources, templates)

                if let i = index(of: serverID) {
                    servers[i].availableTools = fetchedTools
                    servers[i].availablePrompts = fetchedPrompts
                    servers[i].availableResources = fetchedResources
                    servers[i].availableResourceTemplates = fetchedTemplates
                }
            } catch is CancellationError {
                // Refresh was cancelled; keep the current lists.
            } catch {
                if let i = index(of: serverID) {
                    servers[i].errorMessage = error.localizedDescription
                }
            }
            if let i = index(of: serverID) {
                servers[i].isLoadingData = false
            }
            refreshTasks[serverID] = nil
        }
    }

    // MARK: - Server events

    private func handleServerEvent(_ event: ServerEvent) {
        switch event {
        case .toolsListChanged(let serverID):
            refreshList(serverID: serverID, kind: "tools") { connection in
                try await connection.listTools(serverID: serverID)
            } apply: { server, tools in
                server.availableTools = tools
            }
        case .promptsListChanged(let serverID):
            refreshList(serverID: serverID, kind: "prompts") { connection in
                try await connection.listPrompts(serverID: serverID)
            } apply: { server, prompts in
                server.availablePrompts = prompts
            }
        case .resourcesListChanged(let serverID):
            refreshList(serverID: serverID, kind: "resources") { connection in
                async let resources = connection.listResources(serverID: serverID)
                async let templates = connection.listResourceTemplates(serverID: serverID)
                return try await (resources, templates)
            } apply: { server, lists in
                server.availableResources = lists.0
                server.availableResourceTemplates = lists.1
            }
        case .resourceUpdated(let serverID, let uri):
            if let i = index(of: serverID) {
                servers[i].updatedResourceURIs.insert(uri)
            }
        case .logMessage(let serverID, let message):
            if let i = index(of: serverID) {
                servers[i].logMessages.append(message)
                if servers[i].logMessages.count > 500 {
                    servers[i].logMessages.removeFirst(
                        servers[i].logMessages.count - 500)
                }
            }
        case .elicitationCompleted(let serverID, let elicitationId):
            Logger.server.info(
                "Elicitation \(elicitationId, privacy: .public) completed for server \(serverID, privacy: .public)"
            )
            if let i = index(of: serverID) {
                servers[i].logMessages.append(
                    ServerLogMessage(
                        level: .info,
                        logger: "Companion",
                        data: .string("Elicitation completed: \(elicitationId)")
                    ))
            }
        }
    }

    private func refreshList<Item>(
        serverID: String,
        kind: String,
        fetch: @escaping @Sendable (any ServerConnecting) async throws -> Item,
        apply: @escaping (inout Server, Item) -> Void
    ) {
        let key = "\(serverID):\(kind)"
        guard listRefreshTasks[key] == nil else { return }
        let connection = self.connection
        listRefreshTasks[key] = Task { [weak self] in
            defer { self?.listRefreshTasks[key] = nil }
            do {
                let item = try await fetch(connection)
                guard let self, let i = index(of: serverID) else { return }
                apply(&servers[i], item)
            } catch {
                Logger.server.error(
                    "Failed to refresh \(kind, privacy: .public) after list-changed notification: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    // MARK: - Sidecar settings and secrets

    func sidecarSettings(forServerNamed name: String) -> ServerSidecarSettings {
        settingsStore.settings(forServerNamed: name)
    }

    func bearerToken(forServerNamed name: String) -> String? {
        keychain.string(for: KeychainStore.bearerTokenAccount(serverName: name))
    }

    func oauthClientSecret(forServerNamed name: String) -> String? {
        keychain.string(for: KeychainStore.oauthClientSecretAccount(serverName: name))
    }

    /// Saves roots, OAuth preferences, and secrets for a server.
    ///
    /// The add and edit sheets call this before `addServer` or
    /// `updateServer`, so the connection reads the new values
    /// when it starts. Changes that affect the transport
    /// (OAuth and bearer token) restart a connected server.
    /// Root changes notify the server without a restart.
    func saveSidecarSettings(
        _ settings: ServerSidecarSettings,
        bearerToken: String?,
        oauthClientSecret: String?,
        forServerNamed name: String
    ) {
        let oldSettings = settingsStore.settings(forServerNamed: name)
        let oldBearerToken = self.bearerToken(forServerNamed: name)

        settingsStore.save(settings, forServerNamed: name)
        keychain.setString(
            bearerToken, for: KeychainStore.bearerTokenAccount(serverName: name))
        keychain.setString(
            oauthClientSecret,
            for: KeychainStore.oauthClientSecretAccount(serverName: name))

        guard let server = servers.first(where: { $0.name == name }),
            server.status.isConnected
        else { return }

        if oldSettings.useOAuth != settings.useOAuth || oldBearerToken != bearerToken {
            restart(serverID: server.id)
        } else if oldSettings.roots != settings.roots {
            let serverID = server.id
            Task {
                await connection.notifyRootsChanged(serverID: serverID)
            }
        }
    }

    // MARK: - Calls (used by detail views)

    func testConnection(_ server: Server) async throws {
        try await connection.testConnection(server)
    }

    func ping(serverID: String) async throws {
        try await connection.ping(serverID: serverID)
    }

    func callTool(
        serverID: String,
        name: String,
        arguments: [String: Value],
        progressHandler: (@Sendable (ToolProgress) -> Void)? = nil
    ) async throws -> MCP.CallTool.Result {
        try await connection.callTool(
            serverID: serverID, name: name, arguments: arguments,
            progressHandler: progressHandler)
    }

    func getPrompt(serverID: String, name: String, arguments: [String: String]) async throws
        -> MCP.GetPrompt.Result
    {
        try await connection.getPrompt(serverID: serverID, name: name, arguments: arguments)
    }

    func readResource(serverID: String, uri: String) async throws -> MCP.ReadResource.Result {
        if let i = index(of: serverID) {
            servers[i].updatedResourceURIs.remove(uri)
        }
        return try await connection.readResource(serverID: serverID, uri: uri)
    }

    func setLoggingLevel(serverID: String, level: MCP.LogLevel) async throws {
        try await connection.setLoggingLevel(serverID: serverID, level: level)
        if let i = index(of: serverID) {
            servers[i].logLevel = level
        }
    }

    func clearLogMessages(serverID: String) {
        if let i = index(of: serverID) {
            servers[i].logMessages = []
        }
    }

    func completePromptArgument(
        serverID: String, promptName: String, argumentName: String,
        argumentValue: String, context: [String: String]? = nil
    ) async throws -> MCP.Complete.Result.Completion {
        try await connection.completePromptArgument(
            serverID: serverID, promptName: promptName, argumentName: argumentName,
            argumentValue: argumentValue, context: context)
    }

    func completeResourceArgument(
        serverID: String, resourceURI: String, argumentName: String,
        argumentValue: String, context: [String: String]? = nil
    ) async throws -> MCP.Complete.Result.Completion {
        try await connection.completeResourceArgument(
            serverID: serverID, resourceURI: resourceURI, argumentName: argumentName,
            argumentValue: argumentValue, context: context)
    }

    func subscribeToResource(serverID: String, uri: String) async throws {
        try await connection.subscribeToResource(serverID: serverID, uri: uri)
        if let i = index(of: serverID) {
            servers[i].subscribedResourceURIs.insert(uri)
        }
    }

    func unsubscribeFromResource(serverID: String, uri: String) async throws {
        try await connection.unsubscribeFromResource(serverID: serverID, uri: uri)
        if let i = index(of: serverID) {
            servers[i].subscribedResourceURIs.remove(uri)
            servers[i].updatedResourceURIs.remove(uri)
        }
    }

    // MARK: - Persistence

    private func save() {
        do {
            try configStore.save(ConfigFile(servers: servers))
        } catch {
            Logger.persistence.error(
                "Failed to save servers: \(error.localizedDescription, privacy: .public)")
        }
    }
}
