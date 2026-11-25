#if os(macOS)
    import Combine
    import Sparkle
    import SwiftUI

    /// A menu command that asks Sparkle to check for a new release.
    struct CheckForUpdatesView: View {
        @State private var model: Model
        private let updater: SPUUpdater

        init(updater: SPUUpdater) {
            self.updater = updater
            self._model = State(initialValue: Model(updater: updater))
        }

        var body: some View {
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!model.canCheckForUpdates)
        }

        // SPUUpdater publishes canCheckForUpdates through KVO,
        // so mirror it for SwiftUI to observe.
        @MainActor
        @Observable
        final class Model {
            private(set) var canCheckForUpdates = false
            @ObservationIgnored private var cancellable: AnyCancellable?

            init(updater: SPUUpdater) {
                cancellable = updater.publisher(for: \.canCheckForUpdates)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] canCheckForUpdates in
                        self?.canCheckForUpdates = canCheckForUpdates
                    }
            }
        }
    }
#endif
