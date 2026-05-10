import Foundation
import MapKit
import CoreLocation

/// Loads bundled Natural Earth GeoJSON (countries + US states) once and
/// hands out real `MKPolygon` / `MKMultiPolygon` overlays keyed by
/// region name. Used by `ImpactMapView` to draw exact administrative
/// borders instead of approximating with a circle.
///
/// To populate the bundle, drop these files into the Xcode project under
/// `Resources/RegionGeometry/` and check the BinSight app target:
///   - `countries.geojson`  (Natural Earth 110m admin_0_countries)
///   - `us_states.geojson`  (Natural Earth 110m admin_1_states_provinces, US only is fine)
final class RegionGeometryStore {
    static let shared = RegionGeometryStore()

    /// Resolved geometry + a representative center point. The center is
    /// the polygon's coordinate (`MKPolygon.coordinate` ≈ centroid),
    /// used to place a name pill on the map.
    struct Resolved {
        let polygons: [MKPolygon]
        let bounding: MKMapRect
        let center: CLLocationCoordinate2D
    }

    private var countries: [String: Resolved] = [:]
    private var usStates: [String: Resolved] = [:]
    private var loaded = false

    private init() {}

    func country(named raw: String) -> Resolved? {
        ensureLoaded()
        return countries[normalize(raw)]
    }

    /// `state` may be a full name ("Colorado") or postal code ("CO");
    /// both resolve to the same feature.
    func usState(named raw: String) -> Resolved? {
        ensureLoaded()
        return usStates[normalize(raw)]
    }

    private func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        countries = loadFeatures(
            resource: "countries",
            keyExtractors: [
                { $0["NAME"] as? String },
                { $0["ADMIN"] as? String },
                { $0["SOVEREIGNT"] as? String },
                { $0["NAME_LONG"] as? String },
                { $0["FORMAL_EN"] as? String },
                { $0["ISO_A2"] as? String },
                { $0["ISO_A3"] as? String },
            ],
            extraAliases: [
                "united states": ["united states of america", "usa", "us"],
                "united kingdom": ["uk", "great britain", "england"],
                "russia": ["russian federation"],
                "south korea": ["republic of korea", "korea"],
                "north korea": ["democratic people's republic of korea", "dprk"],
            ]
        )
        usStates = loadFeatures(
            resource: "us_states",
            keyExtractors: [
                { $0["name"] as? String },
                { ($0["iso_3166_2"] as? String).flatMap { $0.split(separator: "-").last.map(String.init) } },
                { $0["postal"] as? String },
                { $0["code_hasc"] as? String },
            ],
            extraAliases: [:]
        )
    }

    private func loadFeatures(
        resource: String,
        keyExtractors: [([String: Any]) -> String?],
        extraAliases: [String: [String]]
    ) -> [String: Resolved] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "geojson")
                ?? Bundle.main.url(forResource: resource, withExtension: "json") else {
            #if DEBUG
            print("[RegionGeometryStore] Missing bundled file: \(resource).geojson — see header comment for setup.")
            #endif
            return [:]
        }
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = MKGeoJSONDecoder()
        guard let objects = try? decoder.decode(data) else { return [:] }

        var index: [String: Resolved] = [:]
        for object in objects {
            guard let feature = object as? MKGeoJSONFeature else { continue }
            // Properties JSON lives in `feature.properties` as raw bytes.
            let props: [String: Any] = {
                guard let p = feature.properties,
                      let parsed = try? JSONSerialization.jsonObject(with: p) as? [String: Any]
                else { return [:] }
                return parsed
            }()
            // Collect every polygon under this feature.
            var polygons: [MKPolygon] = []
            for geom in feature.geometry {
                if let mp = geom as? MKMultiPolygon {
                    polygons.append(contentsOf: mp.polygons)
                } else if let p = geom as? MKPolygon {
                    polygons.append(p)
                }
            }
            guard !polygons.isEmpty else { continue }
            let bounding = polygons.dropFirst().reduce(polygons[0].boundingMapRect) {
                $0.union($1.boundingMapRect)
            }
            // Center the label at the centroid of the bounding rect's
            // map projection. Good enough for irregular shapes.
            let centerMap = MKMapPoint(
                x: bounding.midX,
                y: bounding.midY
            ).coordinate
            let resolved = Resolved(polygons: polygons, bounding: bounding, center: centerMap)

            // Index under every name-shaped property the feature exposes,
            // plus any manual aliases.
            var keys: Set<String> = []
            for ex in keyExtractors {
                if let raw = ex(props), !raw.isEmpty {
                    keys.insert(raw.lowercased())
                }
            }
            for key in keys {
                index[key] = resolved
                if let aliases = extraAliases[key] {
                    for a in aliases { index[a.lowercased()] = resolved }
                }
            }
        }
        return index
    }
}
