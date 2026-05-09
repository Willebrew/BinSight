import Foundation

struct ProfileDoc: Codable, Identifiable, Hashable {
    var _id: String
    var authUserId: String
    var email: String?
    var name: String?
    var handle: String?
    var phoneHash: String?
    var privacy: Privacy
    var createdAt: Double
    var id: String { _id }

    struct Privacy: Codable, Hashable {
        var mapOptIn: Bool
        var contactsOptIn: Bool
    }
}

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
    var authUserId: String
    var storageId: String
    var thumbStorageId: String?
    var capturedAt: Double
    var lat: Double?
    var lng: Double?
    var geohash5: String?
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

struct FriendDoc: Codable, Identifiable, Hashable {
    var friendshipId: String
    var status: String
    var requestedBy: String
    var other: Other
    var id: String { friendshipId }
    struct Other: Codable, Hashable {
        var authUserId: String
        var name: String?
        var handle: String?
    }
}

struct FriendMatch: Codable, Hashable, Identifiable {
    var profileId: String
    var authUserId: String
    var name: String?
    var handle: String?
    var id: String { profileId }
}

struct LeaderboardRow: Codable, Hashable, Identifiable {
    var authUserId: String
    var name: String?
    var handle: String?
    var kgRecycled: Double
    var count: Int
    var accuracy: Double
    var id: String { authUserId }
}

struct MapCellDoc: Codable, Hashable, Identifiable {
    var geohash5: String
    var count: Int
    var recycled: Int
    var id: String { geohash5 }
}

struct FacilityDoc: Codable, Hashable, Identifiable {
    var title: String
    var url: String
    var snippet: String
    var id: String { url }
}
