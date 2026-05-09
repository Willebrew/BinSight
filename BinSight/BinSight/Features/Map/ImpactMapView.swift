import SwiftUI
import MapKit
import CoreLocation
import Combine

/// Region-based impact view. Shows an Apple Map with annotations sized by
/// activity, plus a leaderboard list - switchable between country, state,
/// and city aggregations.
struct ImpactMapView: View {
    @State private var rows: [RegionCellDoc] = []
    @State private var subscription: AnyCancellable?
    @State private var level: Level = .country
    @State private var coords: [String: CLLocationCoordinate2D] = [:]
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 140)
    ))

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

                ScrollView {
                    VStack(spacing: 16) {
                        leagueHeader
                        levelPicker
                        mapCard
                        if rows.isEmpty {
                            emptyState
                        } else {
                            leaderboard
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 130)
                }
            }
            .navigationTitle("League")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { resubscribe() }
        .onChange(of: level) { _, _ in
            resubscribe()
            coords.removeAll()
        }
        .onChange(of: rows) { _, newRows in
            geocodeNewLabels(in: newRows)
        }
        .onDisappear { subscription?.cancel() }
    }

    private func resubscribe() {
        subscription?.cancel()
        subscription = ConvexService.shared.subscribeMap(level: level.serverKey)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { rows = $0 })
    }

    // MARK: - Header

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

    // MARK: - Map card

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Map(position: $camera) {
                ForEach(annotated) { p in
                    Annotation(p.cell.label, coordinate: p.coord) {
                        MapPin(cell: p.cell, maxCount: maxCount)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if !annotated.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "leaf.fill").imageScale(.small)
                        Text("\(annotated.count) \(level.rawValue.lowercased())\(annotated.count == 1 ? "" : "s") on the map")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BinSightTokens.Color.recycle)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.white.opacity(0.92), in: Capsule())
                    .overlay(Capsule().stroke(BinSightTokens.Color.recycle.opacity(0.4), lineWidth: 1))
                    .padding(10)
                }
            }
        }
        .padding(6)
        .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(BinSightTokens.Color.recycle.opacity(0.25), lineWidth: 2))
    }

    private struct PlottedRegion: Identifiable {
        let cell: RegionCellDoc
        let coord: CLLocationCoordinate2D
        var id: String { cell.id }
    }

    private var annotated: [PlottedRegion] {
        rows.compactMap { cell in
            guard let c = coords[cell.label] else { return nil }
            return PlottedRegion(cell: cell, coord: c)
        }
    }

    private var maxCount: Int {
        rows.map(\.count).max() ?? 1
    }

    // MARK: - Leaderboard list

    private var leaderboard: some View {
        VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, cell in
                cellRow(rank: index + 1, cell: cell)
            }
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
    }

    // MARK: - Geocoding

    private func geocodeNewLabels(in newRows: [RegionCellDoc]) {
        let geocoder = CLGeocoder()
        for cell in newRows where coords[cell.label] == nil && !cell.label.isEmpty {
            geocoder.geocodeAddressString(cell.label) { placemarks, _ in
                guard let location = placemarks?.first?.location else { return }
                Task { @MainActor in
                    coords[cell.label] = location.coordinate
                    recenterIfNeeded()
                }
            }
        }
    }

    private func recenterIfNeeded() {
        let plotted = annotated
        guard !plotted.isEmpty else { return }
        let lats = plotted.map(\.coord.latitude)
        let lngs = plotted.map(\.coord.longitude)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLng = lngs.min() ?? 0
        let maxLng = lngs.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(2, (maxLat - minLat) * 1.6),
            longitudeDelta: max(2, (maxLng - minLng) * 1.6)
        )
        withAnimation(.easeInOut(duration: 0.6)) {
            camera = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}

// MARK: - Themed map pin

private struct MapPin: View {
    let cell: RegionCellDoc
    let maxCount: Int

    private var fraction: Double {
        guard cell.count > 0 else { return 0 }
        return Double(cell.recycled) / Double(cell.count)
    }

    private var size: CGFloat {
        let scale = Double(cell.count) / Double(max(maxCount, 1))
        return 28 + CGFloat(min(1.0, scale)) * 22
    }

    private var tint: Color {
        if fraction >= 0.66 { return BinSightTokens.Color.recycle }
        if fraction >= 0.33 { return BinSightTokens.Color.accent }
        return BinSightTokens.Color.hazard
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.22))
                    .frame(width: size + 18, height: size + 18)
                Circle()
                    .fill(.white)
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(tint, lineWidth: 3))
                Image(systemName: "leaf.fill")
                    .font(.system(size: size * 0.42, weight: .heavy))
                    .foregroundStyle(tint)
            }
            Text("\(cell.count)")
                .font(.system(.caption2, design: .rounded).weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(tint, in: Capsule())
                .overlay(Capsule().stroke(.white, lineWidth: 1.5))
        }
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
    }
}
