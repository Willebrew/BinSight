import SwiftUI
import AuthenticationServices
import Combine

struct SettingsView: View {
    @EnvironmentObject private var convex: ConvexService
    @StateObject private var apple = AppleSignInCoordinator()
    @State private var profile: ProfileDoc?
    @State private var subscription: AnyCancellable?
    @State private var nameDraft = ""
    @State private var savingName = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    aboutSection
                    accountSection
                    nameSection
                    backendSection
                }
                .padding(20)
            }
            .navigationTitle("Settings")
        }
        .onAppear {
            subscription = ConvexService.shared.subscribeProfile()
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in }, receiveValue: { p in
                    profile = p
                    if let n = p?.displayName, nameDraft.isEmpty { nameDraft = n }
                })
        }
        .onDisappear { subscription?.cancel() }
    }

    // MARK: - Sections

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BinSight").font(.headline)
            Text("Snap a photo of any waste item and BinSight tells you exactly where it goes — recycle, compost, trash, or hazardous.")
                .font(.callout).foregroundStyle(.secondary)
            Text("v0.3 — Convex Auth + Liquid Glass")
                .font(.caption2.monospaced()).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Account").font(.headline)
                Spacer()
                if profile?.isAppleLinked == true {
                    Label("Apple linked", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BinSightTokens.Color.recycle)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: convex.isAuthenticated
                      ? "person.crop.circle.fill"
                      : "person.crop.circle.badge.questionmark")
                    .foregroundStyle(convex.isAuthenticated
                                     ? BinSightTokens.Color.accent
                                     : BinSightTokens.Color.hazard)
                VStack(alignment: .leading) {
                    Text(profile?.displayName ?? (profile?.isAppleLinked == true ? "Apple user" : "Anonymous"))
                        .font(.callout.weight(.semibold))
                    if let email = profile?.email {
                        Text(email).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(convex.isAuthenticated ? "Signed in" : "Not signed in")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if profile?.isAppleLinked != true {
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { await apple.handle(result: result) }
                }
                .signInWithAppleButtonStyle(.whiteOutline)
                .frame(height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                if apple.status == .signingIn {
                    HStack { ProgressView(); Text("Linking Apple ID…").font(.caption) }
                }
                if let err = apple.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display name").font(.headline)
            HStack {
                TextField("Your name", text: $nameDraft)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                Button {
                    saveName()
                } label: {
                    if savingName { ProgressView() } else { Text("Save").font(.subheadline.weight(.semibold)) }
                }
                .disabled(savingName || nameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Shown alongside your scans on the impact map (when we add public profiles).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
    }

    private var backendSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Backend").font(.headline)
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(BinSightTokens.Color.recycle)
                Text("Convex connected").font(.callout)
                Spacer()
            }
            Text(ConvexService.deploymentUrl)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
    }

    private func saveName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        savingName = true
        Task {
            defer { savingName = false }
            try? await ConvexService.shared.setDisplayName(trimmed)
        }
    }
}
