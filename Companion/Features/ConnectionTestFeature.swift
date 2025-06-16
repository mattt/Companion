import ComposableArchitecture
import Dependencies
import Foundation

@Reducer
struct ConnectionTestFeature {
    @ObservableState
    struct State: Equatable {
        var status: Status = .idle
        var errorMessage: String? = nil

        enum Status: Equatable {
            case idle
            case testing
            case success
            case failed
            case cancelled
        }

        var isTesting: Bool {
            status == .testing
        }

        var canTest: Bool {
            status != .testing
        }

        var hasSucceeded: Bool {
            status == .success
        }
    }

    enum Action: Equatable {
        case testConnection(Server)
        case cancelTest
        case testCompleted
        case testFailed(String)
        case testCancelled
        case reset
    }

    @Dependency(\.serverClient) var serverClient

    private enum CancelID { case test }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .testConnection(server):
                state.status = .testing
                state.errorMessage = nil

                return .run { send in
                    do {
                        try await serverClient.testConnection(server)
                        await send(.testCompleted)
                    } catch is CancellationError {
                        await send(.testCancelled)
                    } catch {
                        await send(.testFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.test)

            case .cancelTest:
                state.status = .cancelled
                state.errorMessage = "Test cancelled"

                return .cancel(id: CancelID.test)

            case .testCompleted:
                state.status = .success
                state.errorMessage = nil
                return .none

            case let .testFailed(error):
                state.status = .failed
                state.errorMessage = error
                return .none

            case .testCancelled:
                state.status = .cancelled
                state.errorMessage = "Test cancelled"
                return .none

            case .reset:
                state.status = .idle
                state.errorMessage = nil
                return .cancel(id: CancelID.test)
            }
        }
    }
}
