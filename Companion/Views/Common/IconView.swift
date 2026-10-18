import MCP
import SwiftUI

/// Displays an MCP icon from a server, tool, prompt, or resource.
///
/// Icons may use HTTP or HTTPS URLs, or `data:` URIs with
/// Base64-encoded image data. SVG icons fall back to a symbol
/// because the platform image types cannot render SVG safely.
struct IconView: View {
    let icons: [MCP.Icon]?
    var size: CGFloat = 24
    var fallbackSystemImage: String = "app"

    @Environment(\.colorScheme) private var colorScheme

    private var icon: MCP.Icon? {
        guard let icons, !icons.isEmpty else { return nil }
        let preferredTheme: MCP.Icon.Theme = colorScheme == .dark ? .dark : .light
        return icons.first { $0.theme == preferredTheme }
            ?? icons.first { $0.theme == nil }
            ?? icons.first
    }

    var body: some View {
        Group {
            if let icon, let image = decodedImage(for: icon) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let icon, let url = remoteURL(for: icon) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
    }

    private var placeholder: some View {
        Image(systemName: fallbackSystemImage)
            .font(.system(size: size * 0.7))
            .foregroundStyle(.secondary)
    }

    private func remoteURL(for icon: MCP.Icon) -> URL? {
        guard icon.mimeType != "image/svg+xml" else { return nil }
        guard let url = URL(string: icon.src),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    private func decodedImage(for icon: MCP.Icon) -> Image? {
        guard icon.src.hasPrefix("data:") else { return nil }
        guard let comma = icon.src.firstIndex(of: ",") else { return nil }
        let metadata = icon.src[icon.src.index(icon.src.startIndex, offsetBy: 5)..<comma]
        guard metadata.contains("base64"),
            !metadata.contains("svg")
        else { return nil }
        let base64 = String(icon.src[icon.src.index(after: comma)...])
        guard let data = Data(base64Encoded: base64) else { return nil }

        #if os(macOS)
            guard let nsImage = NSImage(data: data) else { return nil }
            return Image(nsImage: nsImage)
        #else
            guard let uiImage = UIImage(data: data) else { return nil }
            return Image(uiImage: uiImage)
        #endif
    }
}
