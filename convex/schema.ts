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

// Profile rows are 1:1 with `authTables.users` (the auth-managed users table)
// via `authUserId`. We keep profile fields here so they don't conflict with
// auth-provider-controlled columns.
export default defineSchema({
  ...authTables,

  profiles: defineTable({
    authUserId: v.id("users"),
    email: v.optional(v.string()),
    name: v.optional(v.string()),
    handle: v.optional(v.string()),
    phoneHash: v.optional(v.string()),
    privacy: v.object({
      mapOptIn: v.boolean(),
      contactsOptIn: v.boolean(),
    }),
    createdAt: v.number(),
  })
    .index("by_authUserId", ["authUserId"])
    .index("by_phoneHash", ["phoneHash"])
    .index("by_email", ["email"]),

  classifications: defineTable({
    authUserId: v.id("users"),
    storageId: v.id("_storage"),
    thumbStorageId: v.optional(v.id("_storage")),
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
    .index("by_authUser_capturedAt", ["authUserId", "capturedAt"])
    .index("by_geohash5", ["geohash5"])
    .index("by_status", ["status"]),

  friendships: defineTable({
    a: v.id("users"),
    b: v.id("users"),
    status: v.union(v.literal("pending"), v.literal("accepted")),
    requestedBy: v.id("users"),
    createdAt: v.number(),
  })
    .index("by_a_status", ["a", "status"])
    .index("by_b_status", ["b", "status"]),

  leaderboardEntries: defineTable({
    authUserId: v.id("users"),
    period: v.string(),
    kgRecycled: v.number(),
    count: v.number(),
    accuracy: v.number(),
  })
    .index("by_period_kgRecycled", ["period", "kgRecycled"])
    .index("by_user_period", ["authUserId", "period"]),

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
