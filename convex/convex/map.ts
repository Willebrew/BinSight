import { v } from "convex/values";
import { query } from "./_generated/server";

/**
 * Anonymized aggregation of done classifications by administrative region.
 * Returns counts only — never per-user data, never exact coordinates.
 */
export const aggregate = query({
  args: { level: v.union(v.literal("country"), v.literal("state"), v.literal("city")) },
  handler: async (ctx, { level }) => {
    const rows = await ctx.db
      .query("classifications")
      .withIndex("by_status", (q) => q.eq("status", "done"))
      .collect();

    type Cell = { key: string; label: string; count: number; recycled: number };
    const cells = new Map<string, Cell>();
    for (const r of rows) {
      const key =
        level === "country" ? (r.country ?? "")
        : level === "state" ? [r.country, r.state].filter(Boolean).join(" / ")
        : [r.country, r.state, r.city].filter(Boolean).join(" / ");
      if (!key) continue;
      const label =
        level === "country" ? (r.country ?? "")
        : level === "state" ? (r.state ?? "")
        : (r.city ?? "");
      const cell = cells.get(key) ?? { key, label, count: 0, recycled: 0 };
      cell.count += 1;
      cell.recycled += r.items.filter(
        (i) => i.decision === "recycle" || i.decision === "compost",
      ).length;
      cells.set(key, cell);
    }
    return Array.from(cells.values()).sort((a, b) => b.count - a.count);
  },
});
