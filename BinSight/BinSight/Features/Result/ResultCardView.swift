import SwiftUI
import Combine

struct ResultCardView: View {
    let classificationId: String
    @State private var doc: ClassificationDoc?
    @State private var error: String?
    @State private var subscription: AnyCancellable?
    @State private var sparkle = false

    var body: some View {
        ZStack {
            backdrop
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let d = doc {
                        hero(d)
                        body(for: d)
                    } else if let err = error {
                        Text(err).foregroundStyle(.red).padding()
                    } else {
                        loadingState
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
        }
        .onAppear { subscribe() }
        .onDisappear { subscription?.cancel() }
    }

    private var backdrop: some View {
        LinearGradient(
            colors: [Color(.systemGroupedBackground), Color(.systemBackground)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var loadingState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(BinSightTokens.Color.accent)
                .symbolEffect(.variableColor.iterative, isActive: sparkle)
                .onAppear { sparkle = true }
            Text("Analyzing your scan…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(48)
    }

    @ViewBuilder
    private func body(for d: ClassificationDoc) -> some View {
        if d.status == "pending" {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(BinSightTokens.Color.accent)
                Text("Classifying…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        } else if d.status == "error" {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(BinSightTokens.Color.hazard)
                Text(d.errorMessage ?? "Something went wrong.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), variant: .regular)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(d.items.enumerated()), id: \.offset) { idx, item in
                    ItemRow(item: item, delay: Double(idx) * 0.05)
                }
                if let rules = d.localRules, !rules.isEmpty {
                    rulesBox(rules)
                }
                if !d.citations.isEmpty {
                    citationChips(d.citations)
                }
                if let region = regionLabel(for: d) {
                    regionChip(region)
                }
                actionButtons(d)
            }
        }
    }

    private func hero(_ d: ClassificationDoc) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let urlString = d.imageUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            heroPlaceholder
                        }
                    }
                } else {
                    heroPlaceholder
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                LinearGradient(
                    colors: [.black.opacity(0.0), .black.opacity(0.45)],
                    startPoint: .top, endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            )

            // Top-right verified badge
            if d.verified {
                Label("Verified", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(BinSightTokens.Color.recycle)
                    .padding(12)
            }

            // Bottom-leading title overlay
            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                if let primary = d.items.first {
                    Text(primary.label.capitalized)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                Text(Date(timeIntervalSince1970: d.capturedAt / 1000)
                        .formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: 240)
    }

    private var heroPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [BinSightTokens.Color.accent.opacity(0.25), BinSightTokens.Color.recycle.opacity(0.25)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func rulesBox(_ rules: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Local rules", systemImage: "mappin.and.ellipse")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BinSightTokens.Color.accent)
            Text(rules).font(.callout)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .clear)
    }

    private func citationChips(_ urls: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(urls.prefix(6), id: \.self) { u in
                    if let url = URL(string: u), let host = url.host {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Image(systemName: "link").imageScale(.small)
                                Text(host).font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule())
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
    }

    private func regionChip(_ region: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin.circle.fill")
            Text(region)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .foregroundStyle(.secondary)
    }

    private func actionButtons(_ d: ClassificationDoc) -> some View {
        HStack(spacing: 10) {
            ShareLink(item: shareString(for: d)) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            .foregroundStyle(.primary)

            Button(role: .destructive) {
                Task {
                    try? await ConvexService.shared.deleteClassification(id: d._id)
                }
            } label: {
                Label("Delete", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func regionLabel(for d: ClassificationDoc) -> String? {
        let parts = [d.city, d.state, d.country].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func shareString(for d: ClassificationDoc) -> String {
        guard let item = d.items.first else { return "BinSight scan" }
        return "BinSight identified a \(item.label) — \(item.decision.uppercased()) (\(Int(item.confidence * 100))% confidence)."
    }

    private func subscribe() {
        subscription = ConvexService.shared.subscribeClassification(id: classificationId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let e) = completion { error = e.localizedDescription }
                },
                receiveValue: { value in self.doc = value }
            )
    }
}

private struct ItemRow: View {
    let item: ItemDoc
    let delay: Double
    @State private var visible = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            decisionBadge
            VStack(alignment: .leading, spacing: 6) {
                Text(item.label).font(.headline)
                Text(item.material.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(item.disposalNotes).font(.callout)
                ConfidenceBar(value: item.confidence, color: decisionColor)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), variant: .regular)
        .scaleEffect(visible ? 1 : 0.95)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 12)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(delay)) {
                visible = true
            }
        }
    }

    private var decisionColor: Color {
        switch item.decision {
        case "recycle": return BinSightTokens.Color.recycle
        case "compost": return BinSightTokens.Color.compost
        case "hazard":  return BinSightTokens.Color.hazard
        default:        return BinSightTokens.Color.trash
        }
    }

    private var decisionIcon: String {
        switch item.decision {
        case "recycle": return "arrow.3.trianglepath"
        case "compost": return "leaf.fill"
        case "hazard":  return "exclamationmark.triangle.fill"
        default:        return "trash.fill"
        }
    }

    private var decisionBadge: some View {
        ZStack {
            Circle()
                .fill(decisionColor.opacity(0.18))
                .frame(width: 44, height: 44)
            Image(systemName: decisionIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(decisionColor)
        }
    }
}

private struct ConfidenceBar: View {
    let value: Double
    let color: Color
    @State private var animated: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Confidence")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.12))
                    Capsule().fill(color).frame(width: geo.size.width * animated)
                }
            }
            .frame(height: 6)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) {
                animated = value
            }
        }
    }
}

// Minimal wrapping flow layout for citation chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x - bounds.minX + sz.width > maxW {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: sz.width, height: sz.height))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
