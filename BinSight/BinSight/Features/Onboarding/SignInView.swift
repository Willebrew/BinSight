import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var convex: ConvexService
    enum Mode { case signIn, signUp }
    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focused: Field?

    enum Field { case name, email, password }

    var body: some View {
        ZStack {
            backdrop
            ScrollView {
                VStack(spacing: 22) {
                    branding
                    modePicker
                    formCard
                    submitButton
                    if let err = convex.authError {
                        Text(err).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var backdrop: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.16, blue: 0.16),
                Color(red: 0.06, green: 0.34, blue: 0.32),
                Color(red: 0.02, green: 0.10, blue: 0.12),
            ],
            startPoint: .top, endPoint: .bottom
        ).ignoresSafeArea()
    }

    private var branding: some View {
        VStack(spacing: 10) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(BinSightTokens.Color.recycle)
            Text("BinSight").font(.largeTitle.weight(.heavy)).foregroundStyle(.white)
            Text(mode == .signIn ? "Welcome back" : "Create your account")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            modeTab("Sign in", .signIn)
            modeTab("Sign up", .signUp)
        }
        .padding(4)
        .background(.white.opacity(0.10), in: Capsule())
    }

    private func modeTab(_ label: String, _ value: Mode) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { mode = value }
        } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    if mode == value {
                        Capsule().fill(BinSightTokens.Color.accent)
                    }
                }
                .foregroundStyle(mode == value ? .white : .white.opacity(0.7))
        }
        .buttonStyle(.plain)
    }

    private var formCard: some View {
        VStack(spacing: 12) {
            if mode == .signUp {
                field(
                    icon: "person.fill",
                    placeholder: "Name",
                    text: $name,
                    autoCap: .words,
                    focus: .name,
                    content: .name
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            field(
                icon: "envelope.fill",
                placeholder: "Email",
                text: $email,
                keyboard: .emailAddress,
                focus: .email,
                content: .emailAddress
            )
            field(
                icon: "lock.fill",
                placeholder: "Password (min 6 chars)",
                text: $password,
                isSecure: true,
                focus: .password,
                content: mode == .signUp ? .newPassword : .password
            )
        }
        .padding(14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.10)))
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: mode)
    }

    @ViewBuilder
    private func field(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        autoCap: TextInputAutocapitalization = .never,
        isSecure: Bool = false,
        focus: Field,
        content: UITextContentType
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.white.opacity(0.6))
            Group {
                if isSecure {
                    SecureField("", text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.45)))
                } else {
                    TextField("", text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.45)))
                }
            }
            .textInputAutocapitalization(autoCap)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .textContentType(content)
            .focused($focused, equals: focus)
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            HStack {
                if convex.authState == .signingIn {
                    ProgressView().tint(.black)
                } else {
                    Text(mode == .signIn ? "Sign in" : "Create account")
                        .font(.headline)
                }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.white, in: Capsule())
        }
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1 : 0.5)
    }

    private var canSubmit: Bool {
        let okPassword = password.count >= 6
        let okEmail = email.contains("@") && email.contains(".")
        let okName = mode == .signIn || name.trimmingCharacters(in: .whitespaces).count >= 2
        return okEmail && okPassword && okName && convex.authState != .signingIn
    }

    private func submit() {
        focused = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            switch mode {
            case .signIn:
                await convex.signIn(email: trimmedEmail, password: password)
            case .signUp:
                await convex.signUp(name: trimmedName, email: trimmedEmail, password: password)
            }
        }
    }
}
