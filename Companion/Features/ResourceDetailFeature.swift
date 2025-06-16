import ComposableArchitecture
import Foundation
import MCP

@Reducer
struct ResourceDetailFeature {
    @ObservableState
    struct State: Equatable {
        let resource: Resource?
        let template: Resource.Template?
        let serverId: String?
        var isReadingResource = false
        var resourceReadResult: MCP.ReadResource.Result?

        init(resource: Resource, serverId: String? = nil) {
            self.resource = resource
            self.template = nil
            self.serverId = serverId
        }

        init(template: Resource.Template, serverId: String? = nil) {
            self.resource = nil
            self.template = template
            self.serverId = serverId
        }

        var isTemplate: Bool {
            template != nil
        }
    }

    private enum CancelID { case resourceRead }

    enum Action: Equatable {
        case readResourceTapped
        case cancelResourceRead
        case resourceReadCompleted(MCP.ReadResource.Result)
        case resourceReadFailed(String)
        case dismissResult
    }

    @Dependency(\.serverClient) var serverClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .readResourceTapped:
                guard let serverId = state.serverId else {
                    return .send(.resourceReadFailed("No server ID provided"))
                }

                guard let resource = state.resource else {
                    return .send(.resourceReadFailed("Templates cannot be read"))
                }

                state.isReadingResource = true
                state.resourceReadResult = nil

                return .run { [resourceUri = resource.uri] send in
                    do {
                        let result = try await serverClient.readResource(serverId, resourceUri)
                        await send(.resourceReadCompleted(result))
                    } catch {
                        await send(.resourceReadFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.resourceRead)

            case .cancelResourceRead:
                state.isReadingResource = false
                return .cancel(id: CancelID.resourceRead)

            case let .resourceReadCompleted(result):
                state.isReadingResource = false
                state.resourceReadResult = result
                return .none

            case .resourceReadFailed:
                state.isReadingResource = false
                state.resourceReadResult = nil
                return .none

            case .dismissResult:
                state.resourceReadResult = nil
                return .none
            }
        }
    }
}
