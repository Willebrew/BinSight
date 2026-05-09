// Standalone smoke test that mirrors what sage.ts will do.
// Run: PERPLEXITY_API_KEY=... node test-perplexity.mjs <image-path>

import fs from "node:fs";
import path from "node:path";

const CHAT_URL = "https://api.perplexity.ai/chat/completions";
const apiKey = process.env.PERPLEXITY_API_KEY;
if (!apiKey) { console.error("PERPLEXITY_API_KEY required"); process.exit(1); }
const imagePath = process.argv[2];
if (!imagePath) { console.error("usage: node test-perplexity.mjs <image>"); process.exit(1); }

const buf = fs.readFileSync(imagePath);
const ext = path.extname(imagePath).slice(1).toLowerCase();
const mime = ext === "png" ? "image/png" : (ext === "jpg" || ext === "jpeg" ? "image/jpeg" : `image/${ext}`);
const dataUrl = `data:${mime};base64,${buf.toString("base64")}`;

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
            material: { type: "string", description: "pet|hdpe|aluminum|steel|paper|cardboard|glass|organic|mixed|unknown" },
            decision: { type: "string", enum: ["recycle", "trash", "compost", "hazard"] },
            confidence: { type: "number", minimum: 0, maximum: 1 },
            disposalNotes: { type: "string" },
          },
        },
      },
      localRules: { type: "string" },
    },
  },
};

const body = {
  model: "sonar-pro",
  response_format: { type: "json_schema", json_schema: wasteSchema },
  messages: [
    {
      role: "system",
      content:
        "You are BinSight, an expert in municipal waste classification. Identify every distinct waste item visible in the photo. For each item, decide whether it should be recycled, composted, trashed, or treated as hazardous. Use web search when local recycling rules might change the answer. Be conservative.",
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

const t0 = Date.now();
const res = await fetch(CHAT_URL, {
  method: "POST",
  headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
  body: JSON.stringify(body),
});
const json = await res.json();
const ms = Date.now() - t0;

console.log(`Status: ${res.status} (${ms}ms)`);
console.log(`Model: ${json.model}`);
console.log(`Cost: $${json.usage?.cost?.total_cost ?? "?"}`);
console.log(`Citations: ${json.citations?.length ?? 0}`);

const content = json.choices?.[0]?.message?.content;
console.log("\n--- raw content ---");
console.log(content);

if (typeof content === "string") {
  try {
    const parsed = JSON.parse(content);
    console.log("\n--- parsed structured output ---");
    console.log(JSON.stringify(parsed, null, 2));
  } catch (e) {
    console.log("\n(content is not valid JSON)");
  }
}
console.log("\nfirst 3 citations:", (json.citations ?? []).slice(0, 3));
