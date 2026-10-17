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

    /// One task per server, so cancelling one server's work
    /// does not affect any other server.
    private var connectTasks: [String: Task<Void, Never>] = [:]
    private var refreshTasks: [String: Task<Void, Never>] = [:]
    private var pollingTasks: [String: Task<Void, Never>] = [:]

    init(
        connection: any ServerConnecting = MCPServerConnections(),
        configStore: any ServerConfigStoring = FileServerConfigStore()
    ) {
        self.connection = connection
        self.configStore = configStore

        do {
            servers = try configStore.load().servers
        } catch {
            Logger.persistence.error(
                "Failed to load servers: \(error.localizedDescription, privacy: .public)")
            servers = []
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
        let configurationChanged = servers[idx].configuration != configuration
        let wasConnected = servers[idx].status.isConnected

        servers[idx].name = name
        servers[idx].configuration = configuration
        save()

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
        pollingTasks[id]?.cancel()
        pollingTasks[id] = nil

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
                servers[i].errorMessage = nil
                finishConnect(serverID: serverID)

                if result.capabilities.tools?.listChanged == true {
                    startToolPolling(serverID: serverID)
                }
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
        pollingTasks[serverID]?.cancel()
        pollingTasks[serverID] = nil

        if let i = index(of: serverID) {
            servers[i].isConnecting = false
            servers[i].isLoadingData = false
            servers[i].status = .disconnected
            servers[i].availableTools = []
            servers[i].availablePrompts = []
            servers[i].availableResources = []
            servers[i].availableResourceTemplates = []
            servers[i].errorMessage = nil
        }

        Task {
            await connection.disconnect(serverID: serverID)
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

    private func startToolPolling(serverID: String) {
        pollingTasks[serverID]?.cancel()
        pollingTasks[serverID] = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                    guard let self, !Task.isCancelled else { return }
                    let tools = try await connection.listTools(serverID: serverID)
                    if let i = index(of: serverID), servers[i].availableTools != tools {
                        servers[i].availableTools = tools
                    }
                } catch is CancellationError {
                    return
                } catch {
                    try? await Task.sleep(for: .seconds(60))
                }
            }
        }
    }

    // MARK: - Calls (used by detail views)

    func testConnection(_ server: Server) async throws {
        try await connection.testConnection(server)
    }

    func callTool(serverID: String, name: String, arguments: [String: Value]) async throws
        -> MCP.CallTool.Result
    {
        try await connection.callTool(serverID: serverID, name: name, arguments: arguments)
    }

    func getPrompt(serverID: String, name: String, arguments: [String: String]) async throws
        -> MCP.GetPrompt.Result
    {
        try await connection.getPrompt(serverID: serverID, name: name, arguments: arguments)
    }

    func readResource(serverID: String, uri: String) async throws -> MCP.ReadResource.Result {
        try await connection.readResource(serverID: serverID, uri: uri)
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
