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
    // Preserve user-side reviewState (same merge as writePartial). If
    // the user swiped during streaming, we never clobber that state
    // when committing the final snapshot.
    const row = await ctx.db.get(args.id);
    const stateByKey = new Map<string, { reviewState: string; reviewedAt?: number }>();
    for (const it of row?.items ?? []) {
      const key = `${it.label}|${it.material}|${it.decision}`;
      stateByKey.set(key, { reviewState: it.reviewState, reviewedAt: it.reviewedAt });
    }
    const merged = args.items.map((it) => {
      const key = `${it.label}|${it.material}|${it.decision}`;
      const prior = stateByKey.get(key);
      if (prior && prior.reviewState !== "pending") {
        return { ...it, reviewState: prior.reviewState as any, reviewedAt: prior.reviewedAt };
      }
      return it;
    });
    await ctx.db.patch(args.id, {
      status: "done",
      items: merged,
      sources: args.sources,
      localRules: args.localRules,
      citations: args.citations,
      model: args.model,
      verified: args.verified,
    });
  },
});

export const setVerified = internalMutation({
  args: { id: v.id("classifications"), verified: v.boolean() },
  handler: async (ctx, { id, verified }) => {
    await ctx.db.patch(id, { verified });
  },
});

/**
 * Write an in-progress streaming snapshot. Status stays `pending` so the
 * UI knows more is coming, but items + sources + localRules are filled
 * in as soon as we can parse them out of the partial response.
 */
export const writePartial = internalMutation({
  args: {
    id: v.id("classifications"),
    items: v.array(itemValidator),
    sources: v.array(sourceValidator),
    localRules: v.optional(v.string()),
    citations: v.array(v.string()),
    model: v.string(),
  },
  handler: async (ctx, args) => {
    const row = await ctx.db.get(args.id);
    if (!row || row.status !== "pending") return;
    // Preserve any swipe the user has already made during the
    // streaming phase. The classify pipeline may re-stream items after
    // RAG refinement with the original `reviewState: "pending"`, which
    // would otherwise clobber confirmed/rejected items the user has
    // already triaged. Merge by item label+material+decision identity.
    const existing = row.items ?? [];
    const stateByKey = new Map<string, { reviewState: string; reviewedAt?: number }>();
    for (const it of existing) {
      const key = `${it.label}|${it.material}|${it.decision}`;
      stateByKey.set(key, { reviewState: it.reviewState, reviewedAt: it.reviewedAt });
    }
    const merged = args.items.map((it) => {
      const key = `${it.label}|${it.material}|${it.decision}`;
      const prior = stateByKey.get(key);
      if (prior && prior.reviewState !== "pending") {
        return { ...it, reviewState: prior.reviewState as any, reviewedAt: prior.reviewedAt };
      }
      return it;
    });
    await ctx.db.patch(args.id, {
      items: merged,
      sources: args.sources,
      localRules: args.localRules,
      citations: args.citations,
      model: args.model,
    });
  },
});

/**
 * Append a single human-readable progress stage to the row's
 * `progressLog`. The iOS UI subscribes to the row, so each entry
 * lights up the streaming view + fires a haptic as it arrives.
 */
export const appendProgress = internalMutation({
  args: { id: v.id("classifications"), stage: v.string() },
  handler: async (ctx, { id, stage }) => {
    const row = await ctx.db.get(id);
    if (!row) return;
    const log = row.progressLog ?? [];
    // De-dupe consecutive identical stages so we don't spam the UI
    // when the same step gets logged twice.
    if (log.length > 0 && log[log.length - 1].stage === stage) return;
    log.push({ stage, at: Date.now() });
    await ctx.db.patch(id, { progressLog: log });
  },
});

/**
 * Patch a single item's bounding box. Used by the post-result phase
 * after the row has been committed: bbox detection runs in the
 * background and slides into the existing item via this mutation.
 */
export const setItemBbox = internalMutation({
  args: {
    id: v.id("classifications"),
    itemIndex: v.number(),
    bbox: v.object({
      x: v.number(),
      y: v.number(),
      w: v.number(),
      h: v.number(),
    }),
  },
  handler: async (ctx, { id, itemIndex, bbox }) => {
    const row = await ctx.db.get(id);
    if (!row) return;
    if (itemIndex < 0 || itemIndex >= row.items.length) return;
    const items = row.items.map((it, i) =>
      i === itemIndex ? { ...it, bbox } : it,
    );
    await ctx.db.patch(id, { items });
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
 * Wipe every classification + stored image for the calling user.
 * No args. Use from the iOS client or an admin context.
 */
export const wipeMine = mutation({
  args: { email: v.optional(v.string()) },
  handler: async (ctx, { email }) => {
    let userId = await auth.getUserId(ctx);
    if (!userId && email) {
      const u = await ctx.db
        .query("users")
        .withIndex("email", (q) => q.eq("email", email))
        .first();
      if (u) userId = u._id;
    }
    if (!userId) throw new Error("No user");
    const rows = await ctx.db
      .query("classifications")
      .withIndex("by_user_capturedAt", (q) => q.eq("userId", userId))
      .collect();
    for (const row of rows) {
      if (row.storageId) {
        try { await ctx.storage.delete(row.storageId); } catch { /* ignore */ }
      }
      await ctx.db.delete(row._id);
    }
    return { deleted: rows.length };
  },
});

/**
 * Triage one detected item - swipe right = `confirmed` (counts toward
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
 * Bulk triage helper - used by "Confirm all" / "Reject all" actions.
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
