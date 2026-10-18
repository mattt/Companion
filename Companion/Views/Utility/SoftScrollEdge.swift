import SwiftUI

extension View {
    /// Fades scrolled content under the toolbar with the system
    /// soft scroll edge effect where the API exists (OS 26+).
    /// On older systems the scroll view keeps its default edge.
    @ViewBuilder
    func softTopScrollEdgeEffect() -> some View {
        #if os(visionOS)
            self
        #elseif os(macOS) || os(iOS)
            if #available(macOS 26.0, iOS 26.0, *) {
                scrollEdgeEffectStyle(.soft, for: .top)
            } else {
                self
            }
        #endif
    }
}
