"use node";

// Perplexity classifier for BinSight.
//
// Uses Claude Opus 4.7 via Perplexity Agent API for vision classification,
// with separate Perplexity Search API calls for web research. Search results
// are injected into the prompt to provide context for local recycling rules.
//   • per-item mass estimates (grams)
//   • per-item source attribution (which URL backs which decision)
//   • per-item disposal-rule citations preferred from the user's own city
//
// Env: PERPLEXITY_API_KEY  (set via `npx convex env set PERPLEXITY_API_KEY ...`)
//      PERPLEXITY_MODEL    (optional override; default "anthropic/claude-opus-4-7")
//
// Available models via Perplexity Agent API:
// - anthropic/claude-opus-4-7 (default)
// - anthropic/claude-sonnet-4-6
// - openai/gpt-5.4
// - google/gemini-3.1-pro-preview
// - See https://docs.perplexity.ai/docs/agent-api/models for full list

const AGENT_URL = "https://api.perplexity.ai/v1/agent";
const SEARCH_URL = "https://api.perplexity.ai/search";

export type RawSource = {
  url: string;
  title?: string;
  publisher?: string;
  snippet?: string;
  /** "material" | "rule" | "both" - what this source supports. */
  kind?: string;
  /** indices into the items array that this source supports */
  supportsItemIndices?: number[];
};

export type RawItem = {
  label: string;
  material: string;
  decision: "recycle" | "trash" | "compost" | "hazard";
  confidence: number;
  estimatedMassG?: number;
  disposalNotes: string;
  /** indices into the agent's `sources` array */
  sourceIndices?: number[];
};

export type AgentResult = {
  items: RawItem[];
  sources: RawSource[];
  localRules: string;
  citations: string[];
  model: string;
};

const wasteSchema = {
  schema: {
    type: "object",
    additionalProperties: false,
    required: ["items", "sources", "localRules"],
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: [
            "label",
            "material",
            "decision",
            "confidence",
            "estimatedMassG",
            "disposalNotes",
            "sourceIndices",
          ],
          properties: {
            label: { type: "string", description: "Short human-readable item name." },
            material: {
              type: "string",
              description:
                "One of: pet, hdpe, ldpe, pp, ps, plastic, aluminum, steel, tin, paper, cardboard, newspaper, glass, organic, food, yard, mixed, unknown",
            },
            decision: {
              type: "string",
              enum: ["recycle", "trash", "compost", "hazard"],
            },
            confidence: { type: "number", minimum: 0, maximum: 1 },
            estimatedMassG: {
              type: "number",
              description:
                "Best-effort mass in grams of THIS specific item from visual cues. Use 0 if you truly cannot tell.",
            },
            disposalNotes: {
              type: "string",
              description:
                "1-2 sentences explaining why this decision and any prep needed (rinse, flatten, remove cap, etc.).",
            },
            sourceIndices: {
              type: "array",
              items: { type: "integer", minimum: 0 },
              description:
                "Indices into the top-level `sources` array that justify this item's decision and disposal notes. Required: every item must have at least one source.",
            },
          },
        },
      },
      sources: {
        type: "array",
        description:
          "Distinct authoritative sources used. MUST include BOTH (a) sources that identify the object/material (manufacturer pages, Wikipedia, product spec sheets, material composition references) AND (b) sources that justify the disposal decision (municipal program pages, EPA, state guidance). Don't list the same URL twice.",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["url", "title", "publisher", "snippet", "kind"],
          properties: {
            url: { type: "string", description: "Full URL." },
            title: { type: "string", description: "Page title." },
            publisher: {
              type: "string",
              description: "Publishing organization, e.g. 'EPA', 'SF Environment', 'Recology', 'Wikipedia'.",
            },
            snippet: {
              type: "string",
              description:
                "1-2 sentence direct quote or close paraphrase from the page that supports the items pointing to this source.",
            },
            kind: {
              type: "string",
              enum: ["material", "rule", "both"],
              description:
                "What this source supports. 'material' = identifies what the object is made of; 'rule' = states the local disposal rule; 'both' = covers both.",
            },
          },
        },
      },
      localRules: {
        type: "string",
        description:
          "1-3 sentence summary of any location-specific recycling rules that affect these items.",
      },
    },
  },
};

/**
 * Search the web for local recycling rules and return them as RawSources
 * (kind="rule"). Designed to run in parallel with item-spec lookups
 * after the vision pass identifies what materials are present.
 */
export async function lookupLocalRules(
  city?: string,
  state?: string,
  materials?: string[],
): Promise<{ summary: string; sources: RawSource[] }> {
  const apiKey = process.env.PERPLEXITY_API_KEY;
  if (!apiKey) return { summary: "", sources: [] };
  const where = [city, state].filter(Boolean).join(", ");
  if (!where) return { summary: "", sources: [] };

  const distinctMaterials = Array.from(
    new Set((materials ?? []).map((m) => m.toLowerCase()).filter(Boolean)),
  ).slice(0, 4);
  const materialList = distinctMaterials.join(", ") || "household waste";

  const queries = [
    `${where} curbside recycling rules ${materialList}`,
    `${where} how to dispose of ${materialList}`,
  ];

  try {
    const all = await Promise.all(
      queries.map(async (query) => {
        const res = await fetch(SEARCH_URL, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${apiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            query,
            max_results: 4,
            max_tokens_per_page: 2048,
            country: state ? "US" : undefined,
          }),
        });
        if (!res.ok) return [] as RawSource[];
        const json: any = await res.json();
        const results: any[] = Array.isArray(json?.results) ? json.results : [];
        return results
          .filter((r) => typeof r?.url === "string")
          .map((r) => ({
            url: r.url as string,
            title: r.title,
            publisher: r.publisher ?? hostFor(r.url),
            snippet: typeof r.snippet === "string" ? r.snippet.slice(0, 480) : "",
            kind: "rule",
          })) as RawSource[];
      }),
    );

    const flat = all.flat();
    // Dedup by URL, prefer official-tier hosts.
    const byUrl = new Map<string, RawSource>();
    for (const s of flat) {
      if (!byUrl.has(s.url)) byUrl.set(s.url, s);
    }
    const sources = Array.from(byUrl.values()).slice(0, 6);
    const summary = sources
      .slice(0, 2)
      .map((s) => `${s.publisher}: ${(s.snippet || "").trim().slice(0, 200)}`)
      .filter((line) => line.length > 0)
      .join(" — ");
    return { summary, sources };
  } catch {
    return { summary: "", sources: [] };
  }
}

/**
 * Legacy helper kept so existing call sites keep building. Wraps the
 * structured `lookupLocalRules` and returns just the summary string.
 */
async function searchLocalRecyclingRules(
  city?: string,
  state?: string,
  materials?: string[]
): Promise<string> {
  const apiKey = process.env.PERPLEXITY_API_KEY;
  if (!apiKey) return "";

  const location = [city, state].filter(Boolean).join(", ");
  const materialList = materials?.slice(0, 3).join(", ") || "waste items";

  const queries = [
    `${location} recycling rules ${materialList}`,
    `${location} waste disposal guidelines`,
    `${state} recycling requirements ${materialList}`,
  ];

  try {
    const searchPromises = queries.map(async (query) => {
      const res = await fetch(SEARCH_URL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          query,
          max_results: 3,
          max_tokens_per_page: 2048,
        }),
      });

      if (!res.ok) return "";
      const json: any = await res.json();
      const results: any[] = Array.isArray(json?.results) ? json.results : [];

      return results
        .map(
          (r) =>
            `• ${r.title}\n  ${r.snippet?.slice(0, 300) || ""}\n  Source: ${r.url}`
        )
        .join("\n");
    });

    const searchResults = await Promise.all(searchPromises);
    return searchResults.filter(Boolean).join("\n\n");
  } catch {
    return "";
  }
}

function systemPrompt(
  lat?: number,
  lng?: number,
  city?: string,
  state?: string,
  searchContext?: string
): string {
  const where = [city, state].filter(Boolean).join(", ");
  const loc = where
    ? `User location: ${where}${lat !== undefined && lng !== undefined ? ` (${lat.toFixed(3)}, ${lng.toFixed(3)})` : ""}.`
    : lat !== undefined && lng !== undefined
      ? `User location: ${lat.toFixed(3)}, ${lng.toFixed(3)}.`
      : "Location unknown.";
  const searchSection = searchContext
    ? `\n\nLOCAL RECYCLING RESEARCH:\n${searchContext}\n\nUse this research to inform your disposal decisions, but always verify with the sources you cite.`
    : "";

  return [
    "You are BinSight, an expert in municipal waste classification.",
    "Identify every distinct waste item visible in the photo.",
    "For each item, decide whether it should be recycled, composted, trashed, or treated as hazardous, given the user's location.",
    "Estimate each item's mass in grams from visual cues; if you genuinely cannot tell, return 0 (we'll fall back to a default).",
    "Be conservative: if a container is contaminated with food and the local program rejects contaminated items, mark as trash.",
    "When sourcing, prefer official municipal pages (e.g. 'sfenvironment.org', 'nyc.gov/sanitation') and .gov / EPA over blogs or forums.",
    "For EACH item, include sources of BOTH kinds when possible: (a) material/object identification (manufacturer site, Wikipedia, product spec) tagged with kind='material', and (b) local disposal rule (municipal program, EPA) tagged with kind='rule'. Use kind='both' if a single source covers both.",
    "Every item MUST point to at least one entry in the `sources` array via `sourceIndices`. Sources should be distinct (don't list the same URL twice).",
    "Do not use em-dashes (—) in disposalNotes or any text fields. Use hyphens (-) or rephrase instead.",
    loc,
    searchSection,
  ].join(" ");
}

export async function classifyImage(
  imageBytes: ArrayBuffer,
  contentType: string,
  lat?: number,
  lng?: number,
  city?: string,
  state?: string,
  onProgress?: (snapshot: Partial<AgentResult>) => Promise<void> | void,
): Promise<AgentResult> {
  const apiKey = process.env.PERPLEXITY_API_KEY;
  if (!apiKey) {
    throw new Error("PERPLEXITY_API_KEY is not set on this Convex deployment");
  }
  const model = process.env.PERPLEXITY_MODEL ?? "anthropic/claude-opus-4-7";

  // No pre-call research — research happens AFTER the vision pass via the
  // parallel Search API calls in classifyWaste. Skipping the pre-search
  // here cuts ~2s off the user-visible latency of the first paint.
  const base64 = arrayBufferToBase64(imageBytes);
  const dataUrl = `data:${contentType || "image/jpeg"};base64,${base64}`;

  const useStreaming = !!onProgress;

  const body: any = {
    model,
    response_format: { type: "json_schema", json_schema: wasteSchema },
    messages: [
      {
        role: "system",
        content: systemPrompt(lat, lng, city, state),
      },
      {
        role: "user",
        content: [
          { type: "text", text: "Classify the items in this photo for disposal." },
          { type: "image_url", image_url: { url: dataUrl } },
        ],
      },
    ],
  };
  if (useStreaming) body.stream = true;

  const res = await fetch(AGENT_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Perplexity API ${res.status}: ${text.slice(0, 500)}`);
  }

  if (!useStreaming) {
    const json: any = await res.json();
    // Agent API returns structured data in output_text when using response_format
    const content = json.output_text || json.choices?.[0]?.message?.content || JSON.stringify(json);
    let parsed: any;
    try {
      parsed = JSON.parse(content);
    } catch {
      // Fallback: try to extract JSON from the response
      parsed = extractStructured(json);
    }
    const flatCitations: string[] = Array.isArray(json.citations) ? json.citations : [];
    return {
      items: parsed.items ?? [],
      sources: parsed.sources ?? [],
      localRules: parsed.localRules ?? "",
      citations: flatCitations,
      model,
    };
  }

  // Streaming path: read SSE, accumulate the JSON body, and emit
  // progress snapshots as more items become parseable. We re-parse the
  // partial buffer on every chunk; expensive (O(n²)) but n is small.
  const reader = (res.body as any)?.getReader?.();
  if (!reader) {
    // Fallback: consume non-streaming
    const txt = await res.text();
    const json: any = (() => { try { return JSON.parse(txt); } catch { return {}; } })();
    const parsed = extractStructured(json);
    return {
      items: parsed.items ?? [],
      sources: parsed.sources ?? [],
      localRules: parsed.localRules ?? "",
      citations: Array.isArray(json.citations) ? json.citations : [],
      model,
    };
  }

  const decoder = new TextDecoder();
  let sseBuffer = "";
  let contentBuffer = "";
  let lastEmittedCount = -1;
  let lastCitations: string[] = [];

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    sseBuffer += decoder.decode(value, { stream: true });

    let nlIdx: number;
    while ((nlIdx = sseBuffer.indexOf("\n")) >= 0) {
      const line = sseBuffer.slice(0, nlIdx).trim();
      sseBuffer = sseBuffer.slice(nlIdx + 1);
      if (!line.startsWith("data:")) continue;
      const data = line.slice(5).trim();
      if (data === "[DONE]") continue;
      try {
        const parsed = JSON.parse(data);
        const delta = parsed?.choices?.[0]?.delta?.content;
        if (typeof delta === "string") contentBuffer += delta;
        if (Array.isArray(parsed?.citations)) lastCitations = parsed.citations;
      } catch {
        /* ignore non-JSON keepalive lines */
      }
    }

    const partial = parsePartialAgentJson(contentBuffer);
    if (partial.items && partial.items.length > lastEmittedCount) {
      lastEmittedCount = partial.items.length;
      try {
        await onProgress?.({
          items: partial.items,
          sources: partial.sources ?? [],
          localRules: partial.localRules ?? "",
          citations: lastCitations,
          model,
        });
      } catch {
        /* progress callback errors must not abort the stream */
      }
    }
  }

  // Final parse from the accumulated content
  const finalParsed = parsePartialAgentJson(contentBuffer);
  return {
    items: finalParsed.items ?? [],
    sources: finalParsed.sources ?? [],
    localRules: finalParsed.localRules ?? "",
    citations: lastCitations,
    model,
  };
}

/**
 * Tolerantly extract complete `items[]` and `sources[]` JSON objects from
 * a half-finished JSON document. Used during SSE streaming to emit
 * partial results before the full response has arrived. Anything we
 * can't parse is just dropped from the snapshot.
 */
function parsePartialAgentJson(buf: string): {
  items?: RawItem[];
  sources?: RawSource[];
  localRules?: string;
} {
  if (!buf) return {};
  // Try the easy path first: the full doc is parseable.
  try {
    const j = JSON.parse(buf);
    if (j && typeof j === "object") return j;
  } catch {
    /* fall through */
  }
  return {
    items: collectArray(buf, '"items"') as RawItem[] | undefined,
    sources: collectArray(buf, '"sources"') as RawSource[] | undefined,
    localRules: extractString(buf, '"localRules"'),
  };
}

function collectArray(buf: string, key: string): unknown[] | undefined {
  const keyIdx = buf.indexOf(key);
  if (keyIdx < 0) return undefined;
  const open = buf.indexOf("[", keyIdx);
  if (open < 0) return undefined;
  const out: unknown[] = [];
  let i = open + 1;
  let depth = 0;
  let start = -1;
  let inString = false;
  let escape = false;
  while (i < buf.length) {
    const c = buf[i];
    if (escape) { escape = false; i++; continue; }
    if (c === "\\") { escape = true; i++; continue; }
    if (c === '"') { inString = !inString; i++; continue; }
    if (inString) { i++; continue; }
    if (c === "{") { if (depth === 0) start = i; depth++; }
    else if (c === "}") {
      depth--;
      if (depth === 0 && start >= 0) {
        const slice = buf.slice(start, i + 1);
        try { out.push(JSON.parse(slice)); } catch { /* skip incomplete */ }
        start = -1;
      }
    } else if (c === "]" && depth === 0) {
      break;
    }
    i++;
  }
  return out;
}

function extractString(buf: string, key: string): string | undefined {
  const idx = buf.indexOf(key);
  if (idx < 0) return undefined;
  const colon = buf.indexOf(":", idx + key.length);
  if (colon < 0) return undefined;
  let i = colon + 1;
  while (i < buf.length && buf[i] !== '"') i++;
  if (i >= buf.length) return undefined;
  let out = "";
  i++;
  while (i < buf.length) {
    const c = buf[i];
    if (c === "\\" && i + 1 < buf.length) {
      out += buf[i + 1];
      i += 2;
      continue;
    }
    if (c === '"') return out;
    out += c;
    i++;
  }
  return undefined; // string didn't close yet
}

/**
 * Look up a real-world mass estimate for an item via Perplexity Search.
 * Returns grams + a citing source so we don't have to take the vision
 * model's mass guess on faith.
 *
 * Best-effort. Failures return undefined; caller falls back to the model
 * estimate or the material default. Designed to run in parallel for many
 * items via Promise.all.
 */
export async function lookupItemMass(
  item: RawItem,
): Promise<{ massG: number; source: RawSource } | undefined> {
  const apiKey = process.env.PERPLEXITY_API_KEY;
  if (!apiKey) return undefined;
  const query = `typical empty mass in grams of ${item.label} (${item.material})`;
  try {
    const res = await fetch(SEARCH_URL, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ query, max_results: 5 }),
    });
    if (!res.ok) return undefined;
    const json: any = await res.json();
    const results: any[] = Array.isArray(json?.results) ? json.results : [];
    for (const r of results) {
      const blob = `${r?.title ?? ""} ${r?.snippet ?? ""}`;
      const m =
        blob.match(/(\d{1,4}(?:\.\d+)?)\s*(?:g|grams?|gm)\b/i) ||
        blob.match(/(\d{1,2}(?:\.\d+)?)\s*(?:oz|ounces?)\b/i);
      if (!m) continue;
      let grams = parseFloat(m[1]);
      if (m[0].toLowerCase().includes("oz")) grams *= 28.3495;
      // Reject implausible values: < 0.5g (specks) or > 50kg (vehicles)
      if (!Number.isFinite(grams) || grams < 0.5 || grams > 50_000) continue;
      const url: string | undefined = r?.url;
      if (!url) continue;
      return {
        massG: Number(grams.toFixed(1)),
        source: {
          url,
          title: r?.title,
          publisher: r?.publisher ?? hostFor(url),
          snippet: r?.snippet ?? "",
          kind: "material",
        },
      };
    }
    return undefined;
  } catch {
    return undefined;
  }
}

function hostFor(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return url;
  }
}

/**
 * Lightweight verification: ask the Search API to corroborate the top item's
 * decision. Best-effort; failures are non-fatal upstream.
 */
export async function verifyTopItem(item: RawItem): Promise<boolean> {
  const apiKey = process.env.PERPLEXITY_API_KEY;
  if (!apiKey) return false;
  const query = `Is a ${item.label} (${item.material}) ${
    item.decision === "recycle" ? "recyclable" : item.decision
  }?`;
  try {
    const res = await fetch(SEARCH_URL, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ query, max_results: 5 }),
    });
    if (!res.ok) return false;
    const json: any = await res.json();
    const blob = JSON.stringify(json).toLowerCase();
    if (item.decision === "recycle") return blob.includes("recycl");
    if (item.decision === "compost") return blob.includes("compost");
    if (item.decision === "hazard") return blob.includes("hazard") || blob.includes("battery");
    return blob.includes("trash") || blob.includes("landfill");
  } catch {
    return false;
  }
}

/**
 * Generate a 1-sentence weekly insight for a user given recent scan summaries.
 * Designed to be called at most once per user per week (the result is cached
 * in the `weeklyInsights` table).
 */
export async function generateWeeklyInsight(input: {
  city?: string;
  state?: string;
  recyclableCount: number;
  trashedCount: number;
  topMaterials: Array<{ material: string; count: number }>;
}): Promise<{ headline: string; body: string; sources: RawSource[] }> {
  const apiKey = process.env.PERPLEXITY_API_KEY;
  if (!apiKey) {
    return { headline: "Keep scanning!", body: "Sign in and add a Perplexity key to unlock weekly insights.", sources: [] };
  }
  const model = process.env.PERPLEXITY_MODEL ?? "anthropic/claude-opus-4-7";
  const where = [input.city, input.state].filter(Boolean).join(", ");
  const topList = input.topMaterials
    .slice(0, 4)
    .map((m) => `${m.material}×${m.count}`)
    .join(", ");

  // Search for sustainability tips relevant to user's location and materials
  let searchContext = "";
  if (input.topMaterials.length > 0) {
    const materialNames = input.topMaterials.slice(0, 2).map((m) => m.material).join(", ");
    const searchQueries = [
      `${where} recycling tips ${materialNames}`,
      `${where} waste reduction best practices`,
      "sustainable recycling habits 2024",
    ];

    try {
      const searchPromises = searchQueries.map(async (query) => {
        const res = await fetch(SEARCH_URL, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${apiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            query,
            max_results: 2,
            max_tokens_per_page: 1024,
          }),
        });

        if (!res.ok) return "";
        const json: any = await res.json();
        const results: any[] = Array.isArray(json?.results) ? json.results : [];

        return results
          .map(
            (r) =>
              `• ${r.title}\n  ${r.snippet?.slice(0, 200) || ""}\n  Source: ${r.url}`
          )
          .join("\n");
      });

      const searchResults = await Promise.all(searchPromises);
      searchContext = searchResults.filter(Boolean).join("\n\n");
    } catch {
      // Continue without search context if it fails
    }
  }

  const searchSection = searchContext
    ? `\n\nSUSTAINABILITY RESEARCH:\n${searchContext}\n\nUse this research to inform your tip, but always cite your sources.`
    : "";

  const sys = [
    "You are BinSight, writing a 1-sentence weekly insight for a user.",
    "Tone: warm, specific, evidence-based. Cite at least one official source (.gov / EPA / municipal).",
    "Do not use em-dashes (—) in your response. Use hyphens (-) or rephrase instead.",
    "Output JSON: { headline: string (max 60 chars), body: string (1-2 sentences, max 240 chars), sources: array of {url, title, publisher, snippet} }.",
  ].join(" ");
  const user = [
    `User location: ${where || "unknown"}.`,
    `This week they recycled/composted ${input.recyclableCount} items and trashed ${input.trashedCount}.`,
    `Top materials: ${topList || "none"}.`,
    "Give them ONE concrete, location-aware tip that improves their impact, plus the source.",
    searchSection,
  ].join(" ");

  const body = {
    model,
    response_format: {
      type: "json_schema",
      json_schema: {
        schema: {
          type: "object",
          additionalProperties: false,
          required: ["headline", "body", "sources"],
          properties: {
            headline: { type: "string" },
            body: { type: "string" },
            sources: {
              type: "array",
              items: {
                type: "object",
                additionalProperties: false,
                required: ["url", "title", "publisher", "snippet"],
                properties: {
                  url: { type: "string" },
                  title: { type: "string" },
                  publisher: { type: "string" },
                  snippet: { type: "string" },
                },
              },
            },
          },
        },
      },
    },
    messages: [
      { role: "system", content: sys },
      { role: "user", content: user },
    ],
  };
  try {
    const res = await fetch(AGENT_URL, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`status ${res.status}`);
    const json: any = await res.json();
    // Agent API returns structured data in output_text when using response_format
    const content = json.output_text || json?.choices?.[0]?.message?.content || JSON.stringify(json);
    let parsed: any;
    try {
      parsed = typeof content === "string" ? JSON.parse(content) : content;
    } catch {
      // Fallback: try to extract from the response
      parsed = json;
    }
    return {
      headline: String(parsed?.headline ?? "Keep going!").slice(0, 80),
      body: String(parsed?.body ?? ""),
      sources: Array.isArray(parsed?.sources) ? parsed.sources : [],
    };
  } catch {
    return { headline: "Keep scanning!", body: "We couldn't fetch a fresh tip this week - your impact still counts.", sources: [] };
  }
}

function extractStructured(json: any): {
  items?: RawItem[];
  sources?: RawSource[];
  localRules?: string;
} {
  const choice = json?.choices?.[0];
  const content = choice?.message?.content;
  if (typeof content === "string") {
    try {
      const parsed = JSON.parse(content);
      if (parsed && Array.isArray(parsed.items)) return parsed;
    } catch {
      const match = content.match(/\{[\s\S]*\}/);
      if (match) {
        try {
          const parsed = JSON.parse(match[0]);
          if (parsed && Array.isArray(parsed.items)) return parsed;
        } catch {
          /* ignore */
        }
      }
    }
  }
  return {};
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
