import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject private var store = LocalHistoryStore.shared

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
                }
                .padding(20)
            }
            .navigationTitle("Dashboard")
        }
    }

    private var doneRows: [ClassificationDoc] { store.rows.filter { $0.status == "done" } }

    private var summary: some View {
        let scans = doneRows.count
        var recycled = 0, trashed = 0, totalCo2 = 0.0
        for row in doneRows {
            for item in row.items {
                totalCo2 += item.co2Kg
                if item.decision == "recycle" || item.decision == "compost" { recycled += 1 } else { trashed += 1 }
            }
        }
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                statTile(value: "\(scans)", label: "Scans", system: "camera.fill")
                statTile(value: "\(recycled)", label: "Recycled", system: "leaf.fill", tint: BinSightTokens.Color.recycle)
                statTile(value: "\(trashed)", label: "Trash", system: "trash.fill", tint: BinSightTokens.Color.trash)
            }
            if totalCo2 > 0 {
                Text("Estimated CO₂ saved: \(totalCo2, specifier: "%.2f") kg")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func statTile(value: String, label: String, system: String, tint: Color = BinSightTokens.Color.accent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: system).foregroundStyle(tint)
            Text(value).font(.title.weight(.bold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), variant: .regular)
    }

    @ViewBuilder
    private var materialsChart: some View {
        let counts = materialCounts
        if !counts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Materials").font(.headline)
                Chart {
                    ForEach(counts.sorted(by: { $0.value > $1.value }), id: \.key) { kv in
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
        let byDay = dailyCounts
        if !byDay.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Last days").font(.headline)
                Chart {
                    ForEach(byDay.sorted(by: { $0.key < $1.key }), id: \.key) { kv in
                        BarMark(x: .value("Day", kv.key), y: .value("Recycled", kv.value.recycled))
                            .foregroundStyle(BinSightTokens.Color.recycle)
                        BarMark(x: .value("Day", kv.key), y: .value("Trash", kv.value.trashed))
                            .foregroundStyle(BinSightTokens.Color.trash)
                    }
                }
                .frame(height: 200)
            }
            .padding(16)
            .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), variant: .regular)
        }
    }

    private var materialCounts: [String: Int] {
        var out: [String: Int] = [:]
        for row in doneRows {
            for item in row.items { out[item.material, default: 0] += 1 }
        }
        return out
    }

    private var dailyCounts: [String: (recycled: Int, trashed: Int)] {
        var out: [String: (Int, Int)] = [:]
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withFullDate]
        for row in doneRows {
            let day = formatter.string(from: Date(timeIntervalSince1970: row.capturedAt / 1000))
            var t = out[day] ?? (0, 0)
            for item in row.items {
                if item.decision == "recycle" || item.decision == "compost" { t.0 += 1 } else { t.1 += 1 }
            }
            out[day] = t
        }
        return out.mapValues { ($0.0, $0.1) }
    }
}
