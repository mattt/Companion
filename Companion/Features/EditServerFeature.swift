import ComposableArchitecture
import Foundation

@Reducer
struct EditServerFeature {
    @ObservableState
    struct State: Equatable {
        var server: Server
        var name: String
        var transport: ConfigFile.Entry
        var connectionTest: ConnectionTestFeature.State = ConnectionTestFeature.State()

        init(server: Server) {
            self.server = server
            self.name = server.name
            self.transport = server.configuration
        }
    }

    enum Action: Equatable {
        case updateServer(name: String, transport: ConfigFile.Entry)
        case dismiss
        case connectionTest(ConnectionTestFeature.Action)
        case testConnection
        case nameChanged(String)
        case transportChanged(ConfigFile.Entry)
    }

    @Dependency(\.serverClient) var serverClient

    var body: some ReducerOf<Self> {
        Scope(state: \.connectionTest, action: \.connectionTest) {
            ConnectionTestFeature()
        }

        Reduce { state, action in
            switch action {
            case .updateServer, .dismiss:
                return .none

            case let .nameChanged(name):
                state.name = name
                return .send(.connectionTest(.reset))

            case let .transportChanged(transport):
                state.transport = transport
                return .send(.connectionTest(.reset))

            case .testConnection:
                let testServer = Server(
                    name: state.name,
                    configuration: state.transport
                )
                return .send(.connectionTest(.testConnection(testServer)))

            case .connectionTest:
                return .none
            }
        }
    }
}
