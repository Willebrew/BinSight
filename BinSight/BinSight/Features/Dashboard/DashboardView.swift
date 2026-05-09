import SwiftUI
import Charts
import Combine

struct DashboardView: View {
    @State private var metrics: MetricsDoc?
    @State private var subscription: AnyCancellable?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summary
                    materialsChart
                    weeklyChart
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label("View history", systemImage: "tray.full.fill")
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
                    }.foregroundStyle(.primary)

                    NavigationLink {
                        ImpactMapView()
                    } label: {
                        Label("Impact map", systemImage: "map.fill")
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
                    }.foregroundStyle(.primary)

                    NavigationLink {
                        FriendsView()
                    } label: {
                        Label("Friends & leaderboard", systemImage: "person.2.fill")
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
                    }.foregroundStyle(.primary)
                }
                .padding(20)
            }
            .navigationTitle("Dashboard")
        }
        .task {
            subscription = ConvexService.shared.subscribeMetrics()
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in }, receiveValue: { metrics = $0 })
        }
    }

    private var summary: some View {
        let m = metrics
        return HStack(spacing: 12) {
            statTile(value: m?.totalScans ?? 0, label: "Scans", system: "camera.fill")
            statTile(value: m?.totalRecycled ?? 0, label: "Recycled", system: "leaf.fill", tint: BinSightTokens.Color.recycle)
            statTile(value: m?.totalTrashed ?? 0, label: "Trash", system: "trash.fill", tint: BinSightTokens.Color.trash)
        }
    }

    private func statTile(value: Int, label: String, system: String, tint: Color = BinSightTokens.Color.accent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: system).foregroundStyle(tint)
            Text("\(value)").font(.title.weight(.bold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), variant: .regular)
    }

    @ViewBuilder
    private var materialsChart: some View {
        if let m = metrics, !m.byMaterial.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Materials").font(.headline)
                Chart {
                    ForEach(m.byMaterial.sorted(by: { $0.value > $1.value }), id: \.key) { kv in
                        SectorMark(angle: .value("Count", kv.value), innerRadius: .ratio(0.55))
                            .foregroundStyle(by: .value("Material", kv.key))
                    }
                }
                .frame(height: 220)
            }
            .padding(16)
            .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), variant: .regular)
        }
    }

    @ViewBuilder
    private var weeklyChart: some View {
        if let m = metrics, !m.byDay.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Last days").font(.headline)
                Chart {
                    ForEach(m.byDay.sorted(by: { $0.key < $1.key }), id: \.key) { kv in
                        BarMark(x: .value("Day", kv.key), y: .value("Recycled", kv.value.recycled))
                            .foregroundStyle(BinSightTokens.Color.recycle)
                        BarMark(x: .value("Day", kv.key), y: .value("Trash", kv.value.trashed))
                            .foregroundStyle(BinSightTokens.Color.trash)
                    }
                }
                .frame(height: 200)

                if let co2 = metrics?.totalCo2Kg {
                    Text("Estimated CO₂ saved: \(co2, specifier: "%.2f") kg")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), variant: .regular)
        }
    }
}
