import SwiftUI

@main
struct CompanionApp: App {
    @State private var serverStore = ServerStore()
    @AppStorage(AppSettingsKey.appearance) private var appearanceRawValue: String =
        AppAppearance.system.rawValue

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
