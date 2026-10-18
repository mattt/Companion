import SwiftUI

struct WidthPassthroughView: View {
    let width: CGFloat
    let onWidthChange: (CGFloat) -> Void

    var body: some View {
        Rectangle().fill(Color.clear)  // A clear view for geometry purposes
            .task(id: width) {  // Re-runs the task when `width` (Equatable ID) changes
                onWidthChange(width)
            }
            .preference(key: WidthPreferenceKey.self, value: width)  // Continue to set the preference
    }
}

struct WidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()  // Use the latest reported width
    }
}

/// The width of the prompts, resources, and tools list column.
///
/// One value serves all three sections,
/// so the column keeps its size when the user switches sections
/// and across app launches.
enum ListPaneWidth {
    static let defaultsKey = "listPaneWidth"
    static let defaultWidth: CGFloat = 350
    static let range: ClosedRange<CGFloat> = 250...400

    static func clamped(_ width: CGFloat) -> CGFloat {
        min(max(width, range.lowerBound), range.upperBound)
    }

    static func stored(in defaults: UserDefaults = .standard) -> CGFloat {
        let value = defaults.double(forKey: defaultsKey)
        return value > 0 ? clamped(CGFloat(value)) : defaultWidth
    }

    static func store(_ width: CGFloat, in defaults: UserDefaults = .standard) {
        defaults.set(Double(clamped(width)), forKey: defaultsKey)
    }
}
