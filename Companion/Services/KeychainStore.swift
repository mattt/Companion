import Foundation
import Security

/// Stores small secrets in the system Keychain.
///
/// Companion keeps API keys, bearer tokens, OAuth client secrets,
/// and OAuth access tokens here instead of in `servers.json`
/// or `UserDefaults`, where any process could read them.
struct KeychainStore: Sendable {
    var service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "me.mattt.Companion") {
        self.service = service
    }

    func string(for account: String) -> String? {
        guard let data = data(for: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setString(_ value: String?, for account: String) {
        guard let value, !value.isEmpty else {
            delete(account: account)
            return
        }
        setData(Data(value.utf8), for: account)
    }

    func data(for account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    func setData(_ data: Data, for account: String) {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    func rename(from oldAccount: String, to newAccount: String) {
        guard oldAccount != newAccount, let existing = data(for: oldAccount) else { return }
        setData(existing, for: newAccount)
        delete(account: oldAccount)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

// MARK: - Account names

extension KeychainStore {
    static func bearerTokenAccount(serverName: String) -> String {
        "bearer-token:\(serverName)"
    }

    static func oauthClientSecretAccount(serverName: String) -> String {
        "oauth-client-secret:\(serverName)"
    }

    static func oauthTokenAccount(serverName: String) -> String {
        "oauth-token:\(serverName)"
    }

    static func oauthClientIDAccount(serverName: String) -> String {
        "oauth-client-id:\(serverName)"
    }

    static func apiKeyAccount(provider: String) -> String {
        "sampling-api-key:\(provider)"
    }
}
