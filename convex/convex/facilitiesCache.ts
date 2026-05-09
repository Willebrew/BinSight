import { v } from "convex/values";
import { query, internalMutation } from "./_generated/server";

export const getCached = query({
  args: { geohash5: v.string() },
  handler: async (ctx, { geohash5 }) => {
    return await ctx.db
      .query("facilitiesCache")
      .withIndex("by_geohash5", (q) => q.eq("geohash5", geohash5))
      .unique();
  },
});

export const cachePut = internalMutation({
  args: { geohash5: v.string(), facilitiesJson: v.string() },
  handler: async (ctx, { geohash5, facilitiesJson }) => {
    const existing = await ctx.db
      .query("facilitiesCache")
      .withIndex("by_geohash5", (q) => q.eq("geohash5", geohash5))
      .unique();
    if (existing) {
      await ctx.db.patch(existing._id, { facilitiesJson, fetchedAt: Date.now() });
    } else {
      await ctx.db.insert("facilitiesCache", {
        geohash5,
        facilitiesJson,
        fetchedAt: Date.now(),
      });
    }
  },
});
