import MCP
import SwiftUI
import URITemplate

struct ResourceTemplateView: View {
    let template: Resource.Template
    let serverId: String?

    @Environment(ServerStore.self) private var serverStore
    @State private var isReadingResource = false
    @State private var resourceReadResult: MCP.ReadResource.Result?
    @State private var errorMessage: String?
    @State private var templateArguments: [String: String] = [:]
    @State private var readTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Read Templated Resource", systemImage: "doc.text")
                .font(.headline)

            // Template arguments form
            templateArgumentsForm()

            // Preview section
            if isReadingResource {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading content...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .background(.fill.tertiary)
                .cornerRadius(8)
            } else if let result = resourceReadResult {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(
                            "Success",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundColor(.green)
                        .font(.headline)

                        Spacer()

                        Button("Clear") {
                            resourceReadResult = nil
                        }
                        .font(.caption)
                    }

                    // Show resolved URI
                    VStack(alignment: .leading, spacing: 4) {
                            Text("Resolved URI")
                                .font(.caption)
                                .fontWeight(.medium)

                            let resolvedUri: String = {
                                do {
                                    let uriTemplate = try URITemplate(template.uriTemplate)
                                    let variables = templateArguments.mapValues { VariableValue.string($0) }
                                    return uriTemplate.expand(with: variables)
                                } catch {
                                    return "Invalid template: \(error.localizedDescription)"
                                }
                            }()

                            Text(resolvedUri)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.fill.tertiary)
                                .cornerRadius(6)
                                .textSelection(.enabled)
                    }

                    // Show content
                    let content = ResourceContent(
                        text: extractTextContent(from: result.contents),
                        data: extractBinaryContent(from: result.contents)
                    )
                    ContentPreviewView(content: content, mimeType: template.mimeType)
                }
                .padding()
                #if os(visionOS)
                    .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
                #else
                    .background(.fill.quaternary)
                    .cornerRadius(8)
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

    @ViewBuilder
    private func templateArgumentsForm() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Parse template parameters from URI template
            let parameters = extractTemplateParameters(from: template.uriTemplate)

            if !parameters.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Template Parameters")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(parameters, id: \.self) { parameter in
                        TemplateParameterField(
                            parameter: parameter,
                            value: Binding(
                                get: { templateArguments[parameter] ?? "" },
                                set: { templateArguments[parameter] = $0 }
                            ),
                            completionProvider: completionProvider(for: parameter)
                        )
                    }
                }
                .padding()
                .background(.fill.quaternary)
                .cornerRadius(8)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Submit button
            if isReadingResource {
                Button(action: { cancelResourceRead() }) {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button(action: { readTemplate() }) {
                    Text("Submit")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(serverId == nil || !allParametersHaveValues)
            }
        }
    }


    // MARK: - Actions

    private func readTemplate() {
        guard let serverId else {
            errorMessage = "No server ID provided"
            return
        }

        let resourceUri: String
        do {
            let uriTemplate = try URITemplate(template.uriTemplate)
            let variables = templateArguments.mapValues { VariableValue.string($0) }
            resourceUri = uriTemplate.expand(with: variables)
        } catch {
            errorMessage = "Invalid URI template: \(error.localizedDescription)"
            return
        }

        isReadingResource = true
        resourceReadResult = nil
        errorMessage = nil

        readTask = Task {
            do {
                let result = try await serverStore.readResource(
                    serverID: serverId, uri: resourceUri)
                guard !Task.isCancelled else { return }
                resourceReadResult = result
            } catch is CancellationError {
                // Read was cancelled.
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isReadingResource = false
        }
    }

    private func cancelResourceRead() {
        readTask?.cancel()
        readTask = nil
        isReadingResource = false
    }

    private var allParametersHaveValues: Bool {
        let parameters = extractTemplateParameters(from: template.uriTemplate)

        for parameter in parameters {
            let value = templateArguments[parameter] ?? ""
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
        }

        return true
    }

    private func completionProvider(
        for parameter: String
    ) -> ((String) async -> [String])? {
        guard let serverId,
            serverStore.server(id: serverId)?.capabilities?.completions != nil
        else { return nil }

        let resourceURI = template.uriTemplate
        let context = templateArguments.filter {
            $0.key != parameter && !$0.value.isEmpty
        }
        let store = serverStore
        return { value in
            let completion = try? await store.completeResourceArgument(
                serverID: serverId,
                resourceURI: resourceURI,
                argumentName: parameter,
                argumentValue: value,
                context: context.isEmpty ? nil : context
            )
            return completion?.values ?? []
        }
    }

    private func extractTemplateParameters(from template: String) -> [String] {
        let uriTemplate = try? URITemplate(template)
        return uriTemplate?.variables ?? []
    }

    private func extractTextContent(from contents: [Resource.Content]) -> String? {
        let textContents: [String] = contents.compactMap { content in
            if let text = content.text {
                return text
            } else if content.blob != nil {
                return "[Binary Resource: \(content.uri)]"
            }
            return nil
        }

        return textContents.isEmpty ? nil : textContents.joined(separator: "\n\n")
    }

    private func extractBinaryContent(from contents: [Resource.Content]) -> Data? {
        for content in contents {
            if let blob = content.blob {
                return Data(base64Encoded: blob)
            }
        }
        return nil
    }
}

private struct TemplateParameterField: View {
    let parameter: String
    @Binding var value: String
    var completionProvider: ((String) async -> [String])?

    @State private var suggestions: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(parameter)
                .font(.caption)
                .fontWeight(.medium)

            TextField("Enter \(parameter)", text: $value)
                .textFieldStyle(.roundedBorder)

            if !suggestions.isEmpty {
                CompletionSuggestionsView(suggestions: suggestions) { suggestion in
                    value = suggestion
                }
            }
        }
        .task(id: value) {
            guard let completionProvider else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            suggestions = await completionProvider(value)
        }
    }
}
