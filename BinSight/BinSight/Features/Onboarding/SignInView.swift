import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var session: AuthSession
    @State private var email = ""
    @State private var code = ""
    @State private var sending = false

    var body: some View {
        GlassRoot {
            ZStack {
                LinearGradient(
                    colors: [.black, BinSightTokens.Color.accent.opacity(0.4), .black],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ).ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "leaf.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(BinSightTokens.Color.recycle)
                        Text("BinSight")
                            .font(.largeTitle.weight(.bold))
                        Text("Snap your waste. Sort it right.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if session.pendingEmail == nil {
                        emailEntry
                    } else {
                        codeEntry
                    }

                    if let err = session.lastError {
                        Text(err).font(.footnote).foregroundStyle(.red)
                    }

                    Spacer()
                }
                .padding(24)
                .foregroundStyle(.white)
            }
        }
    }

    private var emailEntry: some View {
        VStack(spacing: 12) {
            TextField("you@example.com", text: $email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .padding(14)
                .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
                .foregroundStyle(.white)

            Button {
                guard !sending, !email.isEmpty else { return }
                sending = true
                Task {
                    await session.requestCode(email: email)
                    sending = false
                }
            } label: {
                HStack {
                    if sending { ProgressView().tint(.white) }
                    Text("Email me a code")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .background(BinSightTokens.Color.accent, in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(.white)
        }
    }

    private var codeEntry: some View {
        VStack(spacing: 12) {
            Text("We sent a 6-digit code to\n\(session.pendingEmail ?? "")")
                .multilineTextAlignment(.center)
                .font(.subheadline)

            TextField("123456", text: $code)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title2.monospaced())
                .padding(14)
                .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
                .foregroundStyle(.white)

            Button("Verify") {
                Task { await session.verifyCode(code) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(BinSightTokens.Color.recycle, in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(.white)
        }
    }
}
