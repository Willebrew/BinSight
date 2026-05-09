import Foundation
import Combine

@MainActor
final class CaptureFlow: ObservableObject {
    struct Identified: Identifiable, Hashable { let value: String; var id: String { value } }

    @Published var activeId: Identified?
    @Published private(set) var isWorking = false
    @Published private(set) var lastError: String?

    func classify(jpeg: Data, lat: Double?, lng: Double?) async throws -> String {
        isWorking = true
        defer { isWorking = false }
        lastError = nil

        let imageURL = LocalHistoryStore.shared.storeImage(jpeg)
        let pending = LocalHistoryStore.shared.insertPending(imageURL: imageURL, lat: lat, lng: lng)

        Task {
            do {
                let result = try await PerplexityClient.classify(jpeg: jpeg, lat: lat, lng: lng)
                LocalHistoryStore.shared.update(pending._id) { doc in
                    doc.status = "done"
                    doc.items = result.items
                    doc.localRules = result.localRules
                    doc.citations = result.citations
                    doc.model = result.model
                    doc.verified = false
                }
            } catch {
                LocalHistoryStore.shared.update(pending._id) { doc in
                    doc.status = "error"
                    doc.errorMessage = error.localizedDescription
                }
            }
        }

        return pending._id
    }
}
