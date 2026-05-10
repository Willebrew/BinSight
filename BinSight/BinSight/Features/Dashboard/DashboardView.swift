import SwiftUI
import Charts
import Combine

struct DashboardView: View {
    @State private var metrics: MetricsDoc?
    @State private var rows: [ClassificationDoc] = []
    @State private var percentile: CityPercentileDoc?
    @State private var insight: WeeklyInsightDoc?
    @State private var friends: FriendsDoc?
    @State private var bag: Set<AnyCancellable> = []
    @State private var animatedCo2: Double = 0
    @State private var equivIndex = 0
    @State private var firstScanCelebration = false
    @AppStorage("binsight.hasSeenFirstScan") private var hasSeenFirstScan = false
    @State private var hasReceivedInitialMetrics = false

    private let equivTimer = Timer.publish(every: 4.5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    pendingReviewBanner
                    summaryRow
                    if (metrics?.totalScans ?? 0) == 0 {
                        emptyState
                    } else {
                        equivalencesCarousel
                        if insight != nil {
                            insightCard
                        }
                        streakSection
                        cityPercentileCard
                        paceCard
                        trustScoreCard
                        materialMixCard
                        if let m = metrics, !m.recentHazards.isEmpty {
                            hazardRadarCard(m.recentHazards)
                        }
                        weeklyChart
                        friendsLeaderboardCard
                        recentRow
                        methodologyFooter
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 140)
            }
            .background(backdrop.ignoresSafeArea())
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
        }
        .overlay {
            if firstScanCelebration {
                FirstScanCelebration { firstScanCelebration = false }
                    .transition(.opacity)
            }
        }
        .onAppear {
            ConvexService.shared.subscribeMetrics()
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in }, receiveValue: { newValue in
                    let oldScans = metrics?.totalScans
                    metrics = newValue
                    let target = newValue?.totalCo2Kg ?? 0
                    withAnimation(.easeOut(duration: 0.9)) { animatedCo2 = target }

                    let newScans = newValue?.totalScans ?? 0
                    if hasReceivedInitialMetrics, oldScans == 0, newScans == 1, !hasSeenFirstScan {
                        hasSeenFirstScan = true
                        withAnimation(.easeIn(duration: 0.3)) { firstScanCelebration = true }
                    }
                    if !hasReceivedInitialMetrics {
                        hasReceivedInitialMetrics = true
                        if newScans > 0 { hasSeenFirstScan = true }
                    }
                })
                .store(in: &bag)
            ConvexService.shared.subscribeHistory()
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in },
                      receiveValue: { rows = $0.filter { $0.status == "done" } })
                .store(in: &bag)
            ConvexService.shared.subscribeCityPercentile()
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in }, receiveValue: { percentile = $0 })
                .store(in: &bag)
            ConvexService.shared.subscribeWeeklyInsight()
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in }, receiveValue: { insight = $0 })
                .store(in: &bag)
            ConvexService.shared.subscribeFriends()
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in }, receiveValue: { friends = $0 })
                .store(in: &bag)
            // Best-effort: ask the backend to refresh the weekly insight.
            // The action is cached for 7 days so this is safe to call on appear.
            Task { try? await ConvexService.shared.refreshWeeklyInsight() }
        }
        .onReceive(equivTimer) { _ in
            withAnimation(.easeInOut(duration: 0.6)) {
                equivIndex = (equivIndex + 1) % equivalences.count
            }
        }
        .onDisappear { bag.forEach { $0.cancel() }; bag.removeAll() }
    }

    // MARK: - Hero

    private var hero: some View {
        let m = metrics
        return DuoCard(fill: .white, stroke: BinSightTokens.Color.recycle.opacity(0.28), radius: 28, padding: 0) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    heroGradient
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 10) {
                            DuoBadge(text: "\(m?.streakDays ?? 0) day streak",
                                     systemImage: "flame.fill",
                                     color: BinSightTokens.Color.hazard,
                                     filled: true)
                            Text("Keep the landfill losing.")
                                .font(.system(.title2, design: .rounded).weight(.heavy))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Text("Every confirmed scan earns impact progress.")
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(.white.opacity(0.84))
                        }
                        Spacer()
                        MascotArtView(mood: .celebrate, size: 92, accessory: "leaf.fill")
                            .offset(y: 10)
                    }
                    .padding(18)
                }
                .frame(height: 156)

                VStack(alignment: .leading, spacing: 13) {
                    Text("CO2e kept out of the landfill")
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .textCase(.uppercase)
                        .foregroundStyle(BinSightTokens.Color.softInk)
                        .tracking(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.2f", animatedCo2))
                            .font(.system(size: 54, weight: .heavy, design: .rounded))
                            .foregroundStyle(BinSightTokens.Color.ink)
                        .contentTransition(.numericText(value: animatedCo2))
                    Text("kg")
                        .font(.title3.weight(.semibold))
                            .foregroundStyle(BinSightTokens.Color.softInk)
                }
                if let m, m.totalCo2KgLow > 0 || m.totalCo2KgHigh > 0 {
                    HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                            .imageScale(.small)
                                .foregroundStyle(BinSightTokens.Color.recycle)
                            Text("range \(String(format: "%.2f", m.totalCo2KgLow))-\(String(format: "%.2f", m.totalCo2KgHigh)) kg · EPA WARM v16")
                                .font(.system(.caption2, design: .rounded).weight(.bold))
                                .foregroundStyle(BinSightTokens.Color.softInk)
                    }
                }
                HStack(spacing: 8) {
                    heroChip(icon: "flame.fill", value: "\(m?.streakDays ?? 0)d", label: "streak")
                    heroChip(icon: "checkmark.seal.fill", value: "\(m?.totalRecycled ?? 0)", label: "recycled")
                    heroChip(icon: "trash.fill", value: "\(m?.totalTrashed ?? 0)", label: "trash")
                }
                }
                .padding(18)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var heroGradient: some View {
        LinearGradient(
            colors: [
                BinSightTokens.Color.recycleDark,
                BinSightTokens.Color.recycle,
                BinSightTokens.Color.accent,
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private func heroChip(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).imageScale(.small)
            Text(value).font(.subheadline.weight(.bold))
            Text(label).font(.caption).opacity(0.85)
        }
        .foregroundStyle(colorForHeroChip(icon))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(colorForHeroChip(icon).opacity(0.14), in: Capsule())
    }

    private func colorForHeroChip(_ icon: String) -> Color {
        icon == "trash.fill" ? BinSightTokens.Color.trash : (icon == "flame.fill" ? BinSightTokens.Color.hazard : BinSightTokens.Color.recycle)
    }

    // MARK: - Pending review banner

    @ViewBuilder
    private var pendingReviewBanner: some View {
        let pending = metrics?.totalPendingItems ?? 0
        let scanWithPending = rows.first { $0.needsReview }
        if pending > 0, let row = scanWithPending {
            NavigationLink {
                ResultCardView(classificationId: row._id)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "hand.draw.fill")
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(BinSightTokens.Color.accent, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(pending) item\(pending == 1 ? "" : "s") to review")
                            .font(.subheadline.weight(.semibold))
                        Text("Swipe to confirm or ignore - only confirmed items count.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BinSightTokens.Color.accent.opacity(0.24), lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Summary tiles

    private var summaryRow: some View {
        let m = metrics
        return HStack(spacing: 12) {
            DuoStatTile(value: "\(m?.totalScans ?? 0)", label: "Scans", systemImage: "camera.fill", tint: BinSightTokens.Color.accent)
            DuoStatTile(value: "\(m?.totalRecycled ?? 0)", label: "Diverted", systemImage: "leaf.fill", tint: BinSightTokens.Color.recycle)
            DuoStatTile(value: "\(m?.totalTrashed ?? 0)", label: "Trash", systemImage: "trash.fill", tint: BinSightTokens.Color.trash)
        }
    }

    private func statTile(value: String, label: String, system: String, tint: Color) -> some View {
        DuoStatTile(value: value, label: label, systemImage: system, tint: tint)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            MascotArtView(mood: .thinking, size: 116, accessory: "camera.fill")
            Text("Your first scan is waiting")
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(BinSightTokens.Color.ink)
            Text("Tap the camera button below and snap any waste item - BinSight will tell you exactly how to dispose of it.")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(BinSightTokens.Color.softInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(BinSightTokens.Color.stroke, lineWidth: 2))
    }

    // MARK: - Equivalences carousel
    //
    // We translate the user's accumulated CO2e into relatable units so the
    // headline doesn't stay abstract. All conversion factors are sourced
    // from the EPA Greenhouse Gas Equivalencies Calculator
    // (https://www.epa.gov/energy/greenhouse-gas-equivalencies-calculator)
    // and Forest Service tree-sequestration reports.

    private struct Equiv: Hashable {
        let icon: String
        let label: String
        let detail: String
    }

    private var equivalences: [Equiv] {
        let kg = metrics?.totalCo2Kg ?? 0
        return [
            Equiv(icon: "car.fill",
                  label: String(format: "%.1f miles not driven", kg / 0.404),
                  detail: "EPA Greenhouse Gas Equivalencies — passenger vehicle avg."),
            Equiv(icon: "iphone",
                  label: String(format: "%.0f phone charges", kg / 0.0084),
                  detail: "EPA — avg smartphone full-charge emissions."),
            Equiv(icon: "tree.fill",
                  label: String(format: "%.1f tree-months of CO₂", kg / 9.5),
                  detail: "Urban tree sequestration — USDA Forest Service."),
            Equiv(icon: "bag.fill",
                  label: String(format: "%.0f single-use bags", kg / 0.06),
                  detail: "Avg ~60 g CO₂e per bag — ETH Zurich LCA."),
            Equiv(icon: "lightbulb.fill",
                  label: String(format: "%.0f LED bulb-hours", kg / 0.005),
                  detail: "10W LED on US grid avg — EIA emission factor."),
            Equiv(icon: "fork.knife",
                  label: String(format: "%.1f beef burgers avoided", kg / 4.0),
                  detail: "≈4 kg CO₂e per quarter-pound beef patty — Heller & Keoleian."),
            Equiv(icon: "laptopcomputer",
                  label: String(format: "%.0f hours of laptop use", kg / 0.05),
                  detail: "50 W laptop on US grid avg — EPA eGRID."),
            Equiv(icon: "drop.fill",
                  label: String(format: "%.0f hot-water showers", kg / 2.4),
                  detail: "≈2.4 kg CO₂e per 8-min hot shower — UK Energy Saving Trust."),
            Equiv(icon: "cup.and.saucer.fill",
                  label: String(format: "%.0f cups of coffee", kg / 0.28),
                  detail: "Lifecycle CO₂e per filter-brewed cup — Carbon Trust."),
            Equiv(icon: "wifi",
                  label: String(format: "%.0f hours of video streaming", kg / 0.036),
                  detail: "HD streaming avg — IEA Digitalisation report."),
        ]
    }

    private var equivalencesCarousel: some View {
        VStack(alignment: .leading, spacing: 8) {
            DuoSectionHeader(title: "That's like...", systemImage: "leaf.fill")
            TabView(selection: $equivIndex) {
                ForEach(Array(equivalences.enumerated()), id: \.offset) { idx, eq in
                    equivCard(eq)
                        .tag(idx)
                        .padding(.horizontal, 2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 92)
            HStack(spacing: 5) {
                Spacer()
                ForEach(0..<equivalences.count, id: \.self) { i in
                    Circle()
                        .fill(i == equivIndex
                              ? BinSightTokens.Color.recycle
                              : BinSightTokens.Color.softInk.opacity(0.28))
                        .frame(width: 6, height: 6)
                }
                Spacer()
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BinSightTokens.Color.stroke, lineWidth: 2))
    }

    private func equivCard(_ eq: Equiv) -> some View {
        HStack(spacing: 12) {
            Image(systemName: eq.icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(BinSightTokens.Color.recycle)
                .frame(width: 44, height: 44)
                .background(BinSightTokens.Color.recycle.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(eq.label)
                    .font(.headline)
                    .lineLimit(2)
                Text(eq.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Weekly insight card

    @ViewBuilder
    private var insightCard: some View {
        if let i = insight {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(BinSightTokens.Color.accent)
                    Text("This week").font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text(i.headline).font(.headline)
                if !i.body.isEmpty {
                    Text(i.body).font(.callout).foregroundStyle(.primary.opacity(0.85))
                }
                if let src = i.sources.first, let url = URL(string: src.url) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "link").imageScale(.small)
                            Text(src.publisher.isEmpty ? src.url : src.publisher)
                                .lineLimit(1)
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), variant: .regular)
        }
    }

    // MARK: - Streak grid

    @ViewBuilder
    private var streakSection: some View {
        if let m = metrics {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Streak", systemImage: "flame.fill")
                        .font(.headline)
                        .foregroundStyle(BinSightTokens.Color.hazard)
                    Spacer()
                    Text("\(m.streakDays) day\(m.streakDays == 1 ? "" : "s")")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.primary)
                }
                StreakGrid(scanDays: Set(m.scanDays))
            }
            .padding(14)
            .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), variant: .regular)
        }
    }

    // MARK: - City percentile

    @ViewBuilder
    private var cityPercentileCard: some View {
        if let p = percentile {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("\(p.city) ranking", systemImage: "mappin.and.ellipse")
                        .font(.headline)
                    Spacer()
                    Text("Top \(max(1, 100 - p.percentile + 1))%")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(BinSightTokens.Color.accent.opacity(0.18), in: Capsule())
                        .foregroundStyle(BinSightTokens.Color.accent)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("#\(p.rank)").font(.title.weight(.bold).monospacedDigit())
                    Text("of \(p.total) scanners this week")
                        .font(.caption).foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    let frac = max(0.02, min(1.0, p.myWeekCo2Kg / max(0.001, p.topWeekCo2Kg)))
                    ZStack(alignment: .leading) {
                        Capsule().fill(.thinMaterial)
                        Capsule()
                            .fill(LinearGradient(colors: [BinSightTokens.Color.accent.opacity(0.55), BinSightTokens.Color.accent],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * frac)
                    }
                }
                .frame(height: 8)
                HStack {
                    Text("you: \(String(format: "%.2f", p.myWeekCo2Kg)) kg")
                    Spacer()
                    Text("top: \(String(format: "%.2f", p.topWeekCo2Kg)) kg")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), variant: .regular)
        }
    }

    // MARK: - Pace projection

    @ViewBuilder
    private var paceCard: some View {
        if let m = metrics, m.projectedMonthCo2Kg > 0 || m.monthToDateCo2Kg > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Pace this month", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.headline)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.2f", m.monthToDateCo2Kg))
                        .font(.title2.weight(.bold).monospacedDigit())
                    Text("kg so far →")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "%.2f", m.projectedMonthCo2Kg))
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(BinSightTokens.Color.accent)
                    Text("projected")
                        .font(.caption).foregroundStyle(.secondary)
                }
                paceSpark(m)
            }
            .padding(14)
            .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), variant: .regular)
        }
    }

    private func paceSpark(_ m: MetricsDoc) -> some View {
        let last30 = lastNDays(n: 30)
        let series: [(String, Double)] = last30.map { day in
            (day, m.byDay[day]?.co2 ?? 0)
        }
        return Chart {
            ForEach(Array(series.enumerated()), id: \.offset) { _, kv in
                AreaMark(x: .value("Day", kv.0), y: .value("kg", kv.1))
                    .foregroundStyle(BinSightTokens.Color.accent.opacity(0.25))
            }
            ForEach(Array(series.enumerated()), id: \.offset) { _, kv in
                LineMark(x: .value("Day", kv.0), y: .value("kg", kv.1))
                    .foregroundStyle(BinSightTokens.Color.accent)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 60)
    }

    // MARK: - Trust score

    @ViewBuilder
    private var trustScoreCard: some View {
        if let m = metrics, m.totalScans > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Source quality", systemImage: "checkmark.shield.fill")
                        .font(.headline)
                        .foregroundStyle(BinSightTokens.Color.recycle)
                    Spacer()
                    Text("\(Int(m.trustScore * 100))%")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(BinSightTokens.Color.recycle)
                }
                Text("\(Int(m.trustScore * 100))% of your scans had ≥1 official (.gov / EPA / municipal) source. Average \(String(format: "%.1f", m.avgSourcesPerScan)) sources per scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.thinMaterial)
                        Capsule()
                            .fill(BinSightTokens.Color.recycle)
                            .frame(width: geo.size.width * m.trustScore)
                    }
                }
                .frame(height: 6)
            }
            .padding(14)
            .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), variant: .regular)
        }
    }

    // MARK: - Material mix (by mass)

    @ViewBuilder
    private var materialMixCard: some View {
        if let m = metrics, !m.byMaterialCo2.isEmpty {
            let entries = m.byMaterialCo2
                .sorted(by: { $0.value > $1.value })
                .prefix(6)
                .map { ($0.key, $0.value) }
            let total = entries.reduce(0) { $0 + $1.1 }
            VStack(alignment: .leading, spacing: 10) {
                Text("Where your impact comes from")
                    .font(.headline)
                Text("By kg CO₂e avoided - not by item count. Aluminum punches above its weight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if total > 0 {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.offset) { i, kv in
                                let frac = kv.1 / total
                                Rectangle()
                                    .fill(materialColor(kv.0, idx: i))
                                    .frame(width: geo.size.width * frac)
                            }
                        }
                    }
                    .frame(height: 14)
                    .clipShape(Capsule())
                }
                ForEach(Array(entries.enumerated()), id: \.offset) { i, kv in
                    HStack(spacing: 8) {
                        Circle().fill(materialColor(kv.0, idx: i)).frame(width: 8, height: 8)
                        Text(kv.0.capitalized).font(.caption)
                        Spacer()
                        Text(String(format: "%.2f kg", kv.1))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), variant: .regular)
        }
    }

    private func materialColor(_ key: String, idx: Int) -> Color {
        let palette: [Color] = [
            BinSightTokens.Color.recycle,
            BinSightTokens.Color.accent,
            BinSightTokens.Color.compost,
            BinSightTokens.Color.hazard,
            Color(red: 0.55, green: 0.36, blue: 0.74),
            Color(red: 0.34, green: 0.66, blue: 0.74),
        ]
        return palette[idx % palette.count]
    }

    // MARK: - Hazard radar

    private func hazardRadarCard(_ hazards: [MetricsDoc.HazardItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Hazard items recently scanned", systemImage: "exclamationmark.octagon.fill")
                    .font(.headline)
                    .foregroundStyle(BinSightTokens.Color.hazard)
                Spacer()
            }
            ForEach(hazards.prefix(3)) { h in
                HStack(spacing: 8) {
                    Circle().fill(BinSightTokens.Color.hazard).frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(h.label).font(.subheadline.weight(.semibold))
                        Text(Date(timeIntervalSince1970: h.capturedAt / 1000)
                                .formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    NavigationLink {
                        ResultCardView(classificationId: h.id)
                    } label: {
                        Text("View").font(.caption.weight(.semibold))
                    }
                }
            }
            Text("Hazardous items (batteries, paint, electronics) shouldn't go in the trash. Take them to a certified drop-off.")
                .font(.caption)
                .foregroundStyle(.secondary)
            NavigationLink {
                ImpactMapView()
            } label: {
                Label("Find a take-back near you", systemImage: "map.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(BinSightTokens.Color.hazard.opacity(0.18), in: Capsule())
                    .foregroundStyle(BinSightTokens.Color.hazard)
            }
        }
        .padding(14)
        .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), variant: .regular)
    }

    // MARK: - Friends mini-leaderboard

    @ViewBuilder
    private var friendsLeaderboardCard: some View {
        let accepted = friends?.accepted ?? []
        if !accepted.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Friends", systemImage: "person.2.fill")
                        .font(.headline)
                    Spacer()
                    NavigationLink("View all") { FriendsView() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BinSightTokens.Color.accent)
                }
                ForEach(accepted.prefix(3)) { f in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(BinSightTokens.Color.accent.opacity(0.2))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(initials(for: f))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BinSightTokens.Color.accent)
                            )
                        Text(f.otherDisplayName ?? f.otherEmail ?? "Friend")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        // Friend totals would need a backend query - for now,
                        // we link straight into the Friends tab where the
                        // detailed leaderboard already lives.
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
            .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), variant: .regular)
        }
    }

    private func initials(for f: FriendDoc) -> String {
        let name = f.otherDisplayName ?? f.otherEmail ?? "?"
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].first ?? "?") + String(parts[1].first ?? "?")
        }
        return String(name.prefix(2)).uppercased()
    }

    // MARK: - Recent decisions feed

    private var recentRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent decisions").font(.headline)
                Spacer()
                NavigationLink("View all") { HistoryView() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BinSightTokens.Color.accent)
            }
            VStack(spacing: 8) {
                ForEach(rows.prefix(5)) { row in
                    NavigationLink {
                        ResultCardView(classificationId: row._id)
                    } label: {
                        RecentDecisionRow(row: row)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Weekly chart

    @ViewBuilder
    private var weeklyChart: some View {
        if let m = metrics, !m.byDay.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Last 7 days").font(.headline)
                let last7 = lastNDays(n: 7)
                Chart {
                    ForEach(last7, id: \.self) { day in
                        let d = m.byDay[day] ?? .init(recycled: 0, trashed: 0, co2: 0)
                        BarMark(x: .value("Day", String(day.suffix(5))), y: .value("Diverted", d.recycled))
                            .foregroundStyle(BinSightTokens.Color.recycle)
                        BarMark(x: .value("Day", String(day.suffix(5))), y: .value("Trash", d.trashed))
                            .foregroundStyle(BinSightTokens.Color.trash)
                    }
                }
                .frame(height: 180)
            }
            .padding(16)
            .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous), variant: .regular)
        }
    }

    // MARK: - Methodology footer

    private var methodologyFooter: some View {
        NavigationLink {
            MethodologyView()
        } label: {
            HStack {
                Image(systemName: "info.circle")
                Text("How we measure impact (EPA WARM v16)")
                    .font(.caption.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right").imageScale(.small)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func lastNDays(n: Int) -> [String] {
        let cal = Calendar.current
        var days: [String] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        var cursor = cal.startOfDay(for: Date())
        for _ in 0..<n {
            days.append(formatter.string(from: cursor))
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return days.reversed()
    }

    private var backdrop: some View {
        DuoBackdrop()
    }
}

// MARK: - Streak grid

private struct StreakGrid: View {
    let scanDays: Set<String>

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 15)

    var body: some View {
        let days = lastDays(n: 30)
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(days, id: \.self) { day in
                    let active = scanDays.contains(day)
                    let isToday = day == days.last
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(active
                              ? AnyShapeStyle(LinearGradient(
                                colors: [BinSightTokens.Color.recycle.opacity(0.6),
                                         BinSightTokens.Color.recycle],
                                startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Color.secondary.opacity(0.12)))
                        .frame(height: 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(isToday ? Color.primary.opacity(0.4) : .clear, lineWidth: 1)
                        )
                }
            }
            HStack {
                Text("30 days ago").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("today").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func lastDays(n: Int) -> [String] {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        var cursor = cal.startOfDay(for: Date())
        var out: [String] = []
        for _ in 0..<n {
            out.append(formatter.string(from: cursor))
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return out.reversed()
    }
}

// MARK: - Recent decision row (richer than old card)

private struct RecentDecisionRow: View {
    let row: ClassificationDoc

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let urlString = row.imageUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color.gray.opacity(0.15)
                    }
                } else {
                    Color.gray.opacity(0.15)
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.items.first?.label.capitalized ?? "-")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let item = row.items.first {
                        Text(item.decision.capitalized)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(decisionColor(item.decision), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                if let topSource = row.sources.first {
                    HStack(spacing: 4) {
                        Image(systemName: tierIconFor(topSource.tier))
                            .imageScale(.small)
                            .foregroundStyle(tierColorFor(topSource.tier))
                        Text(topSource.publisher.isEmpty ? hostOf(topSource.url) : topSource.publisher)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else if let r = row.localRules, !r.isEmpty {
                    Text(r).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                if let item = row.items.first, item.co2Kg > 0 {
                    Text(String(format: "%.2f kg CO₂e avoided", item.co2Kg))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(BinSightTokens.Color.recycle)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(10)
        .glassSurface(RoundedRectangle(cornerRadius: 14, style: .continuous), variant: .regular)
    }

    private func decisionColor(_ decision: String) -> Color {
        switch decision {
        case "recycle": return BinSightTokens.Color.recycle
        case "compost": return BinSightTokens.Color.compost
        case "hazard":  return BinSightTokens.Color.hazard
        default:        return BinSightTokens.Color.trash
        }
    }

    private func hostOf(_ s: String) -> String {
        URL(string: s)?.host?.replacingOccurrences(of: "www.", with: "") ?? s
    }

    private func tierIconFor(_ tier: String) -> String {
        switch tier {
        case "official":      return "checkmark.seal.fill"
        case "authoritative": return "newspaper.fill"
        case "community":     return "bubble.left.fill"
        default:              return "link"
        }
    }
    private func tierColorFor(_ tier: String) -> Color {
        switch tier {
        case "official":      return BinSightTokens.Color.recycle
        case "authoritative": return BinSightTokens.Color.accent
        default:              return .secondary
        }
    }
}

// MARK: - First-scan celebration (unchanged)

private struct FirstScanCelebration: View {
    let dismiss: () -> Void
    @State private var pulse = false
    @State private var rotate = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(BinSightTokens.Color.recycle.opacity(0.35))
                        .frame(width: 200, height: 200)
                        .scaleEffect(pulse ? 1.15 : 0.85)
                    Image(systemName: "leaf.circle.fill")
                        .font(.system(size: 96, weight: .light))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(rotate ? 360 : 0))
                }
                .frame(height: 200)
                Text("First scan!")
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                Text("Every item you classify trains your impact.")
                    .font(.system(.callout, design: .rounded).weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button("Keep going", action: dismiss)
                    .buttonStyle(DuoButtonStyle(kind: .neutral))
                    .frame(maxWidth: 260)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { rotate = true }
            HapticEngine.success.notificationOccurred(.success)
        }
        .onTapGesture { dismiss() }
    }
}
