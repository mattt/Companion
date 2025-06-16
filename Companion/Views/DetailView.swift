import ComposableArchitecture
import MCP
import SwiftUI

struct DetailView: View {
    let selection: SidebarSelection?
    let server: Server?
    let store: StoreOf<ServerDetailFeature>?
    let columnVisibility: NavigationSplitViewVisibility

    var body: some View {
        Group {
            if let selection = selection,
                let server = server
            {
                let serverId = server.id

                if let section = selection.section {
                    if let itemId = selection.itemId {
                        // Individual item selected
                        switch section {
                        case .prompts:
                            if let prompt = server.availablePrompts.first(where: { $0.name == itemId }) {
                                PromptDetailView(prompt: prompt, serverId: serverId)
                            } else {
                                EmptyStateView()
                            }
                        case .resources:
                            if let resource = server.availableResources.first(where: { $0.uri == itemId }) {
                                ResourceDetailView(resource: resource, serverId: serverId)
                            } else if let template = server.resourceTemplates.first(where: {
                                $0.uriTemplate == itemId
                            }) {
                                ResourceDetailView(template: template, serverId: serverId)
                            } else {
                                EmptyStateView()
                            }
                        case .tools:
                            if let tool = server.availableTools.first(where: { $0.name == itemId }) {
                                ToolDetailView(
                                    tool: tool,
                                    serverId: server.id
                                )
                            } else {
                                EmptyStateView()
                            }
                        }
                    } else {
                        // Collection selected
                        switch section {
                        case .prompts:
                            PromptListView(
                                prompts: server.availablePrompts,
                                serverId: serverId,
                                columnVisibility: columnVisibility)
                        case .resources:
                            ResourceListView(
                                resources: server.availableResources,
                                templates: server.resourceTemplates,
                                serverId: serverId,
                                columnVisibility: columnVisibility)
                        case .tools:
                            ToolListView(
                                tools: server.availableTools,
                                serverId: serverId,
                                columnVisibility: columnVisibility
                            )
                        }
                    }
                } else {
                    // Server selected
                    if let store = store {
                        ServerDetailView(store: store)
                    } else {
                        Text("Server not found")
                    }
                }
            } else {
                EmptyStateView()
            }
        }
    }
}
