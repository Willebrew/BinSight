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
            DuoBackdrop().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    modePicker
                    formCard
                    Button {
                        submit()
                    } label: {
                        if convex.authState == .signingIn {
                            ProgressView().tint(.white)
                        } else {
                            Label(mode == .signIn ? "Sign In" : "Create Account",
                                  systemImage: mode == .signIn ? "arrow.right.circle.fill" : "person.crop.circle.badge.plus")
                        }
                    }
                    .buttonStyle(DuoButtonStyle(kind: .primary))
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.48)

                    if let err = convex.authError {
                        DuoCard(fill: Color.white.opacity(0.92), stroke: BinSightTokens.Color.trash.opacity(0.25), radius: 16, padding: 12) {
                            Label(err, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(.footnote, design: .rounded).weight(.semibold))
                                .foregroundStyle(BinSightTokens.Color.trash)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 54)
                .padding(.bottom, 36)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var header: some View {
        VStack(spacing: 14) {
            MascotArtView(
                mood: mode == .signIn ? .happy : .celebrate,
                size: 132,
                accessory: mode == .signIn ? "leaf.fill" : "star.fill"
            )
            VStack(spacing: 4) {
                Text("BinSight")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(BinSightTokens.Color.ink)
                Text(mode == .signIn ? "Ready for another scan lesson?" : "Start your impact streak")
                    .font(.system(.callout, design: .rounded).weight(.bold))
                    .foregroundStyle(BinSightTokens.Color.softInk)
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            modeTab("Sign in", .signIn)
            modeTab("Sign up", .signUp)
        }
        .padding(6)
        .background(.white.opacity(0.75), in: Capsule())
        .overlay(Capsule().stroke(.white, lineWidth: 1.5))
    }

    private func modeTab(_ label: String, _ value: Mode) -> some View {
        Button {
            withAnimation(BinSightTokens.Motion.bounce) { mode = value }
        } label: {
            Text(label)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(mode == value ? .white : BinSightTokens.Color.softInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    if mode == value {
                        Capsule().fill(BinSightTokens.Color.accent)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var formCard: some View {
        DuoGlassCard(tint: BinSightTokens.Color.recycle, radius: 24, padding: 14) {
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
            .animation(BinSightTokens.Motion.snap, value: mode)
        }
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
        HStack(spacing: 11) {
            Image(systemName: icon)
                .foregroundStyle(BinSightTokens.Color.accent)
                .frame(width: 26)
            Group {
                if isSecure {
                    SecureField("", text: text, prompt: Text(placeholder).foregroundStyle(BinSightTokens.Color.softInk))
                } else {
                    TextField("", text: text, prompt: Text(placeholder).foregroundStyle(BinSightTokens.Color.softInk))
                }
            }
            .textInputAutocapitalization(autoCap)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .textContentType(content)
            .focused($focused, equals: focus)
            .foregroundStyle(BinSightTokens.Color.ink)
            .font(.system(.body, design: .rounded).weight(.semibold))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 13)
        .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(BinSightTokens.Color.stroke, lineWidth: 1.5))
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
