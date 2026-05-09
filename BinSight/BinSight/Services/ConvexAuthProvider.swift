import Foundation
import ConvexMobile

/// Thin auth provider that hands the JWT stored by `AuthSession` to the
/// Convex client on every request. Replace with the real Convex Auth
/// integration once `@convex-dev/auth` ships an iOS-side helper; this is
/// sufficient for email-OTP where we receive the token from a sign-in call.
final class ConvexAuthProvider: AuthProvider {
    func login() async throws { /* handled out-of-band by AuthSession */ }
    func logout() async throws { TokenStore.clear() }
    func getToken() async throws -> String? { TokenStore.read() }
    func extractIdToken(authResult: Any) -> String? { TokenStore.read() }
}

enum TokenStore {
    private static let key = "binsight.authToken"

    static func read() -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func write(_ token: String) {
        UserDefaults.standard.set(token, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
