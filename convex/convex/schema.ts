import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import { authTables } from "@convex-dev/auth/server";

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
    localRules: v.optional(v.string()),
    citations: v.array(v.string()),
    verified: v.boolean(),
    errorMessage: v.optional(v.string()),
  })
    .index("by_user_capturedAt", ["userId", "capturedAt"])
    .index("by_geohash5", ["geohash5"])
    .index("by_status", ["status"])
    .index("by_country", ["country"])
    .index("by_state", ["state"])
    .index("by_city", ["city"]),

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
