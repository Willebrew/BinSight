"use node";

import { v } from "convex/values";
import { action } from "./_generated/server";
import { internal, api } from "./_generated/api";
import { generateWeeklyInsight } from "./sage";

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * Action: generate (or refresh) the weekly insight for the calling user.
 * Cached for 7 days; idempotent within that window.
 */
export const refresh = action({
  args: { force: v.optional(v.boolean()) },
  handler: async (ctx, { force }): Promise<unknown> => {
    const existing: any = await ctx.runQuery(api.weeklyInsights.latest, {});
    if (existing && !force && Date.now() - existing.generatedAt < WEEK_MS) {
      return existing;
    }

    const summary: any = await ctx.runQuery(api.metrics.summary, {});
    if (!summary) return null;

    const topMaterials = Object.entries(summary.byMaterial as Record<string, number>)
      .sort(([, a], [, b]) => (b as number) - (a as number))
      .slice(0, 4)
      .map(([material, count]) => ({ material, count: count as number }));

    const recent: any = await ctx.runQuery(api.classifications.listForUser, {});
    const here = recent?.find((r: any) => r.city);

    // The action runs as the user (auth context flows through), but we need
    // the user id explicitly to write the insight. Pull it from any recent
    // classification; if there are none, bail.
    if (!recent || recent.length === 0) return null;
    const userId = recent[0].userId;

    const insight = await generateWeeklyInsight({
      city: here?.city,
      state: here?.state,
      recyclableCount: summary.totalRecycled,
      trashedCount: summary.totalTrashed,
      topMaterials,
    });

    const enrichedSources = (insight.sources ?? []).map((s) => ({
      url: s.url,
      title: s.title ?? "",
      publisher: s.publisher ?? "",
      snippet: s.snippet ?? "",
      tier: tierFor(s.url),
      isLocal: false,
      supportsItemIndices: [] as number[],
    }));

    await ctx.runMutation(internal.weeklyInsights.write, {
      userId,
      headline: insight.headline,
      body: insight.body,
      sources: enrichedSources,
    });

    return await ctx.runQuery(api.weeklyInsights.latest, {});
  },
});

const OFFICIAL = [/(^|\.)gov$/i, /(^|\.)mil$/i, /(^|\.)epa\.gov$/i, /(^|\.)recology\.com$/i];
const AUTHORITATIVE = [/\.edu$/i, /(^|\.)nature\.com$/i, /(^|\.)science\.org$/i];
const COMMUNITY = [/(^|\.)reddit\.com$/i, /(^|\.)medium\.com$/i];

function tierFor(url: string): "official" | "authoritative" | "community" | "unknown" {
  let host = url;
  try { host = new URL(url).hostname.replace(/^www\./, ""); } catch { /* */ }
  if (OFFICIAL.some((re) => re.test(host))) return "official";
  if (AUTHORITATIVE.some((re) => re.test(host))) return "authoritative";
  if (COMMUNITY.some((re) => re.test(host))) return "community";
  return "unknown";
}
