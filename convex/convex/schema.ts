import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export const decisionValidator = v.union(
  v.literal("recycle"),
  v.literal("trash"),
  v.literal("compost"),
  v.literal("hazard"),
);

export const itemValidator = v.object({
  label: v.string(),
  material: v.string(),
  decision: decisionValidator,
  confidence: v.number(),
  co2Kg: v.number(),
  disposalNotes: v.string(),
});

export const classificationStatusValidator = v.union(
  v.literal("pending"),
  v.literal("done"),
  v.literal("error"),
);

// `clientId` is a UUID generated on the device on first launch and stored in
// the iOS Keychain. Treat it as an identity hint, not a secure identity —
// real auth lands in a follow-up phase.
export default defineSchema({
  classifications: defineTable({
    clientId: v.string(),
    storageId: v.id("_storage"),
    capturedAt: v.number(),
    lat: v.optional(v.number()),
    lng: v.optional(v.number()),
    geohash5: v.optional(v.string()),
    status: classificationStatusValidator,
    model: v.optional(v.string()),
    items: v.array(itemValidator),
    localRules: v.optional(v.string()),
    citations: v.array(v.string()),
    verified: v.boolean(),
    errorMessage: v.optional(v.string()),
  })
    .index("by_client_capturedAt", ["clientId", "capturedAt"])
    .index("by_geohash5", ["geohash5"])
    .index("by_status", ["status"]),

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
});
