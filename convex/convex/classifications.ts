import { v } from "convex/values";
import { mutation, query, internalMutation } from "./_generated/server";
import { itemValidator } from "./schema";

export const create = mutation({
  args: {
    clientId: v.string(),
    storageId: v.id("_storage"),
    lat: v.optional(v.number()),
    lng: v.optional(v.number()),
    geohash5: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    return await ctx.db.insert("classifications", {
      clientId: args.clientId,
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
  args: { id: v.id("classifications"), clientId: v.string() },
  handler: async (ctx, { id, clientId }) => {
    const row = await ctx.db.get(id);
    if (!row) return null;
    if (row.clientId !== clientId) return null;
    const imageUrl = await ctx.storage.getUrl(row.storageId);
    return { ...row, imageUrl };
  },
});

export const listForClient = query({
  args: { clientId: v.string(), limit: v.optional(v.number()) },
  handler: async (ctx, { clientId, limit }) => {
    const rows = await ctx.db
      .query("classifications")
      .withIndex("by_client_capturedAt", (q) => q.eq("clientId", clientId))
      .order("desc")
      .take(limit ?? 50);
    return await Promise.all(
      rows.map(async (r) => ({ ...r, imageUrl: await ctx.storage.getUrl(r.storageId) })),
    );
  },
});
