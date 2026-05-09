import { v } from "convex/values";
import { query } from "./_generated/server";

/**
 * Anonymized aggregation of done classifications by 5-char geohash.
 */
export const aggregate = query({
  args: { sinceMs: v.optional(v.number()) },
  handler: async (ctx, { sinceMs }) => {
    const cutoff = sinceMs ?? 0;
    const rows = await ctx.db
      .query("classifications")
      .withIndex("by_status", (q) => q.eq("status", "done"))
      .collect();
    const cells = new Map<string, { count: number; recycled: number }>();
    for (const r of rows) {
      if (!r.geohash5) continue;
      if (r.capturedAt < cutoff) continue;
      const cell = cells.get(r.geohash5) ?? { count: 0, recycled: 0 };
      cell.count += 1;
      cell.recycled += r.items.filter(
        (i) => i.decision === "recycle" || i.decision === "compost",
      ).length;
      cells.set(r.geohash5, cell);
    }
    return Array.from(cells, ([geohash5, c]) => ({ geohash5, ...c }));
  },
});
