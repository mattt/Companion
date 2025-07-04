import SwiftUI

import MCP

struct ToolListView: View {
    let tools: [Tool]
    let serverId: String?
    let columnVisibility: NavigationSplitViewVisibility
    @State private var selectedTool: Tool?
    @State private var leftPaneWidth: CGFloat = 350
    @State private var searchText: String = ""

    private var filteredTools: [Tool] {
        if searchText.isEmpty {
            return tools.sorted(by: { $0.name < $1.name })
        } else {
            return tools.filter { tool in
                tool.name.localizedCaseInsensitiveContains(searchText)
                    || tool.description.localizedCaseInsensitiveContains(searchText) == true
                    || tool.annotations.title?.localizedCaseInsensitiveContains(searchText)
                        == true
            }.sorted(by: { $0.name < $1.name })
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Select a tool")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Choose a tool from the list to view its details and input schema")
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
                        if filteredTools.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "wrench.and.screwdriver")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)

                                Text("No tools")
                                    .font(.title2)
                                    .foregroundColor(.secondary)

                                if searchText.isEmpty {
                                    Text("This server doesn't provide any tools")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                } else {
                                    Text("No tools match your search")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            List(selection: $selectedTool) {
                                ForEach(filteredTools, id: \.name) { tool in
                                    ToolRowView(tool: tool, selectedTool: $selectedTool)
                                        .tag(tool)
                                }
                            }
                            .listStyle(.sidebar)
                            .background(
                                GeometryReader { geo in
                                    // Use WidthPassthroughView to update leftPaneWidth directly via .task
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

                    if let selectedTool = selectedTool {
                        ToolDetailView(
                            tool: selectedTool,
                            serverId: serverId
                        )
                    } else if !filteredTools.isEmpty {
                        placeholderView
                    }
                }.toolbar {
                    if !tools.isEmpty {
                        #if os(macOS)
//                        if #available(macOS 26.0, *) {
//                            ToolbarItemGroup(placement: .navigation) {
//                                FilterToolbar(
//                                    searchText: $searchText,
//                                    placeholder: "Filter tools",
//                                    width: leftPaneWidth,
//                                    isVisible: columnVisibility == .all
//                                )
//                            }
//                            .sharedBackgroundVisibility(Visibility.hidden)
//                        } else {
                            ToolbarItemGroup(placement: .navigation) {
                                FilterToolbar(
                                    searchText: $searchText,
                                    placeholder: "Filter tools",
                                    width: leftPaneWidth,
                                    isVisible: columnVisibility == .all
                                )
                            }
//                        }
                        #endif
                    }
                }
            #else
                NavigationStack {
                    List {
                        ForEach(filteredTools, id: \.name) { tool in
                            NavigationLink(
                                destination: ToolDetailView(
                                    tool: tool,
                                    serverId: serverId
                                )
                            ) {
                                ToolRowView(tool: tool, selectedTool: $selectedTool)
                            }
                        }
                    }
                    .navigationTitle("Tools")
                    .navigationBarTitleDisplayMode(.large)
                }
            #endif
        }
        .onAppear {
            if selectedTool == nil, let firstTool = tools.first {
                selectedTool = firstTool
            }
        }
        .onChange(of: searchText, initial: true) { _, newValue in
            // When search changes, ensure selected tool is still visible
            if let selected = selectedTool,
                !filteredTools.contains(where: { $0.name == selected.name })
            {
                selectedTool = filteredTools.first
            } else if selectedTool == nil {
                selectedTool = filteredTools.first
            }
        }
    }
}

private struct ToolRowView: View {
    let tool: Tool
    @Binding var selectedTool: Tool?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let title = tool.annotations.title {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(tool.name)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else {
                        Text(tool.name)
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(.medium)
                    }

                    if !tool.description.isEmpty {
                        Text(tool.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    if let destructive = tool.annotations.destructiveHint, destructive {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(selectedTool?.name == tool.name ? .primary : .red)
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
