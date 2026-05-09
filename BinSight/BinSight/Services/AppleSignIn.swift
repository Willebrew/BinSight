import Foundation
import AuthenticationServices
import Combine
import SwiftUI
import UIKit

/// Bridges ASAuthorizationController to async/await and forwards the Apple
/// identity token to a Convex action that verifies it and links the Apple
/// account to the current authenticated user.
@MainActor
final class AppleSignInCoordinator: ObservableObject {

    enum Status { case idle, signingIn, success, failed }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastError: String?

    /// Called from `SignInWithAppleButton`'s onCompletion. The system sheet
    /// has already shown; we just verify and link the identityToken.
    func handle(result: Result<ASAuthorization, Error>) async {
        status = .signingIn
        lastError = nil
        do {
            let auth = try result.get()
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                throw NSError(domain: "AppleSignIn", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "No identity token returned"])
            }
            let fullName: String? = {
                guard let comps = cred.fullName else { return nil }
                let s = PersonNameComponentsFormatter().string(from: comps)
                return s.isEmpty ? nil : s
            }()
            _ = try await ConvexService.shared.verifyAppleIdentity(
                identityToken: token, fullName: fullName
            )
            status = .success
        } catch {
            lastError = error.localizedDescription
            status = .failed
        }
    }

}
