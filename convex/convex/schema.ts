import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import { authTables } from "@convex-dev/auth/server";

export const decisionValidator = v.union(
  v.literal("recycle"),
  v.literal("trash"),
  v.literal("compost"),
  v.literal("hazard"),
);

export const reviewStateValidator = v.union(
  v.literal("pending"),    // user has not swiped yet
  v.literal("confirmed"),  // user swiped right (counts toward metrics)
  v.literal("rejected"),   // user swiped left (does not count)
);

export const sourceTierValidator = v.union(
  v.literal("official"),       // .gov, EPA, municipal, manufacturer take-back
  v.literal("authoritative"),  // major news, peer-reviewed, established orgs
  v.literal("community"),      // forums, blogs
  v.literal("unknown"),
);

/** What a source backs up: material identification, the disposal rule, or both. */
export const sourceKindValidator = v.union(
  v.literal("material"),
  v.literal("rule"),
  v.literal("both"),
);

/**
 * One source supporting one or more item decisions in a classification.
 * `supportsItemIndices` lets us render per-item attribution without storing
 * the same URL multiple times when several items share a citation.
 */
export const sourceValidator = v.object({
  url: v.string(),
  title: v.string(),
  publisher: v.string(),
  snippet: v.string(),
  // Up to ~3 short verbatim quotes from the source page that justify
  // the items pointing to this source. Optional for back-compat.
  quotes: v.optional(v.array(v.string())),
  tier: sourceTierValidator,
  // Optional for back-compat with classifications written before the
  // material/rule split; new rows always set this.
  kind: v.optional(sourceKindValidator),
  isLocal: v.boolean(),                    // true when host matches user's city/state
  supportsItemIndices: v.array(v.number()),
});

/**
 * One detected waste item.
 *
 * `co2Kg` is the point-estimate (mid-range) for back-compat & quick reads.
 * `co2KgLow`/`co2KgHigh` carry the honest uncertainty band - we always
 * surface a range in the UI rather than pretending to be precise.
 *
 * `estimatedMassG` is the model's per-item mass guess (grams). When the
 * model can't tell, this falls back to a conservative default and
 * `massSource` records which it was so we can show "estimated from photo"
 * vs "default for material" in the methodology UI.
 */
export const itemValidator = v.object({
  label: v.string(),
  material: v.string(),
  decision: decisionValidator,
  confidence: v.number(),

  // Mass + impact
  estimatedMassG: v.number(),
  massSource: v.union(
    v.literal("model"),
    v.literal("default"),
    v.literal("verified"),
    v.literal("rag"),       // grounded against the RAG knowledge base
  ),
  co2Kg: v.number(),
  co2KgLow: v.number(),
  co2KgHigh: v.number(),
  co2Method: v.string(),

  disposalNotes: v.string(),

  // Optional bounding box from the vision model. Coords are normalized
  // [0,1] over the original image; missing means the model didn't or
  // couldn't localize this item.
  bbox: v.optional(v.object({
    x: v.number(),
    y: v.number(),
    w: v.number(),
    h: v.number(),
  })),

  // Source attribution
  sourceIndices: v.array(v.number()),

  // User triage
  reviewState: reviewStateValidator,
  reviewedAt: v.optional(v.number()),

  /**
   * RAG context: top-K reference items the knowledge base returned for
   * this item, plus which (if any) the model explicitly leaned on for
   * its mass estimate. Optional so legacy rows (pre-RAG) keep validating.
   */
  ragSimilar: v.optional(v.array(v.object({
    filename: v.string(),
    similarity: v.number(),
    massGrams: v.number(),
    materialWarm: v.string(),
    objectName: v.string(),
    imageUrl: v.optional(v.string()),
    used: v.boolean(),                  // model cited this reference
  }))),
  ragReasoning: v.optional(v.string()), // model's 1-2 sentence "why this mass"

  /**
   * Rich material breakdown from the fast pipeline (Henry's matestback).
   * One entry per non-zero EPA WARM v16 category. The card UI renders
   * these as a small table so the user can see exactly how mass was
   * partitioned across the object's materials.
   */
  materialBreakdown: v.optional(v.array(v.object({
    warm: v.string(),                  // WARM category name
    massGrams: v.number(),
    confidence: v.string(),            // "low" | "medium" | "high"
    co2Kg: v.number(),                 // kgCO2e saved if recycled
  }))),
  /** Short, user-facing item title from the estimator (e.g. "12 oz Aluminum Soda Can"). */
  itemTitle: v.optional(v.string()),
  /** 1-2 sentence plain-English description for the user. */
  itemDescription: v.optional(v.string()),
});

export const classificationStatusValidator = v.union(
  v.literal("pending"),
  v.literal("done"),
  v.literal("error"),
);

export default defineSchema({
  ...authTables,

  classifications: defineTable({
    userId: v.id("users"),
    storageId: v.id("_storage"),
    capturedAt: v.number(),
    lat: v.optional(v.number()),
    lng: v.optional(v.number()),
    geohash5: v.optional(v.string()),
    city: v.optional(v.string()),
    state: v.optional(v.string()),
    country: v.optional(v.string()),
    status: classificationStatusValidator,
    model: v.optional(v.string()),
    items: v.array(itemValidator),
    sources: v.array(sourceValidator),     // structured, ranked
    citations: v.array(v.string()),        // legacy flat URLs (kept for back-compat)
    localRules: v.optional(v.string()),
    verified: v.boolean(),
    errorMessage: v.optional(v.string()),
    /**
     * Append-only stream of human-readable agent stages emitted while
     * `status === "pending"`. The iOS UI subscribes to the row and
     * renders new entries with a per-line haptic so the user can feel
     * each step the agent takes ("Searching Denver rules…", etc.).
     */
    progressLog: v.optional(v.array(v.object({
      stage: v.string(),
      at: v.number(),
    }))),
  })
    .index("by_user_capturedAt", ["userId", "capturedAt"])
    .index("by_geohash5", ["geohash5"])
    .index("by_status", ["status"])
    .index("by_country", ["country"])
    .index("by_state", ["state"])
    .index("by_city", ["city"]),

  profiles: defineTable({
    userId: v.id("users"),
    displayName: v.optional(v.string()),
    email: v.optional(v.string()),
    appleSub: v.optional(v.string()),
    createdAt: v.number(),
  })
    .index("by_userId", ["userId"])
    .index("by_email", ["email"])
    .index("by_appleSub", ["appleSub"]),

  friendships: defineTable({
    aUserId: v.id("users"),
    bUserId: v.id("users"),
    status: v.union(v.literal("pending"), v.literal("accepted")),
    requestedBy: v.id("users"),
    createdAt: v.number(),
  })
    .index("by_pair", ["aUserId", "bUserId"])
    .index("by_aUserId", ["aUserId"])
    .index("by_bUserId", ["bUserId"]),

  localRulesCache: defineTable({
    geohash5: v.string(),
    rulesJson: v.string(),
    fetchedAt: v.number(),
  }).index("by_geohash5", ["geohash5"]),

  facilitiesCache: defineTable({
    geohash5: v.string(),
    facilitiesJson: v.string(),
    fetchedAt: v.number(),
  }).index("by_geohash5", ["geohash5"]),

  /**
   * Weekly Sonar-generated insight per user. Cached for 7 days; only the
   * current row per user is kept (we delete previous rows when refreshing).
   */
  weeklyInsights: defineTable({
    userId: v.id("users"),
    weekStart: v.number(),       // ms epoch of Monday 00:00 local UTC
    headline: v.string(),
    body: v.string(),
    sources: v.array(sourceValidator),
    generatedAt: v.number(),
  }).index("by_user", ["userId"]),

  /**
   * Reference catalog for RAG-grounded mass estimation. One row per
   * (image, WARM material) pair from Henry's `recycle_dataset_embedded.parquet`.
   * Embeddings come from Perplexity `pplx-embed-context-v1-0.6b` (1024-dim,
   * un-normalized int8 cast to float). Convex handles cosine similarity
   * internally for vector search.
   */
  ragReferenceItems: defineTable({
    // Source image
    imageFilename: v.string(),
    imageSha256: v.string(),
    imageStorageId: v.id("_storage"),

    // Reference data
    objectName: v.string(),
    objectDescription: v.string(),     // text the embedding was produced from
    materialWarm: v.string(),          // EPA WARM v16 category
    massGrams: v.float64(),
    materialConfidence: v.string(),    // "low" | "medium" | "high"
    co2SavedKg: v.float64(),
    warmFactorKgco2ePerKg: v.float64(),
    citationsJson: v.string(),
    materialReasoning: v.string(),
    overallConfidence: v.string(),
    researchSummary: v.string(),
    estimatedTotalMassGrams: v.float64(),
    unaccountedMassGramsNote: v.string(),

    // 1024-dim embedding from pplx-embed-context-v1-0.6b
    embedding: v.array(v.float64()),

    // Provenance
    model: v.string(),
    processedAtUtc: v.string(),
  })
    .index("by_filename", ["imageFilename"])
    .vectorIndex("by_embedding", {
      vectorField: "embedding",
      dimensions: 1024,
      filterFields: ["materialWarm"],
    }),
});
