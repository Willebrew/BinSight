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
// Env: PERPLEXITY_API_KEY
//      PERPLEXITY_MODEL    (optional override; default "anthropic/claude-opus-4-7")
//
// Available models via Perplexity Agent API:
// - anthropic/claude-opus-4-7 (default)
// - anthropic/claude-sonnet-4-6
// - openai/gpt-5.4
// - google/gemini-3.1-pro-preview
// - See https://docs.perplexity.ai/docs/agent-api/models for full list

// Perplexity Agent API (Responses-shape). Body uses `input` (not `messages`)
// with content blocks of type `input_text` / `input_image`. Structured
// output goes under `text.format`. Streaming emits `response.output_text.delta`
// events with a `delta` string.
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
  /** Normalized [0,1] bounding box over the original image. */
  bbox?: { x: number; y: number; w: number; h: number };
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
    required: ["steps", "sources", "localRules", "items"],
    properties: {
      steps: {
        type: "array",
        description:
          "Append-only narration of YOUR actual reasoning + research as you go. Stream this FIRST so the user feels the agent thinking. Each entry is a short user-facing sentence in present tense, ≤60 chars. Examples: 'Spotting the orange Joy-Con grip', 'Recognized as Nintendo Switch controller', 'Lithium battery inside - cannot trash', 'Searching denvergov.org for e-waste rules', 'Confirmed: Denver requires HHW drop-off'. Aim for 5-10 steps that match what you ACTUALLY do.",
        items: { type: "string" },
      },
      sources: {
        type: "array",
        description:
          "Distinct authoritative sources used. MUST include BOTH (a) sources that identify the object/material (manufacturer pages, Wikipedia, product spec sheets, material composition references) AND (b) sources that justify the disposal decision (municipal program pages, EPA, state guidance). Don't list the same URL twice.",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["url", "title", "publisher", "snippet", "quotes", "kind"],
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
            quotes: {
              type: "array",
              minItems: 1,
              maxItems: 3,
              description:
                "1-3 short, VERBATIM quoted sentences (or short clauses) from the page itself that justify the decisions citing this source. Each quote ≤200 characters. Use only words that actually appear on the page (you fetched it). Do not paraphrase here.",
              items: { type: "string" },
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
        minLength: 40,
        description:
          "REQUIRED 2-4 sentence summary of the user's CITY-SPECIFIC disposal rule(s) for these items. Must name the city and reference the actual local program (e.g. 'Denver Recycles…', 'NYC DSNY…'). If you genuinely don't know city-specific rules, fall back to state-level then EPA guidance, but never leave this empty.",
      },
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
            "bbox",
            "sourceIndices",
          ],
          properties: {
            label: { type: "string", description: "Short human-readable item name." },
            material: {
              type: "string",
              description:
                "One of: pet, hdpe, ldpe, film, wrapper, pp, ps, plastic, aluminum, steel, tin, paper, cardboard, newspaper, glass, organic, food, yard, mixed, unknown. Use 'film' for thin flexible plastic packaging like candy wrappers, chip bags, food pouches, plastic shopping bags - NOT 'plastic' (which implies a rigid container).",
            },
            decision: {
              type: "string",
              enum: ["recycle", "trash", "compost", "hazard"],
            },
            confidence: { type: "number", minimum: 0, maximum: 1 },
            estimatedMassG: {
              type: "number",
              description:
                "Best-effort EMPTY mass in grams of THIS specific item, predicted from visual cues (size relative to other objects, shape, wall thickness, material density). ALWAYS return a positive number greater than 0 - you are an expert; make an educated guess. Only use small values (<5g) for genuinely tiny items like a paper clip or candy wrapper.",
            },
            disposalNotes: {
              type: "string",
              description:
                "1-2 sentences explaining why this decision and any prep needed (rinse, flatten, remove cap, etc.).",
            },
            bbox: {
              type: "object",
              additionalProperties: false,
              required: ["x", "y", "w", "h"],
              description:
                "Tight bounding box around THIS item in the photo, normalized to [0,1] where (0,0) is the TOP-LEFT and (1,1) is the BOTTOM-RIGHT of the image. x,y is the top-left corner of the box; w,h is its width and height. Be tight to the visible silhouette.",
              properties: {
                x: { type: "number", minimum: 0, maximum: 1 },
                y: { type: "number", minimum: 0, maximum: 1 },
                w: { type: "number", minimum: 0, maximum: 1 },
                h: { type: "number", minimum: 0, maximum: 1 },
              },
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
    },
  },
};

/**
 * Hosts that almost never have anything useful for waste classification.
 * Stock-photo, image-aggregator, and pure-listing sites get cited often
 * because they have keyword-rich titles, but their snippets don't
 * actually state any rule or spec — so we drop them at the source.
 */
export const JUNK_HOST_PATTERNS = [
  "alamy.com",
  "shutterstock.com",
  "istockphoto.com",
  "stock.adobe.com",
  "vecteezy.com",
  "dreamstime.com",
  "pinterest.com",
  "youtube.com",
  "youtu.be",
  "tiktok.com",
  "kaggle.com",
  "facebook.com",
  "twitter.com",
  "x.com",
  "instagram.com",
  "amazon.com",
  "ebay.com",
  "etsy.com",
  "alibaba.com",
] as const;

const JUNK_REGEX = JUNK_HOST_PATTERNS.map(
  (host) => new RegExp(`(^|\\.)${host.replace(/\./g, "\\.")}$`, "i"),
);

export function isJunkHost(host: string): boolean {
  return JUNK_REGEX.some((re) => re.test(host));
}

export function isJunkUrl(url: string): boolean {
  try {
    return isJunkHost(new URL(url).hostname.replace(/^www\./, ""));
  } catch {
    return true;
  }
}

/** Snippet must mention an actual disposal action to count as a rule source. */
const RULE_KEYWORDS = /\b(recycl|compost|trash|landfill|garbage|hazard|dispose|curbside|bin|cart)\w*/i;

/** Snippet must mention a unit + plausible material descriptor to count as a spec source. */
const SPEC_KEYWORDS = /\b(\d+(?:\.\d+)?\s*(?:g|grams?|gm|oz|ounces?|lb|kg)|aluminum|plastic|polypropylene|polyethylene|polystyrene|PET|HDPE|LDPE|paper|cardboard|glass)\b/i;

const JUNK_DENYLIST = JUNK_HOST_PATTERNS.map((h) => `-${h}`);

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
            max_results: 5,
            max_tokens_per_page: 2048,
            country: state ? "US" : undefined,
            search_domain_filter: JUNK_DENYLIST,
          }),
        });
        if (!res.ok) return [] as RawSource[];
        const json: any = await res.json();
        const results: any[] = Array.isArray(json?.results) ? json.results : [];
        return results
          .filter((r) => {
            if (typeof r?.url !== "string") return false;
            if (isJunkUrl(r.url)) return false;
            const snippet = typeof r?.snippet === "string" ? r.snippet : "";
            // The page must actually mention a disposal action — otherwise
            // it's a results-shaped 404 that won't justify any decision.
            if (!snippet.trim()) return false;
            if (!RULE_KEYWORDS.test(snippet)) return false;
            return true;
          })
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
    const byUrl = new Map<string, RawSource>();
    for (const s of flat) {
      if (!byUrl.has(s.url)) byUrl.set(s.url, s);
    }
    const sources = Array.from(byUrl.values()).slice(0, 4);
    // Pick the first two snippets, normalize whitespace, drop leading
    // bullet/dash artifacts, and clip to one short sentence each. Each
    // entry is delimited by `||` so the UI can render bullets cleanly.
    const summary = sources
      .slice(0, 2)
      .map((s) => cleanRuleSnippet(s.snippet))
      .filter((line) => line.length > 0)
      .join(" || ");
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
    "You are BinSight, an expert in municipal waste classification. You have REAL tool access: `web_search` (live web queries) and `fetch_url` (read a specific page). USE THESE TOOLS - do not rely on training data when local rules might be stale.",
    "OUTPUT JSON IN THIS EXACT ORDER: `steps` first (live narration), then `sources` (every URL you actually retrieved), then `localRules` (city summary), then `items` LAST (each item's `sourceIndices` references the already-emitted `sources` array). This ordering is critical — the user sees each section appear in real time.",
    "STREAM YOUR `steps` ARRAY FIRST. Each entry is one short, present-tense, user-facing sentence narrating what you are *actually* doing right now. Push them in the order you do the work: looking, recognizing, considering materials, searching the web, finding a rule, deciding. The user is feeling each step land - be honest, specific, and concise.",
    "Identify every distinct waste item visible in the photo.",
    "MUST do at least one `web_search` for the user's specific city + the dominant material/category before deciding (e.g. 'Denver curbside recycling Joy-Con electronics'). MUST `fetch_url` the most authoritative result (municipal .gov page) to confirm the rule.",
    "Cite ONLY URLs you actually retrieved via your tools. Do not invent or recall URLs from memory.",
    "Always populate `localRules` with a 2-4 sentence summary of the user's city's disposal rule for the dominant items. Name the program (e.g. 'Denver Recycles', 'NYC DSNY', 'SFE'). This field is what the user reads at a glance - it must never be empty.",
    "Always include at least one source with kind='rule' (a municipal/.gov page that justifies the disposal decision) and at least one with kind='material' (a manufacturer or spec page that justifies what the item is made of).",
    "ASSUME all photographed items are empty/discarded ready for disposal (e.g. a beverage can pictured here is empty, even if liquid is still visible — the user is about to throw it away). Calculate mass and decisions based on the EMPTY item, not full.",
    "ALWAYS fill the `material` field with the dominant material in lowercase: one of `pet`, `hdpe`, `ldpe`, `pp`, `ps`, `plastic`, `aluminum`, `steel`, `tin`, `paper`, `cardboard`, `newspaper`, `glass`, `organic`, `food`, `yard`, `mixed`. Only use `unknown` if you genuinely cannot tell — an aluminum beverage can is `aluminum`, a plastic water bottle is `pet`, a cardboard box is `cardboard`.",
    "Use the field names `label` (short item name), `material`, `decision`, `confidence`, `estimatedMassG`, `disposalNotes`, `bbox`, `sourceIndices`. Do not rename them.",
    "For EACH item, output a TIGHT bounding box `bbox` around its visible silhouette in the photo, using normalized coordinates [0,1] where (0,0)=top-left and (1,1)=bottom-right. `x,y` is the top-left of the box; `w,h` are its width and height. Pad by no more than ~3% beyond the object's edges. If you genuinely cannot localize, return `{x:0,y:0,w:1,h:1}`.",
    "For each item, decide whether it should be recycled, composted, trashed, or treated as hazardous, given the user's location.",
    "PREDICT each item's EMPTY mass in grams using visual cues (size, shape, wall thickness, material density) and your knowledge of typical product weights. NEVER return 0 - always commit to your best educated estimate. Reference points: empty 12oz aluminum can ~14g, empty 250mL aluminum can ~15g, empty 500mL PET bottle ~10g, empty 12oz glass beer bottle ~190g, empty drinking glass / tumbler 200-400g, empty wine glass 150-220g, empty Mason jar 250-400g, empty cardboard cereal box ~50g, empty pizza box ~80g, empty 15oz steel can ~50g, candy wrapper / chip bag ~3-8g, plastic shopping bag ~6g, banana peel ~40g, apple core ~30g, paper coffee cup with sleeve ~12g, single sheet of letter paper ~5g, AA battery ~23g, AAA battery ~12g, 9V battery ~46g, smartphone ~180g, MacBook laptop ~1400g. Scale these for the item's apparent size in the photo. If you're unsure of exact weight, give your best calibrated guess - your prediction beats a flat default.",
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
  onStage?: (stage: string) => Promise<void> | void,
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
    instructions: systemPrompt(lat, lng, city, state),
    input: [
      {
        role: "user",
        content: [
          { type: "input_text", text: "Classify the items in this photo for disposal." },
          { type: "input_image", image_url: dataUrl },
        ],
      },
    ],
    // Real built-in tools: the model fires actual web_search calls
    // against the live web rather than recalling training-data URLs.
    // SSE emits tool-call events we surface as live stages.
    tools: [
      { type: "web_search" },
      { type: "fetch_url" },
    ],
    text: {
      format: {
        type: "json_schema",
        name: "waste_detection",
        schema: wasteSchema.schema,
      },
    },
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
    const content = extractResponsesText(json);
    let parsed: any = {};
    if (content) {
      try {
        parsed = JSON.parse(content);
      } catch {
        const match = content.match(/\{[\s\S]*\}/);
        if (match) {
          try { parsed = JSON.parse(match[0]); } catch { /* ignore */ }
        }
      }
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
    const txt = await res.text();
    const json: any = (() => { try { return JSON.parse(txt); } catch { return {}; } })();
    const content = extractResponsesText(json);
    let parsed: any = {};
    if (content) { try { parsed = JSON.parse(content); } catch { /* ignore */ } }
    return {
      items: parsed.items ?? [],
      sources: parsed.sources ?? [],
      localRules: parsed.localRules ?? "",
      citations: Array.isArray(json.citations) ? json.citations : [],
      model,
    };
  }

  // Responses-API SSE: each event is a JSON object with a `type` field.
  // We care about `response.output_text.delta` (incremental text in `delta`)
  // and `response.completed` (final response object in `response`).
  const decoder = new TextDecoder();
  let sseBuffer = "";
  let contentBuffer = "";
  let lastEmittedCount = -1;
  let lastEmittedStepCount = 0;
  let lastCitations: string[] = [];
  let finalJson: any = null;
  // Live tool-call source discovery: every URL we see in a tool
  // result or citations array gets pushed here so the iOS pills
  // animate in as the agent searches, not just at the end when
  // the structured `sources[]` finally serializes.
  const liveSources: Array<{ url: string; title: string; publisher: string; snippet: string }> = [];
  const seenUrls = new Set<string>();
  const addSource = (url: string, title?: string, publisher?: string, snippet?: string) => {
    if (!url || typeof url !== "string" || !url.startsWith("http")) return false;
    if (seenUrls.has(url)) return false;
    seenUrls.add(url);
    let host = "";
    try { host = new URL(url).host.replace(/^www\./, ""); } catch {}
    liveSources.push({
      url,
      title: title || host,
      publisher: publisher || host,
      snippet: snippet || "",
    });
    return true;
  };
  const stageNow = async (s: string) => {
    try { await onStage?.(s); } catch { /* never block */ }
  };
  // Push live sources to the writePartial pipeline so iOS sees them.
  // Includes whatever items have already been parsed so the partial
  // write doesn't accidentally wipe the items list.
  const flushLiveSources = async () => {
    if (liveSources.length === 0) return;
    const partial = parsePartialAgentJson(contentBuffer);
    try {
      await onProgress?.({
        items: partial.items ? partial.items.map(normalizeItem) : [],
        sources: liveSources.map((s) => ({ ...s, kind: "rule" as const, isLocal: false, supportsItemIndices: [] })) as any,
        localRules: partial.localRules ?? "",
        citations: lastCitations,
        model,
      });
    } catch { /* never block */ }
  };

  const seenEventTypes = new Set<string>();
  // Recursively walk an event payload and harvest any URL-shaped strings.
  // We don't know the exact tool-result shape Perplexity emits, so we
  // scrape any field that looks like a URL with a title nearby.
  const harvestUrls = (node: any): boolean => {
    let added = false;
    const visit = (n: any) => {
      if (!n) return;
      if (typeof n === "string") {
        if (n.startsWith("http://") || n.startsWith("https://")) {
          if (addSource(n)) added = true;
        }
        return;
      }
      if (Array.isArray(n)) {
        for (const x of n) visit(x);
        return;
      }
      if (typeof n === "object") {
        if (typeof n.url === "string" && n.url.startsWith("http")) {
          // Don't fall back to n.source — Perplexity tool events use that
          // as the channel marker (e.g. "web"), not the publishing org.
          // Let addSource derive publisher from the URL host instead.
          if (addSource(n.url, n.title, n.publisher, n.snippet ?? n.text)) {
            added = true;
          }
        }
        for (const k of Object.keys(n)) {
          if (k === "url") continue;
          visit(n[k]);
        }
      }
    };
    visit(node);
    return added;
  };

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
      if (!data || data === "[DONE]") continue;
      try {
        const ev = JSON.parse(data);
        const type: string | undefined = ev?.type;
        // Log every distinct event type once so we can see what
        // Perplexity actually emits for tool calls.
        if (typeof type === "string" && !seenEventTypes.has(type)) {
          seenEventTypes.add(type);
          console.log(`[sage] sse event type: ${type} keys=${Object.keys(ev).join(",")}`);
        }
        if (type === "response.output_text.delta" && typeof ev.delta === "string") {
          contentBuffer += ev.delta;
        } else if (type === "response.completed" && ev.response) {
          finalJson = ev.response;
          if (Array.isArray(finalJson.citations)) lastCitations = finalJson.citations;
          // Final response may carry the full tool-call/citations bundle.
          if (harvestUrls(finalJson)) await flushLiveSources();
        } else if (Array.isArray(ev?.citations)) {
          lastCitations = ev.citations;
          let added = false;
          for (const c of ev.citations) {
            const url = typeof c === "string" ? c : c?.url;
            if (addSource(url, c?.title, c?.publisher, c?.snippet)) added = true;
          }
          if (added) await flushLiveSources();
        } else if (typeof type === "string") {
          // Best-effort: any non-text-delta event might carry tool URLs.
          // Walk the whole envelope and pluck them out.
          const isToolEvent =
            type.includes("tool") || type.includes("search") ||
            type.includes("citation") || type.includes("web") ||
            type.includes("fetch");
          if (isToolEvent) {
            // Surface a stage line if we can identify the tool.
            const toolName: string | undefined =
              ev?.tool_call?.name || ev?.tool?.name || ev?.name ||
              (type.includes("search") ? "web_search" : type.includes("fetch") ? "fetch_url" : undefined);
            const toolArgs: any =
              ev?.tool_call?.input || ev?.tool?.input || ev?.arguments ||
              ev?.input || ev?.query;
            if (toolName === "web_search") {
              const q = String(toolArgs?.query ?? toolArgs ?? "").slice(0, 70);
              if (type.endsWith(".created") || type.includes("started")) {
                await stageNow(q ? `Searching: ${q}` : "Searching the web");
              } else if (type.endsWith(".completed") || type.includes("output") || type.includes("result")) {
                await stageNow("Reading results");
              }
            } else if (toolName === "fetch_url") {
              const u = String(toolArgs?.url ?? toolArgs ?? "");
              const host = u.replace(/^https?:\/\/(www\.)?/, "").split("/")[0];
              if (type.endsWith(".created") || type.includes("started")) {
                await stageNow(host ? `Reading ${host}` : "Reading page");
              }
            }
            if (harvestUrls(ev)) await flushLiveSources();
          }
        }
      } catch {
        /* ignore non-JSON keepalive lines */
      }
    }

    const partial = parsePartialAgentJson(contentBuffer);
    // Drain newly-completed `steps[]` entries to the UI as soon as
    // each one is parseable. This is the model's own narration of
    // what it's doing, not a synthetic heartbeat.
    const partialSteps: string[] = Array.isArray((partial as any).steps)
      ? (partial as any).steps
      : [];
    if (partialSteps.length > lastEmittedStepCount) {
      for (let i = lastEmittedStepCount; i < partialSteps.length; i++) {
        const s = String(partialSteps[i] ?? "").trim();
        if (s) await stageNow(s);
      }
      lastEmittedStepCount = partialSteps.length;
    }
    if (partial.items && partial.items.length > lastEmittedCount) {
      lastEmittedCount = partial.items.length;
      try {
        await onProgress?.({
          items: partial.items.map(normalizeItem),
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

  // Try parsing both the delta-accumulated buffer AND the authoritative
  // response.completed text (if any) and pick whichever yields more items.
  // This avoids the trap where one source is fuller than the other.
  const candidates: string[] = [];
  if (contentBuffer) candidates.push(contentBuffer);
  if (finalJson) {
    const authoritative = extractResponsesText(finalJson);
    if (authoritative) candidates.push(authoritative);
  }
  const parseAttempts = candidates.map((text) => {
    let p = parsePartialAgentJson(text);
    if (!p.items || p.items.length === 0) {
      try {
        const j = JSON.parse(text);
        if (j && Array.isArray(j.items)) p = j;
      } catch { /* ignore */ }
    }
    return { text, parsed: p };
  });
  parseAttempts.sort(
    (a, b) => (b.parsed.items?.length ?? 0) - (a.parsed.items?.length ?? 0),
  );
  const best = parseAttempts[0] ?? { text: "", parsed: {} as any };
  console.log(
    `[sage] stream finished: candidates=${candidates.map((c) => c.length).join(",")}b chosenItems=${best.parsed.items?.length ?? 0}`,
  );
  if (!best.parsed.items || best.parsed.items.length === 0) {
    console.log(`[sage] no items parsed. text head: ${best.text.slice(0, 1200)}`);
  }
  return {
    items: (best.parsed.items ?? []).map(normalizeItem),
    sources: best.parsed.sources ?? [],
    localRules: best.parsed.localRules ?? "",
    citations: lastCitations,
    model,
  };
}

/**
 * Models occasionally drift to alternate field names despite our schema —
 * e.g. `name` instead of `label`, `category` instead of `decision`,
 * `massGrams`/`mass_g` instead of `estimatedMassG`. Map them back so the
 * downstream pipeline doesn't drop the item.
 */
function normalizeItem(raw: any): RawItem {
  const label = raw?.label ?? raw?.name ?? raw?.title ?? "";
  const material = raw?.material ?? raw?.materialType ?? raw?.material_type ?? "unknown";
  let decision = raw?.decision ?? raw?.category ?? raw?.disposal ?? "trash";
  if (typeof decision === "string") {
    const d = decision.toLowerCase().trim();
    if (d.startsWith("recyc")) decision = "recycle";
    else if (d.startsWith("comp")) decision = "compost";
    else if (d.startsWith("haz")) decision = "hazard";
    else decision = "trash";
  }
  const estimatedMassG =
    raw?.estimatedMassG ?? raw?.massGrams ?? raw?.mass_g ?? raw?.massG ?? raw?.mass ?? 0;
  const bboxRaw = raw?.bbox ?? raw?.boundingBox ?? raw?.bounding_box ?? raw?.box;
  let bbox: RawItem["bbox"];
  if (bboxRaw && typeof bboxRaw === "object") {
    const x = Number(bboxRaw.x ?? bboxRaw.left ?? bboxRaw[0]);
    const y = Number(bboxRaw.y ?? bboxRaw.top ?? bboxRaw[1]);
    const w = Number(bboxRaw.w ?? bboxRaw.width ?? bboxRaw[2]);
    const h = Number(bboxRaw.h ?? bboxRaw.height ?? bboxRaw[3]);
    if ([x, y, w, h].every((n) => Number.isFinite(n) && n >= 0 && n <= 1) && w > 0 && h > 0) {
      bbox = { x, y, w, h };
    }
  }
  return {
    label: String(label),
    material: String(material),
    decision: decision as RawItem["decision"],
    confidence: typeof raw?.confidence === "number" ? raw.confidence : 0,
    estimatedMassG: typeof estimatedMassG === "number" ? estimatedMassG : 0,
    disposalNotes: String(raw?.disposalNotes ?? raw?.notes ?? raw?.disposal_notes ?? ""),
    bbox,
    sourceIndices: Array.isArray(raw?.sourceIndices)
      ? raw.sourceIndices
      : Array.isArray(raw?.source_indices)
        ? raw.source_indices
        : [],
  };
}

/** Pull the assistant text out of a Responses-API JSON body. */
function extractResponsesText(json: any): string {
  if (typeof json?.output_text === "string" && json.output_text) return json.output_text;
  const output = Array.isArray(json?.output) ? json.output : [];
  const parts: string[] = [];
  for (const item of output) {
    const content = Array.isArray(item?.content) ? item.content : [];
    for (const c of content) {
      if (typeof c?.text === "string") parts.push(c.text);
    }
  }
  return parts.join("");
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
  steps?: string[];
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
    steps: collectArray(buf, '"steps"') as string[] | undefined,
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
  let stringStart = -1;
  while (i < buf.length) {
    const c = buf[i];
    if (escape) { escape = false; i++; continue; }
    if (c === "\\") { escape = true; i++; continue; }
    if (c === '"') {
      // String element handling: only at array depth 0 (not inside an object)
      if (depth === 0) {
        if (!inString) {
          inString = true;
          stringStart = i;
        } else {
          inString = false;
          // Completed top-level string element.
          const slice = buf.slice(stringStart, i + 1);
          try { out.push(JSON.parse(slice)); } catch { /* skip */ }
          stringStart = -1;
        }
      } else {
        inString = !inString;
      }
      i++;
      continue;
    }
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
  // Two queries in parallel: a focused spec search (for gram values) and
  // a broader material-identification search (for "what is this thing
  // made of, what does it weigh, what's the typical size"). Combined,
  // they guarantee every item gets at least one material-kind source —
  // even if no extractable gram value shows up anywhere.
  const specQuery = `typical empty mass in grams of ${item.label} (${item.material}) — manufacturer specs`;
  const idQuery = `${item.label} ${item.material} material composition product specs weight`;

  const [specHits, idHits] = await Promise.all([
    runSpecSearch(apiKey, specQuery),
    runSpecSearch(apiKey, idQuery),
  ]);

  // First pass: look for a result with both a relevant snippet AND a
  // plausible gram/oz number. Prefer results from the focused spec query.
  const ordered = [...specHits, ...idHits];
  for (const r of ordered) {
    const url: string | undefined = r?.url;
    if (!url || isJunkUrl(url)) continue;
    const snippet = typeof r?.snippet === "string" ? r.snippet : "";
    if (!snippet.trim() || !SPEC_KEYWORDS.test(snippet)) continue;
    const blob = `${r?.title ?? ""} ${snippet}`;
    const m =
      blob.match(/(\d{1,4}(?:\.\d+)?)\s*(?:g|grams?|gm)\b/i) ||
      blob.match(/(\d{1,2}(?:\.\d+)?)\s*(?:oz|ounces?)\b/i);
    if (!m) continue;
    let grams = parseFloat(m[1]);
    if (m[0].toLowerCase().includes("oz")) grams *= 28.3495;
    if (!Number.isFinite(grams) || grams < 0.5 || grams > 50_000) continue;
    return {
      massG: Number(grams.toFixed(1)),
      source: {
        url,
        title: r?.title,
        publisher: r?.publisher ?? hostFor(url),
        snippet: snippet.slice(0, 480),
        kind: "material",
      },
    };
  }

  // Second pass: no extractable gram value, but still attach a material
  // identification source so the UI can show *something* citing what
  // the object is made of. Mass falls back to the WARM table default.
  for (const r of ordered) {
    const url: string | undefined = r?.url;
    if (!url || isJunkUrl(url)) continue;
    const snippet = typeof r?.snippet === "string" ? r.snippet : "";
    if (!snippet.trim()) continue;
    if (!SPEC_KEYWORDS.test(snippet)) continue;
    return {
      massG: 0,                     // tells caller to fall back to material default
      source: {
        url,
        title: r?.title,
        publisher: r?.publisher ?? hostFor(url),
        snippet: snippet.slice(0, 480),
        kind: "material",
      },
    };
  }

  return undefined;
}

async function runSpecSearch(apiKey: string, query: string): Promise<any[]> {
  try {
    const res = await fetch(SEARCH_URL, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        query,
        max_results: 6,
        max_tokens_per_page: 1024,
        search_domain_filter: JUNK_DENYLIST,
      }),
    });
    if (!res.ok) return [];
    const json: any = await res.json();
    return Array.isArray(json?.results) ? json.results : [];
  } catch {
    return [];
  }
}

/**
 * Turn a raw search snippet into a clean one-sentence rule.
 * Strips leading bullets/dashes, collapses whitespace, takes the first
 * sentence (or first ~140 chars) so the UI can render a tidy line.
 */
function cleanRuleSnippet(raw: string | undefined): string {
  if (!raw) return "";
  const collapsed = raw.replace(/\s+/g, " ").trim();
  let stripped = collapsed.replace(/^[-•*–·▪▸▶►‣◦\s]+/, "").trim();

  // Torn-word heuristic: when a search engine cuts a snippet at the
  // wrong character, you sometimes get a lowercase orphan letter glued
  // to the next capitalized word ("rPrinted on…", "sNo plastic…").
  // Strip a leading single-letter run that's immediately followed by
  // an uppercase letter — that pattern almost never appears naturally
  // in well-formed prose.
  stripped = stripped.replace(/^([a-z]{1,2})(?=[A-Z])/, "").trim();

  // Take first sentence-ish span, then clamp length.
  const firstSentence = stripped.split(/(?<=[.!?])\s+/)[0] ?? stripped;
  const trimmed = firstSentence.length > 160
    ? firstSentence.slice(0, 157).replace(/\s+\S*$/, "") + "…"
    : firstSentence;
  return trimmed;
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

  const insightSchema = {
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
  };
  const body = {
    model,
    instructions: sys,
    input: [{ role: "user", content: [{ type: "input_text", text: user }] }],
    text: { format: { type: "json_schema", name: "weekly_insight", schema: insightSchema } },
  };
  try {
    const res = await fetch(AGENT_URL, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`status ${res.status}`);
    const json: any = await res.json();
    const content = extractResponsesText(json);
    let parsed: any = {};
    if (content) {
      try { parsed = JSON.parse(content); } catch { /* ignore */ }
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
