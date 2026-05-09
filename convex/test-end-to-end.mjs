// End-to-end test: upload sample image -> create classification -> run action -> poll for result.
// Requires CONVEX_URL env var (or .env.local).
import fs from "node:fs";
import path from "node:path";
import { ConvexHttpClient } from "convex/browser";
import { api } from "./_generated/api.js";

const url = process.env.CONVEX_URL || "https://small-gerbil-660.convex.cloud";
const imagePath = process.argv[2];
if (!imagePath) { console.error("usage: node test-end-to-end.mjs <image-path>"); process.exit(1); }
const clientId = "test-client-" + Date.now();

const client = new ConvexHttpClient(url);

console.log("1) Generating upload URL...");
const uploadUrl = await client.mutation(api.files.generateUploadUrl, {});
console.log("   upload URL ok");

console.log("2) Uploading image...");
const buf = fs.readFileSync(imagePath);
const ext = path.extname(imagePath).slice(1).toLowerCase();
const mime = ext === "png" ? "image/png" : ext === "jpg" || ext === "jpeg" ? "image/jpeg" : `image/${ext}`;
const upRes = await fetch(uploadUrl, { method: "POST", headers: { "Content-Type": mime }, body: buf });
if (!upRes.ok) { console.error("upload failed", upRes.status, await upRes.text()); process.exit(1); }
const { storageId } = await upRes.json();
console.log("   storageId:", storageId);

console.log("3) Creating classification row...");
const id = await client.mutation(api.classifications.create, { clientId, storageId });
console.log("   id:", id);

console.log("4) Running classifyWaste action...");
const t0 = Date.now();
await client.action(api.classifyWaste.run, { id, clientId });
console.log(`   action done in ${Date.now() - t0}ms`);

console.log("5) Reading result...");
const row = await client.query(api.classifications.getById, { id, clientId });
console.log(JSON.stringify(row, null, 2));
