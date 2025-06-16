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
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()  // Use the latest reported width
    }
}
