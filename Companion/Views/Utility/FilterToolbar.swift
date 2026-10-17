import SwiftUI

/// A reusable filter text field that can be used in toolbars across different collection views.
///
/// On macOS 26 and later the field draws no background of its own and lets the
/// toolbar's Liquid Glass material show through. On earlier versions it draws
/// the classic inset search-field background.
struct FilterToolbar: View {
    @Binding var searchText: String
    let placeholder: String
    let width: CGFloat

    var body: some View {
        #if os(macOS)
            if #available(macOS 26.0, *) {
                field
                    .padding(.horizontal, 10)
                    .frame(width: max(width - 20, 180))
            } else {
                field
                    .padding(.leading, 10)
                    .padding(.trailing, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
                    .frame(width: width - 20)
            }
        #else
            EmptyView()
        #endif
    }

    private var field: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 13))

            TextField(placeholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Clear filter")
            }
        }
    }
}
