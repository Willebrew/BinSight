import SwiftUI
import MapKit
import Combine

/// Local impact map (v0). Shows the user's own classifications pinned at the
/// coordinates captured at scan time. Annotation color reflects the dominant
/// decision for that scan. No backend / friend data yet — when the Convex
/// path lands we'll layer in anonymized geohash5 cells from `convex/map.ts`.
struct ImpactMapView: View {
    @ObservedObject private var store = LocalHistoryStore.shared
    @StateObject private var location = LocationProvider()
    @State private var selectedId: String?
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition, selection: $selectedId) {
                ForEach(pinnedRows) { row in
                    if let coord = coordinate(of: row) {
                        Annotation(row.items.first?.label ?? "Scan", coordinate: coord) {
                            ScanPin(row: row, isSelected: selectedId == row._id)
                        }
                        .tag(row._id)
                    }
                }
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .ignoresSafeArea()

            header
                .padding(.horizontal, 16)
                .padding(.top, 12)
        }
        .safeAreaInset(edge: .bottom) {
            if pinnedRows.isEmpty {
                emptyHint.padding(.horizontal, 16).padding(.bottom, 110)
            } else if let id = selectedId, let row = store.find(id) {
                selectedCard(row).padding(.horizontal, 16).padding(.bottom, 110)
            } else {
                Spacer().frame(height: 90)
            }
        }
        .onAppear {
            location.start()
            if let last = location.last {
                cameraPosition = .region(MKCoordinateRegion(center: last.coordinate,
                                                            latitudinalMeters: 1500,
                                                            longitudinalMeters: 1500))
            }
        }
        .onReceive(location.$last.compactMap { $0 }) { loc in
            guard pinnedRows.isEmpty else { return }
            cameraPosition = .region(MKCoordinateRegion(center: loc.coordinate,
                                                        latitudinalMeters: 1500,
                                                        longitudinalMeters: 1500))
        }
    }

    private var pinnedRows: [ClassificationDoc] {
        store.rows.filter { $0.lat != nil && $0.lng != nil && $0.status == "done" }
    }

    private func coordinate(of row: ClassificationDoc) -> CLLocationCoordinate2D? {
        guard let lat = row.lat, let lng = row.lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "globe.americas.fill")
                    .foregroundStyle(BinSightTokens.Color.recycle)
                Text("Impact map")
                    .font(.headline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassSurface(Capsule(), variant: .regular)

            Spacer(minLength: 0)

            Text("\(pinnedRows.count) scans")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassSurface(Capsule(), variant: .clear)
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 6) {
            Text("No scans pinned here yet")
                .font(.headline)
            Text("Allow location and capture a few items — they'll show up on this map.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous), variant: .regular)
    }

    private func selectedCard(_ row: ClassificationDoc) -> some View {
        HStack(spacing: 12) {
            if let urlString = row.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(row.items.first?.label ?? "Scan").font(.subheadline.weight(.semibold))
                if let item = row.items.first {
                    Text(item.decision.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(decisionColor(item.decision), in: Capsule())
                }
                Text(Date(timeIntervalSince1970: row.capturedAt / 1000)
                        .formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                selectedId = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous), variant: .regular)
    }

    private func decisionColor(_ d: String) -> Color {
        switch d {
        case "recycle": return BinSightTokens.Color.recycle
        case "compost": return BinSightTokens.Color.compost
        case "hazard":  return BinSightTokens.Color.hazard
        default:        return BinSightTokens.Color.trash
        }
    }
}

private struct ScanPin: View {
    let row: ClassificationDoc
    let isSelected: Bool

    var body: some View {
        let color: Color = {
            guard let item = row.items.first else { return .gray }
            switch item.decision {
            case "recycle": return BinSightTokens.Color.recycle
            case "compost": return BinSightTokens.Color.compost
            case "hazard":  return BinSightTokens.Color.hazard
            default:        return BinSightTokens.Color.trash
            }
        }()
        return ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: isSelected ? 44 : 30, height: isSelected ? 44 : 30)
            Circle()
                .fill(color)
                .frame(width: isSelected ? 22 : 16, height: isSelected ? 22 : 16)
                .overlay(Circle().stroke(.white, lineWidth: 2))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}
