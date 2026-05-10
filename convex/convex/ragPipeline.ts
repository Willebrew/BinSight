"use node";

/**
 * RAG runtime pipeline: given one freshly-classified item, produce a
 * grounded mass estimate by:
 *   1. Generating a short visual description of the item.
 *   2. Embedding that description with the SAME model + CONTEXT_PROMPT
 *      Henry used to build the reference catalog.
 *   3. Vector-searching the catalog for the K closest reference items.
 *   4. Asking the vision model to pick a mass given those references.
 *
 * Live model: `pplx-embed-context-v1-0.6b`. 1024-dim, returned as
 * base64_int8 — values are int8 in [-128, 127] cast to float, NOT
 * L2-normalized. Convex's vector search handles cosine similarity
 * internally, so we just hand it the raw float array.
 */

import { CONTEXT_PROMPT, EMBEDDING_MODEL, EMBEDDING_DIM, TOP_K_DEFAULT } from "./ragConstants";

// Contextualized embeddings (catalog used pplx-embed-context-v1-0.6b
// in chunked mode). Matches the path in @perplexity-ai/perplexity_ai's
// `contextualized_embeddings.create()`.
const EMBED_URL = "https://api.perplexity.ai/v1/contextualizedembeddings";
const AGENT_URL = "https://api.perplexity.ai/v1/agent";

export type SimilarRef = {
  imageFilename: string;
  imageUrl: string | null;
  similarity: number;
  objectName: string;
  objectDescription: string;
  materialWarm: string;
  massGrams: number;
  materialConfidence: string;
};

export type RagMassEstimate = {
  massGrams: number;
  source: "rag" | "model" | "default";
  needsResearch: boolean;
  reasoning: string;
  description: string;
  similar: SimilarRef[];
};

/**
 * Embed a query description with the catalog model + context prompt.
 * Decodes the base64_int8 payload back to a float array — values stay
 * un-normalized so they compare apples-to-apples with the corpus.
 */
export async function embedDescription(description: string): Promise<number[]> {
  const apiKey = process.env.PERPLEXITY_API_KEY;
  if (!apiKey) throw new Error("PERPLEXITY_API_KEY not set");

  const res = await fetch(EMBED_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: EMBEDDING_MODEL,
      input: [[CONTEXT_PROMPT, description]],
      encoding_format: "base64_int8",
    }),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`Perplexity embed ${res.status}: ${text.slice(0, 300)}`);
  }
  const json: any = await res.json();
  // Response shape: { data: [ { data: [ { index, embedding }, ... ] } ] }
  // Chunk 0 is the CONTEXT_PROMPT, chunk 1 is the description.
  const chunks: any[] = json?.data?.[0]?.data ?? [];
  const desc = chunks.find((c) => c.index === 1) ?? chunks[1];
  if (!desc?.embedding) {
    throw new Error("[ragPipeline] embedding response missing chunk[1].embedding");
  }
  const buf = Buffer.from(desc.embedding, "base64");
  // Int8Array: each byte is a signed integer in [-128, 127].
  const i8 = new Int8Array(buf.buffer, buf.byteOffset, buf.byteLength);
  const out = new Array<number>(i8.length);
  for (let i = 0; i < i8.length; i++) out[i] = i8[i];
  if (out.length !== EMBEDDING_DIM) {
    throw new Error(
      `[ragPipeline] embedding dim ${out.length} != ${EMBEDDING_DIM} — wrong model?`,
    );
  }
  return out;
}

/**
 * Generate a one-paragraph visual description of a single item, optionally
 * cropped to its bounding box. The description should match the *shape* of
 * Henry's catalog `object_description` — material, form factor, condition,
 * identifying marks — so the embedding lands near the right corpus cluster.
 */
export async function generateItemDescription(
  imageDataUrl: string,
  label: string,
  material: string,
): Promise<string> {
  const apiKey = process.env.PERPLEXITY_API_KEY;
  if (!apiKey) throw new Error("PERPLEXITY_API_KEY not set");

  const instructions = [
    "You are BinSight's RAG describer. Output a SINGLE plain-text paragraph (no preamble, no markdown, no bullet points) describing the indicated waste item.",
    "Cover, in this order: (1) the dominant material(s) and any sub-components, (2) form factor and approximate size class (e.g. 'standard 12oz beverage can', 'paperback book ~200pp'), (3) condition (clean / dirty / dented / wet / labeled), (4) identifying marks (brand, embossed numbers, recycling triangle digit).",
    "Stay 80-160 words. Do not hedge ('maybe', 'possibly') unless genuinely uncertain. Write as if for a reference catalog.",
  ].join(" ");

  const body = {
    model: process.env.PERPLEXITY_MODEL ?? "anthropic/claude-opus-4-7",
    instructions,
    input: [
      {
        role: "user",
        content: [
          {
            type: "input_text",
            text: `Describe this ${label} (material: ${material}) for a reference catalog.`,
          },
          { type: "input_image", image_url: imageDataUrl },
        ],
      },
    ],
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
    throw new Error(`Perplexity describe ${res.status}: ${text.slice(0, 300)}`);
  }
  const json: any = await res.json();
  return extractAgentText(json).trim();
}

/**
 * Final step: hand the original photo + the top-K reference photos+masses to
 * the vision model and ask for a calibrated mass for the user's item, in
 * grams. Returns a structured estimate with `needsResearch=true` when the
 * model couldn't lock in a confident number from the references alone.
 */
export async function estimateMassFromContext(
  imageDataUrl: string,
  label: string,
  material: string,
  similar: SimilarRef[],
): Promise<{ massGrams: number; needsResearch: boolean; reasoning: string }> {
  const apiKey = process.env.PERPLEXITY_API_KEY;
  if (!apiKey) throw new Error("PERPLEXITY_API_KEY not set");

  const refsBlock = similar.slice(0, 5).map((r, i) =>
    `[${i + 1}] ${r.objectName} - ${r.materialWarm} - ${r.massGrams.toFixed(1)} g - sim=${r.similarity.toFixed(3)}\n    ${r.objectDescription}`,
  ).join("\n");

  const instructions = [
    "You are BinSight's RAG mass estimator. Given the user's photo plus a small reference catalog of similar items (each with a known empty mass in grams), estimate the EMPTY mass in grams of the item in the user's photo.",
    "STRICT JSON OUTPUT. Schema: {\"massGrams\": number, \"needsResearch\": boolean, \"reasoning\": string}. No prose outside the JSON.",
    "Calibrate against the references: when the user's item is visually-similar to a reference, return a mass close to it; when the user's item is clearly larger/smaller, scale accordingly and explain in `reasoning`.",
    "Set `needsResearch: true` when the references are too dissimilar to anchor a confident estimate (e.g. all references are <100g but the user's item is clearly a heavy appliance). When `needsResearch: true`, still output your best-guess `massGrams`.",
    "ALWAYS return a positive `massGrams` > 0. `reasoning` ≤ 240 chars.",
  ].join(" ");

  const userText = [
    `Item label: ${label}`,
    `Material: ${material}`,
    "",
    "Reference catalog (top similar items, descending similarity):",
    refsBlock,
  ].join("\n");

  const schema = {
    type: "object",
    additionalProperties: false,
    required: ["massGrams", "needsResearch", "reasoning"],
    properties: {
      massGrams: { type: "number", minimum: 0.1 },
      needsResearch: { type: "boolean" },
      reasoning: { type: "string" },
    },
  };

  const body = {
    model: process.env.PERPLEXITY_MODEL ?? "anthropic/claude-opus-4-7",
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
    text: {
      format: {
        type: "json_schema",
        name: "rag_mass_estimate",
        schema,
      },
    },
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
    throw new Error(`Perplexity mass-estimate ${res.status}: ${text.slice(0, 300)}`);
  }
  const json: any = await res.json();
  const text = extractAgentText(json);
  let parsed: any = {};
  try { parsed = JSON.parse(text); } catch { /* fall through */ }
  const massGrams = typeof parsed?.massGrams === "number" && parsed.massGrams > 0
    ? parsed.massGrams
    : 0;
  return {
    massGrams,
    needsResearch: !!parsed?.needsResearch,
    reasoning: typeof parsed?.reasoning === "string" ? parsed.reasoning.slice(0, 240) : "",
  };
}

/**
 * Batched refinement: hand the original photo + every detected item +
 * each item's top-K RAG references to the model in a SINGLE agent call.
 * The model picks final masses and explicitly cites which reference
 * filenames it leaned on (so the UI can render that as the "tool use"
 * citation). Returns one entry per input item, in order.
 *
 * The model receives the catalog context in its prompt and has the
 * structured-output schema to declare which references it actually
 * used. There's no live function-call (Perplexity Agent only ships
 * web_search/fetch_url as tools), so this is the closest equivalent.
 */
export async function refineItemMassesWithRag(
  imageDataUrl: string,
  items: Array<{
    label: string;
    material: string;
    decision: string;
    estimatedMassG?: number;
    references: SimilarRef[];
  }>,
): Promise<Array<{
  index: number;
  massGrams: number;
  needsResearch: boolean;
  reasoning: string;
  usedFilenames: string[];
}>> {
  if (items.length === 0) return [];
  const apiKey = process.env.PERPLEXITY_API_KEY;
  if (!apiKey) throw new Error("PERPLEXITY_API_KEY not set");

  const itemsBlock = items.map((it, i) => {
    const refs = it.references.slice(0, 5).map((r, ri) =>
      `      [${ri + 1}] ${r.objectName} | ${r.materialWarm} | ${r.massGrams.toFixed(1)} g | sim=${r.similarity.toFixed(3)} | filename="${r.imageFilename}"\n          ${r.objectDescription}`
    ).join("\n");
    return [
      `  Item ${i}: ${it.label}`,
      `    material: ${it.material}`,
      `    decision: ${it.decision}`,
      it.estimatedMassG ? `    vision_mass_estimate_g: ${it.estimatedMassG.toFixed(1)}` : "",
      "    references_from_knowledge_base:",
      refs || "      (none)",
    ].filter(Boolean).join("\n");
  }).join("\n\n");

  const instructions = [
    "You are BinSight's RAG mass refiner. You have a knowledge base of reference waste items, each with a known empty mass in grams. The system has retrieved the closest references for each item in the user's photo.",
    "Your job: for EACH item, return the BEST empty-mass-in-grams estimate. Calibrate against the references when they're a good visual match; override the references when the user's item is clearly a different size/form.",
    "Cite which reference filenames you actually used (`usedFilenames`). If references didn't help, return an empty array and use your own judgment from the photo.",
    "If the references are too dissimilar to anchor a confident estimate, set `needsResearch: true` for that item but still output your best `massGrams`.",
    "STRICT JSON OUTPUT matching the provided schema. No prose outside the JSON.",
    "ALWAYS return positive `massGrams` > 0 for every item. `reasoning` ≤ 200 chars. `usedFilenames` references must come from the supplied references list.",
  ].join(" ");

  const userText = [
    "Items in this photo and their retrieved knowledge-base references:",
    "",
    itemsBlock,
    "",
    "Refine each item's empty mass in grams using the references where they help.",
  ].join("\n");

  const schema = {
    type: "object",
    additionalProperties: false,
    required: ["items"],
    properties: {
      items: {
        type: "array",
        minItems: items.length,
        maxItems: items.length,
        items: {
          type: "object",
          additionalProperties: false,
          required: ["index", "massGrams", "needsResearch", "reasoning", "usedFilenames"],
          properties: {
            index: { type: "integer", minimum: 0 },
            massGrams: { type: "number", minimum: 0.1 },
            needsResearch: { type: "boolean" },
            reasoning: { type: "string" },
            usedFilenames: {
              type: "array",
              items: { type: "string" },
            },
          },
        },
      },
    },
  };

  const body = {
    model: process.env.PERPLEXITY_MODEL ?? "anthropic/claude-opus-4-7",
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
    text: {
      format: {
        type: "json_schema",
        name: "rag_refine",
        schema,
      },
    },
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
    throw new Error(`Perplexity rag-refine ${res.status}: ${text.slice(0, 300)}`);
  }
  const json: any = await res.json();
  const text = extractAgentText(json);
  let parsed: any = {};
  try { parsed = JSON.parse(text); } catch { /* fall through */ }
  const arr: any[] = Array.isArray(parsed?.items) ? parsed.items : [];

  // Defensively normalize. Index out-of-range items get dropped; missing
  // entries are filled with zero-mass / needsResearch=true so the caller
  // can fall back to the vision estimate.
  const out: Array<{
    index: number;
    massGrams: number;
    needsResearch: boolean;
    reasoning: string;
    usedFilenames: string[];
  }> = items.map((_, i) => ({
    index: i,
    massGrams: 0,
    needsResearch: true,
    reasoning: "",
    usedFilenames: [],
  }));
  for (const r of arr) {
    const idx = Number(r?.index);
    if (!Number.isInteger(idx) || idx < 0 || idx >= items.length) continue;
    const m = Number(r?.massGrams);
    out[idx] = {
      index: idx,
      massGrams: Number.isFinite(m) && m > 0 ? m : 0,
      needsResearch: !!r?.needsResearch,
      reasoning: typeof r?.reasoning === "string" ? r.reasoning.slice(0, 200) : "",
      usedFilenames: Array.isArray(r?.usedFilenames)
        ? r.usedFilenames.map((s: any) => String(s)).filter(Boolean)
        : [],
    };
  }
  return out;
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

export { TOP_K_DEFAULT };
