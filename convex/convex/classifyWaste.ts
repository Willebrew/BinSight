"use node";

import { v } from "convex/values";
import { action } from "./_generated/server";
import { internal, api } from "./_generated/api";
import { classifyImage, verifyTopItem, lookupItemMass, type RawSource } from "./sage";
import { estimateCo2 } from "./impactTable";

type StoredSource = {
  url: string;
  title: string;
  publisher: string;
  snippet: string;
  tier: "official" | "authoritative" | "community" | "unknown";
  kind: "material" | "rule" | "both";
  isLocal: boolean;
  supportsItemIndices: number[];
};

type StoredItem = {
  label: string;
  material: string;
  decision: "recycle" | "trash" | "compost" | "hazard";
  confidence: number;
  estimatedMassG: number;
  massSource: "model" | "default" | "verified";
  co2Kg: number;
  co2KgLow: number;
  co2KgHigh: number;
  co2Method: string;
  disposalNotes: string;
  sourceIndices: number[];
  reviewState: "pending" | "confirmed" | "rejected";
};

export const run = action({
  args: { id: v.id("classifications") },
  handler: async (ctx, { id }) => {
    const row = await ctx.runQuery(api.classifications.getById, { id });
    if (!row) throw new Error("Classification row not found or not yours");
    if (row.status !== "pending") return;

    try {
      const blob = await ctx.storage.get(row.storageId);
      if (!blob) throw new Error("Image blob missing from storage");
      const bytes = await blob.arrayBuffer();
      const contentType = (blob as any).type ?? "image/jpeg";

      const agent = await classifyImage(
        bytes,
        contentType,
        row.lat,
        row.lng,
        row.city ?? undefined,
        row.state ?? undefined,
      );

      // 1. Build the item list with mass + co2 ranges + review state.
      const items: StoredItem[] = agent.items.map((it) => {
        const massGramsHint =
          typeof it.estimatedMassG === "number" && it.estimatedMassG > 0
            ? it.estimatedMassG
            : undefined;
        const co2 = estimateCo2(it.material, it.decision, massGramsHint);
        return {
          label: it.label,
          material: it.material,
          decision: it.decision,
          confidence: clamp01(it.confidence),
          estimatedMassG: Number((co2.massKg * 1000).toFixed(2)),
          massSource: massGramsHint !== undefined ? "model" : "default",
          co2Kg: co2.co2Kg,
          co2KgLow: co2.co2KgLow,
          co2KgHigh: co2.co2KgHigh,
          co2Method: co2.method,
          disposalNotes: it.disposalNotes ?? "",
          // sourceIndices are remapped after dedup in step 2
          sourceIndices: Array.isArray(it.sourceIndices)
            ? it.sourceIndices.filter((n) => Number.isInteger(n) && n >= 0)
            : [],
          reviewState: "pending",
        };
      });

      // 2. Build, dedupe, rank, and classify the source array.
      //    `agent.citations` (top-level URLs from the model) are merged in
      //    case the structured `sources` array missed any.
      const merged = mergeSources(agent.sources, agent.citations);
      const remap = new Map<number, number>(); // oldIdx -> newIdx
      const ranked: StoredSource[] = merged.ranked.map((s, newIdx) => {
        const old = s.originalIdx;
        if (old !== undefined) remap.set(old, newIdx);
        const kind = s.kind === "material" || s.kind === "rule" || s.kind === "both"
          ? s.kind
          : "rule";
        return {
          url: s.url,
          title: s.title || hostOf(s.url),
          publisher: s.publisher || hostOf(s.url),
          snippet: s.snippet || "",
          tier: tierFor(s.url),
          kind,
          isLocal: isLocalSource(s.url, row.city ?? undefined, row.state ?? undefined),
          supportsItemIndices: [], // filled below
        };
      });

      // Re-map each item's sourceIndices into the ranked array, and record
      // which items each source supports.
      items.forEach((item, itemIdx) => {
        const remapped: number[] = [];
        for (const oldIdx of item.sourceIndices) {
          const newIdx = remap.get(oldIdx);
          if (newIdx !== undefined && !remapped.includes(newIdx)) {
            remapped.push(newIdx);
            if (!ranked[newIdx].supportsItemIndices.includes(itemIdx)) {
              ranked[newIdx].supportsItemIndices.push(itemIdx);
            }
          }
        }
        item.sourceIndices = remapped;
      });

      // 3. Stream the classification result to the client immediately -
      //    the UI is subscribed to this row, so writing now (before the
      //    verification step) lets users see items, sources, and rules
      //    a few seconds earlier than waiting for verify to finish.
      await ctx.runMutation(internal.classifications.writeResult, {
        id,
        items,
        sources: ranked,
        localRules: agent.localRules,
        citations: agent.citations,
        model: agent.model,
        verified: false,
      });

      // 4. In parallel: verify the decisions AND ground each item's mass
      //    in a real product-spec source. The mass lookup re-anchors the
      //    CO2 number so we don't ship a hallucinated weight; the
      //    verification call sets the verified badge. Both run
      //    concurrently so latency is max(verify, mass), not sum.
      if (items.length > 0) {
        const topN = Math.min(items.length, 3);
        const slice = agent.items.slice(0, topN);
        const [verifyResults, massResults] = await Promise.all([
          Promise.all(slice.map((it) => verifyTopItem(it).catch(() => false))),
          Promise.all(slice.map((it) => lookupItemMass(it).catch(() => undefined))),
        ]);
        const verified = verifyResults.some(Boolean);

        // Apply mass-grounding results: re-run estimateCo2 with the
        // verified mass, attach the source as kind="material", link from
        // the item via sourceIndices.
        let updated = false;
        massResults.forEach((mass, i) => {
          if (!mass) return;
          updated = true;
          const item = items[i];
          const co2 = estimateCo2(item.material, item.decision, mass.massG);
          item.estimatedMassG = mass.massG;
          item.massSource = "verified";
          item.co2Kg = co2.co2Kg;
          item.co2KgLow = co2.co2KgLow;
          item.co2KgHigh = co2.co2KgHigh;
          item.co2Method = `${co2.method} (mass via ${hostOf(mass.source.url)})`;
          // Add the mass source to the ranked list (or merge if already there).
          const existingIdx = ranked.findIndex((s) => s.url === mass.source.url);
          let newIdx: number;
          if (existingIdx >= 0) {
            newIdx = existingIdx;
            if (ranked[newIdx].kind === "rule") ranked[newIdx].kind = "both";
          } else {
            newIdx = ranked.length;
            ranked.push({
              url: mass.source.url,
              title: mass.source.title || hostOf(mass.source.url),
              publisher: mass.source.publisher || hostOf(mass.source.url),
              snippet: mass.source.snippet || "",
              tier: tierFor(mass.source.url),
              kind: "material",
              isLocal: isLocalSource(mass.source.url, row.city ?? undefined, row.state ?? undefined),
              supportsItemIndices: [i],
            });
          }
          if (!ranked[newIdx].supportsItemIndices.includes(i)) {
            ranked[newIdx].supportsItemIndices.push(i);
          }
          if (!item.sourceIndices.includes(newIdx)) {
            item.sourceIndices.push(newIdx);
          }
        });

        if (updated) {
          await ctx.runMutation(internal.classifications.writeResult, {
            id,
            items,
            sources: ranked,
            localRules: agent.localRules,
            citations: agent.citations,
            model: agent.model,
            verified,
          });
        } else {
          await ctx.runMutation(internal.classifications.setVerified, {
            id,
            verified,
          });
        }
      }
    } catch (e: any) {
      await ctx.runMutation(internal.classifications.writeError, {
        id,
        errorMessage: String(e?.message ?? e).slice(0, 500),
      });
      throw e;
    }
  },
});

// ---------- helpers ----------

function clamp01(n: number): number {
  if (!Number.isFinite(n)) return 0;
  if (n < 0) return 0;
  if (n > 1) return 1;
  return n;
}

function hostOf(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return url;
  }
}

const OFFICIAL_HOSTS = [
  // U.S. federal & state
  /(^|\.)epa\.gov$/i,
  /(^|\.)usda\.gov$/i,
  /(^|\.)energy\.gov$/i,
  /(^|\.)gov$/i,
  /(^|\.)mil$/i,
  // Common municipal recycling programs
  /(^|\.)sfenvironment\.org$/i,
  /(^|\.)recology\.com$/i,
  /(^|\.)nyc\.gov$/i,
  /(^|\.)lacity\.gov$/i,
  /(^|\.)seattle\.gov$/i,
  /(^|\.)portlandoregon\.gov$/i,
  /(^|\.)austintexas\.gov$/i,
  /(^|\.)dccc\.org$/i,
  /(^|\.)call2recycle\.org$/i, // manufacturer take-back
  /(^|\.)earth911\.com$/i,
];

const AUTHORITATIVE_HOSTS = [
  /(^|\.)nature\.com$/i,
  /(^|\.)science\.org$/i,
  /(^|\.)nationalgeographic\.com$/i,
  /(^|\.)nytimes\.com$/i,
  /(^|\.)wsj\.com$/i,
  /(^|\.)bbc\.com$/i,
  /(^|\.)bbc\.co\.uk$/i,
  /(^|\.)reuters\.com$/i,
  /(^|\.)apnews\.com$/i,
  /(^|\.)theguardian\.com$/i,
  /(^|\.)wikipedia\.org$/i,
  /\.edu$/i,
];

const COMMUNITY_HOSTS = [
  /(^|\.)reddit\.com$/i,
  /(^|\.)stackexchange\.com$/i,
  /(^|\.)quora\.com$/i,
  /(^|\.)medium\.com$/i,
  /(^|\.)substack\.com$/i,
];

function tierFor(url: string): "official" | "authoritative" | "community" | "unknown" {
  const host = hostOf(url);
  if (OFFICIAL_HOSTS.some((re) => re.test(host))) return "official";
  if (AUTHORITATIVE_HOSTS.some((re) => re.test(host))) return "authoritative";
  if (COMMUNITY_HOSTS.some((re) => re.test(host))) return "community";
  return "unknown";
}

function isLocalSource(url: string, city?: string, state?: string): boolean {
  if (!city && !state) return false;
  const host = hostOf(url).toLowerCase();
  const tokens = [city, state]
    .filter((s): s is string => !!s)
    .flatMap((s) => s.toLowerCase().replace(/[^a-z]/g, " ").split(/\s+/).filter(Boolean));
  return tokens.some((t) => t.length >= 3 && host.includes(t));
}

type MergedSource = {
  url: string;
  title: string;
  publisher: string;
  snippet: string;
  kind?: string;            // "material" | "rule" | "both" if the model tagged it
  originalIdx?: number;     // index in the agent's structured sources array (if any)
};

/**
 * Merge the structured `sources` from the model with any flat `citations`
 * URLs the model surfaced at the top level. De-dup by URL, then rank by
 * tier (official > authoritative > community > unknown), keeping local
 * sources above non-local within the same tier.
 */
function mergeSources(
  structured: RawSource[],
  flat: string[],
): { ranked: MergedSource[] } {
  const byUrl = new Map<string, MergedSource>();
  structured.forEach((s, idx) => {
    if (!s?.url) return;
    const url = s.url.trim();
    if (!url) return;
    const existing = byUrl.get(url);
    byUrl.set(url, {
      url,
      title: existing?.title || s.title || "",
      publisher: existing?.publisher || s.publisher || "",
      snippet: existing?.snippet || s.snippet || "",
      kind: existing?.kind ?? s.kind,
      originalIdx: existing?.originalIdx ?? idx,
    });
  });
  for (const url of flat ?? []) {
    if (!url) continue;
    const trimmed = url.trim();
    if (!trimmed || byUrl.has(trimmed)) continue;
    byUrl.set(trimmed, { url: trimmed, title: "", publisher: "", snippet: "" });
  }
  const arr = Array.from(byUrl.values());

  const tierRank: Record<string, number> = { official: 0, authoritative: 1, community: 2, unknown: 3 };
  arr.sort((a, b) => {
    const ta = tierRank[tierFor(a.url)] ?? 4;
    const tb = tierRank[tierFor(b.url)] ?? 4;
    if (ta !== tb) return ta - tb;
    return 0;
  });
  return { ranked: arr };
}
