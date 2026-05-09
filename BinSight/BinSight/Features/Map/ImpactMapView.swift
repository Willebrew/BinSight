import SwiftUI
import Combine

/// Region-based impact view. Switches between country / state / city
/// aggregations using the new server `map:aggregate` query.
struct ImpactMapView: View {
    @State private var rows: [RegionCellDoc] = []
    @State private var subscription: AnyCancellable?
    @State private var level: Level = .country

    enum Level: String, CaseIterable, Identifiable {
        case country = "Country"
        case state = "State"
        case city = "City"
        var id: String { rawValue }
        var serverKey: String { rawValue.lowercased() }
        var icon: String {
            switch self {
            case .country: return "globe"
            case .state:   return "map"
            case .city:    return "building.2"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DuoBackdrop().ignoresSafeArea()

                VStack(spacing: 16) {
                    leagueHeader
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                    levelPicker
                        .padding(.horizontal, 18)
                    if rows.isEmpty {
                        emptyState
                    } else {
                        leaderboard
                    }
                    Spacer(minLength: 0)
                }
            }
            .navigationTitle("League")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { resubscribe() }
        .onChange(of: level) { _, _ in resubscribe() }
        .onDisappear { subscription?.cancel() }
    }

    private func resubscribe() {
        subscription?.cancel()
        subscription = ConvexService.shared.subscribeMap(level: level.serverKey)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { rows = $0 })
    }

    private var leagueHeader: some View {
        DuoCard(fill: .white, stroke: BinSightTokens.Color.xp.opacity(0.35), radius: 26, padding: 16) {
            HStack(spacing: 14) {
                MascotArtView(mood: .celebrate, size: 82, accessory: "trophy.fill")
                VStack(alignment: .leading, spacing: 5) {
                    Text("Community League")
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(BinSightTokens.Color.ink)
                    Text("Rank regions by confirmed recycling activity.")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(BinSightTokens.Color.softInk)
                }
            }
        }
    }

    private var levelPicker: some View {
        HStack(spacing: 6) {
            ForEach(Level.allCases) { l in
                Button {
                    withAnimation(BinSightTokens.Motion.snap) { level = l }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: l.icon).imageScale(.small)
                        Text(l.rawValue).font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(level == l ? .white : BinSightTokens.Color.softInk)
                    .background {
                        if level == l {
                            Capsule().fill(BinSightTokens.Color.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.white.opacity(0.78), in: Capsule())
        .overlay(Capsule().stroke(.white, lineWidth: 1.5))
    }

    private var leaderboard: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, cell in
                    cellRow(rank: index + 1, cell: cell)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 110)
        }
    }

    private func cellRow(rank: Int, cell: RegionCellDoc) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(rank <= 3 ? BinSightTokens.Color.xp.opacity(0.28) : BinSightTokens.Color.accent.opacity(0.12))
                    .frame(width: 46, height: 46)
                Text("#\(rank)")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(rank <= 3 ? Color(red: 0.70, green: 0.44, blue: 0.00) : BinSightTokens.Color.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(cell.label.isEmpty ? "Unknown" : cell.label)
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(BinSightTokens.Color.ink)
                HStack(spacing: 8) {
                    Label("\(cell.count)", systemImage: "camera.fill")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(BinSightTokens.Color.softInk)
                    Label("\(cell.recycled) recycled", systemImage: "leaf.fill")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(BinSightTokens.Color.recycle)
                }
                DuoProgressBar(value: Double(cell.recycled), total: Double(max(cell.count, 1)), color: BinSightTokens.Color.recycle, height: 10)
            }
            Spacer()
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BinSightTokens.Color.stroke, lineWidth: 2))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            MascotArtView(mood: .thinking, size: 106, accessory: "globe")
            Text("No data here yet").font(.system(.headline, design: .rounded).weight(.heavy)).foregroundStyle(BinSightTokens.Color.ink)
            Text("As people scan items, this map fills in with cities, states, and countries.")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(BinSightTokens.Color.softInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(BinSightTokens.Color.stroke, lineWidth: 2))
        .padding(.horizontal, 18)
    }
}
