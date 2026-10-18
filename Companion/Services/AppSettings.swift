import Foundation
import MCP

/// The app appearance choice in Settings.
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// UserDefaults keys for app-wide settings.
enum AppSettingsKey {
    static let appearance = "appearance"
    static let autoConnectOnLaunch = "connection.autoConnectOnLaunch"
    static let defaultLogLevel = "logging.defaultLevel"
    static let warnDestructiveToolCalls = "tools.warnDestructive"
    static let requestTimeoutMinutes = "clientRequests.timeoutMinutes"
}

/// Reads app-wide settings that services need outside SwiftUI.
enum AppSettings {
    /// The log level to request when a connection opens.
    static func defaultLogLevel(in defaults: UserDefaults = .standard) -> MCP.LogLevel {
        guard let rawValue = defaults.string(forKey: AppSettingsKey.defaultLogLevel),
            let level = MCP.LogLevel(rawValue: rawValue)
        else {
            return .debug
        }
        return level
    }

    static func setDefaultLogLevel(
        _ level: MCP.LogLevel, in defaults: UserDefaults = .standard
    ) {
        defaults.set(level.rawValue, forKey: AppSettingsKey.defaultLogLevel)
    }

    /// How long a sampling or elicitation request waits for the user.
    /// `nil` means it waits until the user answers or the server gives up.
    static func requestTimeout(in defaults: UserDefaults = .standard) -> Duration? {
        let minutes = defaults.integer(forKey: AppSettingsKey.requestTimeoutMinutes)
        guard minutes > 0 else { return nil }
        return .seconds(minutes * 60)
    }
}
