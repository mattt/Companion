import MCP
import SwiftUI

struct ToolDetailView: View {
    let tool: Tool
    let serverId: String?

    @State private var showingInputSchema = false
    @State private var showingOutputSchema = false

    init(tool: Tool, serverId: String? = nil) {
        self.tool = tool
        self.serverId = serverId
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    if tool.icons != nil {
                        IconView(icons: tool.icons, size: 40, fallbackSystemImage: "hammer")
                    }
                    if let title = tool.displayTitle {
                        Text(title)
                            .font(.title)
                            .fontWeight(.bold)
                            .textSelection(.enabled)

                        Text(tool.name)
                            .font(.system(.title3, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .padding(.bottom, 8)
                    } else {
                        Text(tool.name)
                            .font(.system(.title, design: .monospaced))
                            .fontWeight(.bold)
                            .textSelection(.enabled)
                    }

                    // Description (if available)
                    if let description = tool.description, !description.isEmpty {
                        Text(description)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }

                // Tool Hints
                ToolHintsView(annotations: tool.annotations)

                // Schema
                ToolSchemaView(
                    schema: tool.jsonSchema,
                    isExpanded: $showingInputSchema
                )

                if tool.outputJSONSchema != nil {
                    ToolSchemaView(
                        schema: tool.outputJSONSchema,
                        title: "Output Schema",
                        isExpanded: $showingOutputSchema
                    )
                }

                // Tool Calling
                ToolCallView(tool: tool, serverId: serverId)
                    .id("\(serverId ?? "")-\(tool.name)")
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .softTopScrollEdgeEffect()
        #if !os(macOS)
            .navigationTitle(tool.displayTitle ?? tool.name)
            .navigationBarTitleDisplayMode(.large)
        #endif
    }
}
