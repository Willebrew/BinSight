import Foundation
import Combine
import ConvexMobile

/// Single shared `ConvexClient` plus typed helpers used throughout the app.
/// Reads the deployment URL from `Info.plist` `CONVEX_URL`.
@MainActor
final class ConvexService {
    static let shared = ConvexService()

    /// Public Convex deployment URL. Safe to commit — anyone with the URL can
    /// only call public functions; secrets like PERPLEXITY_API_KEY live as
    /// server-side env vars on the deployment.
    static let deploymentUrl = "https://small-gerbil-660.convex.cloud"

    let client: ConvexClient
    let clientId: String

    private init() {
        // Allow Info.plist override (set as a custom string in build settings if you
        // want to swap deployments without recompiling); fall back to the constant.
        let url = (Bundle.main.object(forInfoDictionaryKey: "CONVEX_URL") as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? Self.deploymentUrl
        self.client = ConvexClient(deploymentUrl: url)
        self.clientId = ClientIdentity.current
    }

    // MARK: - Files

    func generateUploadUrl() async throws -> URL {
        let raw: String = try await client.mutation("files:generateUploadUrl")
        guard let u = URL(string: raw) else {
            throw NSError(domain: "Convex", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Bad upload URL"])
        }
        return u
    }

    func upload(image data: Data, contentType: String = "image/jpeg") async throws -> String {
        let url = try await generateUploadUrl()
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (body, response) = try await URLSession.shared.upload(for: req, from: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Convex", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Upload failed"])
        }
        struct UploadResponse: Decodable { let storageId: String }
        return try JSONDecoder().decode(UploadResponse.self, from: body).storageId
    }

    // MARK: - Classifications

    func createClassification(
        storageId: String,
        lat: Double?,
        lng: Double?,
        geohash5: String?
    ) async throws -> String {
        var args: [String: ConvexEncodable?] = [
            "clientId": clientId,
            "storageId": storageId,
        ]
        if let lat { args["lat"] = lat }
        if let lng { args["lng"] = lng }
        if let geohash5 { args["geohash5"] = geohash5 }
        return try await client.mutation("classifications:create", with: args)
    }

    func runClassifyAction(id: String) async throws {
        let args: [String: ConvexEncodable?] = ["id": id, "clientId": clientId]
        let _: String? = try await client.action("classifyWaste:run", with: args)
    }

    func subscribeClassification(id: String) -> AnyPublisher<ClassificationDoc?, ClientError> {
        let args: [String: ConvexEncodable?] = ["id": id, "clientId": clientId]
        return client.subscribe(to: "classifications:getById", with: args, yielding: ClassificationDoc?.self)
            .eraseToAnyPublisher()
    }

    func subscribeHistory() -> AnyPublisher<[ClassificationDoc], ClientError> {
        // Server defaults limit to 50 when omitted. Don't pass it — Swift Ints
        // encode as Convex int64 but the validator wants float64.
        let args: [String: ConvexEncodable?] = ["clientId": clientId]
        return client.subscribe(to: "classifications:listForClient", with: args, yielding: [ClassificationDoc].self)
            .eraseToAnyPublisher()
    }

    func subscribeMetrics() -> AnyPublisher<MetricsDoc?, ClientError> {
        let args: [String: ConvexEncodable?] = ["clientId": clientId]
        return client.subscribe(to: "metrics:summary", with: args, yielding: MetricsDoc?.self)
            .eraseToAnyPublisher()
    }

    func subscribeMap() -> AnyPublisher<[MapCellDoc], ClientError> {
        // Omit sinceMs to use the server default; Convex validator on `number`
        // means float64 and Swift Ints would arrive as int64 and be rejected.
        let args: [String: ConvexEncodable?] = [:]
        return client.subscribe(to: "map:aggregate", with: args, yielding: [MapCellDoc].self)
            .eraseToAnyPublisher()
    }

    func nearbyFacilities(lat: Double, lng: Double, geohash5: String) async throws -> [FacilityDoc] {
        let args: [String: ConvexEncodable?] = ["lat": lat, "lng": lng, "geohash5": geohash5]
        return try await client.action("facilities:nearby", with: args)
    }
}
