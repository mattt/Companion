import Foundation
import SwiftUI

#if canImport(UIKit)
    import UIKit

    extension Bundle {
        public var icon: UIImage? {
            if let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
                let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
                let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
                let lastIcon = iconFiles.last
            {
                return UIImage(named: lastIcon)
            }
            return nil
        }
    }
#elseif canImport(AppKit)
    import AppKit

    extension Bundle {
        public var icon: NSImage? {
            if let iconFileName = infoDictionary?["CFBundleIconFile"] as? String {
                return NSImage(named: iconFileName)
            }
            return NSImage(named: "AppIcon")
        }
    }
#endif

// MARK: -

struct AppIconImage: View {
    let size: CGFloat
    let cornerRadius: CGFloat

    init(size: CGFloat = 80, cornerRadius: CGFloat = 16) {
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        #if canImport(UIKit)
        if let icon = Bundle.main.icon {
            Image(uiImage: icon)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            fallbackIcon
        }
        #elseif canImport(AppKit)
        if let icon = Bundle.main.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            fallbackIcon
        }
        #endif
    }

    private var fallbackIcon: some View {
        Image(systemName: "mcp.fill")
            .font(.system(size: size * 0.6, weight: .light))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
