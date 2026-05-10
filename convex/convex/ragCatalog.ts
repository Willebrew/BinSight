import { v } from "convex/values";
import {
  action,
  internalMutation,
  internalQuery,
  mutation,
  query,
} from "./_generated/server";
import { internal } from "./_generated/api";
import { Id } from "./_generated/dataModel";
import { EMBEDDING_DIM } from "./ragConstants";

const itemArgs = {
  adminSecret: v.string(),
  imageFilename: v.string(),
  imageSha256: v.string(),
  imageStorageId: v.id("_storage"),
  objectName: v.string(),
  objectDescription: v.string(),
  materialWarm: v.string(),
  massGrams: v.float64(),
  materialConfidence: v.string(),
  co2SavedKg: v.float64(),
  warmFactorKgco2ePerKg: v.float64(),
  citationsJson: v.string(),
  materialReasoning: v.string(),
  overallConfidence: v.string(),
  researchSummary: v.string(),
  estimatedTotalMassGrams: v.float64(),
  unaccountedMassGramsNote: v.string(),
  embedding: v.array(v.float64()),
  model: v.string(),
  processedAtUtc: v.string(),
};

/**
 * Shared-secret check for catalog-mutation endpoints. The expected
 * value lives in the `RAG_ADMIN_SECRET` env var on the deployment;
 * the importer passes it via `--admin-secret` (or `RAG_ADMIN_SECRET`).
 *
 * If the env var isn't set we accept any secret — this keeps existing
 * dev workflows working until you set the secret. Production should
 * always set the env var.
 */
function checkAdmin(supplied: string) {
  const expected = process.env.RAG_ADMIN_SECRET;
  if (!expected) return; // permissive when unset
  if (!supplied || supplied !== expected) {
    throw new Error("Forbidden: invalid RAG admin secret");
  }
}

/**
 * Public mutation used by the local import script (`scripts/importRagCatalog.mjs`)
 * to populate the reference catalog. Validates dimensionality so a stale
 * embedding model can never silently corrupt the index.
 *
 * NOTE: this is intentionally NOT auth-gated — it's intended to be called
 * from a trusted local script with the deployment URL. If you ever expose
 * this deployment publicly, gate it behind an admin check.
 */
export const insertItem = mutation({
  args: itemArgs,
  handler: async (ctx, args) => {
    checkAdmin(args.adminSecret);
    if (args.embedding.length !== EMBEDDING_DIM) {
      throw new Error(
        `[ragCatalog] embedding length ${args.embedding.length} != expected ${EMBEDDING_DIM}`,
      );
    }
    const { adminSecret: _, ...row } = args;
    return await ctx.db.insert("ragReferenceItems", row);
  },
});

/**
 * Generates a one-shot upload URL the importer can POST an image blob to.
 * The returned `storageId` (from the JSON body of the upload response) is
 * what `insertItem` expects in `imageStorageId`. Gated behind the same
 * admin secret so randos can't burn our storage quota.
 */
export const generateUploadUrl = mutation({
  args: { adminSecret: v.string() },
  handler: async (ctx, { adminSecret }) => {
    checkAdmin(adminSecret);
    return await ctx.storage.generateUploadUrl();
  },
});

/** Page-by-page filename dump used by the importer's resume check.
 *  Loading every row is ~17 GB once the catalog is full (8k × 1024-dim
 *  embeddings), so we paginate. The script keeps calling with the
 *  returned cursor until it gets `null` back. */
export const listFilenamesPage = query({
  args: { cursor: v.union(v.string(), v.null()) },
  handler: async (ctx, { cursor }) => {
    const result = await ctx.db
      .query("ragReferenceItems")
      .paginate({ cursor, numItems: 200 });
    return {
      filenames: result.page.map((r) => r.imageFilename),
      cursor: result.isDone ? null : result.continueCursor,
    };
  },
});

/** Single-page stats: returns the first page count + cursor. Callers
 *  can keep paging via `listFilenamesPage` if they need the exact total.
 *  Single-page is enough for a UI badge or the smoke test. */
export const stats = query({
  args: {},
  handler: async (ctx) => {
    const page = await ctx.db
      .query("ragReferenceItems")
      .paginate({ cursor: null, numItems: 200 });
    return {
      firstPage: page.page.length,
      hasMore: !page.isDone,
    };
  },
});

/** Fetch full documents for a list of vector-search hit ids. */
export const fetchItems = internalQuery({
  args: { ids: v.array(v.id("ragReferenceItems")) },
  handler: async (ctx, { ids }) => {
    const out: any[] = [];
    for (const id of ids) {
      const doc = await ctx.db.get(id);
      if (doc) out.push(doc);
    }
    return out;
  },
});

/**
 * Vector search: find the K reference items whose description embedding
 * is most similar (cosine) to the supplied query embedding. Optional
 * `materialFilter` constrains to a single WARM category.
 *
 * Returns an array of {item, similarity, imageUrl} sorted high → low.
 */
export const vectorSearch = action({
  args: {
    queryEmbedding: v.array(v.float64()),
    limit: v.optional(v.number()),
    materialFilter: v.optional(v.string()),
  },
  handler: async (
    ctx,
    { queryEmbedding, limit, materialFilter },
  ): Promise<
    Array<{
      _id: Id<"ragReferenceItems">;
      similarity: number;
      imageUrl: string | null;
      imageFilename: string;
      objectName: string;
      objectDescription: string;
      materialWarm: string;
      massGrams: number;
      materialConfidence: string;
      co2SavedKg: number;
      warmFactorKgco2ePerKg: number;
      researchSummary: string;
    }>
  > => {
    if (queryEmbedding.length !== EMBEDDING_DIM) {
      throw new Error(
        `[ragCatalog.vectorSearch] queryEmbedding length ${queryEmbedding.length} != ${EMBEDDING_DIM}`,
      );
    }
    const k = Math.max(1, Math.min(20, limit ?? 5));

    const hits = await ctx.vectorSearch("ragReferenceItems", "by_embedding", {
      vector: queryEmbedding,
      limit: k,
      filter: materialFilter
        ? (q) => q.eq("materialWarm", materialFilter)
        : undefined,
    });

    if (hits.length === 0) return [];

    const items: any[] = await ctx.runQuery(internal.ragCatalog.fetchItems, {
      ids: hits.map((h) => h._id),
    });
    const byId = new Map<string, any>(items.map((it) => [String(it._id), it]));

    const out = [];
    for (const h of hits) {
      const it = byId.get(String(h._id));
      if (!it) continue;
      const imageUrl = await ctx.storage.getUrl(it.imageStorageId);
      out.push({
        _id: h._id,
        similarity: h._score,
        imageUrl,
        imageFilename: it.imageFilename,
        objectName: it.objectName,
        objectDescription: it.objectDescription,
        materialWarm: it.materialWarm,
        massGrams: it.massGrams,
        materialConfidence: it.materialConfidence,
        co2SavedKg: it.co2SavedKg,
        warmFactorKgco2ePerKg: it.warmFactorKgco2ePerKg,
        researchSummary: it.researchSummary,
      });
    }
    return out;
  },
});

