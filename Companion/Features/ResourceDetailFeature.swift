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
        var templateArguments: [String: String] = [:]
        var errorMessage: String?

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
        case readTemplateTapped
        case cancelResourceRead
        case resourceReadCompleted(MCP.ReadResource.Result)
        case resourceReadFailed(String)
        case dismissResult
        case updateTemplateArgument(String, String)
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
                state.errorMessage = nil

                return .run { [resourceUri = resource.uri] send in
                    do {
                        let result = try await serverClient.readResource(serverId, resourceUri)
                        await send(.resourceReadCompleted(result))
                    } catch {
                        await send(.resourceReadFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.resourceRead)

            case .readTemplateTapped:
                guard let serverId = state.serverId else {
                    return .send(.resourceReadFailed("No server ID provided"))
                }

                guard let template = state.template else {
                    return .send(.resourceReadFailed("No template available"))
                }

                // Substitute template arguments into URI template
                let resourceUri = substituteTemplateArguments(
                    template: template.uriTemplate,
                    arguments: state.templateArguments
                )

                state.isReadingResource = true
                state.resourceReadResult = nil
                state.errorMessage = nil

                return .run { send in
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
                state.errorMessage = nil
                return .none

            case let .resourceReadFailed(error):
                state.isReadingResource = false
                state.resourceReadResult = nil
                state.errorMessage = error
                return .none

            case .dismissResult:
                state.resourceReadResult = nil
                state.errorMessage = nil
                return .none

            case let .updateTemplateArgument(key, value):
                state.templateArguments[key] = value
                return .none
            }
        }
    }

    // Helper function to substitute template arguments
    private func substituteTemplateArguments(template: String, arguments: [String: String]) -> String {
        var result = template
        for (key, value) in arguments {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }
}
