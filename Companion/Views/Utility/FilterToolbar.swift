import SwiftUI

/// A reusable filter text field that can be used in toolbars across different collection views
struct FilterToolbar: View {
    @Binding var searchText: String
    let placeholder: String
    let width: CGFloat
    let isVisible: Bool

    var body: some View {
        #if os(macOS)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))

                TextField(placeholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.leading, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
            .frame(width: width - 20)
            .opacity(isVisible ? 1 : 0)
            .animation(nil, value: isVisible)
        #else
            EmptyView()
        #endif
    }
}
