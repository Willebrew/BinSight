import Foundation
import Combine
import ConvexMobile

/// Authenticated Convex client. Reads a JWT from Keychain on startup; if there
/// isn't one, the AuthProvider mints an anonymous account on first call.
@MainActor
final class ConvexService: ObservableObject {
    static let shared = ConvexService()

    static let deploymentUrl = "https://small-gerbil-660.convex.cloud"

    let client: ConvexClientWithAuth<String>
    private let authProvider: AnonymousAuthProvider

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var authError: String?

    private init() {
        let url = (Bundle.main.object(forInfoDictionaryKey: "CONVEX_URL") as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? Self.deploymentUrl
        let provider = AnonymousAuthProvider(deploymentURL: URL(string: url) ?? URL(string: Self.deploymentUrl)!)
        self.authProvider = provider
        self.client = ConvexClientWithAuth(deploymentUrl: url, authProvider: provider)
    }

    /// Call once on app launch. Loads cached token, signs in anonymously if none.
    func bootstrap() async {
        let result = await client.loginFromCache()
        switch result {
        case .success:
            isAuthenticated = true
            authError = nil
        case .failure(let err):
            authError = err.localizedDescription
            // Try a fresh anonymous sign-in (no cached token case).
            let retry = await client.login()
            switch retry {
            case .success:
                isAuthenticated = true
                authError = nil
            case .failure(let e):
                authError = e.localizedDescription
            }
        }
    }

    func signOut() async {
        await client.logout()
        isAuthenticated = false
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
        geohash5: String?,
        city: String?,
        state: String?,
        country: String?
    ) async throws -> String {
        var args: [String: ConvexEncodable?] = ["storageId": storageId]
        if let lat { args["lat"] = lat }
        if let lng { args["lng"] = lng }
        if let geohash5 { args["geohash5"] = geohash5 }
        if let city { args["city"] = city }
        if let state { args["state"] = state }
        if let country { args["country"] = country }
        return try await client.mutation("classifications:create", with: args)
    }

    func runClassifyAction(id: String) async throws {
        let args: [String: ConvexEncodable?] = ["id": id]
        let _: String? = try await client.action("classifyWaste:run", with: args)
    }

    func deleteClassification(id: String) async throws {
        let args: [String: ConvexEncodable?] = ["id": id]
        try await client.mutation("classifications:remove", with: args)
    }

    func subscribeClassification(id: String) -> AnyPublisher<ClassificationDoc?, ClientError> {
        let args: [String: ConvexEncodable?] = ["id": id]
        return client.subscribe(to: "classifications:getById", with: args, yielding: ClassificationDoc?.self)
            .eraseToAnyPublisher()
    }

    func subscribeHistory() -> AnyPublisher<[ClassificationDoc], ClientError> {
        client.subscribe(to: "classifications:listForUser", yielding: [ClassificationDoc].self)
            .eraseToAnyPublisher()
    }

    func subscribeMetrics() -> AnyPublisher<MetricsDoc?, ClientError> {
        client.subscribe(to: "metrics:summary", yielding: MetricsDoc?.self)
            .eraseToAnyPublisher()
    }

    func subscribeMap(level: String) -> AnyPublisher<[RegionCellDoc], ClientError> {
        let args: [String: ConvexEncodable?] = ["level": level]
        return client.subscribe(to: "map:aggregate", with: args, yielding: [RegionCellDoc].self)
            .eraseToAnyPublisher()
    }

    func nearbyFacilities(lat: Double, lng: Double, geohash5: String) async throws -> [FacilityDoc] {
        let args: [String: ConvexEncodable?] = ["lat": lat, "lng": lng, "geohash5": geohash5]
        return try await client.action("facilities:nearby", with: args)
    }

    // MARK: - Profile

    func subscribeProfile() -> AnyPublisher<ProfileDoc?, ClientError> {
        client.subscribe(to: "profiles:me", yielding: ProfileDoc?.self)
            .eraseToAnyPublisher()
    }

    func setDisplayName(_ name: String) async throws {
        let args: [String: ConvexEncodable?] = ["name": name]
        try await client.mutation("profiles:setDisplayName", with: args)
    }

    struct AppleVerifyResult: Decodable {
        let sub: String
        let email: String?
        let fullName: String?
    }

    func verifyAppleIdentity(identityToken: String, fullName: String?) async throws -> AppleVerifyResult {
        var args: [String: ConvexEncodable?] = ["identityToken": identityToken]
        if let fullName { args["fullName"] = fullName }
        return try await client.action("appleAuth:verifyAppleToken", with: args)
    }
}
