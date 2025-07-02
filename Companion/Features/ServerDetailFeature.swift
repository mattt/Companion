import ComposableArchitecture
import Foundation

import enum MCP.Value

@Reducer
struct ServerDetailFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        var server: Server
        var isConnecting: Bool = false
        var isLoadingData: Bool = false
        var error: String?

        init(server: Server) {
            self.server = server
        }

        var id: String {
            server.id
        }

        var isConnected: Bool {
            server.status.isConnected
        }

        var serverStatus: Server.Status {
            server.status
        }

        // Add computed properties for easier access
        var name: String {
            server.name
        }

        var transport: ConfigFile.Entry {
            server.configuration
        }
    }

    enum Action: Equatable {
        case connect
        case disconnect
        case cancel
        case restart
        case edit
        case refresh

        // Internal actions for state updates
        case connectionStarted
        case connectionCompleted
        case connectionFailed(String)
        case connectionCancelled
        case dataLoadStarted
        case dataLoadCompleted
        case dataLoadFailed(String)
        case serverUpdated(Server)
        case errorCleared
    }

    @Dependency(\.serverClient) var serverClient

    private enum CancelID: Sendable, Hashable {
        case connect
        case loadData
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .connect:
                guard !state.isConnected && !state.isConnecting else { return .none }
                state.isConnecting = true
                state.error = nil
                return .run { [server = state.server] send in
                    do {
                        try await serverClient.connect(server)
                        await send(.connectionCompleted)
                    } catch is CancellationError {
                        await send(.connectionCancelled)
                    } catch {
                        await send(.connectionFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.connect)

            case .disconnect:
                guard state.isConnected else { return .none }
                state.isConnecting = false
                state.isLoadingData = false
                state.error = nil
                return .run { [id = state.server.id] send in
                    do {
                        try await serverClient.disconnect(id, true)
                    } catch {
                        await send(.connectionFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.connect)

            case .cancel:
                guard state.isConnecting else { return .none }
                state.isConnecting = false
                state.error = nil
                return .cancel(id: CancelID.connect)

            case .restart:
                return .run { send in
                    await send(.disconnect)
                    try await Task.sleep(for: .milliseconds(100))
                    await send(.connect)
                }

            case .edit:
                // This will be handled by parent to present edit sheet
                return .none

            case .refresh:
                guard state.isConnected else { return .none }
                state.isLoadingData = true
                state.error = nil
                return .run { [id = state.server.id] send in
                    await send(.dataLoadStarted)
                    do {
                        async let tools = serverClient.fetchTools(id)
                        async let prompts = serverClient.fetchPrompts(id)
                        async let resources = serverClient.fetchResources(id)
                        async let templates = serverClient.fetchResourceTemplates(id)

                        let _ = try await (tools, prompts, resources, templates)
                        await send(.dataLoadCompleted)
                    } catch {
                        await send(.dataLoadFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.loadData)

            case .connectionStarted:
                state.isConnecting = true
                state.error = nil
                return .none

            case .connectionCompleted:
                state.isConnecting = false
                state.error = nil
                // Start loading data after successful connection
                return .send(.refresh)

            case let .connectionFailed(error):
                state.isConnecting = false
                state.error = error
                return .none

            case .connectionCancelled:
                state.isConnecting = false
                state.error = nil
                return .none

            case .dataLoadStarted:
                state.isLoadingData = true
                return .none

            case .dataLoadCompleted:
                state.isLoadingData = false
                return .none

            case let .dataLoadFailed(error):
                state.isLoadingData = false
                state.error = error
                return .none

            case let .serverUpdated(server):
                state.server = server
                return .none

            case .errorCleared:
                state.error = nil
                return .none
            }
        }
    }
}
