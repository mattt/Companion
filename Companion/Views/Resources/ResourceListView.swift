import MCP
import QuickLook
import SwiftUI

private enum ResourceItem: Hashable {
    case resource(Resource)
    case template(Resource.Template)

    var id: String {
        switch self {
        case .resource(let res):
            return res.uri
        case .template(let temp):
            return temp.uriTemplate
        }
    }

    var name: String {
        switch self {
        case .resource(let res):
            return res.name
        case .template(let temp):
            return temp.name
        }
    }

    var displayName: String {
        name
    }

    var uri: String {
        switch self {
        case .resource(let res):
            return res.uri
        case .template(let temp):
            return temp.uriTemplate
        }
    }

    var description: String? {
        switch self {
        case .resource(let res):
            return res.description
        case .template(let temp):
            return temp.description
        }
    }

    var mimeType: String? {
        switch self {
        case .resource(let res):
            return res.mimeType
        case .template(let temp):
            return temp.mimeType
        }
    }
}

struct ResourceListView: View {
    let resources: [Resource]
    let templates: [Resource.Template]
    let serverId: String
    let columnVisibility: NavigationSplitViewVisibility
    @State private var selectedResourceID: String?
    @State private var leftPaneWidth: CGFloat = 350
    @State private var searchText: String = ""

    private var allResources: [ResourceItem] {
        let resourceItems = resources.map { ResourceItem.resource($0) }
        let templateItems = templates.map { ResourceItem.template($0) }
        return resourceItems + templateItems
    }

    private var filteredResources: [ResourceItem] {
        if searchText.isEmpty {
            return allResources.sorted(by: { $0.name < $1.name })
        } else {
            return allResources.filter { item in
                item.name.localizedCaseInsensitiveContains(searchText)
                    || item.uri.localizedCaseInsensitiveContains(searchText)
                    || (item.description?.localizedCaseInsensitiveContains(searchText) ?? false)
                    || (item.mimeType?.localizedCaseInsensitiveContains(searchText) ?? false)
            }.sorted(by: { $0.name < $1.name })
        }
    }

    private var selectedResource: ResourceItem? {
        allResources.first { $0.id == selectedResourceID }
    }

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Select a resource")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Choose a resource from the list to view its content and metadata")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.fill.secondary)
    }

    var body: some View {
        Group {
            #if os(macOS)
                HSplitView {
                    VStack(alignment: .leading, spacing: 0) {
                        if filteredResources.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)

                                Text("No resources")
                                    .font(.title2)
                                    .foregroundColor(.secondary)

                                if searchText.isEmpty {
                                    Text("This server doesn't provide any resources")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                } else {
                                    Text("No resources match your search")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            List(
                                filteredResources,
                                id: \.id,
                                selection: $selectedResourceID
                            ) { resourceItem in
                                ResourceRowView(resource: resourceItem)
                                    .tag(resourceItem.id)
                            }
                            .listStyle(.sidebar)
                            .background(
                                GeometryReader { geo in
                                    WidthPassthroughView(width: geo.size.width) {
                                        newCalculatedWidth in
                                        if newCalculatedWidth > 0
                                            && self.leftPaneWidth != newCalculatedWidth
                                        {
                                            self.leftPaneWidth = newCalculatedWidth
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .frame(minWidth: 250, idealWidth: 350, maxWidth: 400)

                    if let selectedResource = selectedResource {
                        switch selectedResource {
                        case .resource(let resource):
                            ResourceDetailView(resource: resource, serverId: serverId)
                        case .template(let template):
                            ResourceDetailView(template: template, serverId: serverId)
                        }
                    } else if !filteredResources.isEmpty {
                        placeholderView
                    }
                }.toolbar {
                    #if os(macOS)
//                        if #available(macOS 26.0, *) {
//                            ToolbarItemGroup(placement: .navigation) {
//                                FilterToolbar(
//                                    searchText: $searchText,
//                                    placeholder: "Filter resources",
//                                    width: leftPaneWidth,
//                                    isVisible: columnVisibility == .all
//                                        && !(resources.isEmpty && templates.isEmpty)
//                                )
//                            }
//                            .sharedBackgroundVisibility(Visibility.hidden)
//                        } else {
                            ToolbarItemGroup(placement: .navigation) {
                                FilterToolbar(
                                    searchText: $searchText,
                                    placeholder: "Filter resources",
                                    width: leftPaneWidth,
                                    isVisible: columnVisibility == .all
                                        && !(resources.isEmpty && templates.isEmpty)
                                )
                            }
//                        }
                    #endif
                }
            #else
                NavigationStack {
                    List(filteredResources, id: \.id) { resourceItem in
                        NavigationLink(
                            destination: Group {
                                switch resourceItem {
                                case .resource(let resource):
                                    ResourceDetailView(resource: resource, serverId: serverId)
                                case .template(let template):
                                    ResourceDetailView(template: template, serverId: serverId)
                                }
                            }
                        ) {
                            ResourceRowView(resource: resourceItem)
                        }
                    }
                    .navigationTitle("Resources")
                    .navigationBarTitleDisplayMode(.large)
                }
            #endif
        }
        .onAppear {
            if selectedResourceID == nil, let firstResource = allResources.first {
                selectedResourceID = firstResource.id
            }
        }
        .onChange(of: searchText) { _, _ in
            // When search changes, ensure selected resource is still visible
            if let selected = selectedResource,
                !filteredResources.contains(where: { $0.id == selected.id })
            {
                selectedResourceID = filteredResources.first?.id
            } else if selectedResourceID == nil {
                selectedResourceID = filteredResources.first?.id
            }
        }
    }
}

private struct ResourceRowView: View {
    let resource: ResourceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(resource.name)
                .font(.subheadline)
                .fontWeight(.medium)

            Text(resource.uri)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)

            if let description = resource.description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 8) {
                // Resource type indicator
                if case .template = resource {
                    Text("Template")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(3)
                }

                // MIME type badge
                if let mimeType = resource.mimeType {
                    Text(mimeType)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(3)
                }

                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}
