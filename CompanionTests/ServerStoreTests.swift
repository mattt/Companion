import Foundation
import MCP
import Testing

@testable import Companion

// MARK: - Fakes

actor FakeServerConnection: ServerConnecting {
    var result: ServerConnectionResult
    var connectError: (any Error)?
    var connectDelay: Duration = .zero
    var tools: [MCP.Tool]
    var completionValues: [String] = ["alpha", "alpine"]

    private(set) var connectCalls: [String] = []
    private(set) var disconnectCalls: [String] = []
    private(set) var testCalls: [String] = []
    private(set) var pingCalls: [String] = []
    private(set) var loggingLevels: [MCP.LogLevel] = []
    private(set) var subscribedURIs: [String] = []
    private(set) var unsubscribedURIs: [String] = []
    private(set) var rootsChangedCalls: [String] = []

    private var eventHandler: (@Sendable (ServerEvent) -> Void)?

    var hasEventHandler: Bool { eventHandler != nil }

    func setEventHandler(_ handler: (@Sendable (ServerEvent) -> Void)?) async {
        eventHandler = handler
    }

    func emit(_ event: ServerEvent) {
        eventHandler?(event)
    }

    init(result: ServerConnectionResult = .stub) {
        self.result = result
        self.tools = result.tools
    }

    func setConnectDelay(_ delay: Duration) { connectDelay = delay }
    func setConnectError(_ error: (any Error)?) { connectError = error }
    func setTools(_ tools: [MCP.Tool]) { self.tools = tools }

    func connect(_ server: Companion.Server) async throws -> ServerConnectionResult {
        connectCalls.append(server.id)
        if connectDelay > .zero {
            try await Task.sleep(for: connectDelay)
        }
        if let connectError {
            throw connectError
        }
        return result
    }

    func disconnect(serverID: String) async {
        disconnectCalls.append(serverID)
    }

    func testConnection(_ server: Companion.Server) async throws {
        testCalls.append(server.id)
        if let connectError {
            throw connectError
        }
    }

    func listTools(serverID: String) async throws -> [MCP.Tool] { tools }
    func listPrompts(serverID: String) async throws -> [MCP.Prompt] { result.prompts }
    func listResources(serverID: String) async throws -> [MCP.Resource] { result.resources }
    func listResourceTemplates(serverID: String) async throws -> [MCP.Resource.Template] {
        result.resourceTemplates
    }

    func ping(serverID: String) async throws {
        pingCalls.append(serverID)
    }

    func callTool(
        serverID: String, name: String, arguments: [String: Value],
        progressHandler: (@Sendable (ToolProgress) -> Void)?
    ) async throws -> MCP.CallTool.Result {
        progressHandler?(ToolProgress(progress: 1, total: 2, message: "Halfway"))
        return MCP.CallTool.Result(
            content: [.text(text: "ok", annotations: nil, _meta: nil)],
            structuredContent: .object(["answer": .int(42)]),
            isError: false)
    }

    func setLoggingLevel(serverID: String, level: MCP.LogLevel) async throws {
        loggingLevels.append(level)
    }

    func completePromptArgument(
        serverID: String, promptName: String, argumentName: String,
        argumentValue: String, context: [String: String]?
    ) async throws -> MCP.Complete.Result.Completion {
        MCP.Complete.Result.Completion(values: completionValues)
    }

    func completeResourceArgument(
        serverID: String, resourceURI: String, argumentName: String,
        argumentValue: String, context: [String: String]?
    ) async throws -> MCP.Complete.Result.Completion {
        MCP.Complete.Result.Completion(values: completionValues)
    }

    func subscribeToResource(serverID: String, uri: String) async throws {
        subscribedURIs.append(uri)
    }

    func unsubscribeFromResource(serverID: String, uri: String) async throws {
        unsubscribedURIs.append(uri)
    }

    func notifyRootsChanged(serverID: String) async {
        rootsChangedCalls.append(serverID)
    }

    func getPrompt(serverID: String, name: String, arguments: [String: String]) async throws
        -> MCP.GetPrompt.Result
    {
        MCP.GetPrompt.Result(description: "desc", messages: [])
    }

    func readResource(serverID: String, uri: String) async throws -> MCP.ReadResource.Result {
        MCP.ReadResource.Result(contents: [])
    }
}

extension ServerConnectionResult {
    static var stub: ServerConnectionResult {
        ServerConnectionResult(
            serverInfo: MCP.Server.Info(name: "Fake", version: "1.0"),
            protocolVersion: "2025-03-26",
            capabilities: MCP.Server.Capabilities(
                prompts: .init(), resources: .init(), tools: .init()),
            instructions: nil,
            tools: [Tool(name: "echo", description: "Echo", inputSchema: .object([:]))],
            prompts: [],
            resources: [],
            resourceTemplates: []
        )
    }
}

final class InMemoryConfigStore: ServerConfigStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ConfigFile
    private(set) var savedConfigs: [ConfigFile] = []

    init(stored: ConfigFile = .empty) {
        self.stored = stored
    }

    func load() throws -> ConfigFile {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func save(_ config: ConfigFile) throws {
        lock.lock()
        defer { lock.unlock() }
        stored = config
        savedConfigs.append(config)
    }
}

// MARK: - Helpers

@MainActor
private func eventually(
    _ description: String,
    timeout: Duration = .seconds(5),
    condition: @MainActor () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now > deadline {
            Issue.record("Timed out waiting for: \(description)")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

private func eventuallyAsync(
    _ description: String,
    timeout: Duration = .seconds(5),
    condition: @Sendable () async -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !(await condition()) {
        if ContinuousClock.now > deadline {
            Issue.record("Timed out waiting for: \(description)")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

// MARK: - Tests

@MainActor
struct ServerStoreTests {
    private func makeStore(
        connection: FakeServerConnection = FakeServerConnection(),
        configStore: InMemoryConfigStore = InMemoryConfigStore()
    ) -> ServerStore {
        ServerStore(connection: connection, configStore: configStore)
    }

    @Test func loadsServersFromConfigStore() {
        let config = ConfigFile(servers: [
            Server(name: "Saved", configuration: .init(stdio: "node"))
        ])
        let store = makeStore(configStore: InMemoryConfigStore(stored: config))

        #expect(store.servers.map(\.name) == ["Saved"])
        #expect(store.servers.first?.status == .disconnected)
    }

    @Test func addServerPersistsSelectsAndConnects() async throws {
        let configStore = InMemoryConfigStore()
        let store = makeStore(configStore: configStore)

        store.addServer(name: "Echo", configuration: .init(stdio: "echo-server"))
        let server = try #require(store.servers.first)

        #expect(store.selection == .server(server))
        #expect(configStore.savedConfigs.last?.servers.map(\.name) == ["Echo"])

        try await eventually("server connects") {
            store.server(id: server.id)?.status == .connected
        }

        let connected = try #require(store.server(id: server.id))
        #expect(connected.availableTools.map(\.name) == ["echo"])
        #expect(connected.serverInfo?.name == "Fake")
        #expect(connected.isConnecting == false)
    }

    @Test func connectFailureSetsErrorStatus() async throws {
        let connection = FakeServerConnection()
        await connection.setConnectError(
            NSError(
                domain: "Fake", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "boom"]))
        let store = makeStore(connection: connection)

        store.addServer(name: "Bad", configuration: .init(stdio: "nope"))
        let server = try #require(store.servers.first)

        try await eventually("server reports error") {
            store.server(id: server.id)?.errorMessage == "boom"
        }

        let failed = try #require(store.server(id: server.id))
        #expect(failed.status == .error("boom"))
        #expect(failed.isConnecting == false)
    }

    @Test func cancellingOneConnectDoesNotCancelAnother() async throws {
        let connection = FakeServerConnection()
        await connection.setConnectDelay(.seconds(1))
        let store = makeStore(connection: connection)

        store.addServer(name: "First", configuration: .init(stdio: "one"))
        store.addServer(name: "Second", configuration: .init(stdio: "two"))
        let first = try #require(store.servers.first { $0.name == "First" })
        let second = try #require(store.servers.first { $0.name == "Second" })

        store.cancelConnect(serverID: first.id)

        try await eventually("first server is disconnected") {
            let s = store.server(id: first.id)
            return s?.status == .disconnected && s?.isConnecting == false
        }
        try await eventually("second server still connects") {
            store.server(id: second.id)?.status == .connected
        }
    }

    @Test func disconnectClearsRuntimeData() async throws {
        let store = makeStore()

        store.addServer(name: "Echo", configuration: .init(stdio: "echo-server"))
        let server = try #require(store.servers.first)
        try await eventually("server connects") {
            store.server(id: server.id)?.status == .connected
        }

        store.disconnect(serverID: server.id)

        let disconnected = try #require(store.server(id: server.id))
        #expect(disconnected.status == .disconnected)
        #expect(disconnected.availableTools.isEmpty)
    }

    @Test func removeServerPersistsAndClearsSelection() async throws {
        let configStore = InMemoryConfigStore()
        let store = makeStore(configStore: configStore)

        store.addServer(name: "Echo", configuration: .init(stdio: "echo-server"))
        let server = try #require(store.servers.first)

        store.removeServer(id: server.id)

        #expect(store.servers.isEmpty)
        #expect(store.selection == nil)
        #expect(configStore.savedConfigs.last?.entries.isEmpty == true)
    }

    @Test func refreshReplacesToolList() async throws {
        let connection = FakeServerConnection()
        let store = makeStore(connection: connection)

        store.addServer(name: "Echo", configuration: .init(stdio: "echo-server"))
        let server = try #require(store.servers.first)
        try await eventually("server connects") {
            store.server(id: server.id)?.status == .connected
        }

        await connection.setTools([
            Tool(name: "shout", description: "Shout", inputSchema: .object([:]))
        ])
        store.refresh(serverID: server.id)

        try await eventually("tool list refreshes") {
            store.server(id: server.id)?.availableTools.map(\.name) == ["shout"]
        }
        #expect(store.server(id: server.id)?.isLoadingData == false)
    }

    @Test func updateWithChangedConfigurationReconnects() async throws {
        let connection = FakeServerConnection()
        let store = makeStore(connection: connection)

        store.addServer(name: "Echo", configuration: .init(stdio: "old"))
        let server = try #require(store.servers.first)
        try await eventually("server connects") {
            store.server(id: server.id)?.status == .connected
        }

        store.updateServer(
            id: server.id, name: "Echo", configuration: .init(stdio: "new"))

        let serverID = server.id
        try await eventuallyAsync("server disconnects and reconnects") {
            let disconnects = await connection.disconnectCalls
            let connects = await connection.connectCalls
            return disconnects == [serverID] && connects == [serverID, serverID]
        }
        try await eventually("server is connected with new configuration") {
            let s = store.server(id: server.id)
            return s?.status == .connected && s?.configuration.command == "new"
        }
    }

    // MARK: - Server events

    private func connectedStore(
        connection: FakeServerConnection
    ) async throws -> (store: ServerStore, serverID: String) {
        let store = makeStore(connection: connection)
        store.addServer(name: "Echo", configuration: .init(stdio: "echo-server"))
        let server = try #require(store.servers.first)
        try await eventually("server connects") {
            store.server(id: server.id)?.status == .connected
        }
        try await eventuallyAsync("event handler registered") {
            await connection.hasEventHandler
        }
        return (store, server.id)
    }

    @Test func toolsListChangedEventRefreshesTools() async throws {
        let connection = FakeServerConnection()
        let (store, serverID) = try await connectedStore(connection: connection)

        await connection.setTools([
            Tool(name: "shout", description: "Shout", inputSchema: .object([:]))
        ])
        await connection.emit(.toolsListChanged(serverID: serverID))

        try await eventually("tool list refreshes from event") {
            store.server(id: serverID)?.availableTools.map(\.name) == ["shout"]
        }
    }

    @Test func logMessageEventAppendsToServerLog() async throws {
        let connection = FakeServerConnection()
        let (store, serverID) = try await connectedStore(connection: connection)

        await connection.emit(
            .logMessage(
                serverID: serverID,
                message: ServerLogMessage(
                    level: .warning, logger: "test", data: .string("careful"))))

        try await eventually("log message appears") {
            store.server(id: serverID)?.logMessages.count == 1
        }
        let message = try #require(store.server(id: serverID)?.logMessages.first)
        #expect(message.level == .warning)
        #expect(message.text == "careful")
    }

    @Test func resourceUpdatedEventMarksResourceAndReadClearsIt() async throws {
        let connection = FakeServerConnection()
        let (store, serverID) = try await connectedStore(connection: connection)

        await connection.emit(
            .resourceUpdated(serverID: serverID, uri: "file:///tmp/a.txt"))

        try await eventually("resource marked updated") {
            store.server(id: serverID)?.updatedResourceURIs.contains("file:///tmp/a.txt")
                == true
        }

        _ = try await store.readResource(serverID: serverID, uri: "file:///tmp/a.txt")
        #expect(
            store.server(id: serverID)?.updatedResourceURIs.contains("file:///tmp/a.txt")
                == false)
    }

    // MARK: - New calls

    @Test func pingReachesConnection() async throws {
        let connection = FakeServerConnection()
        let (store, serverID) = try await connectedStore(connection: connection)

        try await store.ping(serverID: serverID)

        #expect(await connection.pingCalls == [serverID])
    }

    @Test func setLoggingLevelUpdatesServerAndConnection() async throws {
        let connection = FakeServerConnection()
        let (store, serverID) = try await connectedStore(connection: connection)

        try await store.setLoggingLevel(serverID: serverID, level: .error)

        #expect(store.server(id: serverID)?.logLevel == .error)
        #expect(await connection.loggingLevels == [.error])
    }

    @Test func subscribeAndUnsubscribeUpdateServerState() async throws {
        let connection = FakeServerConnection()
        let (store, serverID) = try await connectedStore(connection: connection)

        try await store.subscribeToResource(serverID: serverID, uri: "file:///tmp/a.txt")
        #expect(
            store.server(id: serverID)?.subscribedResourceURIs.contains("file:///tmp/a.txt")
                == true)

        try await store.unsubscribeFromResource(
            serverID: serverID, uri: "file:///tmp/a.txt")
        #expect(
            store.server(id: serverID)?.subscribedResourceURIs.contains("file:///tmp/a.txt")
                == false)
        #expect(await connection.subscribedURIs == ["file:///tmp/a.txt"])
        #expect(await connection.unsubscribedURIs == ["file:///tmp/a.txt"])
    }

    @Test func completionsReturnValues() async throws {
        let connection = FakeServerConnection()
        let (store, serverID) = try await connectedStore(connection: connection)

        let completion = try await store.completePromptArgument(
            serverID: serverID, promptName: "greet", argumentName: "name",
            argumentValue: "al")
        #expect(completion.values == ["alpha", "alpine"])
    }

    @Test func callToolReturnsStructuredContent() async throws {
        let connection = FakeServerConnection()
        let (store, serverID) = try await connectedStore(connection: connection)

        let result = try await store.callTool(
            serverID: serverID, name: "echo", arguments: [:])
        #expect(result.structuredContent == .object(["answer": .int(42)]))
    }
}
