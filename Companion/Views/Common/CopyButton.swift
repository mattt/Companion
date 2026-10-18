import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Copies raw text to the pasteboard.
enum Pasteboard {
    static func copy(_ string: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        #else
            UIPasteboard.general.string = string
        #endif
    }
}

/// A button that copies text and briefly shows a checkmark.
struct CopyButton: View {
    /// Text to copy, or a closure that produces it when tapped.
    let text: () -> String
    private let isDisabled: Bool

    @State private var justCopied = false

    init(text: String) {
        self.text = { text }
        self.isDisabled = text.isEmpty
    }

    init(isDisabled: Bool = false, text: @escaping () -> String) {
        self.text = text
        self.isDisabled = isDisabled
    }

    var body: some View {
        Button {
            Pasteboard.copy(text())
            justCopied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                justCopied = false
            }
        } label: {
            Label(
                justCopied ? "Copied" : "Copy",
                systemImage: justCopied ? "checkmark" : "doc.on.doc"
            )
        }
        .disabled(isDisabled)
    }
}
