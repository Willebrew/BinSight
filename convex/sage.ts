// SAGE-routed call into the Perplexity Agent API for waste classification.
// Returns a typed structured object; web_search tool enabled so the model can
// pull location-specific recycling rules.
//
// Env: PERPLEXITY_API_KEY (set via `npx convex env set PERPLEXITY_API_KEY ...`)
//      PERPLEXITY_MODEL    (optional override; default claude-opus-4-7)

const AGENT_URL = "https://api.perplexity.ai/v1/agent";
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
  name: "waste_detection",
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
    "Use web_search when local recycling rules might change the answer (e.g. plastic film, glass, batteries).",
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
  const model = process.env.PERPLEXITY_MODEL ?? "claude-opus-4-7";

  const base64 = arrayBufferToBase64(imageBytes);
  const dataUrl = `data:${contentType || "image/jpeg"};base64,${base64}`;

  const body = {
    model,
    tools: ["web_search"],
    response_format: { type: "json_schema", json_schema: wasteSchema },
    messages: [
      { role: "system", content: systemPrompt(lat, lng) },
      {
        role: "user",
        content: [
          {
            type: "input_text",
            text: "Classify the items in this photo for disposal.",
          },
          { type: "input_image", image_url: dataUrl },
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
    const text = await res.text();
    throw new Error(`Perplexity Agent API ${res.status}: ${text.slice(0, 500)}`);
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
 * Lightweight verification call: ask the Search API to confirm the top item's
 * recyclability. Returns true if any of the top results contain a matching
 * decision keyword. Best-effort; failures are non-fatal upstream.
 */
export async function verifyTopItem(item: RawItem): Promise<boolean> {
  const apiKey = process.env.PERPLEXITY_API_KEY;
  if (!apiKey) return false;
  const query = `Is a ${item.label} (${item.material}) ${item.decision === "recycle" ? "recyclable" : item.decision}?`;
  const res = await fetch(SEARCH_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ query, max_results: 5 }),
  });
  if (!res.ok) return false;
  const json: any = await res.json();
  const blob = JSON.stringify(json).toLowerCase();
  if (item.decision === "recycle") return blob.includes("recycl");
  if (item.decision === "compost") return blob.includes("compost");
  if (item.decision === "hazard") return blob.includes("hazard") || blob.includes("battery");
  return blob.includes("trash") || blob.includes("landfill");
}

function extractStructured(json: any): { items?: RawItem[]; localRules?: string } {
  // Agent API returns content in a few different shapes depending on model.
  // Try the common ones in order; fall back to scanning for a JSON blob.
  const candidates: any[] = [];
  if (json.output_parsed) candidates.push(json.output_parsed);
  if (json.parsed) candidates.push(json.parsed);
  const choice = json.choices?.[0];
  if (choice?.message?.parsed) candidates.push(choice.message.parsed);
  const content = choice?.message?.content;
  if (typeof content === "string") {
    try {
      candidates.push(JSON.parse(content));
    } catch {
      const match = content.match(/\{[\s\S]*\}/);
      if (match) {
        try {
          candidates.push(JSON.parse(match[0]));
        } catch {
          /* ignore */
        }
      }
    }
  } else if (Array.isArray(content)) {
    for (const part of content) {
      if (part?.type === "output_text" && typeof part.text === "string") {
        try {
          candidates.push(JSON.parse(part.text));
        } catch {
          /* ignore */
        }
      }
    }
  }
  for (const c of candidates) {
    if (c && Array.isArray(c.items)) return c;
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
  // btoa is available in Convex's V8 runtime.
  return btoa(binary);
}
