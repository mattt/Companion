import SwiftUI

@main
struct CompanionApp: App {
    @State private var serverStore = ServerStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(serverStore)
        }
        #if os(macOS)
            .windowStyle(.hiddenTitleBar)
            .windowToolbarStyle(.unified)
        #endif
    }
}
