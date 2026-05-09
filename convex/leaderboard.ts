import { v } from "convex/values";
import { query, internalMutation } from "./_generated/server";

function periodKey(d: Date): string {
  // ISO week period: YYYY-Www
  const tmp = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  const day = tmp.getUTCDay() || 7;
  tmp.setUTCDate(tmp.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(tmp.getUTCFullYear(), 0, 1));
  const weekNo = Math.ceil(((tmp.getTime() - yearStart.getTime()) / 86400000 + 1) / 7);
  return `${tmp.getUTCFullYear()}-W${String(weekNo).padStart(2, "0")}`;
}

export const top = query({
  args: { period: v.optional(v.string()), limit: v.optional(v.number()) },
  handler: async (ctx, { period, limit }) => {
    const p = period ?? periodKey(new Date());
    const rows = await ctx.db
      .query("leaderboardEntries")
      .withIndex("by_period_kgRecycled", (q) => q.eq("period", p))
      .order("desc")
      .take(limit ?? 25);
    return await Promise.all(
      rows.map(async (r) => {
        const profile = await ctx.db
          .query("profiles")
          .withIndex("by_authUserId", (q) => q.eq("authUserId", r.authUserId))
          .unique();
        return {
          authUserId: r.authUserId,
          name: profile?.name,
          handle: profile?.handle,
          kgRecycled: r.kgRecycled,
          count: r.count,
          accuracy: r.accuracy,
        };
      }),
    );
  },
});

export const rebuildCurrentWeek = internalMutation({
  args: {},
  handler: async (ctx) => {
    const period = periodKey(new Date());
    const startOfWeek = startOfIsoWeek(new Date()).getTime();

    const rows = await ctx.db
      .query("classifications")
      .withIndex("by_status", (q) => q.eq("status", "done"))
      .collect();

    const aggregates = new Map<string, { kgRecycled: number; count: number; correct: number }>();
    for (const r of rows) {
      if (r.capturedAt < startOfWeek) continue;
      const key = String(r.authUserId);
      const a = aggregates.get(key) ?? { kgRecycled: 0, count: 0, correct: 0 };
      for (const item of r.items) {
        a.count += 1;
        if (item.decision === "recycle" || item.decision === "compost") {
          a.kgRecycled += item.co2Kg;
          a.correct += 1;
        }
      }
      aggregates.set(key, a);
    }

    const existing = await ctx.db
      .query("leaderboardEntries")
      .filter((q) => q.eq(q.field("period"), period))
      .collect();
    for (const e of existing) await ctx.db.delete(e._id);

    for (const [authUserId, agg] of aggregates) {
      await ctx.db.insert("leaderboardEntries", {
        authUserId: authUserId as any,
        period,
        kgRecycled: Number(agg.kgRecycled.toFixed(3)),
        count: agg.count,
        accuracy: agg.count === 0 ? 0 : agg.correct / agg.count,
      });
    }
  },
});

function startOfIsoWeek(d: Date): Date {
  const day = d.getUTCDay() || 7;
  const monday = new Date(d);
  monday.setUTCHours(0, 0, 0, 0);
  monday.setUTCDate(d.getUTCDate() - (day - 1));
  return monday;
}
