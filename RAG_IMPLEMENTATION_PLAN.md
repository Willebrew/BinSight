# BinSight RAG Database Implementation Plan

## Overview
Integrate Henry's RAG dataset (~7k reference waste items with embeddings) into BinSight to improve mass estimation accuracy through semantic similarity retrieval.

## 🎯 Key Architecture Update: Convex Native Vector Search

**This plan uses Convex's built-in vector search** instead of the original Parquet + in-memory numpy approach. This provides:
- ✅ **Native integration** - no external dependencies
- ✅ **Automatic scaling** - Convex handles performance
- ✅ **Built-in filtering** - filter by material type efficiently
- ✅ **Consistent & real-time** - always up-to-date
- ✅ **Simpler implementation** - less code to maintain

The vector search uses Convex's `vectorIndex` in the schema and `ctx.vectorSearch` API in actions, leveraging approximate nearest neighbor search with cosine similarity.

## Dataset Summary
- **Format**: Apache Parquet (`recycle_dataset_embedded.parquet`)
- **Size**: ~7k (image, material) pairs
- **Embeddings**: 2560-dim using Perplexity `pplx-embed-context-v1-4b` (already embedded by Henry)
- **Content**: Reference images, mass estimates, EPA WARM materials, CO2 calculations, citations
- **Purpose**: Retrieve similar reference items to improve novel waste item mass estimation

**Critical Requirement**: Query embeddings must use the **exact same model** (`pplx-embed-context-v1-4b`) and **context prompt** as the catalog embeddings for vector search to work correctly.

## Architecture Decisions

### 1. Storage Strategy - **UPDATED: Use Convex Native Vector Search**
**Convex Vector Search (Recommended)**
- Store each reference item as a document in a Convex table with vector index
- Use Convex's built-in `vectorIndex` and `ctx.vectorSearch` API
- Leverage cosine similarity via Convex's approximate nearest neighbor search
- **Pros**: Native integration, no external dependencies, automatic scaling, built-in filtering, consistent and always up-to-date
- **Cons**: None - this is the optimal approach for Convex

**This replaces the original plan** that used Parquet storage + in-memory numpy. Convex's vector search is purpose-built for exactly this use case and provides better performance, scalability, and developer experience.

### 2. Integration Points
The RAG retrieval should happen **after** vision classification but **before** final mass estimation in the classification pipeline:

```
Current Flow:
1. Vision classification → items with material/decision
2. Default mass estimation (from impactTable.ts)
3. CO2 calculation

New Flow:
1. Vision classification → items with material/decision
2. Generate description for each detected item
3. RAG retrieval: find similar reference items via embedding similarity
4. Model estimates mass based on retrieved samples
5. CO2 calculation (using RAG-estimated masses)
```

## Implementation Plan

### Phase 1: Convex Backend Setup

#### 1.1 Schema Changes (`convex/convex/schema.ts`)
```typescript
// Add new table for RAG reference items with vector search
ragReferenceItems: defineTable({
  // Image data
  imageFilename: v.string(),
  imageSha256: v.string(),
  imageStorageId: v.id("_storage"),  // Store image in Convex storage

  // Reference data from Henry's dataset
  objectName: v.string(),
  objectDescription: v.string(),
  materialWarm: v.string(),          // EPA WARM material category
  massGrams: v.float64(),
  materialConfidence: v.string(),
  co2SavedKg: v.float64(),
  warmFactorKgco2ePerKg: v.float64(),
  citationsJson: v.string(),         // JSON string of citations
  materialReasoning: v.string(),
  overallConfidence: v.string(),
  researchSummary: v.string(),
  estimatedTotalMassGrams: v.float64(),
  unaccountedMassGramsNote: v.string(),

  // Embedding for vector search (already embedded by Henry)
  embedding: v.array(v.float64()),   // 2560-dim embedding from pplx-embed-context-v1-4b

  // Metadata
  model: v.string(),
  processedAtUtc: v.string(),
}).vectorIndex("by_embedding", {
  vectorField: "embedding",
  dimensions: 2560,                  // Match Henry's embedding model (pplx-embed-context-v1-4b)
  filterFields: ["materialWarm"],    // Enable filtering by material type
}),
```

#### 1.2 New Convex Files

**`convex/convex/ragCatalog.ts`** - RAG reference catalog management
- `importReferenceItems` - Import items from Henry's Parquet into Convex
- `vectorSearch` - Perform vector search using Convex's native API
- `getReferenceItem` - Retrieve full item details by filename
- `getItemByFilename` - Get item details for UI display

**`convex/convex/ragPipeline.ts`** - RAG integration into classification
- `generateItemDescription` - Generate visual description of detected item
- `retrieveSimilarItems` - RAG retrieval using Convex vector search
- `estimateMassFromContext` - Estimate mass using retrieved samples
- `classifyWithRAG` - Enhanced classification action integrating RAG

#### 1.3 Dependencies
**No additional dependencies needed!** Convex's vector search is built-in. We only need:
- Existing `@perplexity-ai/perplexity_ai` for embeddings
- Existing `convex` package (v1.38.0+) which includes vector search

### Phase 2: RAG Retrieval Implementation

#### 2.1 Context Prompt Constants
**`convex/convex/ragConstants.ts`**
```typescript
export const CONTEXT_PROMPT =
  "Context: This is a reference catalog entry for a mobile app that helps " +
  "users identify recyclable waste items and estimate their environmental " +
  "impact. The following description characterizes a single waste object " +
  "(material, form factor, condition, identifying marks). Embeddings of " +
  "these reference descriptions will be compared via similarity search " +
  "against embeddings of novel user-submitted waste-item descriptions to " +
  "retrieve the closest matching catalog entries.";

export const EMBEDDING_MODEL = "pplx-embed-context-v1-4b";  // Updated to match Henry's model
export const EMBEDDING_DIM = 2560;  // Updated from 1024 to match Henry's embeddings
export const TOP_K_DEFAULT = 5;
```

#### 2.2 Import Reference Items
**`convex/convex/ragCatalog.ts`**
```typescript
import { action, internalAction } from "./_generated/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";

// Import items from Henry's Parquet file into Convex with vector search
export const importReferenceItems = internalAction({
  handler: async (ctx) => {
    // 1. Read Parquet file (using a library like 'parquet-js' or convert to JSON)
    const parquetData = await readParquetFile("recycle_dataset_embedded.parquet");

    // 2. For each row, create a Convex document with embedding
    for (const row of parquetData) {
      // Store image in Convex storage
      const imageStorageId = await ctx.storage.store(
        Buffer.from(row.image),
        "image/jpeg"
      );

      // Insert document with vector embedding
      await ctx.runMutation(internal.ragCatalog.insertItem, {
        imageFilename: row.image_filename,
        imageSha256: row.image_sha256,
        imageStorageId: imageStorageId,
        objectName: row.object_name,
        objectDescription: row.object_description,
        materialWarm: row.material_warm,
        massGrams: row.mass_grams,
        materialConfidence: row.material_confidence,
        co2SavedKg: row.co2_saved_kg,
        warmFactorKgco2ePerKg: row.warm_factor_kgco2e_per_kg,
        citationsJson: row.citations_json,
        materialReasoning: row.material_reasoning,
        overallConfidence: row.overall_confidence,
        researchSummary: row.research_summary,
        estimatedTotalMassGrams: row.estimated_total_mass_grams,
        unaccountedMassGramsNote: row.unaccounted_mass_grams_note,
        embedding: row.embedding,  // 1024-dim array
        model: row.model,
        processedAtUtc: row.processed_at_utc,
      });
    }
  },
});

// Helper mutation to insert individual items
export const insertItem = internalMutation({
  args: {
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
  },
  handler: async (ctx, args) => {
    await ctx.db.insert("ragReferenceItems", args);
  },
});
```

#### 2.3 Vector Search using Convex Native API
```typescript
export const vectorSearch = action({
  args: {
    queryEmbedding: v.array(v.float64()),
    limit: v.optional(v.number()),
    materialFilter: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { queryEmbedding, limit = 5, materialFilter } = args;

    // Use Convex's native vector search
    // Note: Convex handles cosine similarity internally for vector search
    // Perplexity embeddings are unnormalized but Convex normalizes for comparison
    const results = await ctx.vectorSearch("ragReferenceItems", "by_embedding", {
      vector: queryEmbedding,
      limit: limit,
      filter: materialFilter
        ? (q) => q.eq("materialWarm", materialFilter)
        : undefined,
    });

    // Fetch full documents for the results
    const items = await ctx.runQuery(internal.ragCatalog.fetchItems, {
      ids: results.map((r) => r._id),
    });

    // Combine with scores
    return items.map((item, index) => ({
      ...item,
      similarity: results[index]._score,  // Cosine similarity score (-1 to 1)
      imageUrl: await ctx.storage.getUrl(item.imageStorageId),
    }));
  },
});

export const fetchItems = internalQuery({
  args: { ids: v.array(v.id("ragReferenceItems")) },
  handler: async (ctx, { ids }) => {
    const items = [];
    for (const id of ids) {
      const item = await ctx.db.get(id);
      if (item) items.push(item);
    }
    return items;
  },
});
```

### Phase 3: Classification Pipeline Integration

#### 3.1 Enhanced Classification Action
Modify `convex/convex/classifyWaste.ts`:

```typescript
export const runWithRAG = action({
  args: { id: v.id("classifications") },
  handler: async (ctx, { id }) => {
    // ... existing vision classification ...

    // NEW: For each detected item, perform RAG retrieval
    const enhancedItems = await Promise.all(
      agent.items.map(async (item) => {
        // Generate visual description
        const description = await generateItemDescription(
          bytes,
          item.label,
          item.material
        );

        // Embed description using Perplexity API with SAME model and context as catalog
        // IMPORTANT: Use pplx-embed-context-v1-4b with CONTEXT_PROMPT to match catalog embeddings
        const embedding = await embedDescription(description);

        // Retrieve similar items using Convex's vector search
        const similarItems = await ctx.runAction(
          internal.ragCatalog.vectorSearch,
          {
            queryEmbedding: embedding,
            limit: 5,
            materialFilter: item.material, // Optional: filter by material type
          }
        );

        // Estimate mass from context
        const massEstimate = await estimateMassFromContext(
          item,
          similarItems,
          description
        );

        return {
          ...item,
          estimatedMassG: massEstimate.massGrams,
          massSource: massEstimate.source, // "rag" | "model" | "default"
          ragContext: {
            description,
            similarItems: similarItems.slice(0, 3), // Store top 3 for UI
            needsResearch: massEstimate.needsResearch,
          },
        };
      })
    );

    // Continue with existing CO2 calculation using RAG masses
    // ...
  },
});
```

#### 3.2 Embedding Generation for Queries
**`convex/convex/ragPipeline.ts`**
```typescript
import { Perplexity } from "@perplexity-ai/perplexity_ai";

// Generate embedding for new descriptions using the SAME model as catalog
async function embedDescription(description: string): Promise<number[]> {
  const client = new Perplexity();

  // Use contextualized embeddings with the same CONTEXT_PROMPT as catalog
  const response = await client.contextualized_embeddings.create({
    model: "pplx-embed-context-v1-4b",  // Must match catalog model
    input: [[CONTEXT_PROMPT, description]],  // Same context structure
  });

  // Extract the embedding (chunk index 1 is the description, chunk 0 is context)
  const chunks = response.data[0].data;
  const descChunk = chunks.find((c) => c.index === 1) || chunks[1];

  // Decode from base64_int8 to float array
  return decodeBase64Int8Embedding(descChunk.embedding);
}

// Helper to decode Perplexity's base64_int8 format
function decodeBase64Int8Embedding(base64: string): number[] {
  const buffer = Buffer.from(base64, 'base64');
  const int8Array = new Int8Array(buffer);
  return Array.from(int8Array).map((val) => val as number);
}
```

#### 3.2 Description Generation
Use the vision model to generate detailed descriptions:

```typescript
async function generateItemDescription(
  imageBytes: ArrayBuffer,
  label: string,
  material: string
): Promise<string> {
  // Call Perplexity Agent API with vision
  // Prompt: "Describe this waste item in detail: material, form factor, 
  // condition, identifying marks. Label: {label}, Material: {material}"
  // Return 1-paragraph description
}
```

#### 3.3 Mass Estimation with Context
```typescript
async function estimateMassFromContext(
  item: RawItem,
  similarItems: ReferenceItem[],
  description: string
): Promise<{
  massGrams: number;
  source: "rag" | "model" | "default";
  needsResearch: boolean;
}> {
  // Call vision model with:
  // - Original image
  // - Retrieved reference images (top 3)
  // - Reference masses
  // - Prompt: "Estimate mass in grams for this item based on similar 
  //   reference items. Reference items: [details]. If uncertain, set 
  //   needsResearch=true and we'll perform additional lookup."
  
  // Return structured output with mass estimate and research flag
}
```

### Phase 4: iOS App Changes

#### 4.1 Models Update (`BinSight/Services/Models.swift`)
```swift
struct ItemDoc: Codable, Hashable, Identifiable {
    // ... existing fields ...
    
    // NEW: RAG context fields
    var ragDescription: String?
    var ragSimilarItems: [SimilarItemReference]?
    var needsResearch: Bool?
}

struct SimilarItemReference: Codable, Hashable, Identifiable {
    var filename: String
    var similarity: Double
    var massGrams: Double
    var material: String
    var id: String { filename }
}
```

#### 4.2 UI Enhancements
**Result Card View** - Show RAG context when available:
- Display "Estimated from similar items" when mass source is "rag"
- Show top 3 similar reference items with thumbnails
- Add "Research more" button if `needsResearch` is true
- Show confidence boost from RAG retrieval

#### 4.3 Research Flow (Optional)
If `needsResearch` is true, trigger additional Perplexity Search API calls to:
- Look up manufacturer specifications
- Find product pages with weight info
- Cross-reference with multiple sources

### Phase 5: Catalog Management

#### 5.1 Initial Catalog Import
Create migration script to import Henry's Parquet data into Convex:

```typescript
// convex/convex/migrations/importRagCatalog.ts
export const importInitialCatalog = internalAction({
  handler: async (ctx) => {
    // This would typically be run as a one-time migration script
    // It reads the Parquet file and imports each row into Convex
    await ctx.runAction(internal.ragCatalog.importReferenceItems);
  },
});
```

Run with: `npx convex run importInitialCatalog`

#### 5.2 Catalog Management
- Add/Update items individually or in batches
- Version tracking via `model` and `processedAtUtc` fields
- Easy to extend with new reference items over time
- No complex versioning needed - Convex handles updates seamlessly

## Testing Strategy

### Unit Tests
1. Embedding normalization and cosine similarity
2. Top-k retrieval accuracy
3. Parquet loading and parsing
4. Mass estimation logic

### Integration Tests
1. End-to-end classification with RAG
2. Catalog upload and activation
3. Similarity search with known queries
4. Fallback to default mass when RAG fails

### Validation Tests
1. Round-trip: known description → embed → retrieve → verify rank 1
2. Mass estimation accuracy on holdout set
3. CO2 calculation consistency
4. Performance: <2s additional latency for RAG retrieval

## Performance Considerations

### Memory
- **No in-memory caching needed** - Convex handles vector index management
- Reference items stored as documents with 2560-dim embeddings
- Images stored in Convex storage (efficient blob storage)
- **Scales automatically** with Convex infrastructure
- Larger embeddings (2560 vs 1024) = ~2.5x storage per embedding, still manageable

### Latency
- Embedding generation: ~500ms (Perplexity API for pplx-embed-context-v1-4b)
- Vector search: <50ms (Convex's approximate nearest neighbor with 2560-dim vectors)
- Document fetch: ~50ms (Convex query)
- Mass estimation with context: ~1-2s (vision API)
- **Total additional latency**: ~1.6-2.6s
- **Better than original plan** due to Convex's optimized vector search

### Cost
- Perplexity embeddings: $0.05 per 1M tokens (pplx-embed-context-v1-4b)
- Estimated cost: ~$0.00001 per classification (for embedding description)
- Negligible compared to vision API costs

### Scalability
- Convex vector search scales automatically
- No need to manage memory or caching
- Handles filtering efficiently via built-in filterFields
- Supports much larger datasets (100k+ items) without architecture changes
- 2560-dim embeddings provide higher quality semantic search vs 1024-dim

## Rollout Plan

### Phase 1: Backend Only (Week 1)
1. Implement RAG catalog management
2. Upload initial Parquet catalog
3. Implement similarity search
4. Unit tests

### Phase 2: Pipeline Integration (Week 2)
1. Integrate RAG into classification action
2. Implement description generation
3. Implement mass estimation with context
4. Integration tests

### Phase 3: iOS Updates (Week 3)
1. Update models to include RAG context
2. Add UI for displaying similar items
3. Add research trigger flow
4. End-to-end testing

### Phase 4: Validation & Tuning (Week 4)
1. A/B test: RAG vs. default mass estimation
2. Measure accuracy improvement
3. Tune TOP_K and thresholds
4. Performance optimization

## Success Metrics

1. **Accuracy**: Mass estimation error reduced by >30% vs. defaults
2. **Latency**: Classification time <8s (currently ~6s)
3. **Coverage**: RAG provides mass estimates for >90% of items
4. **User Trust**: Higher user confirmation rates on RAG-estimated items

## Future Enhancements

1. **User Feedback Loop**: Allow users to correct mass estimates, improve catalog
2. **Dynamic Catalog**: Add user-scanned items to catalog (with consent)
3. **Multi-Model**: Ensemble multiple embedding models
4. **Regional Catalogs**: Location-specific reference items
5. **Vector DB Migration**: Move to Pinecone/Weaviate if scaling needed

## Open Questions

1. **Cost**: Perplexity embedding API costs for description generation
2. **Privacy**: Storing user images in catalog (if adding dynamic items)
3. **Versioning**: How to handle catalog updates without breaking existing classifications
4. **Fallback**: When to fallback to default mass estimation

## Dependencies & Prerequisites

- [ ] Perplexity API key with embeddings access
- [ ] Initial Parquet catalog file from Henry
- [ ] Convex deployment (v1.38.0+) with vector search support
- [ ] Node.js package: parquet-js or similar (for one-time import only)
- [ ] Test dataset for validation

**Note**: No ongoing dependencies needed for vector search - Convex handles it natively!

## Next Steps for Coding Agent

1. **Start with Phase 1.1**: Add `ragReferenceItems` table with vector index to schema
2. **Implement Phase 1.2**: Create `ragCatalog.ts` with import and vector search functions
3. **Test Phase 2**: Import Henry's Parquet data and verify Convex vector search works
4. **Integrate Phase 3**: Modify `classifyWaste.ts` to use RAG with Convex vector search
5. **Update Phase 4**: Modify iOS models and UI to display RAG context
6. **Deploy & Validate**: Run A/B tests and measure improvement

**Key Advantage**: Much simpler implementation with Convex's native vector search - no manual indexing, memory management, or external dependencies needed!

---

**Prepared by**: Devin (for Will's coding agent)
**Date**: 2025-05-09
**Based on**: Henry's RAG dataset handoff