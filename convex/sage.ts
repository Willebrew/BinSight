// Perplexity classifier for BinSight.
//
// Uses /chat/completions with sonar-pro: web search is built into the model,
// citations are returned at the top level, and it accepts vision inputs in
// OpenAI-style `image_url` format. The Agent API endpoint (/v1/agent) was
// considered but rejects vision models — sonar via chat completions is the
// supported path today (validated against /Users/.../product-jpeg-500x500.png).
//
// Env: PERPLEXITY_API_KEY  (set via `npx convex env set PERPLEXITY_API_KEY ...`)
//      PERPLEXITY_MODEL    (optional override; default "sonar-pro")

const CHAT_URL = "https://api.perplexity.ai/chat/completions";
const SEARCH_URL = "https://api.perplexity.ai/search";

export type RawItem = {
  label: string;
  material: string;
  decision: "recycle" | "trash" | "compost" | "hazard";
  confidence: number;
  disposalNotes: string;
};

export type AgentResult = {
  items: RawItem[];
  localRules: string;
  citations: string[];
  model: string;
};

const wasteSchema = {
  schema: {
    type: "object",
    additionalProperties: false,
    required: ["items", "localRules"],
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["label", "material", "decision", "confidence", "disposalNotes"],
          properties: {
            label: { type: "string" },
            material: {
              type: "string",
              description:
                "One of: pet, hdpe, aluminum, steel, paper, cardboard, glass, organic, mixed, unknown",
            },
            decision: {
              type: "string",
              enum: ["recycle", "trash", "compost", "hazard"],
            },
            confidence: { type: "number", minimum: 0, maximum: 1 },
            disposalNotes: { type: "string" },
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

function systemPrompt(lat?: number, lng?: number): string {
  const loc =
    lat !== undefined && lng !== undefined
      ? `User location: ${lat.toFixed(3)}, ${lng.toFixed(3)}.`
      : "Location unknown.";
  return [
    "You are BinSight, an expert in municipal waste classification.",
    "Identify every distinct waste item visible in the photo.",
    "For each item, decide whether it should be recycled, composted, trashed, or treated as hazardous, given the user's location.",
    "Search the web when local recycling rules might change the answer (e.g. plastic film, glass, batteries).",
    "Be conservative: if a container is contaminated with food and the local program rejects contaminated items, mark as trash.",
    loc,
  ].join(" ");
}

export async function classifyImage(
  imageBytes: ArrayBuffer,
  contentType: string,
  lat?: number,
  lng?: number,
): Promise<AgentResult> {
  const apiKey = process.env.PERPLEXITY_API_KEY;
  if (!apiKey) {
    throw new Error("PERPLEXITY_API_KEY is not set on this Convex deployment");
  }
  const model = process.env.PERPLEXITY_MODEL ?? "sonar-pro";

  const base64 = arrayBufferToBase64(imageBytes);
  const dataUrl = `data:${contentType || "image/jpeg"};base64,${base64}`;

  const body = {
    model,
    response_format: { type: "json_schema", json_schema: wasteSchema },
    messages: [
      { role: "system", content: systemPrompt(lat, lng) },
      {
        role: "user",
        content: [
          { type: "text", text: "Classify the items in this photo for disposal." },
          { type: "image_url", image_url: { url: dataUrl } },
        ],
      },
    ],
  };

  const res = await fetch(CHAT_URL, {
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
  const json: any = await res.json();

  const parsed = extractStructured(json);
  const citations: string[] = Array.isArray(json.citations) ? json.citations : [];
  return {
    items: parsed.items ?? [],
    localRules: parsed.localRules ?? "",
    citations,
    model,
  };
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

function extractStructured(json: any): { items?: RawItem[]; localRules?: string } {
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
