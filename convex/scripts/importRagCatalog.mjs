#!/usr/bin/env node
/**
 * One-shot importer for Henry's RAG reference catalog.
 *
 * Reads `recycle_dataset_embedded.parquet` (path passed via --parquet),
 * uploads each row's JPEG to Convex storage, and calls the public
 * `ragCatalog:insertItem` mutation with the row's metadata + 1024-dim
 * embedding.
 *
 * Restartable: on every run we first call `ragCatalog:listFilenames`
 * (internal) and skip rows whose `imageFilename` is already present.
 *
 * Usage:
 *   node scripts/importRagCatalog.mjs \
 *     --parquet ~/Downloads/output.bin \
 *     --convex-url https://small-gerbil-660.convex.cloud \
 *     [--limit 50]   # smoke-test first 50 rows
 *     [--start 0]    # offset for resuming a partial run
 *
 * Or: `CONVEX_URL=...` env var instead of --convex-url.
 *
 * No auth — `insertItem` is intentionally unauthed for one-shot loads.
 * Don't ship a build that exposes this mutation publicly long-term.
 */

import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { ConvexHttpClient } from "convex/browser";
import { parquetReadObjects, parquetMetadataAsync, asyncBufferFromFile } from "hyparquet";
import { compressors } from "hyparquet-compressors";

function parseArgs() {
  const out = {
    parquet: "",
    convexUrl: process.env.CONVEX_URL ?? "",
    limit: 0,
    start: 0,
    adminSecret: process.env.RAG_ADMIN_SECRET ?? "",
  };
  const args = process.argv.slice(2);
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "--parquet") out.parquet = args[++i];
    else if (a === "--convex-url") out.convexUrl = args[++i];
    else if (a === "--limit") out.limit = parseInt(args[++i], 10);
    else if (a === "--start") out.start = parseInt(args[++i], 10);
    else if (a === "--admin-secret") out.adminSecret = args[++i];
  }
  if (!out.parquet) {
    out.parquet = path.join(os.homedir(), "Downloads", "output.bin");
  }
  if (!out.convexUrl) {
    console.error("Need --convex-url or CONVEX_URL env var (e.g. https://small-gerbil-660.convex.cloud).");
    process.exit(1);
  }
  return out;
}

const TEXT_DECODER = new TextDecoder();

function decodeStr(raw) {
  if (raw == null) return "";
  if (typeof raw === "string") return raw;
  if (raw instanceof Uint8Array) return TEXT_DECODER.decode(raw);
  return String(raw);
}

function int8ArrayFromAny(raw) {
  // Henry's `embedding` column is list[float32] (or list[float64] in
  // some builds). Either way hyparquet hands back an iterable of
  // numbers. We coerce to a plain `number[]` since Convex's vector
  // index expects float64.
  if (Array.isArray(raw)) return raw.map((x) => Number(x));
  if (raw && typeof raw === "object" && typeof raw.length === "number") {
    return Array.from(raw, (x) => Number(x));
  }
  throw new Error(`Unexpected embedding type: ${typeof raw}`);
}

function uint8ArrayFromAny(raw) {
  // With utf8:false in parquetReadObjects, BYTE_ARRAY columns come
  // back as Uint8Array.
  if (raw instanceof Uint8Array) return raw;
  if (raw && typeof raw === "object" && typeof raw.length === "number") {
    return new Uint8Array(raw);
  }
  throw new Error(`Unexpected image type: ${typeof raw}`);
}

async function uploadBlob(uploadUrl, bytes, contentType = "image/jpeg") {
  const res = await fetch(uploadUrl, {
    method: "POST",
    headers: { "Content-Type": contentType },
    body: bytes,
  });
  if (!res.ok) {
    throw new Error(`upload failed ${res.status}: ${(await res.text()).slice(0, 200)}`);
  }
  const json = await res.json();
  if (!json?.storageId) throw new Error("upload response missing storageId");
  return json.storageId;
}

async function main() {
  const { parquet, convexUrl, limit, start, adminSecret } = parseArgs();

  console.log(`Parquet : ${parquet}`);
  console.log(`Convex  : ${convexUrl}`);
  console.log(`Range   : start=${start} limit=${limit || "all"}`);
  console.log();

  // 0. Sanity: parquet exists.
  await fs.access(parquet);

  // 1. Connect to Convex.
  const client = new ConvexHttpClient(convexUrl);

  // 2. Build the skip-set so re-runs don't double-import.
  console.log("Reading existing filenames from Convex (paginated)…");
  const existing = new Set();
  let cursor = null;
  for (let page = 0; page < 200; page++) {
    const res = await client.query("ragCatalog:listFilenamesPage", { cursor });
    for (const f of res.filenames ?? []) existing.add(f);
    if (!res.cursor) break;
    cursor = res.cursor;
  }
  console.log(`Already in catalog: ${existing.size}`);

  // 3. Read parquet rows.
  console.log("Opening parquet…");
  const file = await asyncBufferFromFile(parquet);
  const meta = await parquetMetadataAsync(file);
  const totalRows = Number(meta.num_rows);
  console.log(`Total rows in catalog: ${totalRows}`);

  const rowEnd = limit > 0 ? Math.min(totalRows, start + limit) : totalRows;
  console.log(`Will import rows [${start}, ${rowEnd})`);
  console.log();

  // hyparquet streams in row-group chunks; we just collect all needed
  // columns. ~125MB parquet decompressed is fine in memory.
  // utf8:false because the `image` column is binary JPEG bytes — if
  // hyparquet stringifies it the bytes are mangled past recovery. We
  // decode the real text columns ourselves below via decodeStr().
  const rows = await parquetReadObjects({
    file,
    rowStart: start,
    rowEnd: rowEnd,
    compressors,
    utf8: false,
  });

  // 4. Per-row: upload image, call insertItem.
  let inserted = 0;
  let skipped = 0;
  let failed = 0;
  for (let i = 0; i < rows.length; i++) {
    const r = rows[i];
    const idx = start + i;
    const filename = decodeStr(r.image_filename);
    if (!filename) {
      console.warn(`  [${idx}] row missing image_filename — skip`);
      skipped++;
      continue;
    }
    if (existing.has(filename)) {
      skipped++;
      continue;
    }
    try {
      const imgBytes = uint8ArrayFromAny(r.image);
      const embedding = int8ArrayFromAny(r.embedding);
      if (embedding.length !== 1024) {
        throw new Error(`embedding dim ${embedding.length} != 1024`);
      }
      const uploadUrl = await client.mutation("ragCatalog:generateUploadUrl", { adminSecret });
      const storageId = await uploadBlob(uploadUrl, imgBytes);
      await client.mutation("ragCatalog:insertItem", {
        adminSecret,
        imageFilename: filename,
        imageSha256: decodeStr(r.image_sha256),
        imageStorageId: storageId,
        objectName: decodeStr(r.object_name),
        objectDescription: decodeStr(r.object_description),
        materialWarm: decodeStr(r.material_warm),
        massGrams: Number(r.mass_grams ?? 0),
        materialConfidence: decodeStr(r.material_confidence),
        co2SavedKg: Number(r.co2_saved_kg ?? 0),
        warmFactorKgco2ePerKg: Number(r.warm_factor_kgco2e_per_kg ?? 0),
        citationsJson: decodeStr(r.citations_json),
        materialReasoning: decodeStr(r.material_reasoning),
        overallConfidence: decodeStr(r.overall_confidence),
        researchSummary: decodeStr(r.research_summary),
        estimatedTotalMassGrams: Number(r.estimated_total_mass_grams ?? 0),
        unaccountedMassGramsNote: decodeStr(r.unaccounted_mass_grams_note),
        embedding,
        model: decodeStr(r.model),
        processedAtUtc: decodeStr(r.processed_at_utc),
      });
      inserted++;
      if (inserted % 20 === 0 || i === rows.length - 1) {
        const pct = ((idx + 1) / totalRows * 100).toFixed(1);
        console.log(`  [${String(idx).padStart(5)}] ${filename} ✓   (${inserted} inserted, ${skipped} skipped, ${failed} failed, ${pct}%)`);
      }
    } catch (e) {
      failed++;
      console.warn(`  [${idx}] ${filename} ✗  ${e.message}`);
    }
  }

  console.log();
  console.log(`Done. inserted=${inserted}  skipped=${skipped}  failed=${failed}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
