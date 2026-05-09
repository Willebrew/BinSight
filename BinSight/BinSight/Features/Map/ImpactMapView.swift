import SwiftUI
import MapKit
import Combine

struct ImpactMapView: View {
    @State private var cells: [MapCellDoc] = []
    @State private var subscription: AnyCancellable?
    @State private var facilities: [FacilityDoc] = []
    @State private var loadingFacilities = false
    @State private var facilitiesError: String?
    @StateObject private var location = LocationProvider()

    var body: some View {
        Map {
            ForEach(cells) { cell in
                let coord = Geohash.decodeCenter(cell.geohash5)
                Annotation(cell.geohash5, coordinate: coord) {
                    Circle()
                        .fill(BinSightTokens.Color.recycle.opacity(0.6))
                        .frame(width: CGFloat(min(64, 12 + cell.count * 2)),
                               height: CGFloat(min(64, 12 + cell.count * 2)))
                        .overlay(Text("\(cell.count)").font(.caption2.weight(.bold)).foregroundStyle(.white))
                }
            }
            UserAnnotation()
        }
        .navigationTitle("Impact map")
        .safeAreaInset(edge: .bottom) {
            facilitiesPanel
        }
        .task {
            location.start()
            subscription = ConvexService.shared.subscribeMap()
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in }, receiveValue: { cells = $0 })
        }
    }

    private var facilitiesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Nearby recycling", systemImage: "mappin.and.ellipse")
                    .font(.headline)
                Spacer()
                Button {
                    fetchFacilities()
                } label: {
                    if loadingFacilities { ProgressView() } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            if let err = facilitiesError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            ForEach(facilities) { f in
                if let url = URL(string: f.url) {
                    Link(destination: url) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.title).font(.callout.weight(.semibold))
                            Text(f.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }.foregroundStyle(.primary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous), variant: .regular)
        .padding(.horizontal, 12).padding(.bottom, 12)
    }

    private func fetchFacilities() {
        guard let loc = location.last else {
            facilitiesError = "Waiting for location…"
            return
        }
        loadingFacilities = true
        facilitiesError = nil
        Task {
            defer { loadingFacilities = false }
            do {
                let geohash5 = Geohash.encode(latitude: loc.coordinate.latitude,
                                              longitude: loc.coordinate.longitude,
                                              precision: 5)
                facilities = try await ConvexService.shared.nearbyFacilities(
                    lat: loc.coordinate.latitude,
                    lng: loc.coordinate.longitude,
                    geohash5: geohash5
                )
            } catch {
                facilitiesError = error.localizedDescription
            }
        }
    }
}

extension Geohash {
    static func decodeCenter(_ hash: String) -> CLLocationCoordinate2D {
        let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")
        var minLat = -90.0, maxLat = 90.0, minLon = -180.0, maxLon = 180.0
        var even = true
        for ch in hash {
            guard let idx = base32.firstIndex(of: ch) else { continue }
            for bit in (0..<5).reversed() {
                let on = ((idx >> bit) & 1) == 1
                if even {
                    let mid = (minLon + maxLon) / 2
                    if on { minLon = mid } else { maxLon = mid }
                } else {
                    let mid = (minLat + maxLat) / 2
                    if on { minLat = mid } else { maxLat = mid }
                }
                even.toggle()
            }
        }
        return CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
    }
}
