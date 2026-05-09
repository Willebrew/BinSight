import Foundation
import Combine
import UIKit

/// On-device history of classifications. Stores JSON-encoded `ClassificationDoc`s
/// in the Application Support directory and exposes the list as a published
/// Combine stream so views can reactively update. Image bytes are saved alongside
/// each record so users can review history later.
@MainActor
final class LocalHistoryStore: ObservableObject {
    static let shared = LocalHistoryStore()
    @Published private(set) var rows: [ClassificationDoc] = []

    private let dir: URL
    private let metaURL: URL

    private init() {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.dir = support.appendingPathComponent("BinSight", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.metaURL = dir.appendingPathComponent("history.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: metaURL),
              let decoded = try? JSONDecoder().decode([ClassificationDoc].self, from: data)
        else { rows = []; return }
        rows = decoded.sorted { $0.capturedAt > $1.capturedAt }
    }

    func save() {
        let data = try? JSONEncoder().encode(rows)
        try? data?.write(to: metaURL, options: .atomic)
    }

    /// Persist a captured image and return a stable URL the UI can render.
    func storeImage(_ data: Data) -> URL {
        let id = UUID().uuidString
        let url = dir.appendingPathComponent("\(id).jpg")
        try? data.write(to: url, options: .atomic)
        return url
    }

    func insertPending(imageURL: URL, lat: Double?, lng: Double?) -> ClassificationDoc {
        let id = UUID().uuidString
        let doc = ClassificationDoc(
            _id: id,
            authUserId: "local",
            storageId: imageURL.lastPathComponent,
            thumbStorageId: nil,
            capturedAt: Date().timeIntervalSince1970 * 1000,
            lat: lat, lng: lng, geohash5: nil,
            status: "pending",
            model: nil, items: [], localRules: nil,
            citations: [], verified: false, errorMessage: nil,
            imageUrl: imageURL.absoluteString
        )
        rows.insert(doc, at: 0)
        save()
        return doc
    }

    func update(_ id: String, transform: (inout ClassificationDoc) -> Void) {
        guard let idx = rows.firstIndex(where: { $0._id == id }) else { return }
        transform(&rows[idx])
        save()
    }

    func find(_ id: String) -> ClassificationDoc? {
        rows.first(where: { $0._id == id })
    }

    func clearAll() {
        rows = []
        save()
        if let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for url in entries where url.pathExtension == "jpg" {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
