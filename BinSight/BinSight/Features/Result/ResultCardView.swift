import SwiftUI
import Combine
import UIKit

struct ResultCardView: View {
    let classificationId: String
    @State private var doc: ClassificationDoc?
    @State private var error: String?
    @State private var subscription: AnyCancellable?
    @State private var sparkle = false

    var body: some View {
        Group {
            if let d = doc {
                if d.needsReview {
                    // Swipe-first mode: dedicated full-screen triage view.
                    // No outer ScrollView so drag gestures aren't stolen.
                    SwipeTriageScreen(doc: d)
                } else {
                    // Reviewed mode: scrollable list with collapsed rows.
                    reviewedView(for: d)
                }
            } else if let err = error {
                Text(err).foregroundStyle(.red).padding()
            } else {
                loadingState
            }
        }
        .background(backdrop.ignoresSafeArea())
        .onAppear { subscribe() }
        .onDisappear { subscription?.cancel() }
    }

    // MARK: - Reviewed (post-swipe) view

    @ViewBuilder
    private func reviewedView(for d: ClassificationDoc) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(d)
                VStack(alignment: .leading, spacing: 14) {
                    if d.status == "pending" {
                        pendingBlock
                    } else if d.status == "error" {
                        errorBlock(d)
                    } else {
                        summaryBar(d)
                        ForEach(Array(d.items.enumerated()), id: \.offset) { idx, item in
                            CompactItemRow(
                                item: item,
                                sources: sources(for: item, in: d),
                                onChangeReview: { state in
                                    Task {
                                        try? await ConvexService.shared.reviewItem(
                                            id: d._id, itemIndex: idx, state: state
                                        )
                                    }
                                }
                            )
                        }
                        if let rules = d.localRules, !rules.isEmpty {
                            rulesBox(rules)
                        }
                        if let region = regionLabel(for: d) {
                            regionChip(region)
                        }
                        actionButtons(d)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 30)
            }
        }
    }

    private var pendingBlock: some View {
        VStack(spacing: 12) {
            MascotArtView(mood: .thinking, size: 96, accessory: "sparkles")
            ProgressView()
                .controlSize(.large)
                .tint(BinSightTokens.Color.recycle)
            Text("Classifying...")
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(BinSightTokens.Color.ink)
            Text("Identifying the item and looking up disposal rules.")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(BinSightTokens.Color.softInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private func errorBlock(_ d: ClassificationDoc) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(BinSightTokens.Color.hazard)
            Text(d.errorMessage ?? "Something went wrong.")
                .multilineTextAlignment(.center)
                .foregroundStyle(BinSightTokens.Color.softInk)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BinSightTokens.Color.hazard.opacity(0.28), lineWidth: 2))
    }

    private var backdrop: some View {
        DuoBackdrop()
    }

    @ViewBuilder
    private var loadingState: some View {
        VStack(spacing: 14) {
            MascotArtView(mood: .thinking, size: 130, accessory: "magnifyingglass")
                .symbolEffect(.bounce, value: sparkle)
                .onAppear { sparkle = true }
            Text("Analyzing your scan...")
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(BinSightTokens.Color.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(48)
    }

    private func sources(for item: ItemDoc, in d: ClassificationDoc) -> [SourceDoc] {
        item.sourceIndices.compactMap { idx in
            (idx >= 0 && idx < d.sources.count) ? d.sources[idx] : nil
        }
    }

    private func hero(_ d: ClassificationDoc) -> some View {
        ZStack(alignment: .bottomLeading) {
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
            .frame(height: 220)
            .clipped()
            .overlay(
                LinearGradient(
                    colors: [.black.opacity(0.0), .black.opacity(0.55)],
                    startPoint: .center, endPoint: .bottom
                )
            )

            if d.verified {
                Label("Verified", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(BinSightTokens.Color.recycle)
                    .padding(.top, 12).padding(.trailing, 12)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
            }

            // Title sits at the bottom of the hero, well clear of the back button
            VStack(alignment: .leading, spacing: 4) {
                if let primary = d.items.first {
                    Text(primary.label.capitalized)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                }
                Text(Date(timeIntervalSince1970: d.capturedAt / 1000)
                        .formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(14)
        }
        .frame(height: 220)
    }

    private var heroPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [BinSightTokens.Color.accent.opacity(0.25),
                         BinSightTokens.Color.recycle.opacity(0.25)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func summaryBar(_ d: ClassificationDoc) -> some View {
        let confirmed = d.items.filter { $0.reviewState == "confirmed" }.count
        let rejected = d.items.filter { $0.reviewState == "rejected" }.count
        let totalCo2 = d.items
            .filter { $0.reviewState == "confirmed" }
            .reduce(0.0) { $0 + $1.co2Kg }
        return HStack(spacing: 12) {
            chip(icon: "checkmark.circle.fill",
                 text: "\(confirmed) confirmed",
                 color: BinSightTokens.Color.recycle)
            if rejected > 0 {
                chip(icon: "xmark.circle.fill",
                     text: "\(rejected) ignored",
                     color: .secondary)
            }
            Spacer()
            if totalCo2 > 0 {
                Text(String(format: "%.2f kg", totalCo2))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(BinSightTokens.Color.recycle)
            }
        }
        .padding(.horizontal, 4)
    }

    private func chip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).imageScale(.small)
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
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

// MARK: - Swipe-first triage screen
//
// Lives at the root of the navigation, NOT inside a ScrollView. This is
// the key to the gesture working — SwiftUI's drag-gesture absorption from
// outer scroll views is the most common cause of "swipe doesn't work."

private struct SwipeTriageScreen: View {
    let doc: ClassificationDoc

    @State private var dragOffset: CGSize = .zero
    @State private var lastFlash: String?      // brief "Confirmed!" overlay after a swipe
    @State private var flashId = 0

    private var pending: [(offset: Int, item: ItemDoc)] {
        doc.items.enumerated()
            .filter { $0.element.reviewState == "pending" }
            .map { (offset: $0.offset, item: $0.element) }
    }

    var body: some View {
        let items = pending
        VStack(spacing: 0) {
            header(remaining: items.count)
                .padding(.horizontal, 16)
                .padding(.top, 4)

            ZStack {
                ForEach(visibleStack(items), id: \.offset) { entry in
                    let depth = entry.depth
                    let isTop = depth == 0
                    TriageCard(
                        item: entry.item,
                        sources: sources(for: entry.item),
                        imageUrl: doc.imageUrl
                    )
                    .frame(maxWidth: 360)
                    .scaleEffect(isTop ? 1.0 : (1.0 - CGFloat(depth) * 0.04))
                    .offset(
                        x: isTop ? dragOffset.width : 0,
                        y: isTop ? dragOffset.height * 0.15 : CGFloat(depth) * 12
                    )
                    .rotationEffect(isTop ? .degrees(Double(dragOffset.width / 22)) : .zero)
                    .opacity(isTop ? 1.0 : (1.0 - Double(depth) * 0.18))
                    // Decision color "tint" on swipe
                    .overlay {
                        if isTop, abs(dragOffset.width) > 20 {
                            let isConfirm = dragOffset.width > 0
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill((isConfirm ? BinSightTokens.Color.recycle
                                       : Color.secondary).opacity(min(0.35, abs(dragOffset.width) / 400)))
                            VStack {
                                HStack {
                                    if !isConfirm {
                                        decisionStamp("IGNORE",
                                                      color: .secondary,
                                                      angle: -18)
                                            .opacity(min(1, -dragOffset.width / 110))
                                    }
                                    Spacer()
                                    if isConfirm {
                                        decisionStamp("CONFIRM",
                                                      color: BinSightTokens.Color.recycle,
                                                      angle: 18)
                                            .opacity(min(1, dragOffset.width / 110))
                                    }
                                }
                                Spacer()
                            }
                            .padding(28)
                        }
                    }
                    .gesture(isTop ? dragGesture(for: entry.offset) : nil)
                    .animation(.spring(response: 0.45, dampingFraction: 0.78),
                               value: dragOffset)
                }
                if let flash = lastFlash {
                    flashOverlay(flash)
                        .id(flashId)
                        .transition(.scale.combined(with: .opacity))
                }
                if items.isEmpty {
                    finishedOverlay
                }
            }
            .frame(maxHeight: .infinity)

            actionRow(items: items)
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
        }
    }

    // MARK: header

    private func header(remaining: Int) -> some View {
        let total = doc.items.count
        let done = total - remaining
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "hand.draw.fill")
                    .foregroundStyle(BinSightTokens.Color.accent)
                Text("Review \(total) item\(total == 1 ? "" : "s")")
                    .font(.headline)
                Spacer()
                Text("\(done) / \(total)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            DuoProgressBar(value: Double(done), total: Double(max(1, total)), color: BinSightTokens.Color.recycle)
            Text("Swipe right to confirm. Swipe left to ignore. Only confirmed items count.")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(BinSightTokens.Color.softInk)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BinSightTokens.Color.stroke, lineWidth: 2))
    }

    private func actionRow(items: [(offset: Int, item: ItemDoc)]) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Button {
                    Task {
                        try? await ConvexService.shared.reviewAll(id: doc._id, state: "rejected")
                    }
                } label: {
                    Text("Ignore all").font(.caption.weight(.semibold))
                }
                Spacer()
                Button {
                    Task {
                        try? await ConvexService.shared.reviewAll(id: doc._id, state: "confirmed")
                        HapticEngine.success.notificationOccurred(.success)
                    }
                } label: {
                    Text("Confirm all").font(.caption.weight(.semibold))
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)

            HStack(spacing: 12) {
                triageButton("Ignore", system: "xmark", kind: .neutral, color: .secondary) {
                    guard let head = items.first else { return }
                    HapticEngine.tick()
                    send(itemIndex: head.offset, state: "rejected", flickX: -600)
                }
                triageButton("Confirm", system: "checkmark", kind: .primary, color: BinSightTokens.Color.recycle) {
                    guard let head = items.first else { return }
                    HapticEngine.ok()
                    send(itemIndex: head.offset, state: "confirmed", flickX: 600)
                }
            }
        }
    }

    private func triageButton(_ label: String, system: String, kind: DuoButtonKind, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: system)
        }
        .buttonStyle(DuoButtonStyle(kind: kind, isCompact: true))
    }

    @ViewBuilder
    private var finishedOverlay: some View {
        VStack(spacing: 14) {
            MascotArtView(mood: .celebrate, size: 118, accessory: "checkmark.seal.fill")
            Text("All reviewed").font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(BinSightTokens.Color.ink)
            Text("Pull down to see the summary.")
                .font(.system(.callout, design: .rounded).weight(.bold))
                .foregroundStyle(BinSightTokens.Color.softInk)
        }
    }

    private func flashOverlay(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.title.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 22).padding(.vertical, 10)
            .background(text == "Confirmed"
                        ? BinSightTokens.Color.recycle.opacity(0.85)
                        : Color.secondary.opacity(0.7),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
    }

    // MARK: helpers

    private struct StackEntry {
        let offset: Int
        let item: ItemDoc
        let depth: Int
    }

    private func visibleStack(_ items: [(offset: Int, item: ItemDoc)]) -> [StackEntry] {
        let visible = items.prefix(3).enumerated().map { (i, entry) in
            StackEntry(offset: entry.offset, item: entry.item, depth: i)
        }
        return Array(visible.reversed())
    }

    private func sources(for item: ItemDoc) -> [SourceDoc] {
        item.sourceIndices.compactMap { idx in
            (idx >= 0 && idx < doc.sources.count) ? doc.sources[idx] : nil
        }
    }

    private func dragGesture(for itemIndex: Int) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let threshold: CGFloat = 100
                if value.translation.width > threshold {
                    HapticEngine.ok()
                    send(itemIndex: itemIndex, state: "confirmed", flickX: 600)
                } else if value.translation.width < -threshold {
                    HapticEngine.tick()
                    send(itemIndex: itemIndex, state: "rejected", flickX: -600)
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    private func send(itemIndex: Int, state: String, flickX: CGFloat) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            dragOffset = CGSize(width: flickX, height: 0)
        }
        Task { @MainActor in
            try? await ConvexService.shared.reviewItem(
                id: doc._id, itemIndex: itemIndex, state: state
            )
            try? await Task.sleep(nanoseconds: 220_000_000)
            withAnimation(.easeOut(duration: 0.18)) {
                lastFlash = state == "confirmed" ? "Confirmed" : "Ignored"
                flashId += 1
            }
            dragOffset = .zero
            try? await Task.sleep(nanoseconds: 600_000_000)
            withAnimation(.easeOut(duration: 0.2)) { lastFlash = nil }
        }
    }

    private func decisionStamp(_ text: String, color: Color, angle: Double) -> some View {
        Text(text)
            .font(.title.weight(.heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(color, lineWidth: 4)
            )
            .rotationEffect(.degrees(angle))
    }
}

// MARK: - Triage card (the swipeable card shown above)

private struct TriageCard: View {
    let item: ItemDoc
    let sources: [SourceDoc]
    let imageUrl: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // small image strip at top (helps user remember what's in the photo)
            ZStack(alignment: .topLeading) {
                if let urlString = imageUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Color.secondary.opacity(0.15)
                        }
                    }
                    .frame(height: 110)
                    .clipped()
                } else {
                    Color.secondary.opacity(0.15).frame(height: 110)
                }
                LinearGradient(
                    colors: [.black.opacity(0.0), .black.opacity(0.4)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 110)
                HStack(spacing: 8) {
                    decisionBadge
                        .padding(.leading, 10)
                        .padding(.top, 10)
                    Spacer()
                    ConfidencePill(value: item.confidence, color: decisionColor)
                        .padding(.trailing, 10)
                        .padding(.top, 10)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(item.label.capitalized)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(item.material.capitalized)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(decisionColor.opacity(0.14), in: Capsule())
                        .foregroundStyle(decisionColor)
                    if item.co2Kg > 0 {
                        Text(String(format: "%.2f kg CO₂e", item.co2Kg))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Text(item.disposalNotes)
                    .font(.callout)
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(4)

                if let topSource = sources.first {
                    HStack(spacing: 6) {
                        Image(systemName: tierIcon(topSource.tier))
                            .imageScale(.small)
                            .foregroundStyle(tierColor(topSource.tier))
                        Text(topSource.publisher.isEmpty ? hostOf(topSource.url) : topSource.publisher)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        if topSource.isLocal {
                            Text("local")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(BinSightTokens.Color.accent.opacity(0.15), in: Capsule())
                                .foregroundStyle(BinSightTokens.Color.accent)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .frame(height: 360)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(BinSightTokens.Color.stroke, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.12), radius: 22, x: 0, y: 10)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var decisionColor: Color { decisionTint(item.decision) }
    private var decisionBadge: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 42, height: 42)
            Image(systemName: decisionSymbol(item.decision))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(decisionColor)
        }
    }
    private func hostOf(_ s: String) -> String {
        URL(string: s)?.host?.replacingOccurrences(of: "www.", with: "") ?? s
    }
}

// MARK: - Compact item row (post-review, tap to expand)

private struct CompactItemRow: View {
    let item: ItemDoc
    let sources: [SourceDoc]
    let onChangeReview: (String) -> Void

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Always-visible compact line — this is what the user sees by default.
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    decisionBadge
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label).font(.subheadline.weight(.semibold)).lineLimit(1)
                        HStack(spacing: 6) {
                            Text(item.decision.capitalized)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(decisionColor, in: Capsule())
                                .foregroundStyle(.white)
                            Text("\(Int(item.confidence * 100))%")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            if item.co2Kg > 0 {
                                Text("·")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.2f kg", item.co2Kg))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(BinSightTokens.Color.recycle)
                            }
                            if item.reviewState == "rejected" {
                                Text("ignored")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider().padding(.horizontal, 12)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.disposalNotes)
                            .font(.callout)

                        if !sources.isEmpty {
                            SourceListView(sources: sources)
                        }

                        Co2MathView(item: item)

                        HStack(spacing: 12) {
                            Button {
                                let next = item.reviewState == "rejected" ? "confirmed" : "rejected"
                                onChangeReview(next)
                                HapticEngine.tick()
                            } label: {
                                Label(item.reviewState == "rejected" ? "Re-confirm" : "Mark as ignored",
                                      systemImage: item.reviewState == "rejected" ? "arrow.uturn.left" : "xmark.circle")
                                    .font(.caption.weight(.semibold))
                            }
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .opacity(item.reviewState == "rejected" ? 0.55 : 1.0)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BinSightTokens.Color.stroke, lineWidth: 1.5))
    }

    private var decisionColor: Color { decisionTint(item.decision) }
    private var decisionBadge: some View {
        ZStack {
            Circle()
                .fill(decisionColor.opacity(0.18))
                .frame(width: 36, height: 36)
            Image(systemName: decisionSymbol(item.decision))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(decisionColor)
        }
    }
}

// MARK: - Co2 math (in expand)

private struct Co2MathView: View {
    let item: ItemDoc

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "function")
                Text("Calculation")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(BinSightTokens.Color.accent)
            .padding(.bottom, 2)

            row("Material", value: item.material.capitalized)
            row("Mass", value: massString)
            row("Method", value: item.co2Method.isEmpty ? "—" : item.co2Method)
            row("Range", value: item.co2Kg == 0
                ? "no credit applied"
                : String(format: "%.3f – %.3f kg CO₂e", item.co2KgLow, item.co2KgHigh))
        }
        .font(.caption)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var massString: String {
        let label = item.massSource == "model" ? "estimated from photo" : "default for material"
        return "\(Int(item.estimatedMassG.rounded())) g (\(label))"
    }

    private func row(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 76, alignment: .leading)
            Text(value).foregroundStyle(.primary)
            Spacer()
        }
    }
}

// MARK: - Source list (in expand)

private struct SourceListView: View {
    let sources: [SourceDoc]
    @State private var selected: SourceDoc?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Sources")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if sources.contains(where: { $0.tier == "official" }) {
                    Image(systemName: "checkmark.shield.fill")
                        .imageScale(.small)
                        .foregroundStyle(BinSightTokens.Color.recycle)
                }
                Spacer()
            }
            ForEach(sources) { src in
                Button { selected = src } label: { SourceChip(source: src) }
                    .buttonStyle(.plain)
            }
        }
        .sheet(item: $selected) { src in
            SourceSheet(source: src)
                .presentationDetents([.medium])
        }
    }
}

private struct SourceChip: View {
    let source: SourceDoc

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tierIcon(source.tier))
                .imageScale(.small)
                .foregroundStyle(tierColor(source.tier))
            VStack(alignment: .leading, spacing: 1) {
                Text(source.publisher.isEmpty ? hostOf(source.url) : source.publisher)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if !source.title.isEmpty {
                    Text(source.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if source.isLocal {
                Text("local")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(BinSightTokens.Color.accent.opacity(0.15), in: Capsule())
                    .foregroundStyle(BinSightTokens.Color.accent)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func hostOf(_ s: String) -> String {
        URL(string: s)?.host?.replacingOccurrences(of: "www.", with: "") ?? s
    }
}

private struct SourceSheet: View {
    let source: SourceDoc

    var body: some View {
        let label = tierLabel(source.tier)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: tierIcon(source.tier))
                    .foregroundStyle(tierColor(source.tier))
                Text(label).font(.caption.weight(.bold))
                    .foregroundStyle(tierColor(source.tier))
                if source.isLocal {
                    Text("LOCAL")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(BinSightTokens.Color.accent.opacity(0.18), in: Capsule())
                        .foregroundStyle(BinSightTokens.Color.accent)
                }
                Spacer()
            }
            Text(source.title.isEmpty ? hostOf(source.url) : source.title)
                .font(.title3.weight(.bold))
            Text(source.publisher.isEmpty ? hostOf(source.url) : source.publisher)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !source.snippet.isEmpty {
                Text("\u{201C}\(source.snippet)\u{201D}")
                    .font(.callout)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Spacer()
            if let url = URL(string: source.url) {
                Link(destination: url) {
                    Label("Open in Safari", systemImage: "safari")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(BinSightTokens.Color.accent.opacity(0.18),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(BinSightTokens.Color.accent)
                }
            }
        }
        .padding(20)
    }

    private func hostOf(_ s: String) -> String {
        URL(string: s)?.host?.replacingOccurrences(of: "www.", with: "") ?? s
    }
}

// MARK: - Shared

private struct ConfidencePill: View {
    let value: Double
    let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(Int(value * 100))%")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private func decisionTint(_ d: String) -> Color {
    switch d {
    case "recycle": return BinSightTokens.Color.recycle
    case "compost": return BinSightTokens.Color.compost
    case "hazard":  return BinSightTokens.Color.hazard
    default:        return BinSightTokens.Color.trash
    }
}

private func decisionSymbol(_ d: String) -> String {
    switch d {
    case "recycle": return "arrow.3.trianglepath"
    case "compost": return "leaf.fill"
    case "hazard":  return "exclamationmark.triangle.fill"
    default:        return "trash.fill"
    }
}

private func tierIcon(_ t: String) -> String {
    switch t {
    case "official":      return "checkmark.seal.fill"
    case "authoritative": return "newspaper.fill"
    case "community":     return "bubble.left.fill"
    default:              return "link"
    }
}

private func tierColor(_ t: String) -> Color {
    switch t {
    case "official":      return BinSightTokens.Color.recycle
    case "authoritative": return BinSightTokens.Color.accent
    case "community":     return .secondary
    default:              return .secondary
    }
}

private func tierLabel(_ t: String) -> String {
    switch t {
    case "official":      return "OFFICIAL"
    case "authoritative": return "AUTHORITATIVE"
    case "community":     return "COMMUNITY"
    default:              return "WEB"
    }
}
