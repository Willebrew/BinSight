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
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.18, blue: 0.22),
                        Color(red: 0.04, green: 0.10, blue: 0.14),
                    ],
                    startPoint: .top, endPoint: .bottom
                ).ignoresSafeArea()

                VStack(spacing: 16) {
                    levelPicker
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                    if rows.isEmpty {
                        emptyState
                    } else {
                        leaderboard
                    }
                    Spacer(minLength: 0)
                }
            }
            .navigationTitle("Impact map")
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
                    .foregroundStyle(level == l ? .white : .white.opacity(0.65))
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
        .glassSurface(Capsule(), variant: .regular)
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
            Text("#\(rank)")
                .font(.headline.monospaced())
                .frame(width: 38, alignment: .leading)
                .foregroundStyle(.white.opacity(0.7))

            VStack(alignment: .leading, spacing: 4) {
                Text(cell.label.isEmpty ? "Unknown" : cell.label)
                    .font(.headline)
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    Label("\(cell.count)", systemImage: "camera.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                    Label("\(cell.recycled) recycled", systemImage: "leaf.fill")
                        .font(.caption)
                        .foregroundStyle(BinSightTokens.Color.recycle)
                }
                ProgressView(
                    value: Double(cell.recycled),
                    total: Double(max(cell.count, 1))
                )
                .tint(BinSightTokens.Color.recycle)
            }
            Spacer()
        }
        .padding(14)
        .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), variant: .regular)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "globe.badge.chevron.backward")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(BinSightTokens.Color.recycle)
            Text("No data here yet").font(.headline).foregroundStyle(.white)
            Text("As people scan items, this map fills in with cities, states, and countries.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous), variant: .regular)
        .padding(.horizontal, 18)
    }
}
