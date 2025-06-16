import SwiftUI
import MCP
import JSONSchema

struct ToolSchemaView: View {
    let schema: JSONSchema?
    @Binding var isExpanded: Bool
    
    var body: some View {
        if schema != nil {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: { isExpanded.toggle() }) {
                    HStack {
                        Label(
                            "Input Schema",
                            systemImage: "chevron.left.forwardslash.chevron.right"
                        )
                        .font(.headline)

                        Spacer()

                        Image(
                            systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if isExpanded, let schema = schema {
                    Text(formatSchema(schema))
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.fill.tertiary)
                        .cornerRadius(8)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.fill.secondary)
            .cornerRadius(10)
        }
    }
    
    private func formatSchema(_ schema: JSONSchema) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(schema)
            return String(data: data, encoding: .utf8) ?? "Unable to format schema"
        } catch {
            return "Error formatting schema: \(error.localizedDescription)"
        }
    }
}

struct ToolSchemaViewSimple: View {
    let schema: JSONSchema?
    
    var body: some View {
        if schema != nil {
            VStack(alignment: .leading, spacing: 20) {
                if let schema = schema {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(formatSchema(schema))
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.fill.tertiary)
                            .cornerRadius(8)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                Text("No Schema")
                    .font(.title2)
                    .foregroundColor(.secondary)

                Text("This tool does not require input parameters")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
    
    private func formatSchema(_ schema: JSONSchema) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(schema)
            return String(data: data, encoding: .utf8) ?? "Unable to format schema"
        } catch {
            return "Error formatting schema: \(error.localizedDescription)"
        }
    }
}
