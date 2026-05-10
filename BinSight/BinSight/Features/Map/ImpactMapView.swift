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
    /// Resolved geometry per label: center + radius in meters (from
    /// `CLPlacemark.region`). Radius gives every overlay a real-world
    /// scale so the disc shrinks/grows correctly with zoom.
    @State private var geometry: [String: ResolvedRegion] = [:]
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 140)
    ))

    private struct ResolvedRegion {
        let coord: CLLocationCoordinate2D
        /// Empty when we don't have polygon geometry for this region
        /// (currently: every city, plus any country/state missing from
        /// the bundled GeoJSON files).
        let polygons: [MKPolygon]
        /// Combined map rect of all polygons, or nil for pin-only regions.
        let bounding: MKMapRect?
    }

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
        .onChange(of: level) { _, newLevel in
            resubscribe()
            geometry.removeAll()
            // Snap camera to a sensible default for the new level so
            // we're not stuck zoomed in from the previous selection
            // until geocoding finishes.
            withAnimation(.easeInOut(duration: 0.45)) {
                camera = .region(defaultRegion(for: newLevel))
            }
        }
        .onChange(of: rows) { _, newRows in
            geocodeNewLabels(in: newRows)
        }
        .onDisappear { subscription?.cancel() }
    }

    private func defaultRegion(for l: Level) -> MKCoordinateRegion {
        switch l {
        case .country:
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 140))
        case .state:
            // US-centric default; expands once data arrives.
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
                span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 60))
        case .city:
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
                span: MKCoordinateSpan(latitudeDelta: 22, longitudeDelta: 28))
        }
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
                    // Real administrative borders for any region we have
                    // bundled GeoJSON geometry for (countries, US states).
                    if !p.polygons.isEmpty {
                        ForEach(Array(p.polygons.enumerated()), id: \.offset) { _, poly in
                            MapPolygon(poly)
                                .foregroundStyle(tint(for: p.cell).opacity(0.28))
                                .stroke(tint(for: p.cell), lineWidth: 2.5)
                        }
                    } else {
                        // No polygon (e.g. cities): a small pin at the
                        // geocoded coordinate, no fake circle.
                        Annotation(p.cell.label, coordinate: p.coord) {
                            CityPin(cell: p.cell, tint: tint(for: p.cell))
                        }
                    }
                    if !p.polygons.isEmpty {
                        Annotation(p.cell.label, coordinate: p.coord) {
                            RegionLabel(cell: p.cell, tint: tint(for: p.cell))
                        }
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
        let polygons: [MKPolygon]
        let bounding: MKMapRect?
        var id: String { cell.id }
    }

    private var annotated: [PlottedRegion] {
        rows.compactMap { cell in
            guard let g = geometry[cell.label] else { return nil }
            return PlottedRegion(
                cell: cell,
                coord: g.coord,
                polygons: g.polygons,
                bounding: g.bounding
            )
        }
    }

    private var maxCount: Int {
        rows.map(\.count).max() ?? 1
    }

    private func tint(for cell: RegionCellDoc) -> Color {
        let frac = cell.count > 0 ? Double(cell.recycled) / Double(cell.count) : 0
        if frac >= 0.66 { return BinSightTokens.Color.recycle }
        if frac >= 0.33 { return BinSightTokens.Color.accent }
        return BinSightTokens.Color.hazard
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
        let co2 = cell.co2Kg ?? 0
        let users = cell.uniqueUsers ?? 0
        let items = cell.itemsTotal ?? cell.recycled
        let diversion = cell.diversionRate ?? (cell.count > 0 ? Double(cell.recycled) / Double(cell.count) : 0)
        let hazards = cell.itemsHazard ?? 0

        return HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(rank <= 3 ? BinSightTokens.Color.xp.opacity(0.28) : BinSightTokens.Color.accent.opacity(0.12))
                    .frame(width: 46, height: 46)
                Text("#\(rank)")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(rank <= 3 ? Color(red: 0.70, green: 0.44, blue: 0.00) : BinSightTokens.Color.accent)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(cell.label.isEmpty ? "Unknown" : cell.label)
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(BinSightTokens.Color.ink)
                    Spacer()
                    if let last = cell.lastActivity {
                        Text(relativeTime(from: last))
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(BinSightTokens.Color.softInk)
                    }
                }

                // Two columns of headline stats: CO₂ saved + items
                // diverted (left), hazards caught + people active (right).
                HStack(alignment: .top, spacing: 14) {
                    statCol(
                        primary: formatCo2(co2),
                        primaryUnit: "kg CO₂",
                        secondary: "\(items) item\(items == 1 ? "" : "s")",
                        tint: BinSightTokens.Color.recycle,
                        icon: "leaf.fill"
                    )
                    statCol(
                        primary: hazards == 0 ? "—" : "\(hazards)",
                        primaryUnit: "hazards",
                        secondary: users == 0 ? "anonymous" : "\(users) scanner\(users == 1 ? "" : "s")",
                        tint: hazards > 0 ? BinSightTokens.Color.hazard : BinSightTokens.Color.accent,
                        icon: hazards > 0 ? "exclamationmark.triangle.fill" : "person.2.fill"
                    )
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Diversion rate")
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(BinSightTokens.Color.softInk)
                        Spacer()
                        Text("\(Int((diversion * 100).rounded()))%")
                            .font(.system(.caption2, design: .rounded).weight(.heavy).monospacedDigit())
                            .foregroundStyle(BinSightTokens.Color.recycle)
                    }
                    DuoProgressBar(
                        value: diversion,
                        total: 1,
                        color: BinSightTokens.Color.recycle,
                        height: 8
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BinSightTokens.Color.stroke, lineWidth: 2))
    }

    private func statCol(primary: String, primaryUnit: String, secondary: String, tint: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(tint)
                Text(primary)
                    .font(.system(.subheadline, design: .rounded).weight(.heavy).monospacedDigit())
                    .foregroundStyle(BinSightTokens.Color.ink)
                Text(primaryUnit)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(BinSightTokens.Color.softInk)
            }
            Text(secondary)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(BinSightTokens.Color.softInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatCo2(_ kg: Double) -> String {
        if kg >= 100 { return String(format: "%.0f", kg) }
        if kg >= 10 { return String(format: "%.1f", kg) }
        return String(format: "%.2f", kg)
    }

    private func relativeTime(from msEpoch: Double) -> String {
        let now = Date().timeIntervalSince1970 * 1000
        let diff = max(0, now - msEpoch)
        let m = diff / 1000 / 60
        if m < 60 { return "\(Int(m))m ago" }
        let h = m / 60
        if h < 24 { return "\(Int(h))h ago" }
        let d = h / 24
        if d < 30 { return "\(Int(d))d ago" }
        return "\(Int(d / 30))mo ago"
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
        for cell in newRows where geometry[cell.label] == nil && !cell.label.isEmpty {
            // 1) Bundled polygon geometry — preferred path. Real
            //    administrative borders, no network call.
            if let resolved = bundledGeometry(for: cell.label) {
                geometry[cell.label] = ResolvedRegion(
                    coord: resolved.center,
                    polygons: resolved.polygons,
                    bounding: resolved.bounding
                )
                recenterIfNeeded()
                continue
            }
            // 2) Fallback: geocode for a center coordinate (cities,
            //    foreign subdivisions). Renders as a pin, not a circle.
            geocoder.geocodeAddressString(cell.label) { placemarks, _ in
                guard let pm = placemarks?.first, let location = pm.location else { return }
                Task { @MainActor in
                    geometry[cell.label] = ResolvedRegion(
                        coord: location.coordinate,
                        polygons: [],
                        bounding: nil
                    )
                    recenterIfNeeded()
                }
            }
        }
    }

    /// Resolve the bundled polygon for a row label, accounting for the
    /// active level. The state level passes labels like "CO" (postal
    /// code) — the store handles both that and full names.
    private func bundledGeometry(for label: String) -> RegionGeometryStore.Resolved? {
        let store = RegionGeometryStore.shared
        switch level {
        case .country: return store.country(named: label)
        case .state:
            // The map.ts query returns just the state name/abbr at this
            // level. If we ever broaden support beyond the US, we'd
            // need a non-US states file too.
            return store.usState(named: label)
        case .city: return nil
        }
    }

    /// Fit the camera to all plotted regions. When we have polygon
    /// bounding rects, we union them (precise). When we only have pin
    /// coordinates (cities), we widen to a level-appropriate default.
    private func recenterIfNeeded() {
        let plotted = annotated
        guard !plotted.isEmpty else { return }

        // Polygons: union their map rects directly.
        let polyRects = plotted.compactMap { $0.bounding }
        if !polyRects.isEmpty {
            let unioned = polyRects.dropFirst().reduce(polyRects[0]) { $0.union($1) }
            // Pad so borders don't kiss the edges.
            let pad: Double = level == .country ? 0.20 : (level == .state ? 0.25 : 0.35)
            let dx = unioned.size.width * pad
            let dy = unioned.size.height * pad
            let padded = MKMapRect(
                x: unioned.origin.x - dx,
                y: unioned.origin.y - dy,
                width: unioned.size.width + dx * 2,
                height: unioned.size.height + dy * 2
            )
            withAnimation(.easeInOut(duration: 0.6)) {
                camera = .rect(padded)
            }
            return
        }

        // Pin-only fallback (cities): expand around min/max coords.
        var minLat = 90.0, maxLat = -90.0
        var minLng = 180.0, maxLng = -180.0
        for p in plotted {
            minLat = min(minLat, p.coord.latitude)
            maxLat = max(maxLat, p.coord.latitude)
            minLng = min(minLng, p.coord.longitude)
            maxLng = max(maxLng, p.coord.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let pad: Double = level == .city ? 1.8 : 1.6
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.4, (maxLat - minLat) * pad),
            longitudeDelta: max(0.4, (maxLng - minLng) * pad)
        )
        withAnimation(.easeInOut(duration: 0.6)) {
            camera = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}

// MARK: - City pin

/// Small leaf-shaped pin used at the city level, where we don't have
/// polygon geometry to draw a real boundary.
private struct CityPin: View {
    let cell: RegionCellDoc
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(.white).frame(width: 30, height: 30)
                    .overlay(Circle().stroke(tint, lineWidth: 2.5))
                Image(systemName: "leaf.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(tint)
            }
            HStack(spacing: 4) {
                Text(cell.label.isEmpty ? "Unknown" : cell.label)
                    .font(.system(.caption2, design: .rounded).weight(.heavy))
                    .foregroundStyle(BinSightTokens.Color.ink)
                    .lineLimit(1)
                ScanCountBadge(count: cell.count, tint: tint)
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(.white.opacity(0.96), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 1.2))
        }
        .shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Region label

/// Compact pill at the centroid of each region overlay. The big visual
/// is the geographic-radius circle drawn on the map; this just names it
/// and shows the activity count.
private struct RegionLabel: View {
    let cell: RegionCellDoc
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "leaf.fill")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(tint)
            Text(cell.label.isEmpty ? "Unknown" : cell.label)
                .font(.system(.caption2, design: .rounded).weight(.heavy))
                .foregroundStyle(BinSightTokens.Color.ink)
                .lineLimit(1)
            ScanCountBadge(count: cell.count, tint: tint)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.white.opacity(0.96), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
    }
}

/// Tiny "📷 N scans" badge used inside the map labels. The icon
/// makes it clear what the number represents (was previously just a
/// bare digit). `fixedSize` prevents the parent capsule from
/// truncating the count to ellipsis dots when the label text is wide.
private struct ScanCountBadge: View {
    let count: Int
    let tint: Color
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "camera.fill")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(.white)
            Text("\(count) scan\(count == 1 ? "" : "s")")
                .font(.system(.caption2, design: .rounded).weight(.heavy).monospacedDigit())
                .foregroundStyle(.white)
        }
        .fixedSize()
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(tint, in: Capsule())
    }
}
