import SwiftUI

#if os(macOS)
    import Sparkle
#endif

@main
struct CompanionApp: App {
    @State private var serverStore = ServerStore()
    @AppStorage(AppSettingsKey.appearance) private var appearanceRawValue: String =
        AppAppearance.system.rawValue

    #if os(macOS)
        // Starting the updater here makes it check for releases
        // on Sparkle's schedule for the app's lifetime;
        // the SUFeedURL and SUPublicEDKey keys in Info.plist do nothing on their own.
        private let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    #endif

    private var preferredColorScheme: ColorScheme? {
        switch AppAppearance(rawValue: appearanceRawValue) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(serverStore)
                .preferredColorScheme(preferredColorScheme)
        }
        #if os(macOS)
            .windowStyle(.hiddenTitleBar)
            .windowToolbarStyle(.unified)
            .commands {
                CommandGroup(after: .appInfo) {
                    CheckForUpdatesView(updater: updaterController.updater)
                }
            }
        #endif

        #if os(macOS)
            Settings {
                SettingsView()
                    .environment(serverStore)
                    .preferredColorScheme(preferredColorScheme)
            }
        #endif
    }
}
