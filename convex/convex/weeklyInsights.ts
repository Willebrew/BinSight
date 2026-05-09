import { v } from "convex/values";
import { query, internalMutation } from "./_generated/server";
import { auth } from "./auth";
import { sourceValidator } from "./schema";

/**
 * Public query: latest insight for the signed-in user. Subscribed by the
 * Dashboard. Returns null if no insight has ever been generated.
 */
export const latest = query({
  args: {},
  handler: async (ctx) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) return null;
    const row = await ctx.db
      .query("weeklyInsights")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .order("desc")
      .first();
    return row;
  },
});

export const write = internalMutation({
  args: {
    userId: v.id("users"),
    headline: v.string(),
    body: v.string(),
    sources: v.array(sourceValidator),
  },
  handler: async (ctx, args) => {
    // Only keep the latest row per user.
    const old = await ctx.db
      .query("weeklyInsights")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .collect();
    for (const r of old) await ctx.db.delete(r._id);

    const now = new Date();
    const monday = new Date(now);
    const day = (monday.getUTCDay() + 6) % 7; // 0 = Mon
    monday.setUTCDate(monday.getUTCDate() - day);
    monday.setUTCHours(0, 0, 0, 0);

    await ctx.db.insert("weeklyInsights", {
      userId: args.userId,
      weekStart: monday.getTime(),
      headline: args.headline,
      body: args.body,
      sources: args.sources,
      generatedAt: Date.now(),
    });
  },
});
