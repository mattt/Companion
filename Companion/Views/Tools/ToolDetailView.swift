import ComposableArchitecture
import MCP
import SwiftUI

struct ToolDetailView: View {
    let store: StoreOf<ToolDetailFeature>

    init(tool: Tool, serverId: String? = nil) {
        self.store = Store(initialState: ToolDetailFeature.State(tool: tool, serverId: serverId)) {
            ToolDetailFeature()
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    if let title = store.tool.annotations.title {
                        Text(title)
                            .font(.title)
                            .fontWeight(.bold)
                            .textSelection(.enabled)

                        Text(store.tool.name)
                            .font(.system(.title3, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .padding(.bottom, 8)
                    } else {
                        Text(store.tool.name)
                            .font(.system(.title, design: .monospaced))
                            .fontWeight(.bold)
                            .textSelection(.enabled)
                    }

                    // Description (if available)
                    if !store.tool.description.isEmpty {
                        Text(store.tool.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }

                // Tool Hints
                ToolHintsView(annotations: store.tool.annotations)

                // Schema
                ToolSchemaView(
                    schema: store.tool.inputSchema,
                    isExpanded: .init(
                        get: { store.showingInputSchema },
                        set: { _ in store.send(.toggleInputSchema) }
                    )
                )

                // Tool Calling
                ToolCallView(store: store)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        #if !os(macOS)
            .navigationTitle(store.tool.annotations.title ?? store.tool.name)
            .navigationBarTitleDisplayMode(.large)
        #endif
    }
}
