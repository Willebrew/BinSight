import SwiftUI
import Combine

struct HistoryView: View {
    @State private var rows: [ClassificationDoc] = []
    @State private var openId: String?
    @State private var subscription: AnyCancellable?

    var body: some View {
        Group {
            if rows.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(rows) { row in
                        Button { openId = row._id } label: {
                            HistoryRow(doc: row)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { try? await ConvexService.shared.deleteClassification(id: row._id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 130, for: .scrollContent)
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .background(DuoBackdrop().ignoresSafeArea())
        .onAppear {
            subscription = ConvexService.shared.subscribeHistory()
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in }, receiveValue: { rows = $0 })
        }
        .onDisappear { subscription?.cancel() }
        .sheet(item: Binding(
            get: { openId.map { Identified(value: $0) } },
            set: { openId = $0?.value }
        )) { id in
            ResultCardView(classificationId: id.value)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            MascotArtView(mood: .thinking, size: 112, accessory: "tray.fill")
            Text("No scans yet")
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(BinSightTokens.Color.ink)
            Text("Tap the camera tab to start scanning waste.")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(BinSightTokens.Color.softInk)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct Identified: Identifiable { let value: String; var id: String { value } }
}

private struct HistoryRow: View {
    let doc: ClassificationDoc

    var body: some View {
        HStack(spacing: 14) {
            thumbnail
            VStack(alignment: .leading, spacing: 6) {
                Text(doc.items.first?.label.capitalized
                     ?? (doc.status == "pending" ? "Classifying…" : "—"))
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(BinSightTokens.Color.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    decisionPill
                    if let region = regionLabel {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin")
                                .imageScale(.small)
                            Text(region)
                        }
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(BinSightTokens.Color.softInk)
                        .lineLimit(1)
                    }
                    if let kg = primaryCo2 {
                        Text(String(format: "%.2f kg", kg))
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(BinSightTokens.Color.recycle)
                    }
                }
                Text(dateLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BinSightTokens.Color.softInk)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(BinSightTokens.Color.softInk.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(BinSightTokens.Color.stroke, lineWidth: 1.5))
    }

    private var thumbnail: some View {
        Group {
            if let urlString = doc.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        thumbnailPlaceholder
                    }
                }
            } else {
                thumbnailPlaceholder
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Image(systemName: duoDecisionSymbol(doc.items.first?.decision ?? "trash"))
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .padding(5)
                .background(decisionColor, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                .offset(x: -4, y: 4)
        }
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            decisionColor.opacity(0.2)
            Image(systemName: duoDecisionSymbol(doc.items.first?.decision ?? "trash"))
                .foregroundStyle(decisionColor)
        }
    }

    private var decisionPill: some View {
        Text((doc.items.first?.decision ?? "—").capitalized)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(decisionColor, in: Capsule())
    }

    private var regionLabel: String? {
        let parts = [doc.city, doc.state].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.first
    }

    private var dateLabel: String {
        Date(timeIntervalSince1970: doc.capturedAt / 1000)
            .formatted(.relative(presentation: .named))
    }

    private var primaryCo2: Double? {
        let confirmed = doc.items.filter { $0.reviewState == "confirmed" }
        let total = confirmed.reduce(0.0) { $0 + $1.co2Kg }
        return total > 0 ? total : nil
    }

    private var decisionColor: Color {
        switch doc.items.first?.decision {
        case "recycle": return BinSightTokens.Color.recycle
        case "compost": return BinSightTokens.Color.compost
        case "hazard":  return BinSightTokens.Color.hazard
        default:        return BinSightTokens.Color.trash
        }
    }
}
