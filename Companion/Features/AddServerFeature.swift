import ComposableArchitecture
import Foundation

@Reducer
struct AddServerFeature {
    @ObservableState
    struct State: Equatable {
        var name: String = ""
        var transport: ConfigFile.Entry = .init(stdio: "")
        var connectionTest: ConnectionTestFeature.State = ConnectionTestFeature.State()

        init() {}
    }

    enum Action: Equatable {
        case addServer(name: String, transport: ConfigFile.Entry)
        case dismiss
        case connectionTest(ConnectionTestFeature.Action)
        case testConnection
    }

    @Dependency(\.serverClient) var serverClient

    var body: some ReducerOf<Self> {
        Scope(state: \.connectionTest, action: \.connectionTest) {
            ConnectionTestFeature()
        }

        Reduce { state, action in
            switch action {
            case .addServer, .dismiss:
                return .none

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
