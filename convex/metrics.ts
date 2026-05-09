import { query } from "./_generated/server";
import { auth } from "./auth";

export const summary = query({
  args: {},
  handler: async (ctx) => {
    const authUserId = await auth.getUserId(ctx);
    if (!authUserId) return null;

    const rows = await ctx.db
      .query("classifications")
      .withIndex("by_authUser_capturedAt", (q) => q.eq("authUserId", authUserId))
      .filter((q) => q.eq(q.field("status"), "done"))
      .collect();

    let totalCo2 = 0;
    let totalRecycled = 0;
    let totalTrashed = 0;
    const byMaterial: Record<string, number> = {};
    const byDay: Record<string, { recycled: number; trashed: number }> = {};

    for (const r of rows) {
      const dayKey = new Date(r.capturedAt).toISOString().slice(0, 10);
      byDay[dayKey] ??= { recycled: 0, trashed: 0 };
      for (const item of r.items) {
        totalCo2 += item.co2Kg;
        byMaterial[item.material] = (byMaterial[item.material] ?? 0) + 1;
        if (item.decision === "recycle" || item.decision === "compost") {
          totalRecycled += 1;
          byDay[dayKey].recycled += 1;
        } else {
          totalTrashed += 1;
          byDay[dayKey].trashed += 1;
        }
      }
    }

    const accuracy =
      totalRecycled + totalTrashed === 0
        ? 0
        : totalRecycled / (totalRecycled + totalTrashed);

    return {
      totalScans: rows.length,
      totalRecycled,
      totalTrashed,
      totalCo2Kg: Number(totalCo2.toFixed(3)),
      accuracy,
      byMaterial,
      byDay,
    };
  },
});
