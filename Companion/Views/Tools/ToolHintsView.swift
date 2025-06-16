import SwiftUI
import MCP

struct ToolHintsView: View {
    let annotations: Tool.Annotations
    
    var body: some View {
        if !annotations.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Behavior Hints", systemImage: "lightbulb")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HintsLayout {
                    if let readOnly = annotations.readOnlyHint {
                        AnnotationRow(
                            icon: readOnly ? "lock.fill" : "lock.open.fill",
                            title: readOnly ? "Read-only" : "Can modify",
                            description: readOnly
                                ? "This tool does not modify its environment"
                                : "This tool can modify its environment",
                            color: readOnly ? .green : .orange
                        )
                    }

                    if let destructive = annotations.destructiveHint {
                        AnnotationRow(
                            icon: destructive
                                ? "exclamationmark.triangle.fill"
                                : "checkmark.shield.fill",
                            title: destructive ? "Destructive" : "Non-destructive",
                            description: destructive
                                ? "May perform destructive updates"
                                : "Performs only additive updates",
                            color: destructive ? .red : .green
                        )
                    }

                    if let idempotent = annotations.idempotentHint {
                        AnnotationRow(
                            icon: idempotent
                                ? "circle.lefthalf.filled" : "arrow.clockwise",
                            title: idempotent ? "Idempotent" : "Not idempotent",
                            description: idempotent
                                ? "Repeated calls have no additional effect"
                                : "Each call may have different effects",
                            color: idempotent ? .blue : .gray
                        )
                    }

                    if let openWorld = annotations.openWorldHint {
                        AnnotationRow(
                            icon: openWorld ? "globe" : "cube.box",
                            title: openWorld ? "Open world" : "Closed world",
                            description: openWorld
                                ? "Interacts with external entities"
                                : "Limited to a closed domain",
                            color: openWorld ? .purple : .brown
                        )
                    }
                }
            }
            .padding()
            #if os(visionOS)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            #else
            .background(.fill.secondary)
            .cornerRadius(10)
            #endif
        }
    }
}

struct AnnotationRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Custom Layout for Hints
private struct HintsLayout: Layout {
    private let spacing: CGFloat = 8
    private let minColumnWidth: CGFloat = 200
    private let maxColumns = 2

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
        // Handle edge cases
        guard availableWidth > 0 && availableWidth.isFinite else {
            return 1
        }

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
            return min(2, maxPossibleColumns)  // Better than 3x1 for hints
        case 4:
            return min(2, maxPossibleColumns)  // Perfect 2x2
        default:
            return min(maxColumns, maxPossibleColumns)
        }
    }
}
