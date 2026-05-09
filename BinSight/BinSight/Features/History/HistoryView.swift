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
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(rows) { row in
                            HistoryRow(doc: row, onTap: { openId = row._id })
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 110)
                }
            }
        }
        .navigationTitle("History")
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
            Image(systemName: "tray.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("No scans yet").font(.headline)
            Text("Tap the camera tab to start scanning waste.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct Identified: Identifiable { let value: String; var id: String { value } }
}

private struct HistoryRow: View {
    let doc: ClassificationDoc
    let onTap: () -> Void
    @State private var dragOffset: CGFloat = 0
    @State private var deleteHinted = false

    private let deleteThreshold: CGFloat = -88

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete background
            HStack {
                Spacer()
                Image(systemName: "trash.fill")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .background(BinSightTokens.Color.trash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(min(1, abs(dragOffset) / 88))

            // Main row
            Button(action: onTap) { rowContent }
                .buttonStyle(.plain)
                .offset(x: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { v in
                            dragOffset = min(0, v.translation.width)
                            let crossed = dragOffset < deleteThreshold
                            if crossed != deleteHinted {
                                deleteHinted = crossed
                                let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
                            }
                        }
                        .onEnded { v in
                            if v.translation.width < deleteThreshold {
                                Task { try? await ConvexService.shared.deleteClassification(id: doc._id) }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    dragOffset = -600
                                }
                            } else {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            // Decision color band
            Capsule()
                .fill(decisionColor)
                .frame(width: 4, height: 64)
                .padding(.vertical, 4)

            // Image
            if let urlString = doc.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                placeholder: { Color.gray.opacity(0.2) }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Title + meta
            VStack(alignment: .leading, spacing: 4) {
                Text(doc.items.first?.label.capitalized ?? (doc.status == "pending" ? "Classifying…" : "—"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let first = doc.items.first {
                    HStack(spacing: 6) {
                        Text(first.decision.capitalized)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(decisionColor, in: Capsule())
                        if let region = regionLabel {
                            Label(region, systemImage: "mappin")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                if let rules = doc.localRules, !rules.isEmpty {
                    Text(rules)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: 96)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
    }

    private var regionLabel: String? {
        let parts = [doc.city, doc.state].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.first
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
