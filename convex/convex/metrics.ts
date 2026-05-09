import { query } from "./_generated/server";
import { auth } from "./auth";

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Headline metrics for the Dashboard.
 *
 * Only items with `reviewState === "confirmed"` count toward CO2 + decision
 * tallies. Pending items are awaiting user swipe-review. Rejected items
 * never count.
 */
export const summary = query({
  args: {},
  handler: async (ctx) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) return null;

    const rows = await ctx.db
      .query("classifications")
      .withIndex("by_user_capturedAt", (q) => q.eq("userId", userId))
      .filter((q) => q.eq(q.field("status"), "done"))
      .collect();

    let totalCo2 = 0;
    let totalCo2Low = 0;
    let totalCo2High = 0;
    let totalRecycled = 0;
    let totalTrashed = 0;
    let totalHazard = 0;
    let totalCompost = 0;
    let totalMassG = 0;
    let totalPending = 0;

    const byMaterial: Record<string, number> = {};
    const byMaterialMassG: Record<string, number> = {};
    const byMaterialCo2: Record<string, number> = {};
    const byDay: Record<string, { recycled: number; trashed: number; co2: number }> = {};
    const scanDays = new Set<string>();

    let scansWithSources = 0;
    let scansWithOfficialSource = 0;
    let totalSources = 0;

    const recentHazards: Array<{
      id: string;
      label: string;
      capturedAt: number;
      city?: string;
      state?: string;
    }> = [];

    for (const r of rows) {
      const dayKey = isoDay(r.capturedAt);
      scanDays.add(dayKey);
      byDay[dayKey] ??= { recycled: 0, trashed: 0, co2: 0 };

      // Source-quality stats are per-classification, not per-item.
      const sources = r.sources ?? [];
      const officialCount = sources.filter((s) => s.tier === "official").length;
      if (sources.length > 0) {
        scansWithSources += 1;
        totalSources += sources.length;
        if (officialCount > 0) scansWithOfficialSource += 1;
      }

      for (const item of r.items) {
        if (item.reviewState === "pending") {
          totalPending += 1;
          continue;
        }
        if (item.reviewState !== "confirmed") continue;

        // Decision tallies
        if (item.decision === "recycle") totalRecycled += 1;
        else if (item.decision === "compost") totalCompost += 1;
        else if (item.decision === "hazard") totalHazard += 1;
        else totalTrashed += 1;

        const isDiverted = item.decision === "recycle" || item.decision === "compost";
        if (isDiverted) byDay[dayKey].recycled += 1;
        else byDay[dayKey].trashed += 1;

        // CO2 (legacy items may lack the low/high band — fall back to ±20%)
        const lo = item.co2KgLow ?? item.co2Kg * 0.8;
        const hi = item.co2KgHigh ?? item.co2Kg * 1.2;
        totalCo2 += item.co2Kg;
        totalCo2Low += lo;
        totalCo2High += hi;
        byDay[dayKey].co2 += item.co2Kg;

        // Material mix
        byMaterial[item.material] = (byMaterial[item.material] ?? 0) + 1;
        byMaterialMassG[item.material] =
          (byMaterialMassG[item.material] ?? 0) + (item.estimatedMassG ?? 0);
        byMaterialCo2[item.material] =
          (byMaterialCo2[item.material] ?? 0) + item.co2Kg;
        totalMassG += item.estimatedMassG ?? 0;

        // Hazard radar candidates (last 30 days)
        if (item.decision === "hazard" && Date.now() - r.capturedAt < 30 * DAY_MS) {
          recentHazards.push({
            id: r._id as unknown as string,
            label: item.label,
            capturedAt: r.capturedAt,
            city: r.city,
            state: r.state,
          });
        }
      }
    }

    // Streak: number of consecutive days ending today with at least one
    // *confirmed* scan.
    const streakDays = computeStreak(scanDays);

    // Pace projection: linearly extrapolate this month's CO2 trajectory.
    const now = new Date();
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).getTime();
    const daysIntoMonth = Math.max(1, Math.ceil((Date.now() - monthStart) / DAY_MS));
    const totalDaysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    const monthCo2 = rows.reduce((sum, r) => {
      if (r.capturedAt < monthStart) return sum;
      return (
        sum +
        r.items
          .filter((it) => it.reviewState === "confirmed")
          .reduce((s, it) => s + it.co2Kg, 0)
      );
    }, 0);
    const projectedMonthCo2 = (monthCo2 / daysIntoMonth) * totalDaysInMonth;

    const accuracyDenom = totalRecycled + totalTrashed + totalCompost + totalHazard;
    const trustScore =
      scansWithSources === 0
        ? 0
        : scansWithOfficialSource / scansWithSources;

    recentHazards.sort((a, b) => b.capturedAt - a.capturedAt);

    return {
      totalScans: rows.length,
      totalRecycled: totalRecycled + totalCompost,
      totalTrashed,
      totalHazard,
      totalCompost,
      totalPendingItems: totalPending,
      totalCo2Kg: round3(totalCo2),
      totalCo2KgLow: round3(totalCo2Low),
      totalCo2KgHigh: round3(totalCo2High),
      totalMassKg: round3(totalMassG / 1000),
      streakDays,
      accuracy: accuracyDenom === 0 ? 0 : (totalRecycled + totalCompost) / accuracyDenom,
      trustScore,                                  // 0..1, fraction of scans with ≥1 official source
      avgSourcesPerScan: scansWithSources === 0 ? 0 : totalSources / scansWithSources,
      projectedMonthCo2Kg: round3(projectedMonthCo2),
      monthToDateCo2Kg: round3(monthCo2),
      byMaterial,
      byMaterialMassG: roundMap(byMaterialMassG),
      byMaterialCo2: roundMap(byMaterialCo2, 3),
      byDay,
      recentHazards: recentHazards.slice(0, 5),
      scanDays: Array.from(scanDays).sort(),       // for the 30-day streak grid UI
    };
  },
});

/**
 * Where the user ranks in their own city this week, anonymously aggregated
 * across all users with the same `city` token.
 *
 * Returns null when there isn't enough data (fewer than 3 distinct users)
 * to make percentile claims meaningful.
 */
export const cityPercentile = query({
  args: {},
  handler: async (ctx) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) return null;

    const myProfile = await ctx.db
      .query("classifications")
      .withIndex("by_user_capturedAt", (q) => q.eq("userId", userId))
      .order("desc")
      .take(20);
    const myCity = myProfile.find((r) => r.city)?.city;
    const myState = myProfile.find((r) => r.state)?.state;
    if (!myCity) return null;

    const weekAgo = Date.now() - 7 * DAY_MS;

    const cityRows = await ctx.db
      .query("classifications")
      .withIndex("by_city", (q) => q.eq("city", myCity))
      .filter((q) => q.eq(q.field("status"), "done"))
      .collect();

    // Group by user, sum confirmed CO2 in last 7 days.
    const totals = new Map<string, number>();
    for (const r of cityRows) {
      if (r.capturedAt < weekAgo) continue;
      const sum = r.items
        .filter((it) => it.reviewState === "confirmed")
        .reduce((s, it) => s + it.co2Kg, 0);
      totals.set(r.userId, (totals.get(r.userId) ?? 0) + sum);
    }

    if (totals.size < 3) return null;

    const sorted = Array.from(totals.entries()).sort((a, b) => b[1] - a[1]);
    const myRank = sorted.findIndex(([uid]) => uid === userId);
    if (myRank < 0) return null;

    const percentile = Math.round(((sorted.length - myRank) / sorted.length) * 100);
    return {
      city: myCity,
      state: myState,
      rank: myRank + 1,
      total: sorted.length,
      percentile,                  // 100 = best, 1 = worst
      myWeekCo2Kg: round3(sorted[myRank][1]),
      topWeekCo2Kg: round3(sorted[0][1]),
    };
  },
});

function isoDay(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

function computeStreak(days: Set<string>): number {
  let streak = 0;
  const cursor = new Date();
  cursor.setUTCHours(0, 0, 0, 0);
  while (days.has(cursor.toISOString().slice(0, 10))) {
    streak += 1;
    cursor.setUTCDate(cursor.getUTCDate() - 1);
  }
  return streak;
}

function round3(n: number): number {
  return Number(n.toFixed(3));
}

function roundMap(map: Record<string, number>, decimals = 1): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [k, v] of Object.entries(map)) {
    out[k] = Number(v.toFixed(decimals));
  }
  return out;
}
