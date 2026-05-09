import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = LocalHistoryStore.shared
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    aboutSection
                    apiSection
                    dataSection
                }
                .padding(20)
            }
            .navigationTitle("Settings")
        }
        .confirmationDialog("Erase all local history?", isPresented: $showResetConfirm) {
            Button("Erase", role: .destructive) {
                LocalHistoryStore.shared.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BinSight").font(.headline)
            Text("Snap a photo of any waste item, and BinSight will tell you whether to recycle, compost, trash, or treat it as hazardous.")
                .font(.callout).foregroundStyle(.secondary)
            Text("v0.1 — direct Perplexity mode")
                .font(.caption2.monospaced()).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
    }

    private var apiSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Classification API").font(.headline)
            HStack {
                Image(systemName: PerplexityClient.isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(PerplexityClient.isConfigured ? BinSightTokens.Color.recycle : BinSightTokens.Color.hazard)
                Text(PerplexityClient.isConfigured ? "Perplexity API key configured" : "PERPLEXITY_API_KEY missing in Info.plist")
                    .font(.callout)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Data").font(.headline)
            Text("\(store.rows.count) scans saved on this device")
                .font(.callout).foregroundStyle(.secondary)
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Text("Erase history").frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .glassSurface(RoundedRectangle(cornerRadius: 14, style: .continuous), variant: .clear)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
    }
}
