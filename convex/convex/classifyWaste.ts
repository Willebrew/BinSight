"use node";

/**
 * Fast classification pipeline (Henry's `matestback`-backed).
 *
 * Flow per scan:
 *   1. Pull JPEG bytes from Convex storage.
 *   2. In parallel:
 *      a. POST to the matestback `/estimate` endpoint
 *         (image → caption → embed → RAG → WARM mass breakdown).
 *      b. Look up the user's city-specific disposal rules via
 *         the existing Perplexity-Search-backed `lookupLocalRules`.
 *   3. Map the response into our `classifications` row schema:
 *      one item with a rich material breakdown, a decision derived
 *      from the dominant WARM bucket, and the local-rule paragraph
 *      stored as the row's `localRules`.
 *
 * Target wall time: ~3-4s end-to-end. The matestback service does
 * the heavy lifting (caption + embed + RAG + structured estimate);
 * the local-rules fan-out runs in parallel so it doesn't add
 * additional latency to the visible result.
 */

import { v } from "convex/values";
import { action } from "./_generated/server";
import { internal, api } from "./_generated/api";
import {
  classifyImage,
  lookupLocalRules,
  type RawSource,
} from "./sage";
import {
  callFastEstimate,
  decisionForWarm,
  materialSlugForWarm,
  dominantWarm,
  co2SavedKgForWarm,
  detectBbox,
} from "./henrysPipeline";
import { estimateCo2 } from "./impactTable";

type StoredSource = {
  url: string;
  title: string;
  publisher: string;
  snippet: string;
  quotes?: string[];
  tier: "official" | "authoritative" | "community" | "unknown";
  kind: "material" | "rule" | "both";
  isLocal: boolean;
  supportsItemIndices: number[];
};

type StoredItemMaterial = {
  warm: string;
  massGrams: number;
  confidence: string;
  co2Kg: number;
};

type StoredItem = {
  label: string;
  material: string;
  decision: "recycle" | "trash" | "compost" | "hazard";
  confidence: number;
  estimatedMassG: number;
  massSource: "model" | "default" | "verified" | "rag";
  co2Kg: number;
  co2KgLow: number;
  co2KgHigh: number;
  co2Method: string;
  disposalNotes: string;
  bbox?: { x: number; y: number; w: number; h: number };
  sourceIndices: number[];
  reviewState: "pending" | "confirmed" | "rejected";
  materialBreakdown?: StoredItemMaterial[];
  itemTitle?: string;
  itemDescription?: string;
};

export const run = action({
  args: { id: v.id("classifications") },
  handler: async (ctx, { id }) => {
    const row = await ctx.runQuery(api.classifications.getById, { id });
    if (!row) throw new Error("Classification row not found or not yours");
    if (row.status !== "pending") return;

    const stage = async (s: string) => {
      try { await ctx.runMutation(internal.classifications.appendProgress, { id, stage: s }); }
      catch { /* best-effort */ }
    };

    try {
      await stage("Reading photo");
      const blob = await ctx.storage.get(row.storageId);
      if (!blob) throw new Error("Image blob missing from storage");
      const bytes = await blob.arrayBuffer();
      const contentType = (blob as any).type ?? "image/jpeg";

      // PHASE 1: fast pipeline (caption + embed + RAG + estimate).
      // Runs FIRST so the user sees the item card the moment it
      // returns. Local rules (slower, less critical) come after.
      //
      // If the fast backend is down (Henry working on it, network
      // hiccup, etc.), we fall through to the legacy Perplexity-Agent
      // vision pipeline as a backstop so the user still gets a result.
      await stage("Captioning the item");
      let fast: Awaited<ReturnType<typeof callFastEstimate>>;
      try {
        fast = await callFastEstimate(bytes, contentType);
      } catch (fastErr: any) {
        console.warn(
          "[classifyWaste] fast pipeline unavailable, falling back to legacy:",
          fastErr?.message ?? fastErr,
        );
        await stage("Fast backend unavailable — using legacy vision");
        await runLegacyFallback(ctx, id, row, bytes, contentType, stage);
        return;
      }
      const ms = fast.timings_ms;
      const detail = ms
        ? ` (caption ${Math.round(ms.caption ?? 0)}ms · predict ${Math.round(ms.predict ?? 0)}ms)`
        : "";
      await stage(`Knowledge base calibrated${detail}`);
      await stage(`Found ${fast.item_title || "item"}`);

      // Map Henry's WARM materials → one item with a breakdown.
      const dom = dominantWarm(fast.materials);
      const decision = dom ? decisionForWarm(dom.warm) : "trash";
      const materialSlug = dom ? materialSlugForWarm(dom.warm) : "mixed";
      const breakdown: StoredItemMaterial[] = Object.entries(fast.materials)
        .filter(([, e]) => (e?.mass_grams ?? 0) > 0)
        .map(([warm, e]) => ({
          warm,
          massGrams: Number((e.mass_grams ?? 0).toFixed(2)),
          confidence: String(e.confidence ?? "low"),
          co2Kg: Number(co2SavedKgForWarm(warm, e.mass_grams ?? 0).toFixed(4)),
        }))
        .sort((a, b) => b.massGrams - a.massGrams);

      const totalMassG = breakdown.reduce((s, m) => s + m.massGrams, 0);
      const totalCo2 = Number(fast.co2_saved_kg.toFixed(4));
      const itemConfidence = confidenceToNumber(
        dom ? fast.materials[dom.warm].confidence : "low",
      );

      const item: StoredItem = {
        label: fast.item_title || "Item",
        material: materialSlug,
        decision,
        confidence: itemConfidence,
        estimatedMassG: Number(totalMassG.toFixed(2)),
        massSource: "rag",
        co2Kg: totalCo2,
        co2KgLow: Number((totalCo2 * 0.85).toFixed(4)),
        co2KgHigh: Number((totalCo2 * 1.15).toFixed(4)),
        co2Method: "EPA WARM v16 (RAG-grounded via fast pipeline)",
        disposalNotes: disposalNotesFor(decision, fast.item_title || "this item"),
        sourceIndices: [],            // filled in once rules complete
        reviewState: "pending",
        materialBreakdown: breakdown,
        itemTitle: fast.item_title,
        itemDescription: fast.item_description,
      };

      // Stream the item now. Status stays `pending`, so the iOS
      // streaming view keeps the activity feed visible above the
      // newly-arrived card while the local-rules layer runs in the
      // background and source pills animate in.
      await ctx.runMutation(internal.classifications.writePartial, {
        id,
        items: [item],
        sources: [],
        localRules: undefined,
        citations: [],
        model: fast.timings_ms
          ? `fast(total=${Math.round(fast.timings_ms.total ?? 0)}ms)`
          : "fast",
      });

      // PHASE 2: local rules. Runs AFTER the card is on screen so
      // the user perceives the result faster. As stages stream, the
      // card stays visible and source pills slide in once the rules
      // search returns.
      const where = [row.city, row.state].filter(Boolean).join(", ");
      if (where) await stage(`Checking ${where} rules`);
      const rulesT0 = Date.now();
      console.log(`[classifyWaste] lookupLocalRules start: city=${row.city ?? ""} state=${row.state ?? ""} mats=${breakdown.map((b) => b.warm).slice(0, 3).join("|")}`);
      const rules = await lookupLocalRules(
        row.city ?? undefined,
        row.state ?? undefined,
        breakdown.map((b) => b.warm).slice(0, 3),
      );
      console.log(`[classifyWaste] lookupLocalRules done in ${Date.now() - rulesT0}ms: summary=${rules.summary ? rules.summary.length : 0}chars sources=${rules.sources.length}`);
      if (rules.summary) await stage("Local rules ready");

      const ranked: StoredSource[] = (rules.sources ?? []).map((s) => ({
        url: s.url,
        title: s.title || hostOf(s.url),
        publisher: s.publisher || hostOf(s.url),
        snippet: s.snippet || "",
        quotes: extractQuotes(s),
        tier: tierFor(s.url),
        kind: "rule" as const,
        isLocal: isLocalSource(s.url, row.city ?? undefined, row.state ?? undefined),
        supportsItemIndices: [0],
      }));
      const finalItem: StoredItem = {
        ...item,
        sourceIndices: ranked.map((_, i) => i),
      };

      await stage("Done");
      await ctx.runMutation(internal.classifications.writeResult, {
        id,
        items: [finalItem],
        sources: ranked,
        localRules: rules.summary || row.localRules || undefined,
        citations: ranked.map((s) => s.url),
        model: fast.timings_ms
          ? `fast(total=${Math.round(fast.timings_ms.total ?? 0)}ms)`
          : "fast",
        verified: !fast.needs_more_research,
      });

      // PHASE 3 (post-result polish): bounding-box detection. Runs
      // AFTER the row has flipped to `done` so the user already sees
      // their card in the swipe view; the bbox just slides in as a
      // photo overlay when the call returns. Failures are silent —
      // missing bbox is a non-event for the user.
      try {
        const dataUrl = `data:${contentType || "image/jpeg"};base64,${arrayBufferToBase64(bytes)}`;
        const bbox = await detectBbox(
          dataUrl,
          fast.item_title,
          fast.item_description,
          row.city ?? undefined,
          row.state ?? undefined,
        );
        if (bbox) {
          await ctx.runMutation(internal.classifications.setItemBbox, {
            id,
            itemIndex: 0,
            bbox,
          });
        }
      } catch (e: any) {
        console.warn("[classifyWaste] bbox detection failed:", e?.message ?? e);
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

/**
 * Backstop classification path. Runs only when Henry's fast backend
 * is unreachable. Uses the legacy Perplexity-Agent vision pipeline
 * (the same code that shipped before the fast-pipeline rewrite) and
 * commits a complete row in one shot so the user still gets a real
 * result. Slower (~6-10s) and shaped slightly differently — multi-
 * item, no `materialBreakdown`, bbox comes from the vision model
 * rather than a separate post-result call.
 */
async function runLegacyFallback(
  ctx: any,
  id: any,
  row: any,
  bytes: ArrayBuffer,
  contentType: string,
  stage: (s: string) => Promise<void>,
): Promise<void> {
  await stage("Looking at the photo");
  const agent = await classifyImage(
    bytes,
    contentType,
    row.lat,
    row.lng,
    row.city ?? undefined,
    row.state ?? undefined,
    undefined, // no streaming progress callback in fallback path
    stage,
  );

  // Map RawItem[] → StoredItem[]. Each item carries its own bbox
  // already (the vision model was prompted for it).
  // The non-streaming path of classifyImage doesn't run normalizeItem,
  // so model freeform decisions like "donate (Lions Recycle For Sight);
  // trash if broken" can leak through. Coerce to our 4-value enum here.
  const items: StoredItem[] = agent.items
    .filter((it) => typeof it?.label === "string" && typeof it?.decision === "string")
    .map((it) => {
      const massGramsHint =
        typeof it.estimatedMassG === "number" && it.estimatedMassG > 0
          ? it.estimatedMassG
          : undefined;
      const material = it.material ?? "unknown";
      const decision = coerceDecision(it.decision);
      const co2 = estimateCo2(
        material,
        decision,
        massGramsHint,
        massGramsHint !== undefined ? "model" : "default",
      );
      return {
        label: it.label,
        material,
        decision,
        confidence: clamp01(it.confidence ?? 0),
        estimatedMassG: Number((co2.massKg * 1000).toFixed(2)),
        massSource: massGramsHint !== undefined ? "model" : "default",
        co2Kg: co2.co2Kg,
        co2KgLow: co2.co2KgLow,
        co2KgHigh: co2.co2KgHigh,
        co2Method: co2.method,
        disposalNotes: it.disposalNotes ?? "",
        bbox: it.bbox,
        sourceIndices: Array.isArray(it.sourceIndices)
          ? it.sourceIndices.filter((n) => Number.isInteger(n) && n >= 0)
          : [],
        reviewState: "pending",
      };
    });

  // Map RawSource[] → StoredSource[]. The legacy agent emits both
  // material and rule sources together; preserve the kind it tagged.
  const ranked: StoredSource[] = agent.sources
    .filter((s) => !!s.url)
    .map((s, i) => ({
      url: s.url,
      title: s.title || hostOf(s.url),
      publisher: s.publisher || hostOf(s.url),
      snippet: s.snippet || "",
      quotes: extractQuotes(s),
      tier: tierFor(s.url),
      kind: (s.kind === "material" || s.kind === "rule" || s.kind === "both")
        ? s.kind
        : "rule",
      isLocal: isLocalSource(s.url, row.city ?? undefined, row.state ?? undefined),
      // Legacy agent items carry sourceIndices into the source array
      // but the array is order-preserved here, so index `i` is what
      // upstream items will reference.
      supportsItemIndices: items.flatMap((it, itemIdx) =>
        it.sourceIndices.includes(i) ? [itemIdx] : [],
      ),
    }));

  await stage("Done");
  await ctx.runMutation(internal.classifications.writeResult, {
    id,
    items,
    sources: ranked,
    localRules: agent.localRules || row.localRules || undefined,
    citations: agent.citations,
    model: `legacy(${agent.model})`,
    verified: true,
  });
}

/**
 * Coerce a freeform model decision string to our 4-value enum. Looks
 * for tokens like "recycle" / "compost" / "hazard" anywhere in the
 * string, defaulting to "trash" when nothing matches. Matches the
 * spirit of `normalizeItem` in sage.ts.
 */
function coerceDecision(
  raw: string | undefined,
): "recycle" | "trash" | "compost" | "hazard" {
  const d = (raw ?? "").toLowerCase();
  if (/\bhazard|haz waste|hhw|e-waste|battery|toxic|paint/.test(d)) return "hazard";
  if (/\bcompost|organic|food waste|yard waste/.test(d)) return "compost";
  if (/\brecycl|donate|reuse|drop ?off|take[- ]back/.test(d)) return "recycle";
  return "trash";
}

function clamp01(n: number): number {
  if (!Number.isFinite(n)) return 0;
  if (n < 0) return 0;
  if (n > 1) return 1;
  return n;
}

function arrayBufferToBase64(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf);
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

function disposalNotesFor(
  decision: "recycle" | "trash" | "compost" | "hazard",
  itemDisplay: string,
): string {
  switch (decision) {
    case "recycle":
      return `Place ${itemDisplay} in your curbside recycling bin. Empty and rinse if it held food or liquid.`;
    case "compost":
      return `Compost ${itemDisplay} or place it in your green-waste cart.`;
    case "hazard":
      return `Take ${itemDisplay} to a certified hazardous waste / e-waste drop-off — do NOT place it in the trash or recycling.`;
    case "trash":
    default:
      return `Place ${itemDisplay} in regular household trash unless your local rules say otherwise.`;
  }
}

function confidenceToNumber(level: string | undefined): number {
  switch ((level ?? "low").toLowerCase()) {
    case "high":   return 0.9;
    case "medium": return 0.65;
    case "low":
    default:       return 0.4;
  }
}

function extractQuotes(s: any): string[] {
  if (Array.isArray(s?.quotes)) {
    const out: string[] = [];
    for (const q of s.quotes) {
      const txt = String(q ?? "").trim();
      if (txt.length === 0) continue;
      out.push(txt.slice(0, 240));
      if (out.length >= 3) break;
    }
    if (out.length > 0) return out;
  }
  const snippet = String(s?.snippet ?? "").trim();
  if (snippet.length === 0) return [];
  const parts = snippet
    .split(/(?<=[.!?])\s+/)
    .map((p: string) => p.trim())
    .filter((p: string) => p.length > 0);
  return parts.slice(0, 3).map((p: string) => p.slice(0, 240));
}

function hostOf(url: string): string {
  try { return new URL(url).hostname.replace(/^www\./, ""); }
  catch { return url; }
}

const OFFICIAL_HOSTS = [
  /(^|\.)epa\.gov$/i,
  /(^|\.)usda\.gov$/i,
  /(^|\.)energy\.gov$/i,
  /(^|\.)gov$/i,
  /(^|\.)mil$/i,
  /(^|\.)sfenvironment\.org$/i,
  /(^|\.)recology\.com$/i,
  /(^|\.)nyc\.gov$/i,
  /(^|\.)denvergov\.org$/i,
  /(^|\.)bouldercolorado\.gov$/i,
  /(^|\.)call2recycle\.org$/i,
  /(^|\.)earth911\.com$/i,
];

const AUTHORITATIVE_HOSTS = [
  /(^|\.)wikipedia\.org$/i,
  /(^|\.)nature\.com$/i,
  /(^|\.)reuters\.com$/i,
  /\.edu$/i,
];

const COMMUNITY_HOSTS = [
  /(^|\.)reddit\.com$/i,
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
