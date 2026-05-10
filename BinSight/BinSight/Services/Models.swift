import Foundation

// MARK: - Sources

/// One ranked source backing one or more item decisions.
struct SourceDoc: Codable, Hashable, Identifiable {
    var url: String
    var title: String
    var publisher: String
    var snippet: String
    var quotes: [String]?         // up to 3 verbatim quotes from the page
    var tier: String              // official | authoritative | community | unknown
    var kind: String?             // material | rule | both (optional for back-compat)
    var isLocal: Bool
    var supportsItemIndices: [Int]
    var id: String { url }
}

// MARK: - Items

struct BoundingBox: Codable, Hashable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

/// One row in the rich material breakdown returned by the fast pipeline.
/// We surface these as a small table inside the item card so the user
/// can see exactly how mass was partitioned across the object's
/// EPA WARM v16 categories.
struct ItemMaterial: Codable, Hashable, Identifiable {
    var warm: String
    var massGrams: Double
    var confidence: String     // low | medium | high
    var co2Kg: Double          // kgCO2e saved if recycled
    var id: String { warm }
}

/// One reference-catalog hit attached to an `ItemDoc`. Surface in the UI
/// as a tappable thumbnail with mass + similarity. `used == true` means
/// the model explicitly cited this reference when refining the mass.
struct RagSimilar: Codable, Hashable, Identifiable {
    var filename: String
    var similarity: Double
    var massGrams: Double
    var materialWarm: String
    var objectName: String
    var imageUrl: String?
    var used: Bool
    var id: String { filename }
}

struct ItemDoc: Codable, Hashable, Identifiable {
    var label: String
    var material: String
    var decision: String          // recycle | trash | compost | hazard
    var confidence: Double
    var estimatedMassG: Double
    var massSource: String        // model | default | verified | rag
    var co2Kg: Double
    var co2KgLow: Double
    var co2KgHigh: Double
    var co2Method: String
    var disposalNotes: String
    var bbox: BoundingBox?
    var sourceIndices: [Int]
    var reviewState: String       // pending | confirmed | rejected
    var reviewedAt: Double?
    /// RAG knowledge-base hits attached to this item. Each entry is one
    /// reference catalog photo; `used == true` means the model
    /// explicitly leaned on it for the mass estimate.
    var ragSimilar: [RagSimilar]?
    var ragReasoning: String?
    /// Rich WARM-category breakdown from the fast pipeline. Each entry is
    /// a non-zero category with grams + per-row CO₂ savings; sorted
    /// heaviest-first server-side.
    var materialBreakdown: [ItemMaterial]?
    /// Short product-style title from the estimator (e.g.
    /// "Corrugated Cardboard Shipping Box"). Optional; falls back to `label`.
    var itemTitle: String?
    /// 1-2 sentence plain-English item description from the estimator.
    /// Distinct from `disposalNotes` (which is decision-specific guidance).
    var itemDescription: String?
    var id: String { "\(label)-\(material)-\(decision)" }

    private enum CodingKeys: String, CodingKey {
        case label, material, decision, confidence
        case estimatedMassG, massSource
        case co2Kg, co2KgLow, co2KgHigh, co2Method
        case disposalNotes, bbox, sourceIndices
        case reviewState, reviewedAt
        case ragSimilar, ragReasoning
        case materialBreakdown, itemTitle, itemDescription
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
        bbox = try? c.decode(BoundingBox.self, forKey: .bbox)
        sourceIndices = (try? c.decode([Int].self, forKey: .sourceIndices)) ?? []
        reviewState = (try? c.decode(String.self, forKey: .reviewState)) ?? "confirmed"
        reviewedAt = try? c.decode(Double.self, forKey: .reviewedAt)
        ragSimilar = try? c.decode([RagSimilar].self, forKey: .ragSimilar)
        ragReasoning = try? c.decode(String.self, forKey: .ragReasoning)
        materialBreakdown = try? c.decode([ItemMaterial].self, forKey: .materialBreakdown)
        itemTitle = try? c.decode(String.self, forKey: .itemTitle)
        itemDescription = try? c.decode(String.self, forKey: .itemDescription)
    }

    init(label: String, material: String, decision: String, confidence: Double,
         estimatedMassG: Double, massSource: String,
         co2Kg: Double, co2KgLow: Double, co2KgHigh: Double, co2Method: String,
         disposalNotes: String, bbox: BoundingBox? = nil, sourceIndices: [Int],
         reviewState: String, reviewedAt: Double?) {
        self.label = label; self.material = material; self.decision = decision
        self.confidence = confidence
        self.estimatedMassG = estimatedMassG; self.massSource = massSource
        self.co2Kg = co2Kg; self.co2KgLow = co2KgLow; self.co2KgHigh = co2KgHigh
        self.co2Method = co2Method
        self.disposalNotes = disposalNotes; self.bbox = bbox
        self.sourceIndices = sourceIndices
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
    var progressLog: [ProgressEntry]?

    struct ProgressEntry: Codable, Hashable, Identifiable {
        var stage: String
        var at: Double
        var id: String { "\(at)-\(stage)" }
    }
    var id: String { _id }

    /// True when at least one item still needs user review.
    var needsReview: Bool {
        items.contains { $0.reviewState == "pending" }
    }

    private enum CodingKeys: String, CodingKey {
        case _id, userId, storageId, capturedAt, lat, lng, geohash5
        case city, state, country, status, model, items, sources
        case localRules, citations, verified, errorMessage, imageUrl, progressLog
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
        progressLog = try? c.decode([ProgressEntry].self, forKey: .progressLog)
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
    // Legacy aliases (kept for back-compat with older UI bits).
    var count: Int
    var recycled: Int
    // Richer stats added 2026-05-10.
    var scans: Int?
    var itemsTotal: Int?
    var itemsRecycled: Int?
    var itemsTrashed: Int?
    var itemsHazard: Int?
    var co2Kg: Double?
    var uniqueUsers: Int?
    var activeDays: Int?
    var lastActivity: Double?
    var diversionRate: Double?
    var hazardRate: Double?
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

struct DropoffResultDoc: Codable, Hashable {
    var places: [Place]
    var query: String

    struct Place: Codable, Hashable, Identifiable {
        var name: String
        var address: String
        var notes: String
        var acceptsThisItem: String
        var hours: String
        var phone: String
        var sourceUrl: String
        var id: String { "\(name)|\(address)" }
    }
}

struct FriendCompareDoc: Codable, Hashable {
    var me: FriendCompareStats
    var friends: [FriendCompareStats]
}

struct FriendCompareStats: Codable, Hashable, Identifiable {
    var userId: String
    var totalScans: Int
    var totalRecycled: Int
    var totalTrashed: Int
    var totalCo2Kg: Double
    var streakDays: Int
    var displayName: String?
    var email: String?
    var id: String { userId }
}

struct FriendRequestResult: Codable, Hashable {
    var status: String   // pending | accepted | self | no_such_user
    var friendshipId: String?
}
