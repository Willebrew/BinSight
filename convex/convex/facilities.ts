"use node";

import { v } from "convex/values";
import { action } from "./_generated/server";
import { api, internal } from "./_generated/api";

const SEARCH_URL = "https://api.perplexity.ai/search";
const ONE_DAY_MS = 24 * 60 * 60 * 1000;

export const nearby = action({
  args: { lat: v.number(), lng: v.number(), geohash5: v.string() },
  handler: async (ctx, { lat, lng, geohash5 }): Promise<Array<{ title: string; url: string; snippet: string }>> => {
    const cached = await ctx.runQuery(api.facilitiesCache.getCached, { geohash5 });
    if (cached && Date.now() - cached.fetchedAt < ONE_DAY_MS) {
      return JSON.parse(cached.facilitiesJson);
    }
    const apiKey = process.env.PERPLEXITY_API_KEY;
    if (!apiKey) throw new Error("PERPLEXITY_API_KEY not set");
    const res = await fetch(SEARCH_URL, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        query: `Recycling drop-off facilities and centers near ${lat.toFixed(3)}, ${lng.toFixed(3)} with addresses and accepted materials`,
        max_results: 8,
      }),
    });
    if (!res.ok) throw new Error(`Search API ${res.status}`);
    const json: any = await res.json();
    const results = (json.results ?? []).map((r: any) => ({
      title: r.title,
      url: r.url,
      snippet: r.snippet ?? r.text ?? "",
    }));
    await ctx.runMutation(internal.facilitiesCache.cachePut, {
      geohash5,
      facilitiesJson: JSON.stringify(results),
    });
    return results;
  },
});
