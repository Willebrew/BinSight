import Foundation
import Combine
import ConvexMobile

/// Authenticated Convex client. Reads a JWT from Keychain on startup; the user
/// must sign in with email + password (Convex Auth Password provider).
@MainActor
final class ConvexService: ObservableObject {
    static let shared = ConvexService()

    static let deploymentUrl = "https://small-gerbil-660.convex.cloud"

    let client: ConvexClientWithAuth<String>
    private let authProvider: PasswordAuthProvider

    enum AuthState {
        case unknown        // app just booted, haven't checked Keychain yet
        case signedOut      // confirmed no session
        case signingIn
        case signedIn
    }

    @Published private(set) var authState: AuthState = .unknown
    @Published private(set) var authError: String?

    private init() {
        let url = (Bundle.main.object(forInfoDictionaryKey: "CONVEX_URL") as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? Self.deploymentUrl
        let provider = PasswordAuthProvider(deploymentURL: URL(string: url) ?? URL(string: Self.deploymentUrl)!)
        self.authProvider = provider
        self.client = ConvexClientWithAuth(deploymentUrl: url, authProvider: provider)
    }

    /// Call once on app launch. Restores cached session, or transitions to
    /// `.signedOut` so the UI shows SignInView.
    func bootstrap() async {
        let result = await client.loginFromCache()
        switch result {
        case .success:
            authState = .signedIn
            authError = nil
        case .failure:
            authState = .signedOut
        }
    }

    func signIn(email: String, password: String) async {
        await runPasswordFlow(email: email, password: password, flow: .signIn)
    }

    func signUp(name: String, email: String, password: String) async {
        await runPasswordFlow(email: email, password: password, flow: .signUp)
        if authState == .signedIn {
            // Stamp the email + name on the user's profile.
            try? await setProfileEmail(email)
            if !name.isEmpty {
                try? await setDisplayName(name)
            }
        }
    }

    private func runPasswordFlow(email: String, password: String, flow: PasswordAuthProvider.Flow) async {
        authState = .signingIn
        authError = nil
        authProvider.pendingCredentials = (email, password, flow)
        let result = await client.login()
        switch result {
        case .success:
            authState = .signedIn
            authError = nil
        case .failure(let err):
            authState = .signedOut
            authError = friendlyError(err)
        }
    }

    func signOut() async {
        await client.logout()
        authState = .signedOut
    }

    private func friendlyError(_ err: Error) -> String {
        let msg = err.localizedDescription
        if msg.contains("InvalidAccountId") { return "No account found for that email." }
        if msg.contains("InvalidSecret") || msg.contains("Invalid password") { return "Wrong password." }
        if msg.contains("AccountAlreadyExists") { return "An account already exists with that email." }
        return msg
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

    /// Triage one detected item - `state` ∈ "confirmed" | "rejected" | "pending".
    func reviewItem(id: String, itemIndex: Int, state: String) async throws {
        let args: [String: ConvexEncodable?] = [
            "id": id,
            "itemIndex": Double(itemIndex),
            "state": state,
        ]
        try await client.mutation("classifications:reviewItem", with: args)
    }

    func reviewAll(id: String, state: String) async throws {
        let args: [String: ConvexEncodable?] = ["id": id, "state": state]
        try await client.mutation("classifications:reviewAll", with: args)
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

    func subscribeCityPercentile() -> AnyPublisher<CityPercentileDoc?, ClientError> {
        client.subscribe(to: "metrics:cityPercentile", yielding: CityPercentileDoc?.self)
            .eraseToAnyPublisher()
    }

    func subscribeWeeklyInsight() -> AnyPublisher<WeeklyInsightDoc?, ClientError> {
        client.subscribe(to: "weeklyInsights:latest", yielding: WeeklyInsightDoc?.self)
            .eraseToAnyPublisher()
    }

    func refreshWeeklyInsight(force: Bool = false) async throws {
        let args: [String: ConvexEncodable?] = ["force": force]
        let _: WeeklyInsightDoc? = try await client.action("weeklyInsightsAction:refresh", with: args)
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

    func bestDropoff(classificationId: String) async throws -> DropoffResultDoc {
        let args: [String: ConvexEncodable?] = ["classificationId": classificationId]
        return try await client.action("dropoff:findBest", with: args)
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

    func setProfileEmail(_ email: String) async throws {
        let args: [String: ConvexEncodable?] = ["email": email]
        try await client.mutation("profiles:setEmail", with: args)
    }

    // MARK: - Friends

    func subscribeFriends() -> AnyPublisher<FriendsDoc, ClientError> {
        client.subscribe(to: "friends:list", yielding: FriendsDoc.self)
            .eraseToAnyPublisher()
    }

    func subscribeFriendCompare() -> AnyPublisher<FriendCompareDoc?, ClientError> {
        client.subscribe(to: "friends:compareStats", yielding: FriendCompareDoc?.self)
            .eraseToAnyPublisher()
    }

    func requestFriendByEmail(_ email: String) async throws -> FriendRequestResult {
        let args: [String: ConvexEncodable?] = ["email": email]
        return try await client.mutation("friends:requestByEmail", with: args)
    }

    func respondFriendRequest(friendshipId: String, accept: Bool) async throws {
        let args: [String: ConvexEncodable?] = ["friendshipId": friendshipId, "accept": accept]
        try await client.mutation("friends:respond", with: args)
    }

    func removeFriend(friendshipId: String) async throws {
        let args: [String: ConvexEncodable?] = ["friendshipId": friendshipId]
        try await client.mutation("friends:remove", with: args)
    }
}
