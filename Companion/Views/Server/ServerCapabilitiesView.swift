import SwiftUI
import MCP

struct ServerCapabilitiesView: View {
    let capabilities: MCP.Server.Capabilities

    var body: some View {
        if capabilityGroups.isEmpty {
            HStack {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
                Text("No capabilities")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        } else {
            CapabilitiesLayout {
                ForEach(capabilityGroups, id: \.id) { group in
                    CapabilityGroupView(group: group)
                }
            }
        }
    }

    private var capabilityGroups: [CapabilityGroup] {
        var groups: [CapabilityGroup] = []

        // Core capabilities
        if capabilities.logging != nil {
            groups.append(
                CapabilityGroup(
                    id: "logging",
                    title: "Logging",
                    description: "Server can send log messages",
                    icon: "doc.text",
                    features: []
                ))
        }

        if capabilities.sampling != nil {
            groups.append(
                CapabilityGroup(
                    id: "sampling",
                    title: "Sampling",
                    description: "Supports sampling completions",
                    icon: "text.cursor",
                    features: []
                ))
        }

        // Prompts
        if let prompts = capabilities.prompts {
            var features: [String] = []
            if prompts.listChanged == true {
                features.append("Live prompt list updates")
            }

            groups.append(
                CapabilityGroup(
                    id: "prompts",
                    title: "Prompts",
                    description: "Offers prompt templates",
                    icon: "bubble.left.and.text.bubble.right",
                    features: features
                ))
        }

        // Resources
        if let resources = capabilities.resources {
            var features: [String] = []
            if resources.subscribe == true {
                features.append("Resource subscriptions")
            }
            if resources.listChanged == true {
                features.append("Live resource list updates")
            }

            groups.append(
                CapabilityGroup(
                    id: "resources",
                    title: "Resources",
                    description: "Provides readable resources",
                    icon: "doc.richtext",
                    features: features
                ))
        }

        // Tools
        if let tools = capabilities.tools {
            var features: [String] = []
            if tools.listChanged == true {
                features.append("Live tool list updates")
            }

            groups.append(
                CapabilityGroup(
                    id: "tools",
                    title: "Tools",
                    description: "Offers callable tools",
                    icon: "hammer",
                    features: features
                ))
        }

        return groups
    }
}

// MARK: - Custom Layout
struct CapabilitiesLayout: Layout {
    private let spacing: CGFloat = 16
    private let minColumnWidth: CGFloat = 280
    private let maxColumns = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let columnCount = calculateColumnCount(for: subviews.count, availableWidth: width)
        let columnWidth = (width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        let isSingleColumn = columnCount == 1

        // Calculate the height needed for each cell
        let cellHeights: [CGFloat] = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
        }
        let maxCellHeight = cellHeights.max() ?? 0

        // Calculate row heights
        var rowHeights: [CGFloat] = []
        let itemsPerRow = columnCount
        for rowIndex in 0..<Int(ceil(Double(subviews.count) / Double(itemsPerRow))) {
            if isSingleColumn {
                // Use natural height for each cell in single column
                let startIndex = rowIndex * itemsPerRow
                let endIndex = min(startIndex + itemsPerRow, subviews.count)
                let rowHeight = cellHeights[startIndex..<endIndex].max() ?? 0
                rowHeights.append(rowHeight)
            } else {
                // Use max cell height for all rows in multi-column
                rowHeights.append(maxCellHeight)
            }
        }

        let totalHeight = rowHeights.reduce(0, +) + CGFloat(max(0, rowHeights.count - 1)) * spacing
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let columnCount = calculateColumnCount(for: subviews.count, availableWidth: bounds.width)
        let columnWidth = (bounds.width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        let isSingleColumn = columnCount == 1

        // Calculate the height needed for each cell
        let cellHeights: [CGFloat] = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
        }
        let maxCellHeight = cellHeights.max() ?? 0

        // Calculate row heights
        var rowHeights: [CGFloat] = []
        let itemsPerRow = columnCount
        for rowIndex in 0..<Int(ceil(Double(subviews.count) / Double(itemsPerRow))) {
            if isSingleColumn {
                let startIndex = rowIndex * itemsPerRow
                let endIndex = min(startIndex + itemsPerRow, subviews.count)
                let rowHeight = cellHeights[startIndex..<endIndex].max() ?? 0
                rowHeights.append(rowHeight)
            } else {
                rowHeights.append(maxCellHeight)
            }
        }

        // Place subviews
        for (index, subview) in subviews.enumerated() {
            let row = index / columnCount
            let column = index % columnCount

            let x = bounds.minX + CGFloat(column) * (columnWidth + spacing)
            let y = bounds.minY + (0..<row).reduce(0) { $0 + rowHeights[$1] + spacing }

            let proposedHeight = isSingleColumn ? nil : maxCellHeight

            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: columnWidth, height: proposedHeight)
            )
        }
    }

    private func calculateColumnCount(for itemCount: Int, availableWidth: CGFloat) -> Int {
        // Single column for narrow screens
        if availableWidth < minColumnWidth * 1.5 {
            return 1
        }

        // Calculate optimal columns based on width and item count
        let maxPossibleColumns = min(Int(availableWidth / minColumnWidth), maxColumns)

        switch itemCount {
        case 1:
            return 1
        case 2:
            return min(2, maxPossibleColumns)
        case 3:
            return min(3, maxPossibleColumns)  // Better than 2+1 orphan
        case 4:
            return min(2, maxPossibleColumns)  // Perfect 2x2
        case 5:
            return min(3, maxPossibleColumns)  // 3+2 is better than 2+2+1
        case 6:
            return min(3, maxPossibleColumns)  // Perfect 3x2
        case 7, 8:
            return min(4, maxPossibleColumns)  // 4x2 for 8, 4+3 for 7
        default:
            return min(maxColumns, maxPossibleColumns)
        }
    }
}

struct CapabilityGroupView: View {
    let group: CapabilityGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with icon and title
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: group.icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(group.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(group.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Features (if any)
            if !group.features.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(group.features, id: \.self) { feature in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)

                            Text(feature)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 34)  // Align with title text
            }

            // Add spacer to push content to top and fill available height
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.5), lineWidth: 0.5)
        )
    }
}

struct CapabilityGroup {
    let id: String
    let title: String
    let description: String
    let icon: String
    let features: [String]
}



#Preview {
    ScrollView {
        VStack(spacing: 20) {
            // Full capabilities example
            VStack(alignment: .leading, spacing: 12) {
                Text("Full Capabilities")
                    .font(.headline)

                ServerCapabilitiesView(
                    capabilities: MCP.Server.Capabilities(
                        logging: MCP.Server.Capabilities.Logging(),
                        prompts: MCP.Server.Capabilities.Prompts(listChanged: true),
                        resources: MCP.Server.Capabilities.Resources(subscribe: true, listChanged: true),
                        sampling: MCP.Server.Capabilities.Sampling(),
                        tools: MCP.Server.Capabilities.Tools(listChanged: true)
                    ))
            }
            .padding()
            .background(.fill.secondary)
            .cornerRadius(10)

            // Basic capabilities example
            VStack(alignment: .leading, spacing: 12) {
                Text("Basic Capabilities")
                    .font(.headline)

                ServerCapabilitiesView(
                    capabilities: MCP.Server.Capabilities(
                        logging: MCP.Server.Capabilities.Logging(),
                        tools: MCP.Server.Capabilities.Tools()
                    ))
            }
            .padding()
            .background(.fill.secondary)
            .cornerRadius(10)

            // No capabilities example
            VStack(alignment: .leading, spacing: 12) {
                Text("No Capabilities")
                    .font(.headline)

                ServerCapabilitiesView(capabilities: MCP.Server.Capabilities())
            }
            .padding()
            .background(.fill.secondary)
            .cornerRadius(10)
        }
        .padding()
    }
}
