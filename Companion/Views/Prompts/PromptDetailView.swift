import MCP
import SwiftUI

struct PromptDetailView: View {
    let prompt: Prompt
    let serverId: String?

    @Environment(ServerStore.self) private var serverStore
    @State private var isCallingPrompt = false
    @State private var promptCallResult: MCP.GetPrompt.Result?
    @State private var errorMessage: String?
    @State private var argumentValues: [String: String]
    @State private var callTask: Task<Void, Never>?

    init(prompt: Prompt, serverId: String? = nil) {
        self.prompt = prompt
        self.serverId = serverId
        _argumentValues = State(
            initialValue: Dictionary(
                uniqueKeysWithValues: (prompt.arguments ?? []).map { ($0.name, "") }
            )
        )
    }

    private var allRequiredArgumentsProvided: Bool {
        guard let arguments = prompt.arguments, !arguments.isEmpty else { return true }

        for argument in arguments where argument.required == true {
            if argumentValues[argument.name]?.isEmpty != false {
                return false
            }
        }
        return true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    // Title
                    #if os(macOS)
                        Text(prompt.name)
                            .font(.title)
                            .fontWeight(.bold)
                            .textSelection(.enabled)
                    #endif

                    // Description (if available)
                    if let description = prompt.description, !description.isEmpty {
                        Text(description)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }

                // Interactive Form
                VStack(alignment: .leading, spacing: 12) {
                    Label("Use Prompt", systemImage: "play.rectangle")
                        .font(.headline)

                    if let arguments = prompt.arguments, !arguments.isEmpty {
                        ForEach(arguments, id: \.name) { argument in
                            ArgumentInputView(
                                argument: argument,
                                value: argumentValues[argument.name] ?? "",
                                onValueChange: { newValue in
                                    argumentValues[argument.name] = newValue
                                }
                            )
                        }
                    } else {
                        Text("This prompt has no arguments")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    if isCallingPrompt {
                        Button(action: { cancelPromptCall() }) {
                            Label("Cancel", systemImage: "xmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    } else {
                        Button(action: { usePrompt() }) {
                            Text("Submit")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(serverId == nil)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Prompt Result
                    if let result = promptCallResult {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Success", systemImage: "checkmark.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.green)

                                Spacer()

                                Button("Clear") {
                                    promptCallResult = nil
                                }
                                .font(.caption)
                            }

                            if let description = result.description {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Description:")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text(description)
                                        .font(.body)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding()
                                        .background(.fill.tertiary)
                                        .cornerRadius(8)
                                        .textSelection(.enabled)
                                }
                            }

                            if !result.messages.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Messages (\(result.messages.count)):")
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    ForEach(Array(result.messages.enumerated()), id: \.offset) {
                                        index, message in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Message \(index + 1) - \(message.role.rawValue)")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(.secondary)

                                            Text(formatMessageContent(message.content))
                                                .font(.system(.body, design: .monospaced))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding()
                                                .background(.fill.tertiary)
                                                .cornerRadius(8)
                                                .textSelection(.enabled)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        #if os(visionOS)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        #else
                            .background(.fill.secondary)
                            .cornerRadius(10)
                        #endif
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                #if os(visionOS)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                #else
                    .background(.fill.secondary)
                    .cornerRadius(10)
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(prompt.name)
    }


    // MARK: - Actions

    private func usePrompt() {
        guard let serverId else {
            errorMessage = "No server ID provided"
            return
        }

        guard allRequiredArgumentsProvided else {
            errorMessage = "Please provide all required arguments"
            return
        }

        isCallingPrompt = true
        promptCallResult = nil
        errorMessage = nil

        let arguments = argumentValues.filter { !$0.value.isEmpty }
        let promptName = prompt.name

        callTask = Task {
            do {
                let result = try await serverStore.getPrompt(
                    serverID: serverId, name: promptName, arguments: arguments)
                guard !Task.isCancelled else { return }
                promptCallResult = result
            } catch is CancellationError {
                // Call was cancelled.
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isCallingPrompt = false
        }
    }

    private func cancelPromptCall() {
        callTask?.cancel()
        callTask = nil
        isCallingPrompt = false
    }

    private func formatMessageContent(_ content: Prompt.Message.Content) -> String {
        switch content {
        case .text(let text):
            return text
        case .image(let data, let mimeType):
            return "[Image: \(mimeType), \(data.count) bytes]"
        case .audio(let data, let mimeType):
            return "[Audio: \(mimeType), \(data.count) bytes]"
        case .resource(let resource, _, _):
            if let text = resource.text {
                return "[Resource: \(resource.uri)]\n\(text)"
            } else {
                return "[Resource: \(resource.uri)]"
            }
        case .resourceLink(let uri, let name, _, _, _, _):
            return "[Resource link: \(name)] \(uri)"
        }
    }
}

struct ArgumentInputView: View {
    let argument: Prompt.Argument
    let value: String
    let onValueChange: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(argument.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if argument.required == true {
                    Text("*")
                        .foregroundColor(.red)
                        .fontWeight(.bold)
                }

                Spacer()

                Text(argument.required == true ? "Required" : "Optional")
                    .font(.caption)
                    .foregroundColor(
                        argument.required == true ? .red : .secondary)
            }

            if let description = argument.description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            TextField(
                "Enter \(argument.name)",
                text: Binding(
                    get: { value },
                    set: onValueChange
                )
            )
            .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
