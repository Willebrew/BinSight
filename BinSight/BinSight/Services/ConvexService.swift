import Foundation
import Combine
import ConvexMobile

/// Single shared `ConvexClient` plus typed helpers used throughout the app.
/// Reads the deployment URL from `Info.plist` `CONVEX_URL`.
@MainActor
final class ConvexService: ObservableObject {
    static let shared = ConvexService()

    let client: ConvexClientWithAuth
    let deploymentUrl: URL

    private init() {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "CONVEX_URL") as? String,
            let url = URL(string: raw)
        else {
            fatalError("CONVEX_URL missing or invalid in Info.plist. Set it to your Convex deployment URL (e.g. https://xxx.convex.cloud)")
        }
        self.deploymentUrl = url
        self.client = ConvexClientWithAuth(deploymentUrl: raw, authProvider: ConvexAuthProvider())
    }

    // MARK: - Files

    func generateUploadUrl() async throws -> URL {
        let raw: String = try await client.mutation("files:generateUploadUrl")
        guard let u = URL(string: raw) else {
            throw NSError(domain: "Convex", code: -1, userInfo: [NSLocalizedDescriptionKey: "Bad upload URL"])
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
            throw NSError(domain: "Convex", code: -2, userInfo: [NSLocalizedDescriptionKey: "Upload failed"])
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
        struct Args: Encodable {
            let storageId: String
            let lat: Double?
            let lng: Double?
            let geohash5: String?
        }
        let args = Args(storageId: storageId, lat: lat, lng: lng, geohash5: geohash5)
        let id: String = try await client.mutation("classifications:create", args: args)
        return id
    }

    func runClassifyAction(id: String) async throws {
        struct Args: Encodable { let id: String }
        let _: String? = try await client.action("classifyWaste:run", args: Args(id: id))
    }

    func subscribeClassification(id: String) -> AnyPublisher<ClassificationDoc?, Error> {
        struct Args: Encodable { let id: String }
        return client.subscribe(to: "classifications:getById", args: Args(id: id), as: ClassificationDoc?.self)
            .eraseToAnyPublisher()
    }

    func subscribeHistory() -> AnyPublisher<[ClassificationDoc], Error> {
        struct Args: Encodable { let limit: Int = 50 }
        return client.subscribe(to: "classifications:listForUser", args: Args(), as: [ClassificationDoc].self)
            .eraseToAnyPublisher()
    }

    // MARK: - Profile

    func subscribeMe() -> AnyPublisher<ProfileDoc?, Error> {
        client.subscribe(to: "users:me", as: ProfileDoc?.self).eraseToAnyPublisher()
    }

    func ensureProfile() async throws {
        let _: String? = try await client.mutation("users:ensureProfile")
    }

    func updateProfile(name: String? = nil, handle: String? = nil, phoneHash: String? = nil,
                       mapOptIn: Bool? = nil, contactsOptIn: Bool? = nil) async throws {
        struct Args: Encodable {
            let name: String?
            let handle: String?
            let phoneHash: String?
            let mapOptIn: Bool?
            let contactsOptIn: Bool?
        }
        let _: String? = try await client.mutation(
            "users:updateProfile",
            args: Args(name: name, handle: handle, phoneHash: phoneHash,
                       mapOptIn: mapOptIn, contactsOptIn: contactsOptIn)
        )
    }

    // MARK: - Metrics, friends, leaderboard, map

    func subscribeMetrics() -> AnyPublisher<MetricsDoc?, Error> {
        client.subscribe(to: "metrics:summary", as: MetricsDoc?.self).eraseToAnyPublisher()
    }

    func subscribeFriends() -> AnyPublisher<[FriendDoc], Error> {
        client.subscribe(to: "friends:list", as: [FriendDoc].self).eraseToAnyPublisher()
    }

    func findFriendsByPhoneHashes(_ hashes: [String]) async throws -> [FriendMatch] {
        struct Args: Encodable { let hashes: [String] }
        return try await client.query("users:findByPhoneHashes", args: Args(hashes: hashes))
    }

    func subscribeLeaderboard() -> AnyPublisher<[LeaderboardRow], Error> {
        client.subscribe(to: "leaderboard:top", as: [LeaderboardRow].self).eraseToAnyPublisher()
    }

    func subscribeMap() -> AnyPublisher<[MapCellDoc], Error> {
        struct Args: Encodable { let sinceMs: Double = 0 }
        return client.subscribe(to: "map:aggregate", args: Args(), as: [MapCellDoc].self)
            .eraseToAnyPublisher()
    }

    func nearbyFacilities(lat: Double, lng: Double, geohash5: String) async throws -> [FacilityDoc] {
        struct Args: Encodable { let lat: Double; let lng: Double; let geohash5: String }
        return try await client.action(
            "facilities:nearby",
            args: Args(lat: lat, lng: lng, geohash5: geohash5)
        )
    }
}
