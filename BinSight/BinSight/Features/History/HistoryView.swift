import SwiftUI

struct HistoryView: View {
    @ObservedObject private var store = LocalHistoryStore.shared
    @State private var openId: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if store.rows.isEmpty {
                    Text("No scans yet — tap the shutter on the camera tab to get started.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(40)
                }
                ForEach(store.rows) { row in
                    Button { openId = row._id } label: { HistoryRow(doc: row) }
                        .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .navigationTitle("History")
        .sheet(item: Binding(
            get: { openId.map { Identified(value: $0) } },
            set: { openId = $0?.value }
        )) { id in
            ResultCardView(classificationId: id.value)
        }
    }

    private struct Identified: Identifiable { let value: String; var id: String { value } }
}

private struct HistoryRow: View {
    let doc: ClassificationDoc

    var body: some View {
        HStack(spacing: 12) {
            if let urlString = doc.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                placeholder: { Color.gray.opacity(0.2) }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(doc.items.first?.label ?? (doc.status == "pending" ? "Classifying…" : "—"))
                    .font(.headline)
                    .lineLimit(1)
                Text(Date(timeIntervalSince1970: doc.capturedAt / 1000).formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
                if let first = doc.items.first {
                    Text(first.decision.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(color(for: first.decision), in: Capsule())
                }
            }
            Spacer()
        }
        .padding(12)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
    }

    private func color(for decision: String) -> Color {
        switch decision {
        case "recycle": return BinSightTokens.Color.recycle
        case "compost": return BinSightTokens.Color.compost
        case "hazard":  return BinSightTokens.Color.hazard
        default:        return BinSightTokens.Color.trash
        }
    }
}
