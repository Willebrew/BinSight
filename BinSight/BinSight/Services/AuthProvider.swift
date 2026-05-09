import Foundation
import ConvexMobile
import Security

/// Auth provider that issues a Convex Auth session JWT via the `Password`
/// provider. `pendingCredentials` is set by the SignInView before calling
/// `client.login()`; once signed in, the JWT + refreshToken live in Keychain.
///
/// The Convex Swift SDK calls `loginFromCache` whenever it needs a fresh
/// token (notably when the WebSocket gets a 401 from an expired JWT). We
/// use that hook to swap our refreshToken for a new pair of tokens via the
/// Convex Auth `auth:signIn` action - without a working refresh path, the
/// WebSocket wedges silently after token expiry.
final class PasswordAuthProvider: AuthProvider {
    typealias T = String  // the JWT (id token)

    private let deploymentURL: String

    enum Flow: String { case signIn, signUp }

    /// Set by the UI immediately before triggering `client.login()`. Cleared
    /// on success.
    var pendingCredentials: (email: String, password: String, flow: Flow)?

    init(deploymentURL: URL) {
        self.deploymentURL = deploymentURL.absoluteString
    }

    func login(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
        guard let creds = pendingCredentials else {
            throw NSError(domain: "Auth", code: -10, userInfo: [
                NSLocalizedDescriptionKey: "Missing credentials"
            ])
        }
        let pair = try await passwordSignIn(email: creds.email, password: creds.password, flow: creds.flow)
        TokenStore.write(pair)
        pendingCredentials = nil
        onIdToken(pair.token)
        return pair.token
    }

    /// Called by the SDK on app boot AND on token expiry. We try to refresh
    /// first; if that fails (no refresh token, or server rejects), fall back
    /// to whatever JWT is in Keychain - but if we have nothing at all, throw
    /// so the UI shows the sign-in screen.
    func loginFromCache(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
        let cached = TokenStore.read()
        if let refresh = cached?.refreshToken,
           let refreshed = try? await tokenRefresh(refreshToken: refresh) {
            TokenStore.write(refreshed)
            onIdToken(refreshed.token)
            return refreshed.token
        }
        if let token = cached?.token {
            onIdToken(token)
            return token
        }
        throw NSError(domain: "Auth", code: -11, userInfo: [
            NSLocalizedDescriptionKey: "Not signed in"
        ])
    }

    func logout() async throws { TokenStore.clear() }

    func extractIdToken(from authResult: String) -> String { authResult }

    /// Calls the public `auth:signIn` action (unauthenticated client) with
    /// the Password provider params. Convex Auth handles hashing/verification.
    private func passwordSignIn(email: String, password: String, flow: Flow) async throws -> TokenPair {
        let unauthClient = ConvexClient(deploymentUrl: deploymentURL)
        let params: [String: ConvexEncodable?] = [
            "email": email,
            "password": password,
            "flow": flow.rawValue,
        ]
        let args: [String: ConvexEncodable?] = [
            "provider": "password",
            "params": params,
        ]
        let result: SignInResult = try await unauthClient.action("auth:signIn", with: args)
        guard let tokens = result.tokens, let token = tokens.token else {
            throw NSError(domain: "Auth", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Sign-in returned no token"
            ])
        }
        return TokenPair(token: token, refreshToken: tokens.refreshToken)
    }

    /// Trades a refresh token for a fresh JWT pair via `auth:signIn`.
    private func tokenRefresh(refreshToken: String) async throws -> TokenPair {
        let unauthClient = ConvexClient(deploymentUrl: deploymentURL)
        let args: [String: ConvexEncodable?] = ["refreshToken": refreshToken]
        let result: SignInResult = try await unauthClient.action("auth:signIn", with: args)
        guard let tokens = result.tokens, let token = tokens.token else {
            throw NSError(domain: "Auth", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Refresh returned no token"
            ])
        }
        return TokenPair(token: token, refreshToken: tokens.refreshToken ?? refreshToken)
    }

    private struct SignInResult: Decodable {
        let tokens: Tokens?
        struct Tokens: Decodable {
            let token: String?
            let refreshToken: String?
        }
    }
}

// MARK: - Keychain-backed token store

struct TokenPair: Codable {
    let token: String
    let refreshToken: String?
}

enum TokenStore {
    private static let service = "com.binsight.authToken"
    private static let account = "default"

    static func read() -> TokenPair? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        // Newer entries are JSON-encoded TokenPair; older entries are raw
        // JWT strings. Handle both so existing sessions don't break.
        if let pair = try? JSONDecoder().decode(TokenPair.self, from: data) {
            return pair
        }
        if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
            return TokenPair(token: raw, refreshToken: nil)
        }
        return nil
    }

    static func write(_ pair: TokenPair) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = (try? JSONEncoder().encode(pair)) ?? Data()
        SecItemAdd(add as CFDictionary, nil)
    }

    static func clear() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
    }
}
