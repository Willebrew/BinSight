import Foundation

// MARK: - Sources

/// One ranked source backing one or more item decisions.
struct SourceDoc: Codable, Hashable, Identifiable {
    var url: String
    var title: String
    var publisher: String
    var snippet: String
    var tier: String              // official | authoritative | community | unknown
    var isLocal: Bool
    var supportsItemIndices: [Int]
    var id: String { url }
}

// MARK: - Items

struct ItemDoc: Codable, Hashable, Identifiable {
    var label: String
    var material: String
    var decision: String          // recycle | trash | compost | hazard
    var confidence: Double
    var estimatedMassG: Double
    var massSource: String        // model | default
    var co2Kg: Double
    var co2KgLow: Double
    var co2KgHigh: Double
    var co2Method: String
    var disposalNotes: String
    var sourceIndices: [Int]
    var reviewState: String       // pending | confirmed | rejected
    var reviewedAt: Double?
    var id: String { "\(label)-\(material)-\(decision)" }

    // Tolerate legacy rows that predate the new fields. Once the migration
    // backfills everything we can drop these custom decode paths.
    private enum CodingKeys: String, CodingKey {
        case label, material, decision, confidence
        case estimatedMassG, massSource
        case co2Kg, co2KgLow, co2KgHigh, co2Method
        case disposalNotes, sourceIndices
        case reviewState, reviewedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        material = try c.decode(String.self, forKey: .material)
        decision = try c.decode(String.self, forKey: .decision)
        confidence = try c.decode(Double.self, forKey: .confidence)
        estimatedMassG = (try? c.decode(Double.self, forKey: .estimatedMassG)) ?? 0
        massSource = (try? c.decode(String.self, forKey: .massSource)) ?? "default"
        co2Kg = try c.decode(Double.self, forKey: .co2Kg)
        co2KgLow = (try? c.decode(Double.self, forKey: .co2KgLow)) ?? (co2Kg * 0.8)
        co2KgHigh = (try? c.decode(Double.self, forKey: .co2KgHigh)) ?? (co2Kg * 1.2)
        co2Method = (try? c.decode(String.self, forKey: .co2Method)) ?? ""
        disposalNotes = try c.decode(String.self, forKey: .disposalNotes)
        sourceIndices = (try? c.decode([Int].self, forKey: .sourceIndices)) ?? []
        reviewState = (try? c.decode(String.self, forKey: .reviewState)) ?? "confirmed"
        reviewedAt = try? c.decode(Double.self, forKey: .reviewedAt)
    }

    init(label: String, material: String, decision: String, confidence: Double,
         estimatedMassG: Double, massSource: String,
         co2Kg: Double, co2KgLow: Double, co2KgHigh: Double, co2Method: String,
         disposalNotes: String, sourceIndices: [Int],
         reviewState: String, reviewedAt: Double?) {
        self.label = label; self.material = material; self.decision = decision
        self.confidence = confidence
        self.estimatedMassG = estimatedMassG; self.massSource = massSource
        self.co2Kg = co2Kg; self.co2KgLow = co2KgLow; self.co2KgHigh = co2KgHigh
        self.co2Method = co2Method
        self.disposalNotes = disposalNotes; self.sourceIndices = sourceIndices
        self.reviewState = reviewState; self.reviewedAt = reviewedAt
    }
}

// MARK: - Classifications

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
    var status: String            // pending | done | error
    var model: String?
    var items: [ItemDoc]
    var sources: [SourceDoc]
    var localRules: String?
    var citations: [String]
    var verified: Bool
    var errorMessage: String?
    var imageUrl: String?
    var id: String { _id }

    /// True when at least one item still needs user review.
    var needsReview: Bool {
        items.contains { $0.reviewState == "pending" }
    }

    private enum CodingKeys: String, CodingKey {
        case _id, userId, storageId, capturedAt, lat, lng, geohash5
        case city, state, country, status, model, items, sources
        case localRules, citations, verified, errorMessage, imageUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(String.self, forKey: ._id)
        userId = try? c.decode(String.self, forKey: .userId)
        storageId = try c.decode(String.self, forKey: .storageId)
        capturedAt = try c.decode(Double.self, forKey: .capturedAt)
        lat = try? c.decode(Double.self, forKey: .lat)
        lng = try? c.decode(Double.self, forKey: .lng)
        geohash5 = try? c.decode(String.self, forKey: .geohash5)
        city = try? c.decode(String.self, forKey: .city)
        state = try? c.decode(String.self, forKey: .state)
        country = try? c.decode(String.self, forKey: .country)
        status = try c.decode(String.self, forKey: .status)
        model = try? c.decode(String.self, forKey: .model)
        items = (try? c.decode([ItemDoc].self, forKey: .items)) ?? []
        sources = (try? c.decode([SourceDoc].self, forKey: .sources)) ?? []
        localRules = try? c.decode(String.self, forKey: .localRules)
        citations = (try? c.decode([String].self, forKey: .citations)) ?? []
        verified = (try? c.decode(Bool.self, forKey: .verified)) ?? false
        errorMessage = try? c.decode(String.self, forKey: .errorMessage)
        imageUrl = try? c.decode(String.self, forKey: .imageUrl)
    }
}

// MARK: - Metrics

struct MetricsDoc: Codable, Hashable {
    var totalScans: Int
    var totalRecycled: Int
    var totalTrashed: Int
    var totalHazard: Int
    var totalCompost: Int
    var totalPendingItems: Int
    var totalCo2Kg: Double
    var totalCo2KgLow: Double
    var totalCo2KgHigh: Double
    var totalMassKg: Double
    var streakDays: Int
    var accuracy: Double
    var trustScore: Double
    var avgSourcesPerScan: Double
    var projectedMonthCo2Kg: Double
    var monthToDateCo2Kg: Double
    var byMaterial: [String: Int]
    var byMaterialMassG: [String: Double]
    var byMaterialCo2: [String: Double]
    var byDay: [String: DayCounts]
    var recentHazards: [HazardItem]
    var scanDays: [String]

    struct DayCounts: Codable, Hashable {
        var recycled: Int
        var trashed: Int
        var co2: Double
    }

    struct HazardItem: Codable, Hashable, Identifiable {
        var id: String
        var label: String
        var capturedAt: Double
        var city: String?
        var state: String?
    }
}

struct CityPercentileDoc: Codable, Hashable {
    var city: String
    var state: String?
    var rank: Int
    var total: Int
    var percentile: Int
    var myWeekCo2Kg: Double
    var topWeekCo2Kg: Double
}

struct WeeklyInsightDoc: Codable, Hashable {
    var _id: String?
    var userId: String?
    var weekStart: Double
    var headline: String
    var body: String
    var sources: [SourceDoc]
    var generatedAt: Double
}

// MARK: - Other docs (unchanged)

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
