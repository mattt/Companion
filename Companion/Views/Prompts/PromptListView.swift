import MCP
import SwiftUI

struct PromptListView: View {
    let prompts: [Prompt]
    let serverId: String?
    let columnVisibility: NavigationSplitViewVisibility
    @State private var selectedPrompt: Prompt?
    @State private var leftPaneWidth: CGFloat = 350
    @State private var searchText: String = ""

    private var filteredPrompts: [Prompt] {
        if searchText.isEmpty {
            return prompts.sorted(by: { $0.name < $1.name })
        } else {
            return prompts.filter { prompt in
                prompt.name.localizedCaseInsensitiveContains(searchText)
                    || (prompt.description?.localizedCaseInsensitiveContains(searchText)
                        ?? false)
            }.sorted(by: { $0.name < $1.name })
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Select a prompt")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Choose a prompt from the list to view its details and test with arguments")
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
                        if filteredPrompts.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "text.bubble")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)

                                Text("No prompts")
                                    .font(.title2)
                                    .foregroundColor(.secondary)

                                if searchText.isEmpty {
                                    Text("This server doesn't provide any prompts")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                } else {
                                    Text("No prompts match your search")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            List(selection: $selectedPrompt) {
                                ForEach(filteredPrompts, id: \.name) { prompt in
                                    PromptRowView(prompt: prompt)
                                        .tag(prompt)
                                }
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

                    if let selectedPrompt = selectedPrompt {
                        PromptDetailView(prompt: selectedPrompt, serverId: serverId)
                    } else if !filteredPrompts.isEmpty {
                        placeholderView
                    }
                }.toolbar {
                    #if os(macOS)
//                        if #available(macOS 26.0, *) {
//                            ToolbarItemGroup(placement: .navigation) {
//                                FilterToolbar(
//                                    searchText: $searchText,
//                                    placeholder: "Filter prompts",
//                                    width: leftPaneWidth,
//                                    isVisible: columnVisibility == .all && !prompts.isEmpty
//                                )
//                            }
//                            .sharedBackgroundVisibility(Visibility.hidden)
//                        } else {
                            ToolbarItemGroup(placement: .navigation) {
                                FilterToolbar(
                                    searchText: $searchText,
                                    placeholder: "Filter prompts",
                                    width: leftPaneWidth,
                                    isVisible: columnVisibility == .all && !prompts.isEmpty
                                )
                            }
//                        }
                    #endif
                }
            #else
                NavigationStack {
                    List {
                        ForEach(filteredPrompts, id: \.name) { prompt in
                            NavigationLink(
                                destination: PromptDetailView(prompt: prompt, serverId: serverId)
                            ) {
                                PromptRowView(prompt: prompt)
                            }
                        }
                    }
                    .navigationTitle("Prompts")
                    .navigationBarTitleDisplayMode(.large)
                }
            #endif
        }
        .onAppear {
            if selectedPrompt == nil, let firstPrompt = prompts.first {
                selectedPrompt = firstPrompt
            }
        }
        .onChange(of: searchText) { _, _ in
            // When search changes, ensure selected prompt is still visible
            if let selected = selectedPrompt,
                !filteredPrompts.contains(where: { $0.name == selected.name })
            {
                selectedPrompt = filteredPrompts.first
            } else if selectedPrompt == nil {
                selectedPrompt = filteredPrompts.first
            }
        }
    }
}

struct PromptRowView: View {
    let prompt: Prompt

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(prompt.name)
                .font(.subheadline)
                .fontWeight(.medium)

            if let description = prompt.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            if let arguments = prompt.arguments, !arguments.isEmpty {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 4)
                {
                    GridRow {
                        Text("Args:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .gridColumnAlignment(.leading)

                        FlowLayout(spacing: 4) {
                            ForEach(arguments, id: \.name) { argument in
                                Text(argument.name)
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.secondary.opacity(0.15))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(
                                                argument.required == true
                                                    ? Color.secondary.opacity(0.3)
                                                    : Color.secondary.opacity(0.2),
                                                lineWidth: argument.required == true ? 1 : 0.5
                                            )
                                    )
                            }
                        }
                        .gridColumnAlignment(.leading)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ArgumentTokenView: View {
    let argument: Prompt.Argument

    var body: some View {
        Text(argument.name)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        argument.required == true
                            ? Color.accentColor.opacity(0.8)
                            : Color.secondary.opacity(0.3)
                    )
            )
            .foregroundColor(
                argument.required == true
                    ? .white
                    : .primary
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        argument.required == true
                            ? Color.clear
                            : Color.secondary.opacity(0.5),
                        lineWidth: 1
                    )
            )
    }
}

// Simple flow layout for argument tokens
struct FlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, in: proposal.replacingUnspecifiedDimensions()).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let offsets = layout(sizes: sizes, in: bounds.size).offsets

        for (subview, offset) in zip(subviews, offsets) {
            subview.place(
                at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(sizes: [CGSize], in containerSize: CGSize) -> (
        size: CGSize, offsets: [CGPoint]
    ) {
        var result: [CGPoint] = []
        var currentPosition = CGPoint.zero
        var lineHeight: CGFloat = 0
        var maxY: CGFloat = 0

        for size in sizes {
            if currentPosition.x + size.width > containerSize.width && !result.isEmpty {
                // Move to next line
                currentPosition.x = 0
                currentPosition.y += lineHeight + spacing
                lineHeight = 0
            }

            result.append(currentPosition)
            currentPosition.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxY = max(maxY, currentPosition.y + size.height)
        }

        return (size: CGSize(width: containerSize.width, height: maxY), offsets: result)
    }
}
