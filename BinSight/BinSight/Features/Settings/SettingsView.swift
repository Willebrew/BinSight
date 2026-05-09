import SwiftUI

struct SettingsView: View {
    @State private var convexURL: String = ConvexService.deploymentUrl

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    aboutSection
                    backendSection
                    deviceSection
                }
                .padding(20)
            }
            .navigationTitle("Settings")
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BinSight").font(.headline)
            Text("Snap a photo of any waste item, and BinSight will tell you whether to recycle, compost, trash, or treat it as hazardous.")
                .font(.callout).foregroundStyle(.secondary)
            Text("v0.2 — Convex backend, sonar-pro classifier")
                .font(.caption2.monospaced()).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
    }

    private var backendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Backend").font(.headline)
            HStack(spacing: 8) {
                Image(systemName: convexURL.isEmpty ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(convexURL.isEmpty ? BinSightTokens.Color.hazard : BinSightTokens.Color.recycle)
                Text(convexURL.isEmpty ? "CONVEX_URL missing" : "Connected")
                    .font(.callout)
                Spacer()
            }
            if !convexURL.isEmpty {
                Text(convexURL)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
    }

    @EnvironmentObject private var convex: ConvexService
    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Account").font(.headline)
            HStack(spacing: 8) {
                Image(systemName: convex.isAuthenticated ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.questionmark")
                    .foregroundStyle(convex.isAuthenticated ? BinSightTokens.Color.recycle : BinSightTokens.Color.hazard)
                Text(convex.isAuthenticated ? "Signed in (anonymous)" : "Not signed in")
                    .font(.callout)
                Spacer()
            }
            Text("Anonymous accounts identify your scans on the backend. Sign In with Apple is on the roadmap.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
    }
}
