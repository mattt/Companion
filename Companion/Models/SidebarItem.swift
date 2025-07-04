import Foundation
import MCP

// MARK: - Sidebar Item Types
enum SidebarItem: Hashable, Identifiable, Equatable {
    case server(Server)
    case prompts(serverId: String, prompts: [MCP.Prompt])
    case resources(serverId: String, resources: [MCP.Resource], templates: [MCP.Resource.Template])
    case tools(serverId: String, tools: [MCP.Tool])
    case prompt(MCP.Prompt)
    case resource(MCP.Resource)
    case resourceTemplate(MCP.Resource.Template)
    case tool(MCP.Tool)

    var id: String {
        switch self {
        case .server(let server):
            return server.id
        case .prompts(let serverId, _):
            return "\(serverId)-prompts"
        case .resources(let serverId, _, _):
            return "\(serverId)-resources"
        case .tools(let serverId, _):
            return "\(serverId)-tools"
        case .prompt(let prompt):
            return prompt.name
        case .resource(let resource):
            return resource.uri
        case .resourceTemplate(let template):
            return template.uriTemplate
        case .tool(let tool):
            return tool.name
        }
    }

    var name: String {
        switch self {
        case .server(let server):
            return server.name
        case .prompts:
            return "Prompts"
        case .resources:
            return "Resources"
        case .tools:
            return "Tools"
        case .prompt(let prompt):
            return prompt.name
        case .resource(let resource):
            return resource.name.nonempty ?? resource.uri
        case .resourceTemplate(let template):
            return template.name.nonempty ?? template.uriTemplate
        case .tool(let tool):
            return tool.name
        }
    }

    var children: [SidebarItem]? {
        switch self {
        case .server(let server):
            // Only show children when server is connected
            guard server.status == .connected else { return nil }
            
            var items: [SidebarItem] = []
            if server.capabilities?.prompts != nil {
                items.append(.prompts(serverId: server.id, prompts: server.availablePrompts))
            }
            if server.capabilities?.resources != nil {
                items.append(
                    .resources(
                        serverId: server.id,
                        resources: server.availableResources,
                        templates: server.availableResourceTemplates
                    ))
            }
            if server.capabilities?.tools != nil {
                items.append(.tools(serverId: server.id, tools: server.availableTools))
            }
            return items.isEmpty ? nil : items
        case .prompts(_, let prompts):
            return prompts.isEmpty ? nil : prompts.map { .prompt($0) }
        case .resources(_, let resources, let templates):
            var items: [SidebarItem] = resources.map { .resource($0) }
            items.append(contentsOf: templates.map { .resourceTemplate($0) })
            return items.isEmpty ? nil : items
        case .tools(_, let tools):
            return tools.isEmpty ? nil : tools.map { .tool($0) }
        case .prompt, .resource, .resourceTemplate, .tool:
            return nil
        }
    }
}

// MARK: - Sidebar Selection
enum SidebarSection: Hashable, Equatable {
    case prompts
    case resources
    case tools
}

struct SidebarSelection: Hashable, Equatable {
    let serverId: String
    let section: SidebarSection?
    let itemId: String?

    init(serverId: String, section: SidebarSection? = nil, itemId: String? = nil) {
        self.serverId = serverId
        self.section = section
        self.itemId = itemId
    }

    // Convenience initializers
    static func server(_ server: Server) -> SidebarSelection {
        SidebarSelection(serverId: server.id)
    }

    static func prompts(serverId: String) -> SidebarSelection {
        SidebarSelection(serverId: serverId, section: .prompts)
    }

    static func resources(serverId: String) -> SidebarSelection {
        SidebarSelection(serverId: serverId, section: .resources)
    }

    static func tools(serverId: String) -> SidebarSelection {
        SidebarSelection(serverId: serverId, section: .tools)
    }

    static func prompt(serverId: String, promptName: String) -> SidebarSelection {
        SidebarSelection(serverId: serverId, section: .prompts, itemId: promptName)
    }

    static func resource(serverId: String, resourceUri: String) -> SidebarSelection {
        SidebarSelection(serverId: serverId, section: .resources, itemId: resourceUri)
    }

    static func tool(serverId: String, toolName: String) -> SidebarSelection {
        SidebarSelection(serverId: serverId, section: .tools, itemId: toolName)
    }
}
