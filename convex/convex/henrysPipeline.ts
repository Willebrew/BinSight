"use node";

/**
 * Thin async wrapper around Henry's `matestback` REST endpoint
 * (image → WARM material breakdown in ~3-4s).
 *
 * The hosted instance is HTTP-only (no TLS), so iOS would need an ATS
 * exception to call it directly. We proxy through Convex instead so
 * the iOS app keeps talking to a single HTTPS API surface (Convex)
 * and we get auth gating + a place to fan out to the local-rules
 * lookup in parallel.
 *
 * Spec: see `/Users/willkillebrew/Desktop/HackathonBackend/README.md`.
 */

// Hosted matestback: port 80 is closed, real port is 8080. Override
// via the FAST_API_URL env var on the deployment if Henry moves it.
const FAST_API_URL = process.env.FAST_API_URL ?? "http://hackathon-api.gtischler.com:8080";

export type WarmMaterialEntry = {
  mass_grams: number;
  confidence: "low" | "medium" | "high";
};

export type WarmRetrieval = {
  rank: number;
  similarity: number;
  object_name: string;
  material_warm: string;
  mass_grams: number;
};

export type FastEstimateResponse = {
  item_title: string;
  item_description: string;
  caption: string;
  materials: Record<string, WarmMaterialEntry>;
  co2_saved_kg: number;
  needs_more_research: boolean;
  retrievals: WarmRetrieval[];
  timings_ms?: Record<string, number>;
};

/**
 * POST a JPEG to /estimate. Returns the full structured response. The
 * `?timings=true` query param embeds per-phase timings in the body so
 * we can surface the sub-second caption/embed/rag/predict breakdown
 * in the iOS progress feed.
 */
export async function callFastEstimate(
  imageBytes: ArrayBuffer,
  contentType: string,
): Promise<FastEstimateResponse> {
  const form = new FormData();
  const blob = new Blob([imageBytes as ArrayBuffer], {
    type: contentType || "image/jpeg",
  });
  form.append("image", blob, "scan.jpg");

  const url = `${FAST_API_URL}/estimate?timings=true`;
  const res = await fetch(url, {
    method: "POST",
    body: form,
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`Fast pipeline ${res.status}: ${text.slice(0, 300)}`);
  }
  const json = (await res.json()) as FastEstimateResponse;
  return json;
}

/**
 * EPA WARM v16 factor table (kgCO2e per kg of recycled material; negative
 * = emissions saved vs. landfill). Mirrors Henry's `WARM_FACTORS` in
 * `matestback/warm.py` so per-material CO2 numbers stay in sync.
 */
export const WARM_FACTORS: Record<string, number> = {
  "Aluminum Cans": -10.0612,
  "Aluminum Ingot": -7.9407,
  "Copper Wire": -4.9481,
  "Mixed Metals": -4.8404,
  "Wood Flooring": -4.0619,
  "Mixed Paper (primarily from offices)": -3.9458,
  "Mixed Paper (primarily residential)": -3.9083,
  "Mixed Paper (general)": -3.9083,
  "Corrugated Containers": -3.4561,
  "Textbooks": -3.4221,
  "Magazines/third-class mail": -3.3838,
  "Office Paper": -3.1567,
  "Mixed Recyclables": -3.0875,
  "Newspaper": -2.9854,
  "Phonebooks": -2.8906,
  "Carpet": -2.6253,
  "Structural Steel": -2.1261,
  "Steel Cans": -2.0195,
  "Dimensional Lumber": -1.8294,
  "Desktop CPUs": -1.6390,
  "Portable Electronic Devices": -1.1704,
  "PET": -1.1417,
  "Flat-Panel Displays": -1.0938,
  "Mixed Plastics": -1.0202,
  "Mixed Electronics": -0.9963,
  "Fly Ash": -0.9538,
  "PP": -0.8750,
  "HDPE": -0.8360,
  "CRT Displays": -0.6278,
  "Hard-Copy Devices": -0.6145,
  "Tires": -0.4148,
  "Electronic Peripherals": -0.4016,
  "Glass": -0.3043,
  "Asphalt Shingles": -0.0991,
  "Asphalt Concrete": -0.0892,
  "Concrete": -0.0088,
  "Drywall": 0.0288,
};

/** kgCO2e saved (positive = good) for a given mass + WARM bucket. */
export function co2SavedKgForWarm(warm: string, massG: number): number {
  const factor = WARM_FACTORS[warm] ?? 0;
  return (massG / 1000) * -factor;
}

/**
 * Map an EPA WARM v16 category onto our internal disposal decision.
 * Decisions are deterministic given the WARM bucket — no LLM needed.
 *
 * Reference: `/Users/willkillebrew/Desktop/HackathonBackend/matestback/warm.py`.
 */
export function decisionForWarm(
  warm: string,
): "recycle" | "trash" | "compost" | "hazard" {
  switch (warm) {
    // Universally recyclable
    case "Aluminum Cans":
    case "Aluminum Ingot":
    case "Copper Wire":
    case "Mixed Metals":
    case "Mixed Paper (primarily from offices)":
    case "Mixed Paper (primarily residential)":
    case "Mixed Paper (general)":
    case "Corrugated Containers":
    case "Textbooks":
    case "Magazines/third-class mail":
    case "Office Paper":
    case "Mixed Recyclables":
    case "Newspaper":
    case "Phonebooks":
    case "Structural Steel":
    case "Steel Cans":
    case "PET":
    case "Mixed Plastics":
    case "PP":
    case "HDPE":
    case "Glass":
      return "recycle";

    // Electronics → hazard / e-waste
    case "Desktop CPUs":
    case "Portable Electronic Devices":
    case "Flat-Panel Displays":
    case "Mixed Electronics":
    case "CRT Displays":
    case "Hard-Copy Devices":
    case "Electronic Peripherals":
    case "Tires":
      return "hazard";

    // Construction / inert / non-curbside
    case "Wood Flooring":
    case "Carpet":
    case "Dimensional Lumber":
    case "Fly Ash":
    case "Asphalt Shingles":
    case "Asphalt Concrete":
    case "Concrete":
    case "Drywall":
      return "trash";

    default:
      return "trash";
  }
}

/**
 * Map a WARM category onto our internal short material slug. Mirrors
 * the strings used elsewhere in the app (PET, HDPE, aluminum, etc.).
 */
export function materialSlugForWarm(warm: string): string {
  switch (warm) {
    case "Aluminum Cans":
    case "Aluminum Ingot":
      return "aluminum";
    case "Steel Cans":
    case "Structural Steel":
      return "steel";
    case "Copper Wire":
    case "Mixed Metals":
      return "metal";
    case "PET":
      return "pet";
    case "HDPE":
      return "hdpe";
    case "PP":
      return "pp";
    case "Mixed Plastics":
      return "plastic";
    case "Glass":
      return "glass";
    case "Corrugated Containers":
      return "cardboard";
    case "Newspaper":
      return "newspaper";
    case "Magazines/third-class mail":
    case "Mixed Paper (primarily from offices)":
    case "Mixed Paper (primarily residential)":
    case "Mixed Paper (general)":
    case "Office Paper":
    case "Textbooks":
    case "Phonebooks":
      return "paper";
    case "Desktop CPUs":
    case "Portable Electronic Devices":
    case "Mixed Electronics":
    case "Flat-Panel Displays":
    case "CRT Displays":
    case "Hard-Copy Devices":
    case "Electronic Peripherals":
      return "electronics";
    case "Tires":
      return "tire";
    case "Wood Flooring":
    case "Dimensional Lumber":
      return "wood";
    case "Carpet":
      return "textile";
    case "Asphalt Shingles":
    case "Asphalt Concrete":
    case "Concrete":
    case "Drywall":
    case "Fly Ash":
      return "construction";
    case "Mixed Recyclables":
      return "mixed";
    default:
      return "mixed";
  }
}

/**
 * Post-result bounding-box detection. Runs AFTER the user already sees
 * their card so its latency doesn't gate the headline result — the
 * bbox just slides in as an overlay when the call returns.
 *
 * Uses Perplexity Agent (Claude Opus 4.7 by default) with a JSON
 * schema clamped to a single normalized [0,1] rect. The user's city/
 * state is passed in for context — it doesn't change the geometry,
 * but does help the model distinguish "the item the user means" when
 * the photo is busy.
 */
const AGENT_URL = "https://api.perplexity.ai/v1/agent";

export async function detectBbox(
  imageDataUrl: string,
  itemTitle: string,
  itemDescription: string,
  city?: string,
  state?: string,
): Promise<{ x: number; y: number; w: number; h: number } | null> {
  const apiKey = process.env.PERPLEXITY_API_KEY;
  if (!apiKey) return null;
  const where = [city, state].filter(Boolean).join(", ");
  const locClause = where ? ` (user located in ${where})` : "";

  const instructions =
    "Output STRICT JSON matching the provided schema only — no preamble, no markdown. Locate the SPECIFIC waste item described and return a tight, normalized bounding box around its visible silhouette. Coordinates are in [0,1] where (0,0) is the TOP-LEFT and (1,1) is the BOTTOM-RIGHT of the image. x,y is the top-left corner of the box; w,h are width and height. Pad by no more than ~3% beyond the object's edges. If the object covers most of the frame, use the full frame {x:0,y:0,w:1,h:1}.";

  const userText =
    `Item: ${itemTitle}\n` +
    `Description: ${itemDescription}${locClause}\n\n` +
    `Return a tight normalized bounding box around this item.`;

  const schema = {
    type: "object",
    additionalProperties: false,
    required: ["x", "y", "w", "h"],
    properties: {
      x: { type: "number", minimum: 0, maximum: 1 },
      y: { type: "number", minimum: 0, maximum: 1 },
      w: { type: "number", minimum: 0, maximum: 1 },
      h: { type: "number", minimum: 0, maximum: 1 },
    },
  };

  const body = {
    model: process.env.PERPLEXITY_BBOX_MODEL ?? process.env.PERPLEXITY_MODEL ?? "anthropic/claude-opus-4-7",
    instructions,
    input: [
      {
        role: "user",
        content: [
          { type: "input_text", text: userText },
          { type: "input_image", image_url: imageDataUrl },
        ],
      },
    ],
    text: { format: { type: "json_schema", name: "bbox", schema } },
  };

  const res = await fetch(AGENT_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    console.warn(`[detectBbox] ${res.status}: ${text.slice(0, 300)}`);
    return null;
  }
  const json: any = await res.json();
  const text = extractAgentText(json);
  let parsed: any = {};
  try { parsed = JSON.parse(text); }
  catch {
    const m = text.match(/\{[\s\S]*\}/);
    if (m) { try { parsed = JSON.parse(m[0]); } catch {} }
  }
  const x = Number(parsed?.x);
  const y = Number(parsed?.y);
  const w = Number(parsed?.w);
  const h = Number(parsed?.h);
  if (![x, y, w, h].every((n) => Number.isFinite(n) && n >= 0 && n <= 1)) return null;
  if (w <= 0 || h <= 0) return null;
  if (x + w > 1.001 || y + h > 1.001) return null;
  return { x, y, w, h };
}

function extractAgentText(json: any): string {
  if (typeof json?.output_text === "string" && json.output_text.length > 0) {
    return json.output_text;
  }
  const out = json?.output;
  if (Array.isArray(out)) {
    for (const block of out) {
      const content = block?.content;
      if (Array.isArray(content)) {
        for (const c of content) {
          if (typeof c?.text === "string" && c.text.length > 0) return c.text;
        }
      }
    }
  }
  return "";
}

/**
 * Pick the most-mass non-zero WARM category. Used to drive the item's
 * primary `decision` and `material` fields when the response covers
 * multiple categories (e.g. aluminum can + paper label).
 */
export function dominantWarm(
  materials: Record<string, WarmMaterialEntry>,
): { warm: string; massG: number } | null {
  let best: { warm: string; massG: number } | null = null;
  for (const [warm, entry] of Object.entries(materials)) {
    const m = entry?.mass_grams ?? 0;
    if (m <= 0) continue;
    if (!best || m > best.massG) best = { warm, massG: m };
  }
  return best;
}
