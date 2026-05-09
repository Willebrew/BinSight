import CoreLocation
import Combine

@MainActor
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var last: CLLocation?
    @Published private(set) var status: CLAuthorizationStatus = .notDetermined
    @Published private(set) var placemark: CLPlacemark?
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastGeocodeAt: Date = .distantPast

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            manager.startUpdatingLocation()
        }
    }

    func stop() { manager.stopUpdatingLocation() }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.status = manager.authorizationStatus
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.startUpdatingLocation()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.last = loc
            // Reverse-geocode at most once per minute to populate city/state/country.
            if Date().timeIntervalSince(self.lastGeocodeAt) > 60 {
                self.lastGeocodeAt = Date()
                Task.detached { [geocoder = self.geocoder] in
                    if let place = try? await geocoder.reverseGeocodeLocation(loc).first {
                        await MainActor.run { self.placemark = place }
                    }
                }
            }
        }
    }
}

/// 5-character geohash, ~5km precision.
enum Geohash {
    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    static func encode(latitude: Double, longitude: Double, precision: Int = 5) -> String {
        var minLat = -90.0, maxLat = 90.0
        var minLon = -180.0, maxLon = 180.0
        var bit = 0, ch = 0, even = true
        var hash = ""
        while hash.count < precision {
            if even {
                let mid = (minLon + maxLon) / 2
                if longitude >= mid { ch |= (1 << (4 - bit)); minLon = mid } else { maxLon = mid }
            } else {
                let mid = (minLat + maxLat) / 2
                if latitude >= mid { ch |= (1 << (4 - bit)); minLat = mid } else { maxLat = mid }
            }
            even.toggle()
            if bit < 4 { bit += 1 } else { hash.append(base32[ch]); bit = 0; ch = 0 }
        }
        return hash
    }
}
