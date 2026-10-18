import SwiftUI

import MCP

struct ToolListView: View {
    let tools: [Tool]
    let serverId: String?
    let columnVisibility: NavigationSplitViewVisibility
    @State private var selectedTool: Tool?
    @State private var leftPaneWidth: CGFloat
    @State private var widthPersistTask: Task<Void, Never>?
    @State private var searchText: String = ""
    @FocusState private var isListFocused: Bool

    init(
        tools: [Tool],
        serverId: String?,
        columnVisibility: NavigationSplitViewVisibility
    ) {
        self.tools = tools
        self.serverId = serverId
        self.columnVisibility = columnVisibility
        _leftPaneWidth = State(initialValue: ListPaneWidth.stored())
    }

    private var filteredTools: [Tool] {
        if searchText.isEmpty {
            return tools.sorted(by: { $0.name < $1.name })
        } else {
            return tools.filter { $0.matchesFilter(searchText) }
                .sorted(by: { $0.name < $1.name })
        }
    }

    private func scheduleWidthPersist(_ width: CGFloat) {
        widthPersistTask?.cancel()
        widthPersistTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            ListPaneWidth.store(width)
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
                            .focused($isListFocused)
                            .onAppear { isListFocused = true }
                            .onMoveCommand { direction in
                                moveSelection(direction)
                            }
                            .background(
                                GeometryReader { geo in
                                    // Use WidthPassthroughView to update leftPaneWidth directly via .task
                                    WidthPassthroughView(width: geo.size.width) {
                                        newCalculatedWidth in
                                        if newCalculatedWidth > 0
                                            && self.leftPaneWidth != newCalculatedWidth
                                        {
                                            self.leftPaneWidth = newCalculatedWidth
                                            self.scheduleWidthPersist(newCalculatedWidth)
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .frame(
                        minWidth: ListPaneWidth.range.lowerBound,
                        idealWidth: leftPaneWidth,
                        maxWidth: ListPaneWidth.range.upperBound)

                    if let selectedTool = selectedTool {
                        ToolDetailView(
                            tool: selectedTool,
                            serverId: serverId
                        )
                        .id(selectedTool.name)
                    } else if !filteredTools.isEmpty {
                        placeholderView
                    }
                }.toolbar {
                    // Omit the item entirely when the sidebar is hidden.
                    // Fading the field out would leave its empty glass
                    // capsule behind in the toolbar on macOS 26 and later.
                    if !tools.isEmpty, columnVisibility == .all {
                        ToolbarItemGroup(placement: .navigation) {
                            FilterToolbar(
                                searchText: $searchText,
                                placeholder: "Filter tools",
                                width: leftPaneWidth
                            )
                        }
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
        .onDisappear {
            ListPaneWidth.store(leftPaneWidth)
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

    #if os(macOS)
        private func moveSelection(_ direction: MoveCommandDirection) {
            guard !filteredTools.isEmpty else { return }

            let currentIndex = selectedTool.flatMap { selected in
                filteredTools.firstIndex { $0.name == selected.name }
            }

            let nextIndex: Int
            switch direction {
            case .up:
                nextIndex = max((currentIndex ?? 0) - 1, 0)
            case .down:
                nextIndex = min((currentIndex ?? -1) + 1, filteredTools.count - 1)
            default:
                return
            }

            selectedTool = filteredTools[nextIndex]
        }
    #endif
}

private struct ToolRowView: View {
    let tool: Tool
    @Binding var selectedTool: Tool?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let title = tool.displayTitle {
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

                    if let description = tool.description, !description.isEmpty {
                        Text(description)
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

extension MCP.Tool {
    /// Whether the tool matches a filter string by name, title, or description.
    func matchesFilter(_ searchText: String) -> Bool {
        name.localizedCaseInsensitiveContains(searchText)
            || displayTitle?.localizedCaseInsensitiveContains(searchText) == true
            || description?.localizedCaseInsensitiveContains(searchText) == true
    }
}
