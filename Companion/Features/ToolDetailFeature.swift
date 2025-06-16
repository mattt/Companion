import ComposableArchitecture
import Foundation
import JSONSchema
import MCP

@Reducer
struct ToolDetailFeature {
    @ObservableState
    struct State: Equatable {
        let tool: Tool
        let serverId: String?
        var isCallingTool = false
        var toolCallResult: MCP.CallTool.Result?
        var showingInputSchema = false
        var formInputs: [String: String] = [:]

        init(tool: Tool, serverId: String? = nil) {
            self.tool = tool
            self.serverId = serverId
        }
    }

    private enum CancelID { case toolCall }

    enum Action: Equatable {
        case callToolTapped
        case cancelToolCall
        case toolCallCompleted(MCP.CallTool.Result)
        case toolCallFailed(String)
        case toggleInputSchema
        case dismissResult
        case updateFormInput(String, String)
    }

    @Dependency(\.serverClient) var serverClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .callToolTapped:
                guard let serverId = state.serverId else {
                    return .send(.toolCallFailed("No server ID provided"))
                }

                state.isCallingTool = true
                state.toolCallResult = nil

                return .run { [toolName = state.tool.name, formInputs = state.formInputs] send in
                    do {
                        // Convert form inputs to MCP.Value arguments
                        let arguments = convertFormInputsToArguments(formInputs)
                        let result = try await serverClient.callTool(serverId, toolName, arguments)
                        await send(.toolCallCompleted(result))
                    } catch {
                        await send(.toolCallFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.toolCall)

            case .cancelToolCall:
                state.isCallingTool = false
                return .cancel(id: CancelID.toolCall)

            case let .toolCallCompleted(result):
                state.isCallingTool = false
                state.toolCallResult = result
                return .none

            case .toolCallFailed:
                state.isCallingTool = false
                // For failed calls, we'll set toolCallResult to nil and show the error through other UI
                state.toolCallResult = nil
                return .none

            case .toggleInputSchema:
                state.showingInputSchema.toggle()
                return .none

            case .dismissResult:
                state.toolCallResult = nil
                return .none

            case let .updateFormInput(key, value):
                state.formInputs[key] = value
                return .none
            }
        }
    }

    private func convertFormInputsToArguments(_ formInputs: [String: String]) -> [String: MCP.Value]
    {
        var arguments: [String: MCP.Value] = [:]

        for (key, value) in formInputs {
            if value.isEmpty { continue }

            // Try to parse as different types
            if let intValue = Int(value) {
                arguments[key] = .int(intValue)
            } else if let doubleValue = Double(value) {
                arguments[key] = .double(doubleValue)
            } else if let boolValue = Bool(value) {
                arguments[key] = .bool(boolValue)
            } else {
                arguments[key] = .string(value)
            }
        }

        return arguments
    }
}
