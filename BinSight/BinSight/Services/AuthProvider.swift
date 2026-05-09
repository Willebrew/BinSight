import Foundation
import ConvexMobile
import Security

/// AnonymousAuthProvider mints a session JWT by calling the `auth:signIn`
/// action exposed by `@convex-dev/auth`. Stores the JWT in Keychain so it
/// survives app restarts. The user identity is durable; if the device
/// reinstalls without keychain restoration we fall back to a fresh anonymous
/// account, which is acceptable for v0.
final class AnonymousAuthProvider: AuthProvider {
    typealias T = String  // the JWT

    private let deploymentURL: String

    init(deploymentURL: URL) {
        self.deploymentURL = deploymentURL.absoluteString
    }

    func login(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
        let token = try await signInAnonymous()
        TokenStore.write(token)
        onIdToken(token)
        return token
    }

    func loginFromCache(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
        if let cached = TokenStore.read() {
            onIdToken(cached)
            return cached
        }
        return try await login(onIdToken: onIdToken)
    }

    func logout() async throws { TokenStore.clear() }

    func extractIdToken(from authResult: String) -> String { authResult }

    /// Calls the public `auth:signIn` action with the Anonymous provider.
    /// Uses an unauthenticated `ConvexClient` so we don't loop through our
    /// own auth provider before we have a token.
    private func signInAnonymous() async throws -> String {
        let unauthClient = ConvexClient(deploymentUrl: deploymentURL)
        let args: [String: ConvexEncodable?] = [
            "provider": "anonymous",
            "params": [String: ConvexEncodable?]()
        ]
        let result: SignInResult = try await unauthClient.action("auth:signIn", with: args)
        guard let token = result.tokens?.token else {
            throw NSError(domain: "Auth", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "auth:signIn returned no token"
            ])
        }
        return token
    }

    private struct SignInResult: Decodable {
        let tokens: Tokens?
        let started: Bool?
        let redirect: String?
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
