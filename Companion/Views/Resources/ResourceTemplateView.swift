import ComposableArchitecture
import MCP
import SwiftUI

struct ResourceTemplateView: View {
    let store: StoreOf<ResourceDetailFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Content", systemImage: "text.bubble")
                .font(.headline)

            // Template arguments form
            templateArgumentsForm()

            // Preview section
            if store.isReadingResource {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading content...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .background(.fill.tertiary)
                .cornerRadius(8)
            } else if let result = store.resourceReadResult {
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
                            store.send(.dismissResult)
                        }
                        .font(.caption)
                    }

                    // Show resolved URI
                    if let template = store.template {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Resolved URI")
                                .font(.caption)
                                .fontWeight(.medium)

                            let resolvedUri = substituteTemplateArguments(
                                template: template.uriTemplate,
                                arguments: store.templateArguments
                            )

                            Text(resolvedUri)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.fill.tertiary)
                                .cornerRadius(6)
                                .textSelection(.enabled)
                        }
                    }

                    // Show content
                    let content = ResourceContent(
                        text: extractTextContent(from: result.contents),
                        data: extractBinaryContent(from: result.contents)
                    )
                    ContentPreviewView(content: content, mimeType: store.template?.mimeType)
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
            let parameters = extractTemplateParameters(from: store.template?.uriTemplate ?? "")

            if !parameters.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Template Parameters")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(parameters, id: \.self) { parameter in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(parameter)
                                .font(.caption)
                                .fontWeight(.medium)

                            TextField(
                                "Enter \(parameter)",
                                text: Binding(
                                    get: { store.templateArguments[parameter] ?? "" },
                                    set: { store.send(.updateTemplateArgument(parameter, $0)) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding()
                .background(.fill.quaternary)
                .cornerRadius(8)
            }

            // Submit button
            if store.isReadingResource {
                Button(action: { store.send(.cancelResourceRead) }) {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button(action: { store.send(.readTemplateTapped) }) {
                    Text("Submit")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(store.serverId == nil || !allParametersHaveValues)
            }
        }
    }

    private var allParametersHaveValues: Bool {
        let parameters = extractTemplateParameters(from: store.template?.uriTemplate ?? "")

        for parameter in parameters {
            let value = store.templateArguments[parameter] ?? ""
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
        }

        return true
    }

    private func extractTemplateParameters(from template: String) -> [String] {
        let pattern = #"\{([^}]+)\}"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(template.startIndex..<template.endIndex, in: template)
        let matches = regex.matches(in: template, range: range)

        return matches.compactMap { match in
            if let range = Range(match.range(at: 1), in: template) {
                return String(template[range])
            }
            return nil
        }
    }

    private func substituteTemplateArguments(template: String, arguments: [String: String])
        -> String
    {
        var result = template
        for (key, value) in arguments {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
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
