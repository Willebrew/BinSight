import SwiftUI
import Combine

struct SettingsView: View {
    @EnvironmentObject private var convex: ConvexService
    @State private var profile: ProfileDoc?
    @State private var subscription: AnyCancellable?
    @State private var nameDraft = ""
    @State private var savingName = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    profileHero
                    aboutSection
                    accountSection
                    nameSection
                    methodologyLink
                    signOutButton
                }
                .padding(20)
                .padding(.bottom, 130)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .background(DuoBackdrop().ignoresSafeArea())
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

    private var profileHero: some View {
        DuoCard(fill: .white, stroke: BinSightTokens.Color.recycle.opacity(0.28), radius: 26, padding: 18) {
            HStack(spacing: 15) {
                MascotArtView(mood: .happy, size: 86, accessory: "person.fill")
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile?.displayName ?? "BinSight learner")
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(BinSightTokens.Color.ink)
                    Text(profile?.email ?? "Tune your impact coach")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(BinSightTokens.Color.softInk)
                        .lineLimit(1)
                    DuoBadge(text: convex.authState == .signedIn ? "Signed in" : "Guest",
                             systemImage: convex.authState == .signedIn ? "checkmark.seal.fill" : "person.crop.circle",
                             color: convex.authState == .signedIn ? BinSightTokens.Color.recycle : BinSightTokens.Color.hazard)
                }
                Spacer()
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            DuoSectionHeader(title: "About", systemImage: "leaf.fill")
            Text("BinSight uses AI to identify waste items and provide accurate disposal guidance for recycling, composting, trash, and hazardous materials.")
                .font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(BinSightTokens.Color.softInk)
            Text("Version 1.0")
                .font(.caption2.monospaced().weight(.semibold)).foregroundStyle(BinSightTokens.Color.softInk)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BinSightTokens.Color.stroke, lineWidth: 1.5))
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                DuoSectionHeader(title: "Account", systemImage: "person.crop.circle.fill")
                Spacer()
                if profile?.isAppleLinked == true {
                    Label("Apple linked", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BinSightTokens.Color.recycle)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: (convex.authState == .signedIn)
                      ? "person.crop.circle.fill"
                      : "person.crop.circle.badge.questionmark")
                    .foregroundStyle((convex.authState == .signedIn)
                                     ? BinSightTokens.Color.accent
                                     : BinSightTokens.Color.hazard)
                VStack(alignment: .leading) {
                    Text(profile?.displayName ?? (profile?.isAppleLinked == true ? "Apple user" : "Anonymous"))
                        .font(.system(.callout, design: .rounded).weight(.heavy))
                    if let email = profile?.email {
                        Text(email).font(.system(.caption, design: .rounded).weight(.semibold)).foregroundStyle(BinSightTokens.Color.softInk)
                    } else {
                        Text((convex.authState == .signedIn) ? "Signed in" : "Not signed in")
                            .font(.system(.caption, design: .rounded).weight(.semibold)).foregroundStyle(BinSightTokens.Color.softInk)
                    }
                }
                Spacer()
            }

            // Sign In with Apple requires a paid Apple Developer account.
            // Once you upgrade the team that signs this app, re-add the
            // SIWA capability + bring back AppleSignIn.swift to enable it.
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BinSightTokens.Color.stroke, lineWidth: 1.5))
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DuoSectionHeader(title: "Display name", systemImage: "pencil")
            HStack {
                TextField("Your name", text: $nameDraft)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(BinSightTokens.Color.stroke, lineWidth: 1.5))
                Button {
                    saveName()
                } label: {
                    if savingName { ProgressView() } else { Text("Save") }
                }
                .buttonStyle(DuoButtonStyle(kind: .secondary, isCompact: true))
                .disabled(savingName || nameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Shown alongside your scans on the impact map (when we add public profiles).")
                .font(.system(.caption, design: .rounded).weight(.semibold)).foregroundStyle(BinSightTokens.Color.softInk)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BinSightTokens.Color.stroke, lineWidth: 1.5))
    }

    private var methodologyLink: some View {
        NavigationLink {
            MethodologyView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "function")
                    .foregroundStyle(BinSightTokens.Color.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Methodology").font(.system(.subheadline, design: .rounded).weight(.heavy))
                    Text("How CO₂ + sources are measured")
                        .font(.system(.caption, design: .rounded).weight(.semibold)).foregroundStyle(BinSightTokens.Color.softInk)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BinSightTokens.Color.stroke, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var signOutButton: some View {
        Button(role: .destructive) {
            Task { await convex.signOut() }
        } label: {
            Text("Sign out")
        }
        .buttonStyle(DuoButtonStyle(kind: .destructive))
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
