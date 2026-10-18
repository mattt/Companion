import MCP
import SwiftUI

/// Review sheet for a `sampling/createMessage` request.
///
/// The user generates a completion with the configured model,
/// may edit the text (or type a response by hand),
/// then sends it to the server or declines the request.
struct SamplingRequestView: View {
    let request: PendingSamplingRequest
    @Environment(ServerStore.self) private var store

    private var coordinator: ClientFeatureCoordinator { store.featureCoordinator }

    var body: some View {
        @Bindable var request = request

        NavigationStack {
            Form {
                Section("Request") {
                    LabeledContent("Server", value: request.serverName)
                    LabeledContent(
                        "Max tokens", value: "\(request.parameters.maxTokens)")
                    if let temperature = request.parameters.temperature {
                        LabeledContent(
                            "Temperature", value: temperature.formatted())
                    }
                    if let hints = request.parameters.modelPreferences?.hints,
                        !hints.isEmpty
                    {
                        LabeledContent(
                            "Model hints",
                            value: hints.compactMap(\.name).joined(separator: ", "))
                    }
                }

                if let systemPrompt = request.parameters.systemPrompt {
                    Section("System prompt") {
                        Text(systemPrompt)
                            .textSelection(.enabled)
                    }
                }

                Section("Messages") {
                    ForEach(
                        Array(request.parameters.messages.enumerated()), id: \.offset
                    ) { _, message in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.role.rawValue.capitalized)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            Text(SamplingService.promptText(for: [message]))
                                .textSelection(.enabled)
                        }
                    }
                }

                Section {
                    if request.isGenerating {
                        HStack {
                            ProgressView()
                            Text("Generating…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Generate Response") {
                            Task { await coordinator.generate(for: request) }
                        }
                    }

                    if let error = request.generationError {
                        Text(error)
                            .foregroundStyle(.red)
                    }

                    TextEditor(text: $request.generatedText)
                        .font(.body)
                        .frame(minHeight: 120)

                    if let model = request.modelName {
                        LabeledContent("Model", value: model)
                    }
                } header: {
                    Text("Response")
                } footer: {
                    Text("You can edit the generated text, or type a response yourself.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Sampling Request")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Decline", role: .destructive) {
                        coordinator.declineSampling(request)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send Response") {
                        coordinator.approveSampling(request)
                    }
                    .disabled(
                        request.generatedText.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty || request.isGenerating
                    )
                }
            }
        }
        .interactiveDismissDisabled()
        #if os(macOS)
            .frame(minWidth: 520, minHeight: 560)
        #endif
    }
}
