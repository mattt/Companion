import ComposableArchitecture
import Foundation

import enum MCP.Value

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var serverDetails: IdentifiedArrayOf<ServerDetailFeature.State> = []
        var selection: SidebarSelection?
        var isLoading = false
        var error: String?
        @Presents var editServer: EditServerFeature.State?
        @Presents var addServer: AddServerFeature.State?

        init() {
            // Initialize with empty servers - will be loaded from ServerClient
        }

        var servers: IdentifiedArrayOf<Server> {
            IdentifiedArrayOf(uniqueElements: serverDetails.map { $0.server })
        }

        func serverDetail(_ serverId: String) -> ServerDetailFeature.State? {
            serverDetails[id: serverId]
        }
    }

    enum Action: Equatable {
        case task
        case serversUpdated(IdentifiedArrayOf<Server>)
        case selectionChanged(SidebarSelection?)

        case removeServer(id: String)
        case loadingChanged(Bool)
        case errorOccurred(String?)
        case presentAddServer
        case addExampleServer
        case addServerPresentation(PresentationAction<AddServerFeature.Action>)
        case presentEditServer(Server)
        case editServer(PresentationAction<EditServerFeature.Action>)
        case serverDetail(id: String, action: ServerDetailFeature.Action)
    }

    @Dependency(\.serverClient) var serverClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return .run { send in
                    // Load existing servers
                    let servers = await serverClient.getServers()
                    await send(.serversUpdated(servers))

                    // Observe server changes
                    for await updatedServers in await serverClient.observeServers() {
                        await send(.serversUpdated(updatedServers))
                    }
                }

            case let .serversUpdated(servers):
                print("AppFeature: Received server update. \(servers.count) servers:")
                for server in servers {
                    print(
                        "  - \(server.name): \(server.status) (\(server.availableTools.count) tools)"
                    )
                }

                // Preserve current selection if it still exists
                let currentSelection = state.selection

                // Update or create ServerDetailFeature.State for each server
                var newServerDetails: IdentifiedArrayOf<ServerDetailFeature.State> = []
                for server in servers {
                    if let existingDetail = state.serverDetails[id: server.id] {
                        // Update existing server detail with new server data
                        var updatedDetail = existingDetail
                        updatedDetail.server = server
                        newServerDetails.append(updatedDetail)
                    } else {
                        // Create new server detail
                        newServerDetails.append(ServerDetailFeature.State(server: server))
                    }
                }
                state.serverDetails = newServerDetails

                // Re-apply selection if the selected item still exists
                if let currentSelection = currentSelection {
                    // Find the server that matches the current selection
                    if let server = servers.first(where: {
                        $0.id == currentSelection.serverId
                    }) {
                        // Update selection with current server data
                        if let section = currentSelection.section {
                            switch section {
                            case .prompts:
                                if !server.availablePrompts.isEmpty {
                                    state.selection = .prompts(serverId: currentSelection.serverId)
                                }
                            case .resources:
                                if !server.availableResources.isEmpty {
                                    state.selection = .resources(
                                        serverId: currentSelection.serverId)
                                }
                            case .tools:
                                if !server.availableTools.isEmpty {
                                    state.selection = .tools(serverId: currentSelection.serverId)
                                }
                            }
                        } else {
                            // Server selection
                            state.selection = .server(server)
                        }
                    } else {
                        // Server no longer exists, clear selection
                        state.selection = nil
                    }
                }

                return .none

            case let .selectionChanged(selection):
                state.selection = selection
                return .none

            case let .removeServer(id):
                // Clear selection if removed server was selected
                if let selection = state.selection,
                    selection.serverId == id
                {
                    state.selection = nil
                }
                // Remove from server details
                state.serverDetails.remove(id: id)
                return .run { _ in
                    await serverClient.removeServer(id)
                }

            case let .loadingChanged(isLoading):
                state.isLoading = isLoading
                return .none

            case let .errorOccurred(error):
                state.error = error
                return .none

            case let .presentEditServer(server):
                state.editServer = EditServerFeature.State(server: server)
                return .none

            case .editServer(.presented(.updateServer(let name, let transport))):
                guard let editServerState = state.editServer else {
                    return .none
                }
                let serverId = editServerState.server.id
                guard state.serverDetails[id: serverId] != nil else {
                    print("AppFeature: Server \(serverId) not found for update")
                    return .none
                }
                let updatedServer = Server(
                    id: serverId,
                    name: name,
                    configuration: transport
                )
                print("AppFeature: Updating server '\(name)' with status: \(updatedServer.status)")
                state.editServer = nil
                return .run { send in
                    await serverClient.updateServer(updatedServer)
                    print("AppFeature: Server '\(name)' updated, now auto-connecting...")
                    await send(.serverDetail(id: serverId, action: .connect))
                }

            case .editServer(.presented(.testConnection)):
                // Test connection actions are handled internally by EditServerFeature
                return .none

            case .editServer(.presented(.connectionTest)):
                // Connection test actions are handled internally by EditServerFeature
                return .none

            case .editServer(.presented(.dismiss)):
                state.editServer = nil
                return .none

            case .editServer:
                return .none

            case .presentAddServer:
                state.addServer = AddServerFeature.State()
                return .none

            case .addExampleServer:
                let exampleServer = Server(
                    name: "Everything",
                    configuration: .init(stdio: "npx", arguments: ["-y", "@modelcontextprotocol/server-everything"])
                )
                print("AppFeature: Adding example server '\(exampleServer.name)'")
                return .run { send in
                    await serverClient.addServer(exampleServer)
                    print("AppFeature: Example server added, now auto-connecting...")
                    // Wait a brief moment for the server to be processed and state updated
                    try? await Task.sleep(for: .milliseconds(100))
                    await send(.serverDetail(id: exampleServer.id, action: .connect))
                }

            case .addServerPresentation(.presented(.addServer(let name, let transport))):
                let newServer = Server(
                    name: name,
                    configuration: transport
                )
                print("AppFeature: Adding new server '\(name)' with status: \(newServer.status)")
                state.addServer = nil
                return .run { send in
                    await serverClient.addServer(newServer)
                    print(
                        "AppFeature: Server '\(name)' added to ServerClient, now auto-connecting..."
                    )
                    await send(.serverDetail(id: newServer.id, action: .connect))
                }

            case .addServerPresentation(.presented(.testConnection)):
                // Test connection actions are handled internally by AddServerFeature
                return .none

            case .addServerPresentation(.presented(.connectionTest)):
                // Connection test actions are handled internally by AddServerFeature
                return .none

            case .addServerPresentation(.presented(.dismiss)):
                state.addServer = nil
                return .none

            case .addServerPresentation:
                return .none

            case let .serverDetail(id, action):
                // Handle special actions that require AppFeature coordination
                switch action {
                case .edit:
                    guard let serverDetail = state.serverDetails[id: id] else { return .none }
                    return .send(.presentEditServer(serverDetail.server))
                default:
                    // Handle the action in the focused ServerDetailFeature
                    guard var serverDetail = state.serverDetails[id: id] else { return .none }

                    // Create a mini-store to run the ServerDetailFeature reducer
                    let serverFeature = ServerDetailFeature()
                    let effect = serverFeature.reduce(into: &serverDetail, action: action)

                    // Update the state with the modified server detail
                    state.serverDetails[id: id] = serverDetail

                    // Map any effects to include the server ID
                    return effect.map { .serverDetail(id: id, action: $0) }
                }
            }
        }
        .ifLet(\.$editServer, action: \.editServer) {
            EditServerFeature()
        }
        .ifLet(\.$addServer, action: \.addServerPresentation) {
            AddServerFeature()
        }
    }
}
