/**
 * Constants shared across the RAG pipeline. Must match the catalog
 * embedding configuration in Henry's `build_embedding_dataset.py`
 * exactly — otherwise query embeddings live in a different subspace
 * and similarity scores become unreliable.
 *
 * See `DATABASE_HANDOFF.md` for the original spec.
 */

/** Identical to `CONTEXT_PROMPT` in Henry's `build_embedding_dataset.py`. */
export const CONTEXT_PROMPT =
  "Context: This is a reference catalog entry for a mobile app that helps " +
  "users identify recyclable waste items and estimate their environmental " +
  "impact. The following description characterizes a single waste object " +
  "(material, form factor, condition, identifying marks). Embeddings of " +
  "these reference descriptions will be compared via similarity search " +
  "against embeddings of novel user-submitted waste-item descriptions to " +
  "retrieve the closest matching catalog entries.";

/** The exact embedding model used to build the reference catalog. */
export const EMBEDDING_MODEL = "pplx-embed-context-v1-0.6b";

/** Dimensionality matches the catalog. Convex vector index is sized to this. */
export const EMBEDDING_DIM = 1024;

/** Default top-K for retrieval. */
export const TOP_K_DEFAULT = 5;
