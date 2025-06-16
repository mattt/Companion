import ComposableArchitecture
import SwiftUI

@main
struct CompanionApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(
                store: Store(initialState: AppFeature.State()) {
                    AppFeature()
                        ._printChanges()
                }
            )
        }
        #if os(macOS)
            .windowStyle(.hiddenTitleBar)
            .windowToolbarStyle(.unified)
        #endif
    }
}
