import ComposableArchitecture
import Foundation
import MCP

@Reducer
struct PromptDetailFeature {
    @ObservableState
    struct State: Equatable {
        let prompt: Prompt
        let serverId: String?
        var isCallingPrompt = false
        var promptCallResult: MCP.GetPrompt.Result?
        var argumentValues: [String: String] = [:]

        init(prompt: Prompt, serverId: String? = nil) {
            self.prompt = prompt
            self.serverId = serverId

            // Initialize argument values
            if let arguments = prompt.arguments {
                for argument in arguments {
                    self.argumentValues[argument.name] = ""
                }
            }
        }

        var allRequiredArgumentsProvided: Bool {
            guard let arguments = prompt.arguments, !arguments.isEmpty else { return true }

            for argument in arguments {
                if argument.required == true {
                    if argumentValues[argument.name]?.isEmpty != false {
                        return false
                    }
                }
            }
            return true
        }
    }

    private enum CancelID { case promptCall }

    enum Action: Equatable {
        case usePromptTapped
        case cancelPromptCall
        case promptCallCompleted(MCP.GetPrompt.Result)
        case promptCallFailed(String)
        case argumentChanged(String, String)
        case dismissResult
    }

    @Dependency(\.serverClient) var serverClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .usePromptTapped:
                guard let serverId = state.serverId else {
                    return .send(.promptCallFailed("No server ID provided"))
                }

                guard state.allRequiredArgumentsProvided else {
                    return .send(.promptCallFailed("Please provide all required arguments"))
                }

                state.isCallingPrompt = true
                state.promptCallResult = nil

                return .run {
                    [promptName = state.prompt.name, argumentValues = state.argumentValues] send in
                    do {
                        // Convert string arguments to MCP Values
                        let mcpArguments: [String: Value] = argumentValues.compactMapValues {
                            value in
                            value.isEmpty ? nil : .string(value)
                        }

                        let result = try await serverClient.getPrompt(
                            serverId, promptName, mcpArguments)
                        await send(.promptCallCompleted(result))
                    } catch {
                        await send(.promptCallFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.promptCall)

            case .cancelPromptCall:
                state.isCallingPrompt = false
                return .cancel(id: CancelID.promptCall)

            case let .promptCallCompleted(result):
                state.isCallingPrompt = false
                state.promptCallResult = result
                return .none

            case .promptCallFailed:
                state.isCallingPrompt = false
                // For failed calls, we'll set promptCallResult to nil and show the error through other UI
                state.promptCallResult = nil
                return .none

            case let .argumentChanged(name, value):
                state.argumentValues[name] = value
                return .none

            case .dismissResult:
                state.promptCallResult = nil
                return .none
            }
        }
    }
}
