import { v } from "convex/values";
import { mutation, query, internalMutation } from "./_generated/server";
import { auth } from "./auth";
import { itemValidator } from "./schema";

export const create = mutation({
  args: {
    storageId: v.id("_storage"),
    lat: v.optional(v.number()),
    lng: v.optional(v.number()),
    geohash5: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const authUserId = await auth.getUserId(ctx);
    if (!authUserId) throw new Error("Not authenticated");
    return await ctx.db.insert("classifications", {
      authUserId,
      storageId: args.storageId,
      capturedAt: Date.now(),
      lat: args.lat,
      lng: args.lng,
      geohash5: args.geohash5,
      status: "pending",
      items: [],
      citations: [],
      verified: false,
    });
  },
});

export const writeResult = internalMutation({
  args: {
    id: v.id("classifications"),
    items: v.array(itemValidator),
    localRules: v.optional(v.string()),
    citations: v.array(v.string()),
    model: v.string(),
    verified: v.boolean(),
  },
  handler: async (ctx, args) => {
    await ctx.db.patch(args.id, {
      status: "done",
      items: args.items,
      localRules: args.localRules,
      citations: args.citations,
      model: args.model,
      verified: args.verified,
    });
  },
});

export const writeError = internalMutation({
  args: { id: v.id("classifications"), errorMessage: v.string() },
  handler: async (ctx, { id, errorMessage }) => {
    await ctx.db.patch(id, { status: "error", errorMessage });
  },
});

export const getById = query({
  args: { id: v.id("classifications") },
  handler: async (ctx, { id }) => {
    const row = await ctx.db.get(id);
    if (!row) return null;
    const authUserId = await auth.getUserId(ctx);
    if (row.authUserId !== authUserId) return null;
    const imageUrl = await ctx.storage.getUrl(row.storageId);
    return { ...row, imageUrl };
  },
});

export const listForUser = query({
  args: { limit: v.optional(v.number()) },
  handler: async (ctx, { limit }) => {
    const authUserId = await auth.getUserId(ctx);
    if (!authUserId) return [];
    const rows = await ctx.db
      .query("classifications")
      .withIndex("by_authUser_capturedAt", (q) => q.eq("authUserId", authUserId))
      .order("desc")
      .take(limit ?? 50);
    return await Promise.all(
      rows.map(async (r) => ({ ...r, imageUrl: await ctx.storage.getUrl(r.storageId) })),
    );
  },
});
