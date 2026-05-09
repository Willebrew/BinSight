import Foundation
import ConvexMobile
import Security

/// AnonymousAuthProvider talks to `@convex-dev/auth`'s HTTP routes (deployed
/// at `<deployment>.convex.site/api/auth/...`) to mint and store a session
/// JWT. Each device gets a real Convex `users` row tied to that token.
final class AnonymousAuthProvider: AuthProvider {
    typealias T = String  // the JWT

    private let siteURL: URL

    init(deploymentURL: URL) {
        // .convex.cloud -> .convex.site
        let host = (deploymentURL.host ?? "").replacingOccurrences(of: ".convex.cloud", with: ".convex.site")
        self.siteURL = URL(string: "https://\(host)") ?? deploymentURL
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
        // No cached token — sign in anonymously now.
        let token = try await signInAnonymous()
        TokenStore.write(token)
        onIdToken(token)
        return token
    }

    func logout() async throws {
        TokenStore.clear()
    }

    func extractIdToken(from authResult: String) -> String {
        authResult
    }

    private func signInAnonymous() async throws -> String {
        let url = siteURL.appendingPathComponent("api/auth/signIn")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "provider": "anonymous",
            "params": [:]
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "Auth", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "signIn failed (\((response as? HTTPURLResponse)?.statusCode ?? 0)): \(body.prefix(300))"
            ])
        }
        struct SignInResponse: Decodable {
            let tokens: Tokens?
            let token: String?
            struct Tokens: Decodable { let token: String? }
        }
        let decoded = try JSONDecoder().decode(SignInResponse.self, from: data)
        if let t = decoded.tokens?.token { return t }
        if let t = decoded.token { return t }
        // Convex auth may return slightly different shapes; fall back to raw string scan.
        if let body = String(data: data, encoding: .utf8) {
            throw NSError(domain: "Auth", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "signIn returned no token: \(body.prefix(200))"
            ])
        }
        throw NSError(domain: "Auth", code: -3, userInfo: [NSLocalizedDescriptionKey: "Empty signIn response"])
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
