import Foundation

struct ItemDoc: Codable, Hashable, Identifiable {
    var label: String
    var material: String
    var decision: String   // recycle | trash | compost | hazard
    var confidence: Double
    var co2Kg: Double
    var disposalNotes: String
    var id: String { "\(label)-\(material)-\(decision)" }
}

struct ClassificationDoc: Codable, Identifiable, Hashable {
    var _id: String
    var userId: String?
    var storageId: String
    var capturedAt: Double
    var lat: Double?
    var lng: Double?
    var geohash5: String?
    var city: String?
    var state: String?
    var country: String?
    var status: String     // pending | done | error
    var model: String?
    var items: [ItemDoc]
    var localRules: String?
    var citations: [String]
    var verified: Bool
    var errorMessage: String?
    var imageUrl: String?
    var id: String { _id }
}

struct MetricsDoc: Codable, Hashable {
    var totalScans: Int
    var totalRecycled: Int
    var totalTrashed: Int
    var totalCo2Kg: Double
    var accuracy: Double
    var byMaterial: [String: Int]
    var byDay: [String: DayCounts]

    struct DayCounts: Codable, Hashable {
        var recycled: Int
        var trashed: Int
    }
}

struct RegionCellDoc: Codable, Hashable, Identifiable {
    var key: String
    var label: String
    var count: Int
    var recycled: Int
    var id: String { key }
}

struct FacilityDoc: Codable, Hashable, Identifiable {
    var title: String
    var url: String
    var snippet: String
    var id: String { url }
}

struct ProfileDoc: Codable, Hashable {
    var userId: String
    var displayName: String?
    var email: String?
    var appleSub: String?
    var isAppleLinked: Bool
}

struct FriendsDoc: Codable, Hashable {
    var accepted: [FriendDoc]
    var incoming: [FriendDoc]
    var outgoing: [FriendDoc]
}

struct FriendDoc: Codable, Hashable, Identifiable {
    var friendshipId: String
    var status: String
    var requestedBy: String
    var otherUserId: String
    var otherDisplayName: String?
    var otherEmail: String?
    var id: String { friendshipId }
}

struct FriendRequestResult: Codable, Hashable {
    var status: String   // pending | accepted | self | no_such_user
    var friendshipId: String?
}
