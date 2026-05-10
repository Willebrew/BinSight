import SwiftUI
import Combine
import UIKit

struct ResultCardView: View {
    let classificationId: String
    @State private var doc: ClassificationDoc?
    @State private var error: String?
    @State private var subscription: AnyCancellable?
    @State private var sparkle = false
    @State private var hadDoc = false
    @State private var lastItemCount = 0
    @State private var lastStatus: String?
    @State private var thinkingActive = false
    @State private var lastProgressCount = 0
    /// True once we've seen this row in `pending` state. Replays of
    /// already-done scans never flip this, so they skip the catch-up
    /// haptics and feel identical to fresh scans (just silent).
    @State private var hasSeenLive = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let d = doc {
                if d.needsReview && d.status == "done" {
                    // Swipe-first mode kicks in only once the row is
                    // committed. While `status == "pending"` we keep
                    // the streaming view up so the activity feed +
                    // source pills can keep flowing under the just-
                    // arrived item card.
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
        .onDisappear {
            subscription?.cancel()
            if thinkingActive {
                HapticEngine.stopThinking()
                thinkingActive = false
            }
        }
    }

    // MARK: - Reviewed (post-swipe) view

    @ViewBuilder
    private func reviewedView(for d: ClassificationDoc) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(d)
                    .background(alignment: .top) {
                        // Stretchy header backstop: covers the rubber-band
                        // overscroll region above the hero so we never see
                        // white sheet background bleeding through.
                        Color.black.opacity(0.35)
                            .frame(height: 600)
                            .offset(y: -600)
                    }
                VStack(alignment: .leading, spacing: 14) {
                    if d.status == "pending" {
                        streamingBlock(d)
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
                .padding(.bottom, 140)
            }
        }
    }

    @ViewBuilder
    private func streamingBlock(_ d: ClassificationDoc) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small).tint(BinSightTokens.Color.recycle)
                Text(streamHeadline(for: d))
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(BinSightTokens.Color.ink)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: streamHeadline(for: d))
                    .id(streamHeadline(for: d))
                    .transition(.opacity)
                Spacer()
                if !d.items.isEmpty {
                    Text("\(d.items.count) found")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(BinSightTokens.Color.softInk)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.2), value: d.items.count)
                }
            }

            // Live agent activity feed - each entry buzzes when it
            // arrives (see handleHaptics).
            agentFeed(d)

            // Source pills appear here as the model emits sources
            // through the streaming JSON parser. Even when the server
            // flushes several sources in one Convex update, we stagger
            // their reveal locally so the user feels each one land.
            StaggeredSourcePills(sources: Array(d.sources.prefix(8)))

            if !d.items.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(d.items.enumerated()), id: \.offset) { idx, item in
                        StreamingItemRow(item: item)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.85)
                                    .combined(with: .move(edge: .leading))
                                    .combined(with: .opacity),
                                removal: .opacity))
                            .id("stream-\(idx)-\(item.label)")
                    }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.78), value: d.items.count)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func agentFeed(_ d: ClassificationDoc) -> some View {
        let log = d.progressLog ?? []
        VStack(alignment: .leading, spacing: 6) {
            ForEach(log.suffix(5).reversed()) { entry in
                AgentFeedRow(text: entry.stage, isLatest: entry.id == log.last?.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity))
                    .id(entry.id)
            }
            if log.isEmpty {
                AgentFeedRow(text: "Waking up the agent…", isLatest: true)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: log.count)
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
                CachedRemoteImage(url: d.imageUrl.flatMap(URL.init(string:))) {
                    heroPlaceholder
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .clipped()
            .overlay(
                BoundingBoxOverlay(
                    imageURL: d.imageUrl.flatMap(URL.init(string:)),
                    items: d.items
                )
                .clipped()
            )
            .overlay(
                LinearGradient(
                    colors: [.black.opacity(0.0), .black.opacity(0.55)],
                    startPoint: .center, endPoint: .bottom
                )
            )

            if d.verified {
                Label("Verified", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(BinSightTokens.Color.recycle, in: Capsule())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 2)
                    .padding(.top, 14).padding(.trailing, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
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
        .frame(height: 320)
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
        let itemWord = confirmed == 1 ? "item" : "items"
        return HStack(spacing: 12) {
            chip(icon: "checkmark.circle.fill",
                 text: "\(confirmed) verified \(itemWord)",
                 color: BinSightTokens.Color.recycle)
            if rejected > 0 {
                chip(icon: "xmark.circle.fill",
                     text: "\(rejected) ignored",
                     color: .secondary)
            }
            Spacer()
            if totalCo2 > 0 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%.2f kg CO₂e", totalCo2))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(BinSightTokens.Color.recycle)
                    Text("avoided")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BinSightTokens.Color.recycle.opacity(0.85))
                }
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

    /// Strip leading bullet glyphs and torn-word artifacts from a rule
    /// snippet at render time. Mirrors `cleanRuleSnippet` on the
    /// backend so legacy rows (whose `localRules` were stored before
    /// the fix landed server-side) still render cleanly.
    private func sanitizeRuleSnippet(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip leading bullets / dashes.
        var stripped = collapsed
            .replacingOccurrences(of: #"^[-•*–·▪▸▶►‣◦\s]+"#, with: "", options: .regularExpression)
        // Torn-word fix: a 1-2 char lowercase orphan glued to an
        // uppercase word ("rPrinted on…") is almost always a search-
        // engine boundary glitch — strip it.
        stripped = stripped.replacingOccurrences(
            of: #"^([a-z]{1,2})(?=[A-Z])"#,
            with: "",
            options: .regularExpression
        )
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func rulesBox(_ rules: String) -> some View {
        let bullets = rules
            .components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map(sanitizeRuleSnippet)
            .filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: 8) {
            Label("Local rules", systemImage: "mappin.and.ellipse")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BinSightTokens.Color.accent)
            if bullets.count <= 1 {
                Text(bullets.first ?? rules).font(.callout)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•").font(.callout.weight(.bold))
                                .foregroundStyle(BinSightTokens.Color.accent)
                            Text(line).font(.callout)
                        }
                    }
                }
            }
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
                    await MainActor.run { dismiss() }
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
        return "BinSight identified a \(item.label) - \(item.decision.uppercased()) (\(Int(item.confidence * 100))% confidence)."
    }

    private func subscribe() {
        subscription = ConvexService.shared.subscribeClassification(id: classificationId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let e) = completion { error = e.localizedDescription }
                },
                receiveValue: { value in
                    if value == nil && hadDoc {
                        if thinkingActive { HapticEngine.stopThinking(); thinkingActive = false }
                        dismiss()
                        return
                    }
                    if value != nil { hadDoc = true }
                    handleHaptics(for: value)
                    self.doc = value
                }
            )
    }

    /// Drives the streaming-haptic feel: a continuous thinking pulse
    /// while the row is `pending`, a per-decision tap whenever new
    /// items land in `items`, and a celebratory swell when the row
    /// transitions to `done`. Each new item buzzes regardless of
    /// which view actually shows it — convex sometimes flips
    /// pending+[] straight to done+[item], so onAppear on a streaming
    /// row would miss the moment.
    /// Map the agent's latest progress stage into a human phase header.
    /// Phases are intentionally short and present-tense so the title
    /// reads like a status, not a sentence. Order of checks matters —
    /// later phases override earlier ones once we see evidence of them.
    private func streamHeadline(for d: ClassificationDoc) -> String {
        let log = d.progressLog ?? []
        let latest = log.last?.stage.lowercased() ?? ""

        if d.items.count > 0 { return "Classifying…" }
        if latest.contains("done") { return "Wrapping up…" }
        // Fast-pipeline stages, in canonical order.
        if latest.contains("rules ready") || latest.contains("knowledge base calibrated") {
            return "Compiling result…"
        }
        if latest.contains("checking") && latest.contains("rules") {
            return "Reading local rules…"
        }
        if latest.contains("calibrat") || latest.contains("knowledge base") {
            return "Calibrating…"
        }
        if latest.contains("caption") {
            return "Captioning…"
        }
        if latest.contains("photo") || log.isEmpty {
            return "Looking…"
        }
        return "Looking…"
    }

    private func handleHaptics(for value: ClassificationDoc?) {
        guard let v = value else { return }

        // If the row is already terminal when it first appears, the
        // user is reviewing a past scan — there's nothing to "feel
        // landing", so we silently baseline counters and skip the
        // tap/itemRevealed cascade. Live scans (status=pending at
        // first paint) get the full magical haptic treatment below.
        let progress = v.progressLog ?? []
        if !hasSeenLive && v.status != "pending" {
            lastProgressCount = progress.count
            lastItemCount = v.items.count
            lastStatus = v.status
            return
        }
        if v.status == "pending" { hasSeenLive = true }

        // Each new agent stage lands as a strong, deliberate tap so
        // every step is *felt*, not just heard. Multiple lines that
        // arrive in the same subscription tick all fire (staggered).
        if progress.count > lastProgressCount {
            let added = progress.count - lastProgressCount
            for i in 0..<added {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                    HapticEngine.tap()
                }
            }
        }
        lastProgressCount = progress.count

        // Per-item taps for any newly-arrived items, staggered so
        // multi-item arrivals don't collapse into a single buzz.
        let count = v.items.count
        if count > lastItemCount {
            let newItems = Array(v.items.suffix(count - lastItemCount))
            for (i, item) in newItems.enumerated() {
                let delay = Double(i) * 0.14
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    HapticEngine.itemRevealed(decision: item.decision)
                }
            }
        }
        // Re-baseline if items shrank (partials replaced by final list).
        lastItemCount = count

        // Status transitions. The continuous "thinking" pulse purrs
        // for the entire ~3s wait — from the moment the row goes
        // pending until the first item actually materializes. Stage
        // taps (above) ride on top of the purr; the user feels both
        // the steady "I'm working" rhythm and each step landing.
        if v.status == "pending" && v.items.isEmpty {
            if !thinkingActive {
                HapticEngine.startThinking()
                thinkingActive = true
            }
        } else if thinkingActive {
            HapticEngine.stopThinking()
            thinkingActive = false
        }
        if v.status != "pending", lastStatus == "pending" {
            if v.status == "done" {
                let postItemDelay = max(0.18, Double(count) * 0.16)
                DispatchQueue.main.asyncAfter(deadline: .now() + postItemDelay) {
                    HapticEngine.scanComplete()
                }
            } else if v.status == "error" {
                HapticEngine.failed()
            }
        }
        lastStatus = v.status
    }
}

// MARK: - Agent feed row

/// One line in the live "what the agent is doing" feed shown while
/// the row is `pending`. The latest line gets a pulsing dot so the
/// user can tell at a glance which step is in progress.
private struct AgentFeedRow: View {
    let text: String
    let isLatest: Bool
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isLatest ? BinSightTokens.Color.recycle : BinSightTokens.Color.softInk.opacity(0.35))
                .frame(width: 7, height: 7)
                .scaleEffect(isLatest && pulse ? 1.6 : 1.0)
                .opacity(isLatest ? 1 : 0.45)
                .onAppear {
                    if isLatest {
                        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }
                }
            Text(text)
                .font(.system(.subheadline, design: .rounded).weight(isLatest ? .heavy : .semibold))
                .foregroundStyle(isLatest
                                 ? BinSightTokens.Color.ink
                                 : BinSightTokens.Color.softInk)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(isLatest ? 0.95 : 0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isLatest
                        ? BinSightTokens.Color.recycle.opacity(0.35)
                        : BinSightTokens.Color.stroke.opacity(0.5),
                        lineWidth: 1)
        )
    }
}

// MARK: - Pill flow layout

/// Simple wrapping flow layout: places children left-to-right, wraps
/// to a new row when the next child would overflow the available
/// width. Used by the source pills strip so every source stays
/// visible without horizontal scrolling.
private struct PillFlowLayout: Layout {
    var spacing: CGFloat
    var runSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var totalW: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth && x > 0 {
                y += rowH + runSpacing
                x = 0
                rowH = 0
            }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            totalW = max(totalW, x - spacing)
        }
        return CGSize(width: totalW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.minX + maxWidth && x > bounds.minX {
                y += rowH + runSpacing
                x = bounds.minX
                rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Staggered source pills

/// Buffers incoming sources locally so when the server flushes a
/// batch in a single Convex update, pills reveal one-at-a-time with
/// a soft tap haptic each, instead of all popping in together.
private struct StaggeredSourcePills: View {
    let sources: [SourceDoc]
    @State private var revealedURLs: [String] = []
    @State private var pendingURLs: [String] = []
    @State private var isDraining = false

    var body: some View {
        Group {
            if !revealedURLs.isEmpty {
                PillFlowLayout(spacing: 8, runSpacing: 8) {
                    ForEach(visiblePills, id: \.url) { src in
                        SourcePill(source: src)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.6)
                                    .combined(with: .move(edge: .top))
                                    .combined(with: .opacity),
                                removal: .opacity))
                    }
                }
            }
        }
        .onAppear { syncIncoming() }
        .onChange(of: sources.map(\.url)) { _, _ in syncIncoming() }
    }

    private var visiblePills: [SourceDoc] {
        let revealedSet = Set(revealedURLs)
        return sources.filter { revealedSet.contains($0.url) }
    }

    private func syncIncoming() {
        let revealedSet = Set(revealedURLs)
        let new = sources.map(\.url).filter { !revealedSet.contains($0) && !pendingURLs.contains($0) }
        guard !new.isEmpty else { return }
        pendingURLs.append(contentsOf: new)
        if !isDraining { drain() }
    }

    private func drain() {
        guard !pendingURLs.isEmpty else { isDraining = false; return }
        isDraining = true
        let next = pendingURLs.removeFirst()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            revealedURLs.append(next)
        }
        HapticEngine.tap()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) { drain() }
    }
}

// MARK: - Source pill (live)

/// Tiny pill showing a source's favicon + publisher name. Animates
/// in as the model emits new sources through the streaming JSON
/// parser. Tapping opens the URL.
private struct SourcePill: View {
    let source: SourceDoc

    var body: some View {
        Link(destination: URL(string: source.url) ?? URL(string: "https://example.com")!) {
            HStack(spacing: 6) {
                CachedRemoteImage(url: faviconURL(for: source.url)) {
                    Circle()
                        .fill(BinSightTokens.Color.softInk.opacity(0.15))
                        .overlay(
                            Text(initial(for: source))
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(BinSightTokens.Color.softInk)
                        )
                }
                .frame(width: 16, height: 16)
                .clipShape(Circle())
                Text(displayName(for: source))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BinSightTokens.Color.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white, in: Capsule())
            .overlay(Capsule().stroke(BinSightTokens.Color.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func displayName(for s: SourceDoc) -> String {
        if !s.publisher.isEmpty { return s.publisher }
        return URL(string: s.url)?.host?.replacingOccurrences(of: "www.", with: "") ?? s.url
    }

    private func initial(for s: SourceDoc) -> String {
        let name = displayName(for: s)
        return String(name.prefix(1)).uppercased()
    }

    private func faviconURL(for raw: String) -> URL? {
        guard let host = URL(string: raw)?.host else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?sz=64&domain=\(host)")
    }
}

// MARK: - Streaming row

private struct StreamingItemRow: View {
    let item: ItemDoc
    @State private var hasFired = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: decisionSymbol(item.decision))
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(decisionTint(item.decision), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label.capitalized)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .foregroundStyle(BinSightTokens.Color.ink)
                Text(item.material.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BinSightTokens.Color.softInk)
            }
            Spacer()
            Text(item.decision.capitalized)
                .font(.caption.weight(.heavy))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(decisionTint(item.decision).opacity(0.18), in: Capsule())
                .foregroundStyle(decisionTint(item.decision))
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(decisionTint(item.decision).opacity(0.25), lineWidth: 1.5))
        // Haptics for item reveals are driven from the subscription
        // side (handleHaptics) so they still fire even when the row
        // itself never gets a chance to render — e.g. when convex
        // flips status straight from pending+[] to done+[item].
    }
}

// MARK: - Bounding-box overlay
//
// Renders a labelled rectangle for every item that has a normalized
// `bbox`. We need the natural size of the image so we can compute the
// scaled+cropped visible rect inside our 220pt aspect-fill container,
// which is fetched separately via URLSession (AsyncImage doesn't expose
// it). Boxes for items outside the visible crop just clip naturally.

private struct BoundingBoxOverlay: View {
    let imageURL: URL?
    let items: [ItemDoc]
    @State private var natural: CGSize?

    var body: some View {
        GeometryReader { proxy in
            let container = proxy.size
            let visible = aspectFillRect(natural: natural, in: container)
            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    if let bb = item.bbox, !coversMostOfFrame(bb) {
                        boxView(item: item, bb: bb, container: container, visible: visible)
                    }
                }
            }
        }
        .task(id: imageURL) { await loadNaturalSize() }
    }

    @ViewBuilder
    private func boxView(item: ItemDoc, bb: BoundingBox, container: CGSize, visible: CGRect) -> some View {
        let rawX = visible.minX + CGFloat(bb.x) * visible.width
        let rawY = visible.minY + CGFloat(bb.y) * visible.height
        let rawW = CGFloat(bb.w) * visible.width
        let rawH = CGFloat(bb.h) * visible.height
        let x = max(0, rawX)
        let y = max(0, rawY)
        let w = max(24, min(rawW - (x - rawX), container.width - x))
        let h = max(24, min(rawH - (y - rawY), container.height - y))
        let color = decisionTint(item.decision)
        let labelInside = y < 26
        // Render box and label as siblings; label gets its intrinsic
        // width via .fixedSize() and clips against the hero's outer
        // .clipped() if it extends past the right edge. Anchored to the
        // box's left edge but allowed to grow rightward freely.
        Group {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color, lineWidth: 2.5)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.10))
                )
                .frame(width: w, height: h)
                .offset(x: x, y: y)
            HStack(spacing: 4) {
                Image(systemName: decisionSymbol(item.decision))
                    .font(.system(size: 9, weight: .heavy))
                Text(shortLabel(item.label))
                    .font(.system(size: 10, weight: .heavy))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color, in: Capsule())
            .fixedSize()
            .offset(x: x + (labelInside ? 6 : 0),
                    y: y + (labelInside ? 6 : -20))
        }
        .allowsHitTesting(false)
    }

    /// Trim the model's verbose labels to something that actually fits
    /// above a small bounding box. Drops parenthetical asides and clamps
    /// to ~22 chars.
    private func shortLabel(_ raw: String) -> String {
        var s = raw
        if let i = s.firstIndex(of: "(") {
            s = String(s[..<i])
        }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.count > 22 {
            s = String(s.prefix(20)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return s
    }

    private func coversMostOfFrame(_ bb: BoundingBox) -> Bool {
        // If the model just drew a box around essentially the whole photo,
        // the rectangle adds clutter without information - drop it.
        bb.w * bb.h > 0.78
    }

    private func aspectFillRect(natural: CGSize?, in container: CGSize) -> CGRect {
        guard let n = natural, n.width > 0, n.height > 0,
              container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = max(container.width / n.width, container.height / n.height)
        let w = n.width * scale
        let h = n.height * scale
        return CGRect(
            x: (container.width - w) / 2,
            y: (container.height - h) / 2,
            width: w, height: h
        )
    }

    private func loadNaturalSize() async {
        guard let url = imageURL else { return }
        if let img = await BinSightImageCache.loadImage(for: url) {
            await MainActor.run { natural = img.size }
        }
    }
}

// MARK: - Swipe-first triage screen
//
// Lives at the root of the navigation, NOT inside a ScrollView. This is
// the key to the gesture working - SwiftUI's drag-gesture absorption from
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
                .padding(.top, 28)

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
            .padding(.vertical, 14)
            .frame(maxHeight: .infinity)

            actionRow(items: items)
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
        }
        .onChange(of: pending.count) { _, _ in
            if dragOffset != .zero {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    dragOffset = .zero
                }
            }
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
            defer {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    dragOffset = .zero
                }
            }
            try? await ConvexService.shared.reviewItem(
                id: doc._id, itemIndex: itemIndex, state: state
            )
            try? await Task.sleep(nanoseconds: 220_000_000)
            withAnimation(.easeOut(duration: 0.18)) {
                lastFlash = state == "confirmed" ? "Confirmed" : "Ignored"
                flashId += 1
            }
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
                CachedRemoteImage(url: imageUrl.flatMap(URL.init(string:))) {
                    Color.secondary.opacity(0.15)
                }
                .frame(height: 110)
                .clipped()
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

                if !sources.isEmpty {
                    let materialSrc = sources.first(where: { ($0.kind ?? "") == "material" || ($0.kind ?? "") == "both" })
                    let ruleSrc = sources.first(where: { ($0.kind ?? "") == "rule" || ($0.kind ?? "") == "both" })
                        ?? sources.first(where: { $0.kind == nil })
                    VStack(alignment: .leading, spacing: 4) {
                        if let s = materialSrc {
                            sourceBadge(label: "material", source: s, tint: BinSightTokens.Color.accent)
                        }
                        if let s = ruleSrc, s.url != materialSrc?.url {
                            sourceBadge(label: s.isLocal ? "local rule" : "rule",
                                        source: s,
                                        tint: BinSightTokens.Color.recycle)
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

    private func sourceBadge(label: String, source: SourceDoc, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(.caption2.weight(.heavy))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(tint.opacity(0.16), in: Capsule())
                .foregroundStyle(tint)
            Text(source.publisher.isEmpty ? hostOf(source.url) : source.publisher)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
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
            // Always-visible compact line - this is what the user sees by default.
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    decisionBadge
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.itemTitle ?? item.label).font(.subheadline.weight(.semibold)).lineLimit(1)
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
                            if item.massSource == "rag",
                               let count = item.ragSimilar?.filter({ $0.used }).count,
                               count > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "books.vertical.fill")
                                        .font(.system(size: 9, weight: .heavy))
                                    Text("\(count) ref\(count == 1 ? "" : "s")")
                                        .font(.caption2.weight(.heavy).monospacedDigit())
                                }
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(BinSightTokens.Color.accent.opacity(0.18), in: Capsule())
                                .foregroundStyle(BinSightTokens.Color.accent)
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
                        // Plain-English item description from the fast
                        // pipeline (separate from `disposalNotes` which
                        // is the decision-specific guidance).
                        if let desc = item.itemDescription, !desc.isEmpty {
                            Text(desc)
                                .font(.callout)
                                .foregroundStyle(.primary.opacity(0.85))
                        }
                        Text(item.disposalNotes)
                            .font(.callout)

                        // Rich material breakdown (WARM categories ×
                        // grams) — the fast pipeline's signature output.
                        if let breakdown = item.materialBreakdown, !breakdown.isEmpty {
                            MaterialBreakdownView(materials: breakdown)
                        }

                        if !sources.isEmpty {
                            SourceListView(sources: sources)
                        }

                        if let similar = item.ragSimilar, !similar.isEmpty {
                            RagContextBlock(item: item, similar: similar)
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

// MARK: - RAG context block (in expand)

/// Surface the knowledge-base references the model considered for this
/// item — both the cited ones (used = leaned on for the mass estimate)
/// and the not-used neighbors. Each thumbnail is tappable, opening a
/// detail sheet with the reference's stored mass + research summary.
private struct RagContextBlock: View {
    let item: ItemDoc
    let similar: [RagSimilar]
    @State private var selected: RagSimilar?

    var body: some View {
        let used = similar.filter { $0.used }
        let other = similar.filter { !$0.used }
        let ordered = used + other

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical.fill")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(BinSightTokens.Color.accent)
                Text(headerText(usedCount: used.count, totalCount: similar.count))
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(BinSightTokens.Color.ink)
                Spacer()
            }

            if let reasoning = item.ragReasoning, !reasoning.isEmpty {
                Text("\u{201C}\(reasoning)\u{201D}")
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ordered) { ref in
                        Button { selected = ref } label: {
                            RagThumbView(ref: ref)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(BinSightTokens.Color.accent.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(BinSightTokens.Color.accent.opacity(0.25), lineWidth: 1)
        )
        .sheet(item: $selected) { ref in
            RagReferenceSheet(ref: ref)
                .presentationDetents([.medium])
        }
    }

    private func headerText(usedCount: Int, totalCount: Int) -> String {
        if item.massSource == "rag" && usedCount > 0 {
            return "Calibrated against \(usedCount) reference\(usedCount == 1 ? "" : "s") (\(totalCount) considered)"
        }
        return "Knowledge base · \(totalCount) similar reference\(totalCount == 1 ? "" : "s")"
    }
}

private struct RagThumbView: View {
    let ref: RagSimilar
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let url = ref.imageUrl.flatMap(URL.init(string:)) {
                        CachedRemoteImage(url: url) {
                            Rectangle().fill(BinSightTokens.Color.softInk.opacity(0.15))
                        }
                    } else {
                        Rectangle()
                            .fill(BinSightTokens.Color.softInk.opacity(0.15))
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            )
                    }
                }
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(ref.used ? BinSightTokens.Color.accent : Color.black.opacity(0.08),
                                lineWidth: ref.used ? 2 : 1)
                )
                if ref.used {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white, BinSightTokens.Color.accent)
                        .padding(4)
                }
            }
            Text("\(Int(ref.massGrams.rounded())) g")
                .font(.system(.caption2, design: .rounded).weight(.heavy).monospacedDigit())
                .foregroundStyle(BinSightTokens.Color.ink)
            Text("sim \(String(format: "%.2f", ref.similarity))")
                .font(.system(size: 9, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(width: 84)
    }
}

private struct RagReferenceSheet: View {
    let ref: RagSimilar
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let url = ref.imageUrl.flatMap(URL.init(string:)) {
                    CachedRemoteImage(url: url) {
                        Rectangle().fill(BinSightTokens.Color.softInk.opacity(0.12))
                    }
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                HStack(spacing: 8) {
                    if ref.used {
                        Label("Cited", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.heavy))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(BinSightTokens.Color.accent.opacity(0.18), in: Capsule())
                            .foregroundStyle(BinSightTokens.Color.accent)
                    }
                    Text(ref.materialWarm)
                        .font(.caption.weight(.heavy))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(BinSightTokens.Color.softInk.opacity(0.12), in: Capsule())
                        .foregroundStyle(BinSightTokens.Color.ink)
                    Spacer()
                }
                Text(ref.objectName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(BinSightTokens.Color.ink)
                Group {
                    detailRow("Mass", "\(Int(ref.massGrams.rounded())) g")
                    detailRow("Similarity", String(format: "%.3f", ref.similarity))
                    detailRow("Source", "Reference catalog")
                }
            }
            .padding(20)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Text(value).foregroundStyle(.primary)
            Spacer()
        }
        .font(.subheadline)
    }
}

// MARK: - Material breakdown (in expand)

/// A small table that shows the WARM-category-by-WARM-category
/// breakdown the fast pipeline returned. Each row is one material
/// with its gram weight, confidence, and CO₂ savings vs. landfill.
private struct MaterialBreakdownView: View {
    let materials: [ItemMaterial]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "scalemass.fill")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(BinSightTokens.Color.recycle)
                Text("Material breakdown")
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(BinSightTokens.Color.ink)
                Spacer()
                Text("EPA WARM v16")
                    .font(.system(size: 9, design: .rounded).weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)
            }
            VStack(spacing: 6) {
                ForEach(materials) { m in
                    MaterialRow(material: m)
                }
            }
        }
        .padding(12)
        .background(BinSightTokens.Color.recycle.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(BinSightTokens.Color.recycle.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct MaterialRow: View {
    let material: ItemMaterial

    private var confidenceTint: Color {
        switch material.confidence.lowercased() {
        case "high":   return BinSightTokens.Color.recycle
        case "medium": return BinSightTokens.Color.accent
        default:       return BinSightTokens.Color.softInk
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(material.warm)
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(BinSightTokens.Color.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(formattedMass(material.massGrams))
                .font(.system(.caption, design: .rounded).weight(.heavy).monospacedDigit())
                .foregroundStyle(BinSightTokens.Color.ink)
            Text(material.confidence.lowercased())
                .font(.system(size: 9, design: .rounded).weight(.heavy))
                .foregroundStyle(confidenceTint)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(confidenceTint.opacity(0.15), in: Capsule())
            Text(formattedCo2(material.co2Kg))
                .font(.system(.caption2, design: .rounded).weight(.heavy).monospacedDigit())
                .foregroundStyle(BinSightTokens.Color.recycle)
                .frame(width: 64, alignment: .trailing)
        }
    }

    private func formattedMass(_ g: Double) -> String {
        if g < 1 { return String(format: "%.1f g", g) }
        if g < 100 { return String(format: "%.0f g", g) }
        return "\(Int(g.rounded())) g"
    }

    private func formattedCo2(_ kg: Double) -> String {
        if kg <= 0 { return "—" }
        if kg < 0.01 { return String(format: "%.3f kg", kg) }
        if kg < 1 { return String(format: "%.2f kg", kg) }
        return String(format: "%.1f kg", kg)
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
            row("Method", value: item.co2Method.isEmpty ? "-" : item.co2Method)
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
        let label: String
        switch item.massSource {
        case "rag":      label = "calibrated from knowledge base"
        case "verified": label = "verified from web sources"
        case "model":    label = "estimated from photo"
        default:         label = "default for material"
        }
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
    @Environment(\.openURL) private var openURL

    var body: some View {
        let label = tierLabel(source.tier)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
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

                if !displayedQuotes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("From the source")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)
                        ForEach(Array(displayedQuotes.enumerated()), id: \.offset) { _, q in
                            QuoteBlock(text: q, accent: tierColor(source.tier))
                        }
                    }
                }
                Spacer(minLength: 24)
                if let url = URL(string: source.url) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Open in browser", systemImage: "arrow.up.right.square.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(BinSightTokens.Color.accent.opacity(0.18),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(BinSightTokens.Color.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
    }

    /// Prefer the model's verbatim `quotes` array. Fall back to splitting
    /// the legacy single `snippet` into sentence-sized chunks so older
    /// rows (written before quotes existed) still surface useful text.
    private var displayedQuotes: [String] {
        let raw: [String]
        if let qs = source.quotes, !qs.isEmpty {
            raw = qs
        } else {
            let snippet = source.snippet
            if snippet.isEmpty { return [] }
            raw = snippet.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        }
        return raw
            .map(Self.cleanQuote)
            .filter { Self.isReadableQuote($0) }
            .prefix(3)
            .map { $0 }
    }

    /// Normalize a raw scraped string for display. Search engines
    /// often hand back text where every character or word is on its
    /// own line (PDF column scrapes, table cells), which would render
    /// vertically inside our QuoteBlock. Collapse all whitespace
    /// (incl. newlines) to single spaces and trim ellipsis trailers.
    static func cleanQuote(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop trailing ellipses pasted from snippet truncation.
        let withoutTrailingEllipsis = collapsed
            .replacingOccurrences(of: #"[\s…\.]+$"#, with: "", options: .regularExpression)
        return withoutTrailingEllipsis
    }

    /// Reject quotes that are clearly garbage scrapes — too short or
    /// dominated by single-character "words" (the column-strip
    /// fingerprint that produced the vertical "L\nA\nT\nI\nO\nN" in
    /// older screenshots).
    static func isReadableQuote(_ q: String) -> Bool {
        guard q.count >= 12 else { return false }
        let words = q.split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return false }
        let shortWords = words.filter { $0.count <= 1 }
        // If more than 40% of "words" are single chars, it's a column scrape.
        if Double(shortWords.count) / Double(words.count) > 0.4 { return false }
        // Reject quotes that start with stray legal-doc fragments.
        let lower = q.lowercased()
        let junkPrefixes = ["rules and regulations", "date of final signature", "effective date", "approvals"]
        if junkPrefixes.contains(where: { lower.hasPrefix($0) }) { return false }
        return true
    }

    private func hostOf(_ s: String) -> String {
        URL(string: s)?.host?.replacingOccurrences(of: "www.", with: "") ?? s
    }
}

private struct QuoteBlock: View {
    let text: String
    let accent: Color
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent.opacity(0.6))
                .frame(width: 3)
            Text("\u{201C}\(text)\u{201D}")
                .font(.callout)
                .italic()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
