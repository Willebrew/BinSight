import { v } from "convex/values";
import { mutation, query, internalMutation } from "./_generated/server";
import { auth } from "./auth";
import { itemValidator, sourceValidator, reviewStateValidator } from "./schema";

export const create = mutation({
  args: {
    storageId: v.id("_storage"),
    lat: v.optional(v.number()),
    lng: v.optional(v.number()),
    geohash5: v.optional(v.string()),
    city: v.optional(v.string()),
    state: v.optional(v.string()),
    country: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) throw new Error("Not authenticated");
    return await ctx.db.insert("classifications", {
      userId,
      storageId: args.storageId,
      capturedAt: Date.now(),
      lat: args.lat,
      lng: args.lng,
      geohash5: args.geohash5,
      city: args.city,
      state: args.state,
      country: args.country,
      status: "pending",
      items: [],
      sources: [],
      citations: [],
      verified: false,
    });
  },
});

export const writeResult = internalMutation({
  args: {
    id: v.id("classifications"),
    items: v.array(itemValidator),
    sources: v.array(sourceValidator),
    localRules: v.optional(v.string()),
    citations: v.array(v.string()),
    model: v.string(),
    verified: v.boolean(),
  },
  handler: async (ctx, args) => {
    await ctx.db.patch(args.id, {
      status: "done",
      items: args.items,
      sources: args.sources,
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
    const userId = await auth.getUserId(ctx);
    const row = await ctx.db.get(id);
    if (!row) return null;
    if (row.userId !== userId) return null;
    const imageUrl = await ctx.storage.getUrl(row.storageId);
    return { ...row, imageUrl };
  },
});

export const listForUser = query({
  args: {},
  handler: async (ctx) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) return [];
    const rows = await ctx.db
      .query("classifications")
      .withIndex("by_user_capturedAt", (q) => q.eq("userId", userId))
      .order("desc")
      .take(50);
    return await Promise.all(
      rows.map(async (r) => ({ ...r, imageUrl: await ctx.storage.getUrl(r.storageId) })),
    );
  },
});

export const remove = mutation({
  args: { id: v.id("classifications") },
  handler: async (ctx, { id }) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) throw new Error("Not authenticated");
    const row = await ctx.db.get(id);
    if (!row || row.userId !== userId) return;
    if (row.storageId) {
      await ctx.storage.delete(row.storageId);
    }
    await ctx.db.delete(id);
  },
});

/**
 * Triage one detected item — swipe right = `confirmed` (counts toward
 * metrics), swipe left = `rejected` (does not count). `pending` items are
 * intentionally excluded from CO2 / scan stats so the dashboard reflects
 * only what the user has personally validated.
 */
export const reviewItem = mutation({
  args: {
    id: v.id("classifications"),
    itemIndex: v.number(),
    state: reviewStateValidator,
  },
  handler: async (ctx, { id, itemIndex, state }) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) throw new Error("Not authenticated");
    const row = await ctx.db.get(id);
    if (!row || row.userId !== userId) throw new Error("Not found");
    if (itemIndex < 0 || itemIndex >= row.items.length) {
      throw new Error("itemIndex out of range");
    }
    const next = row.items.map((it, i) =>
      i === itemIndex ? { ...it, reviewState: state, reviewedAt: Date.now() } : it,
    );
    await ctx.db.patch(id, { items: next });
  },
});

/**
 * Bulk triage helper — used by "Confirm all" / "Reject all" actions.
 */
export const reviewAll = mutation({
  args: {
    id: v.id("classifications"),
    state: reviewStateValidator,
  },
  handler: async (ctx, { id, state }) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) throw new Error("Not authenticated");
    const row = await ctx.db.get(id);
    if (!row || row.userId !== userId) throw new Error("Not found");
    const now = Date.now();
    const next = row.items.map((it) =>
      it.reviewState === "pending" ? { ...it, reviewState: state, reviewedAt: now } : it,
    );
    await ctx.db.patch(id, { items: next });
  },
});
