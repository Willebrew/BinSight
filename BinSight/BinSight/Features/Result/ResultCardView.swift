import SwiftUI

struct ResultCardView: View {
    let classificationId: String
    @State private var doc: ClassificationDoc?
    @State private var error: String?

    var body: some View {
        GlassRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let d = doc {
                        header(d)
                        if d.status == "pending" {
                            HStack { ProgressView(); Text("Classifying…") }
                                .padding(.vertical, 24)
                                .frame(maxWidth: .infinity)
                        } else if d.status == "error" {
                            Text(d.errorMessage ?? "Something went wrong.")
                                .foregroundStyle(.red)
                        } else {
                            ForEach(d.items) { item in
                                ItemRow(item: item)
                            }
                            if let rules = d.localRules, !rules.isEmpty {
                                rulesBox(rules)
                            }
                            if !d.citations.isEmpty {
                                citations(d.citations)
                            }
                        }
                    } else if let err = error {
                        Text(err).foregroundStyle(.red)
                    } else {
                        ProgressView().padding(40)
                    }
                }
                .padding(20)
            }
        }
        .task { subscribe() }
    }

    private func header(_ d: ClassificationDoc) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let urlString = d.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Result")
                    .font(.title2.weight(.bold))
                Text(Date(timeIntervalSince1970: d.capturedAt / 1000).formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
                if d.verified {
                    Label("Verified", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BinSightTokens.Color.recycle)
                }
            }
            Spacer()
        }
    }

    private func rulesBox(_ rules: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Local rules", systemImage: "mappin.and.ellipse")
                .font(.caption.weight(.semibold))
            Text(rules).font(.callout)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .clear)
    }

    private func citations(_ urls: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sources").font(.caption.weight(.semibold))
            ForEach(urls, id: \.self) { u in
                if let url = URL(string: u) {
                    Link(u, destination: url).font(.caption).lineLimit(1)
                }
            }
        }
    }

    private func subscribe() {
        let cancellable = ConvexService.shared.subscribeClassification(id: classificationId)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let e) = completion { error = e.localizedDescription }
            } receiveValue: { value in
                self.doc = value
            }
        // Hold ownership for view lifetime
        Self.subscriptions[classificationId] = cancellable
    }

    private static var subscriptions: [String: AnyCancellable] = [:]
}

private struct ItemRow: View {
    let item: ItemDoc

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            decisionPill
            VStack(alignment: .leading, spacing: 4) {
                Text(item.label).font(.headline)
                Text(item.material.capitalized).font(.caption).foregroundStyle(.secondary)
                Text(item.disposalNotes).font(.callout)
                ProgressView(value: item.confidence)
                    .tint(decisionColor)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), variant: .regular)
    }

    private var decisionColor: Color {
        switch item.decision {
        case "recycle": return BinSightTokens.Color.recycle
        case "compost": return BinSightTokens.Color.compost
        case "hazard":  return BinSightTokens.Color.hazard
        default:        return BinSightTokens.Color.trash
        }
    }

    private var decisionPill: some View {
        Text(item.decision.capitalized)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(decisionColor.opacity(0.18), in: Capsule())
            .foregroundStyle(decisionColor)
    }
}

import Combine
