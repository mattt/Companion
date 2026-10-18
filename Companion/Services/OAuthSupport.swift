import AuthenticationServices
import Foundation
import MCP

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Presents OAuth authorization pages in a secure browser session.
///
/// The SDK calls `presentAuthorizationURL(_:)` during the
/// authorization-code flow and expects the redirect URL back.
/// Companion registers the `companion` URL scheme for the redirect.
final class OAuthBrowserPresenter: NSObject, OAuthAuthorizationDelegate, @unchecked Sendable {
    static let callbackScheme = "companion"
    static let redirectURI = URL(string: "companion://oauth/callback")!

    private let lock = NSLock()
    private var session: ASWebAuthenticationSession?

    private func setSession(_ session: ASWebAuthenticationSession?) {
        lock.lock()
        defer { lock.unlock() }
        self.session = session
    }

    func presentAuthorizationURL(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let session = ASWebAuthenticationSession(
                    url: url,
                    callback: .customScheme(Self.callbackScheme)
                ) { [weak self] callbackURL, error in
                    self?.setSession(nil)
                    if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(
                            throwing: OAuthPresentationError.noCallbackURL)
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                setSession(session)
                if !session.start() {
                    setSession(nil)
                    continuation.resume(throwing: OAuthPresentationError.failedToStart)
                }
            }
        }
    }
}

extension OAuthBrowserPresenter: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if os(macOS)
                return NSApplication.shared.keyWindow
                    ?? NSApplication.shared.windows.first
                    ?? ASPresentationAnchor()
            #else
                let window = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
                    .first { $0.isKeyWindow }
                return window ?? ASPresentationAnchor()
            #endif
        }
    }
}

enum OAuthPresentationError: Swift.Error, LocalizedError {
    case failedToStart
    case noCallbackURL

    var errorDescription: String? {
        switch self {
        case .failedToStart:
            return "Could not open the sign-in page."
        case .noCallbackURL:
            return "Sign-in finished without a response from the server."
        }
    }
}

/// Persists OAuth tokens in the Keychain, one item per server.
final class KeychainTokenStorage: TokenStorage, @unchecked Sendable {
    private let keychain: KeychainStore
    private let account: String

    init(keychain: KeychainStore = KeychainStore(), serverName: String) {
        self.keychain = keychain
        self.account = KeychainStore.oauthTokenAccount(serverName: serverName)
    }

    func save(_ token: OAuthAccessToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        keychain.setData(data, for: account)
    }

    func load() -> OAuthAccessToken? {
        guard let data = keychain.data(for: account) else { return nil }
        return try? JSONDecoder().decode(OAuthAccessToken.self, from: data)
    }

    func clear() {
        keychain.delete(account: account)
    }
}
