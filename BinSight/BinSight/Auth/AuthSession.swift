import Foundation
import Combine

/// Local auth state. The actual sign-in flow runs against Convex Auth's
/// HTTP endpoints (the deployment exposes them via `convex/http.ts`).
@MainActor
final class AuthSession: ObservableObject {
    static let shared = AuthSession()

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var pendingEmail: String?
    @Published private(set) var lastError: String?

    private var endpoint: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CONVEX_URL") as? String,
              let url = URL(string: raw) else { return nil }
        return url
    }

    /// Convex Auth's HTTP routes live on `<deployment>.convex.site` (not .cloud).
    private var siteUrl: URL? {
        guard let host = endpoint?.host else { return nil }
        let siteHost = host.replacingOccurrences(of: ".convex.cloud", with: ".convex.site")
        return URL(string: "https://\(siteHost)")
    }

    func bootstrap() async {
        isAuthenticated = TokenStore.read() != nil
    }

    func requestCode(email: String) async {
        lastError = nil
        guard let site = siteUrl else { lastError = "No deployment URL"; return }
        var req = URLRequest(url: site.appendingPathComponent("api/auth/signin/resend-otp"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email])
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                lastError = "Could not send code"
                return
            }
            pendingEmail = email
        } catch {
            lastError = error.localizedDescription
        }
    }

    func verifyCode(_ code: String) async {
        lastError = nil
        guard let site = siteUrl, let email = pendingEmail else { lastError = "No pending email"; return }
        var req = URLRequest(url: site.appendingPathComponent("api/auth/callback/resend-otp"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email, "code": code])
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                lastError = "Invalid code"
                return
            }
            struct Token: Decodable { let token: String? }
            if let token = try? JSONDecoder().decode(Token.self, from: data).token {
                TokenStore.write(token)
                isAuthenticated = true
                pendingEmail = nil
                Task { try? await ConvexService.shared.ensureProfile() }
            } else {
                lastError = "Sign-in succeeded but no token in response"
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        TokenStore.clear()
        isAuthenticated = false
        pendingEmail = nil
    }
}
