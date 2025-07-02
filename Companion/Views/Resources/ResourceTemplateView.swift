import ComposableArchitecture
import MCP
import SwiftUI

struct ResourceTemplateView: View {
    let store: StoreOf<ResourceDetailFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Template Usage", systemImage: "text.bubble")
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
                VStack(alignment: .leading, spacing: 12) {
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
            } else {
                // Default template explanation
                VStack(spacing: 12) {
                    Image(systemName: "text.bubble")
                        .font(.largeTitle)
                        .foregroundColor(.orange)

                    Text("Resource Template")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text(
                        "Fill in the parameters above and click 'Read Template' to load the resource content."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .background(.fill.tertiary)
                .cornerRadius(8)
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

            // Read template section with error handling
            readTemplateSection()
        }
    }

    @ViewBuilder
    private func readTemplateSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Read template button and status
            HStack {
                if store.isReadingResource {
                    Button("Cancel", action: { store.send(.cancelResourceRead) })
                        .foregroundColor(.red)
                } else {
                    Button(action: { store.send(.readTemplateTapped) }) {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("Read Template")
                        }
                    }
                    .disabled(store.serverId == nil)
                }

                Spacer()

                if store.isReadingResource {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 16, height: 16)
                        Text("Loading content...")
                            .foregroundColor(.secondary)
                    }
                } else if store.resourceReadResult != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .frame(width: 16, height: 16)
                        Text("Content loaded")
                            .foregroundColor(.secondary)
                    }
                } else if store.errorMessage != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .frame(width: 16, height: 16)
                        Text("Loading failed")
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Error details (if any)
            if let error = store.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Error Details")
                        .font(.caption)
                        .foregroundColor(.primary)

                    ScrollView {
                        Text(error)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.red)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
            }
        }
        .padding()
        #if os(macOS)
            .background(Color(NSColor.controlBackgroundColor))
        #else
            .background(Color(UIColor.secondarySystemBackground))
        #endif
        .cornerRadius(8)
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
