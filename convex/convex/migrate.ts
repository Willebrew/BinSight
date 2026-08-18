import { internalMutation } from "./_generated/server";

/**
 * One-shot migration: backfill the new schema fields onto pre-existing
 * `classifications` rows so they validate against the upgraded schema.
 */
export const upgradeClassifications = internalMutation({
  args: {},
  handler: async (ctx) => {
    const rows = await ctx.db.query("classifications").collect();
    let upgraded = 0;
    for (const r of rows) {
      const items = (r.items ?? []).map((it: any) => ({
        label: it.label ?? "unknown",
        material: it.material ?? "unknown",
        decision: it.decision ?? "trash",
        confidence: typeof it.confidence === "number" ? it.confidence : 0,
        estimatedMassG: typeof it.estimatedMassG === "number" ? it.estimatedMassG : 0,
        massSource: it.massSource ?? "default",
        co2Kg: typeof it.co2Kg === "number" ? it.co2Kg : 0,
        co2KgLow: typeof it.co2KgLow === "number" ? it.co2KgLow : (typeof it.co2Kg === "number" ? it.co2Kg * 0.8 : 0),
        co2KgHigh: typeof it.co2KgHigh === "number" ? it.co2KgHigh : (typeof it.co2Kg === "number" ? it.co2Kg * 1.2 : 0),
        co2Method: it.co2Method ?? "Legacy estimate (pre-WARM table)",
        disposalNotes: it.disposalNotes ?? "",
        sourceIndices: Array.isArray(it.sourceIndices) ? it.sourceIndices : [],
        reviewState: it.reviewState ?? "confirmed",   // grandfather old scans as confirmed
        reviewedAt: it.reviewedAt,
      }));
      const sources = Array.isArray(r.sources) ? r.sources : [];
      await ctx.db.patch(r._id, { items, sources });
      upgraded += 1;
    }
    return { upgraded };
  },
});
