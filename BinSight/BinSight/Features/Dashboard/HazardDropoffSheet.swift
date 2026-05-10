import SwiftUI
import UIKit

struct HazardDropoffSheet: View {
    let classificationId: String
    let itemLabel: String

    @State private var result: DropoffResultDoc?
    @State private var error: String?
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let result, !result.places.isEmpty {
                    resultsList(result)
                } else {
                    emptyView
                }
            }
            .background(DuoBackdrop().ignoresSafeArea())
            .navigationTitle("Closest drop-off")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { HapticEngine.tap(); dismiss() }
                }
            }
        }
        .task { await load() }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            MascotArtView(mood: .thinking, size: 96, accessory: "magnifyingglass")
            Text("Finding the best place for \(itemLabel)…")
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(BinSightTokens.Color.ink)
                .multilineTextAlignment(.center)
            Text("Searching municipal HHW programs and certified take-back sites near you.")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(BinSightTokens.Color.softInk)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            MascotArtView(mood: .thinking, size: 96, accessory: "questionmark.circle")
            Text("No nearby drop-off found")
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(BinSightTokens.Color.ink)
            Text(error ?? "Try the city's general HHW page or call 311.")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(BinSightTokens.Color.softInk)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultsList(_ r: DropoffResultDoc) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Tap to navigate. Best matches for \(itemLabel)")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(BinSightTokens.Color.softInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(r.places) { place in
                    PlaceRow(place: place)
                }
            }
            .padding(18)
            .padding(.bottom, 40)
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            let r = try await ConvexService.shared.bestDropoff(classificationId: classificationId)
            await MainActor.run {
                self.result = r
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = (error as NSError).localizedDescription
                self.isLoading = false
            }
        }
    }
}

private struct PlaceRow: View {
    let place: DropoffResultDoc.Place

    var body: some View {
        Button {
            tapAndOpen()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(BinSightTokens.Color.hazard, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.name)
                            .font(.system(.headline, design: .rounded).weight(.heavy))
                            .foregroundStyle(BinSightTokens.Color.ink)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Text(place.address)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(BinSightTokens.Color.accent)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                if !place.acceptsThisItem.isEmpty {
                    Label(place.acceptsThisItem, systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BinSightTokens.Color.recycle)
                        .lineLimit(2)
                }
                if !place.notes.isEmpty {
                    Text(place.notes)
                        .font(.callout)
                        .foregroundStyle(BinSightTokens.Color.softInk)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                HStack(spacing: 16) {
                    if !place.hours.isEmpty {
                        Label(place.hours, systemImage: "clock")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BinSightTokens.Color.softInk)
                            .lineLimit(1)
                    }
                    if !place.phone.isEmpty {
                        Button {
                            callPhone()
                        } label: {
                            Label(place.phone, systemImage: "phone.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BinSightTokens.Color.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.caption.weight(.heavy))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(BinSightTokens.Color.hazard.opacity(0.18), in: Capsule())
                        .foregroundStyle(BinSightTokens.Color.hazard)
                }
                if !place.sourceUrl.isEmpty {
                    Link(destination: URL(string: place.sourceUrl) ?? URL(string: "https://example.com")!) {
                        Text(hostOf(place.sourceUrl))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BinSightTokens.Color.accent)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(BinSightTokens.Color.stroke, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func tapAndOpen() {
        HapticEngine.tap()
        openInMaps()
    }

    private func openInMaps() {
        let address = place.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? address
        let nameEncoded = place.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        // Apple Maps deep link. `daddr` triggers turn-by-turn directions
        // from the user's current location; `q` keeps the pin labelled.
        let urlString = "http://maps.apple.com/?daddr=\(encoded)&q=\(nameEncoded)"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }

    private func callPhone() {
        let digits = place.phone.filter { "0123456789+".contains($0) }
        guard !digits.isEmpty, let url = URL(string: "tel:\(digits)") else { return }
        UIApplication.shared.open(url)
    }

    private func hostOf(_ raw: String) -> String {
        URL(string: raw)?.host?.replacingOccurrences(of: "www.", with: "") ?? raw
    }
}
