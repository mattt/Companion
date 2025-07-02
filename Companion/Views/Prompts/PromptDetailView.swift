import ComposableArchitecture
import MCP
import SwiftUI

struct PromptDetailView: View {
    let store: StoreOf<PromptDetailFeature>

    init(prompt: Prompt, serverId: String? = nil) {
        self.store = Store(
            initialState: PromptDetailFeature.State(prompt: prompt, serverId: serverId)
        ) {
            PromptDetailFeature()
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    // Title
                    #if os(macOS)
                        Text(store.prompt.name)
                            .font(.title)
                            .fontWeight(.bold)
                            .textSelection(.enabled)
                    #endif

                    // Description (if available)
                    if let description = store.prompt.description, !description.isEmpty {
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

                    if let arguments = store.prompt.arguments, !arguments.isEmpty {
                        ForEach(arguments, id: \.name) { argument in
                            ArgumentInputView(
                                argument: argument,
                                value: store.argumentValues[argument.name] ?? "",
                                onValueChange: { newValue in
                                    store.send(.argumentChanged(argument.name, newValue))
                                }
                            )
                        }
                    } else {
                        Text("This prompt has no arguments")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    if store.isCallingPrompt {
                        Button(action: { store.send(.cancelPromptCall) }) {
                            Label("Cancel", systemImage: "xmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    } else {
                        Button(action: { store.send(.usePromptTapped) }) {
                            Text("Submit")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(store.serverId == nil)
                    }

                    // Prompt Result
                    if let result = store.promptCallResult {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Success", systemImage: "checkmark.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.green)

                                Spacer()

                                Button("Clear") {
                                    store.send(.dismissResult)
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
        .navigationTitle(store.prompt.name)
    }

    private func formatMessageContent(_ content: Prompt.Message.Content) -> String {
        switch content {
        case .text(let text):
            return text
        case .image(let data, let mimeType):
            return "[Image: \(mimeType), \(data.count) bytes]"
        case .audio(let data, let mimeType):
            return "[Audio: \(mimeType), \(data.count) bytes]"
        case .resource(let uri, _, let text, _):
            if let text = text {
                return "[Resource: \(uri)]\n\(text)"
            } else {
                return "[Resource: \(uri)]"
            }
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
