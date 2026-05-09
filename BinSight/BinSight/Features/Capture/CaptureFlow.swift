import Foundation
import Combine

@MainActor
final class CaptureFlow: ObservableObject {
    struct Identified: Identifiable, Hashable { let value: String; var id: String { value } }

    @Published var activeId: Identified?
    @Published private(set) var isWorking = false
    @Published private(set) var lastError: String?

    func classify(
        jpeg: Data,
        lat: Double?,
        lng: Double?,
        city: String?,
        state: String?,
        country: String?
    ) async throws -> String {
        isWorking = true
        defer { isWorking = false }
        lastError = nil

        let storageId = try await ConvexService.shared.upload(image: jpeg)
        let geohash5: String? = (lat != nil && lng != nil)
            ? Geohash.encode(latitude: lat!, longitude: lng!, precision: 5)
            : nil
        let id = try await ConvexService.shared.createClassification(
            storageId: storageId,
            lat: lat, lng: lng, geohash5: geohash5,
            city: city, state: state, country: country
        )

        Task { try? await runWithRetry(id: id) }
        return id
    }

    private func runWithRetry(id: String) async throws {
        do {
            try await ConvexService.shared.runClassifyAction(id: id)
        } catch {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            try await ConvexService.shared.runClassifyAction(id: id)
        }
    }
}
