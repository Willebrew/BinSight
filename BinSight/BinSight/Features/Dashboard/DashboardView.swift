import SwiftUI
import Charts
import Combine

struct DashboardView: View {
    @State private var metrics: MetricsDoc?
    @State private var rows: [ClassificationDoc] = []
    @State private var bag: Set<AnyCancellable> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    summaryRow
                    if (metrics?.totalScans ?? 0) == 0 {
                        emptyState
                    } else {
                        recentRow
                        materialsChart
                        weeklyChart
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 110)
            }
            .background(backdrop.ignoresSafeArea())
            .navigationTitle("Dashboard")
        }
        .onAppear {
            ConvexService.shared.subscribeMetrics()
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in }, receiveValue: { metrics = $0 })
                .store(in: &bag)
            ConvexService.shared.subscribeHistory()
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in }, receiveValue: { rows = $0.filter { $0.status == "done" } })
                .store(in: &bag)
        }
        .onDisappear { bag.forEach { $0.cancel() }; bag.removeAll() }
    }

    private var hero: some View {
        let m = metrics
        return ZStack(alignment: .topLeading) {
            heroGradient
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("CO₂ kept out of the landfill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .textCase(.uppercase)
                    Spacer()
                    Image(systemName: "leaf.fill").foregroundStyle(.white.opacity(0.85))
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.2f", Double(m?.totalCo2Kg ?? 0)))
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("kg")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                HStack(spacing: 10) {
                    heroChip(icon: "flame.fill", value: "\(streakDays)d", label: "streak")
                    heroChip(icon: "checkmark.seal.fill", value: "\(m?.totalRecycled ?? 0)", label: "recycled")
                    heroChip(icon: "trash.fill", value: "\(m?.totalTrashed ?? 0)", label: "trash")
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var heroGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.34, blue: 0.32),
                Color(red: 0.13, green: 0.55, blue: 0.45),
                Color(red: 0.20, green: 0.74, blue: 0.49),
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
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.white.opacity(0.18), in: Capsule())
    }

    private var summaryRow: some View {
        let m = metrics
        return HStack(spacing: 12) {
            statTile(value: "\(m?.totalScans ?? 0)", label: "Scans", system: "camera.fill", tint: BinSightTokens.Color.accent)
            statTile(value: "\(m?.totalRecycled ?? 0)", label: "Recycled", system: "leaf.fill", tint: BinSightTokens.Color.recycle)
            statTile(value: "\(m?.totalTrashed ?? 0)", label: "Trash", system: "trash.fill", tint: BinSightTokens.Color.trash)
        }
    }

    private func statTile(value: String, label: String, system: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: system).foregroundStyle(tint)
                Spacer()
            }
            Text(value).font(.title.weight(.bold)).foregroundStyle(.primary)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous), variant: .regular)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(BinSightTokens.Color.recycle)
            Text("No scans yet").font(.title3.weight(.semibold))
            Text("Tap the camera button below and snap any waste item — BinSight will tell you exactly how to dispose of it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .glassSurface(RoundedRectangle(cornerRadius: 24, style: .continuous), variant: .regular)
    }

    private var recentRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent scans").font(.headline)
                Spacer()
                NavigationLink("View all") { HistoryView() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BinSightTokens.Color.accent)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(rows.prefix(8)) { row in
                        NavigationLink {
                            ResultCardView(classificationId: row._id)
                        } label: {
                            RecentScanCard(row: row)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var materialsChart: some View {
        if let m = metrics, !m.byMaterial.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Materials").font(.headline)
                Chart {
                    ForEach(m.byMaterial.sorted(by: { $0.value > $1.value }), id: \.key) { kv in
                        SectorMark(angle: .value("Count", kv.value), innerRadius: .ratio(0.6))
                            .foregroundStyle(by: .value("Material", kv.key))
                    }
                }
                .frame(height: 220)
            }
            .padding(16)
            .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous), variant: .regular)
        }
    }

    @ViewBuilder
    private var weeklyChart: some View {
        if let m = metrics, !m.byDay.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Last 7 days").font(.headline)
                Chart {
                    ForEach(m.byDay.sorted(by: { $0.key < $1.key }), id: \.key) { kv in
                        BarMark(x: .value("Day", String(kv.key.suffix(5))), y: .value("Recycled", kv.value.recycled))
                            .foregroundStyle(BinSightTokens.Color.recycle)
                        BarMark(x: .value("Day", String(kv.key.suffix(5))), y: .value("Trash", kv.value.trashed))
                            .foregroundStyle(BinSightTokens.Color.trash)
                    }
                }
                .frame(height: 180)
            }
            .padding(16)
            .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous), variant: .regular)
        }
    }

    private var streakDays: Int {
        let cal = Calendar.current
        let days = Set(rows.map {
            cal.startOfDay(for: Date(timeIntervalSince1970: $0.capturedAt / 1000))
        })
        var streak = 0
        var cursor = cal.startOfDay(for: Date())
        while days.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    private var backdrop: some View {
        LinearGradient(
            colors: [Color(.systemGroupedBackground), Color(.systemBackground)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

private struct RecentScanCard: View {
    let row: ClassificationDoc

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            .frame(width: 124, height: 124)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if let item = row.items.first {
                    Text(item.decision.capitalized)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(decisionColor(item.decision), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }
            Text(row.items.first?.label ?? "—")
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .frame(width: 124, alignment: .leading)
        }
    }

    private func decisionColor(_ decision: String) -> Color {
        switch decision {
        case "recycle": return BinSightTokens.Color.recycle
        case "compost": return BinSightTokens.Color.compost
        case "hazard":  return BinSightTokens.Color.hazard
        default:        return BinSightTokens.Color.trash
        }
    }
}
