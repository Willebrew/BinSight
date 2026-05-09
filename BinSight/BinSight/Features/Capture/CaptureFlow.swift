import Foundation
import Combine
import os

private let captureLog = Logger(subsystem: "BinSight", category: "capture")

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

        // Hard-fail with a clear message if the user isn't signed in. This
        // beats the silent, untraceable Convex auth rejection we'd otherwise
        // get from `generateUploadUrl`.
        guard ConvexService.shared.authState == .signedIn else {
            let msg = "Sign in to classify photos."
            captureLog.error("classify aborted: not signed in (state=\(String(describing: ConvexService.shared.authState)))")
            lastError = msg
            throw NSError(domain: "BinSight", code: 401, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        captureLog.info("classify start: jpeg=\(jpeg.count) bytes, lat=\(lat ?? .nan), lng=\(lng ?? .nan), city=\(city ?? "-")")

        let storageId: String
        do {
            storageId = try await ConvexService.shared.upload(image: jpeg)
            captureLog.info("upload ok: storageId=\(storageId)")
        } catch {
            let msg = "Upload failed: \(error.localizedDescription)"
            captureLog.error("\(msg)")
            lastError = msg
            throw error
        }

        let geohash5: String? = (lat != nil && lng != nil)
            ? Geohash.encode(latitude: lat!, longitude: lng!, precision: 5)
            : nil

        let id: String
        do {
            id = try await ConvexService.shared.createClassification(
                storageId: storageId,
                lat: lat, lng: lng, geohash5: geohash5,
                city: city, state: state, country: country
            )
            captureLog.info("createClassification ok: id=\(id)")
        } catch {
            let msg = "Couldn't create scan: \(error.localizedDescription)"
            captureLog.error("\(msg)")
            lastError = msg
            throw error
        }

        // Kick off the async classify action. Failures here do NOT block the
        // sheet from opening (the Result view subscribes for live status),
        // but we still surface them via lastError + log.
        Task { @MainActor in
            do {
                try await runWithRetry(id: id)
                captureLog.info("classify action complete: id=\(id)")
            } catch {
                let msg = "Classify failed: \(error.localizedDescription)"
                captureLog.error("\(msg)")
                self.lastError = msg
            }
        }
        return id
    }

    private func runWithRetry(id: String) async throws {
        do {
            try await ConvexService.shared.runClassifyAction(id: id)
        } catch {
            captureLog.warning("classify retry after error: \(error.localizedDescription)")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            try await ConvexService.shared.runClassifyAction(id: id)
        }
    }
}
