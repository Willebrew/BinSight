import { v } from "convex/values";
import { action, internalQuery } from "./_generated/server";
import { internal } from "./_generated/api";
import { Id } from "./_generated/dataModel";

const AGENT_URL = "https://api.perplexity.ai/v1/agent";

export type DropoffPlace = {
  name: string;
  address: string;
  notes: string;
  acceptsThisItem: string;
  hours: string;
  phone: string;
  sourceUrl: string;
};

export const _loadRow = internalQuery({
  args: { id: v.id("classifications") },
  handler: async (ctx, { id }) => {
    return await ctx.db.get(id);
  },
});

/**
 * Find the closest *physical* drop-off / take-back locations for a
 * specific scanned item using the Perplexity Agent API. Returns an
 * array of places with full street address so the iOS app can open
 * Apple Maps for navigation.
 */
export const findBest = action({
  args: { classificationId: v.id("classifications") },
  handler: async (
    ctx,
    { classificationId },
  ): Promise<{ places: DropoffPlace[]; query: string }> => {
    const apiKey = process.env.PERPLEXITY_API_KEY;
    if (!apiKey) throw new Error("PERPLEXITY_API_KEY not set on the deployment");

    const row: any = await ctx.runQuery(internal.dropoff._loadRow, {
      id: classificationId as Id<"classifications">,
    });
    if (!row) throw new Error("Scan not found");

    const hazard =
      row.items?.find((i: any) => i.decision === "hazard") ?? row.items?.[0];
    const label = String(hazard?.label ?? "hazardous waste");
    const material = String(hazard?.material ?? "");

    const lat = typeof row.lat === "number" ? row.lat : undefined;
    const lng = typeof row.lng === "number" ? row.lng : undefined;
    const cityState = [row.city, row.state].filter(Boolean).join(", ");
    const where = lat !== undefined && lng !== undefined
      ? `${cityState ? cityState + " " : ""}near coordinates ${lat.toFixed(4)}, ${lng.toFixed(4)}`
      : cityState || "near the user";

    const subject =
      material && !label.toLowerCase().includes(material.toLowerCase())
        ? `${label} (${material})`
        : label;

    const query = `Find the 3 closest physical drop-off / take-back locations that actually accept ${subject} in ${where}.`;

    const instructions = [
      "You are BinSight's drop-off finder. Output STRICT JSON matching the provided schema only - no preamble, no narration, no tool-call syntax, no markdown. Just the JSON object.",
      "Using your training knowledge of US municipal HHW programs and major retailer take-back programs, list 3 SPECIFIC PHYSICAL FACILITIES near the user where they can drop off the scanned item.",
      "Each entry MUST include a real street address that can be pasted into Apple Maps for navigation.",
      "Strongly prefer locations within 30 miles of the user's coordinates. Never list a facility in a different state or metro area.",
      "Prefer in this order: (1) the city's official Household Hazardous Waste / e-waste facility, (2) certified retailer take-back programs with confirmed local stores (Best Buy, Home Depot, Staples, Lowe's, Call2Recycle drop-off points), (3) certified independent recyclers.",
      "Return results sorted closest-first.",
      "If you genuinely don't know any specific local facilities, return an empty `places` array. Never invent or guess street addresses.",
    ].join(" ");

    const schema = {
      type: "object",
      additionalProperties: false,
      required: ["places"],
      properties: {
        places: {
          type: "array",
          minItems: 0,
          maxItems: 5,
          items: {
            type: "object",
            additionalProperties: false,
            required: [
              "name",
              "address",
              "notes",
              "acceptsThisItem",
              "hours",
              "phone",
              "sourceUrl",
            ],
            properties: {
              name: { type: "string", description: "Facility / store name." },
              address: {
                type: "string",
                description:
                  "Full street address suitable for Apple Maps navigation, e.g. '1234 Main St, Denver, CO 80202'.",
              },
              notes: {
                type: "string",
                description:
                  "One-sentence reason this is a good match (1-2 lines max).",
              },
              acceptsThisItem: {
                type: "string",
                description:
                  "Short phrase confirming what they accept that matches the scanned item.",
              },
              hours: { type: "string", description: "Typical hours, may be empty." },
              phone: { type: "string", description: "Phone number, may be empty." },
              sourceUrl: {
                type: "string",
                description: "Authoritative source URL for the facility info.",
              },
            },
          },
        },
      },
    };

    const body: any = {
      model: process.env.PERPLEXITY_MODEL ?? "anthropic/claude-opus-4-7",
      instructions,
      input: [{ role: "user", content: [{ type: "input_text", text: query }] }],
      text: {
        format: {
          type: "json_schema",
          name: "dropoff_locations",
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
      console.error(`[dropoff] agent ${res.status}: ${text.slice(0, 300)}`);
      throw new Error(`Drop-off finder failed (${res.status})`);
    }
    const json: any = await res.json();
    const text = extractText(json);
    let places: DropoffPlace[] = [];
    try {
      const parsed = JSON.parse(text);
      const raw: any[] = Array.isArray(parsed?.places) ? parsed.places : [];
      places = raw
        .map((p) => ({
          name: String(p?.name ?? ""),
          address: String(p?.address ?? ""),
          notes: String(p?.notes ?? ""),
          acceptsThisItem: String(p?.acceptsThisItem ?? ""),
          hours: String(p?.hours ?? ""),
          phone: String(p?.phone ?? ""),
          sourceUrl: String(p?.sourceUrl ?? ""),
        }))
        .filter((p) => p.name && p.address);
    } catch (e) {
      console.error("[dropoff] could not parse agent JSON", e, text.slice(0, 300));
    }
    return { places, query };
  },
});

function extractText(json: any): string {
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
