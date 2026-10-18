import Foundation
import MCP

/// Per-server settings that do not belong in `servers.json`.
///
/// `servers.json` follows the common MCP configuration format,
/// which has no place for roots or OAuth preferences.
/// Companion stores those settings in `UserDefaults`,
/// keyed by server name. Secrets stay in the Keychain.
struct ServerSidecarSettings: Codable, Equatable, Sendable {
    var roots: [MCP.Root] = []
    var useOAuth: Bool = false
    var oauthClientID: String?
}

struct ServerSettingsStore: Sendable {
    private static let keyPrefix = "server-settings:"

    private var defaults: UserDefaults { .standard }

    func settings(forServerNamed name: String) -> ServerSidecarSettings {
        guard let data = defaults.data(forKey: Self.keyPrefix + name),
            let settings = try? JSONDecoder().decode(ServerSidecarSettings.self, from: data)
        else {
            return ServerSidecarSettings()
        }
        return settings
    }

    func save(_ settings: ServerSidecarSettings, forServerNamed name: String) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.keyPrefix + name)
    }

    func removeSettings(forServerNamed name: String) {
        defaults.removeObject(forKey: Self.keyPrefix + name)
    }

    func rename(from oldName: String, to newName: String) {
        guard oldName != newName,
            let data = defaults.data(forKey: Self.keyPrefix + oldName)
        else { return }
        defaults.set(data, forKey: Self.keyPrefix + newName)
        defaults.removeObject(forKey: Self.keyPrefix + oldName)
    }
}
