import Foundation
import ConvexMobile
import Security

/// Auth provider that issues a Convex Auth session JWT via the `Password`
/// provider. `pendingCredentials` is set by the SignInView before calling
/// `client.login()`; once signed in, the JWT lives in Keychain.
final class PasswordAuthProvider: AuthProvider {
    typealias T = String  // the JWT

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
        let token = try await passwordSignIn(email: creds.email, password: creds.password, flow: creds.flow)
        TokenStore.write(token)
        pendingCredentials = nil
        onIdToken(token)
        return token
    }

    func loginFromCache(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
        if let cached = TokenStore.read() {
            onIdToken(cached)
            return cached
        }
        // No cached token + no pending creds — caller (bootstrap) treats this
        // as "not signed in" and shows the sign-in UI.
        throw NSError(domain: "Auth", code: -11, userInfo: [
            NSLocalizedDescriptionKey: "Not signed in"
        ])
    }

    func logout() async throws { TokenStore.clear() }

    func extractIdToken(from authResult: String) -> String { authResult }

    /// Calls the public `auth:signIn` action (unauthenticated client) with
    /// the Password provider params. Convex Auth handles hashing/verification.
    private func passwordSignIn(email: String, password: String, flow: Flow) async throws -> String {
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
        guard let token = result.tokens?.token else {
            throw NSError(domain: "Auth", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Sign-in returned no token"
            ])
        }
        return token
    }

    private struct SignInResult: Decodable {
        let tokens: Tokens?
        struct Tokens: Decodable {
            let token: String
            let refreshToken: String?
        }
    }
}

// MARK: - Keychain-backed token store

enum TokenStore {
    private static let service = "com.binsight.authToken"
    private static let account = "default"

    static func read() -> String? {
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
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
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
