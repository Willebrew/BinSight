"use node";

import { v } from "convex/values";
import { action } from "./_generated/server";
import { internal, api } from "./_generated/api";
import { classifyImage, verifyTopItem } from "./sage";
import { estimateCo2Kg } from "./impactTable";

export const run = action({
  args: { id: v.id("classifications"), clientId: v.string() },
  handler: async (ctx, { id, clientId }) => {
    const row = await ctx.runQuery(api.classifications.getById, { id, clientId });
    if (!row) throw new Error("Classification row not found or not yours");
    if (row.status !== "pending") return; // idempotent

    try {
      const blob = await ctx.storage.get(row.storageId);
      if (!blob) throw new Error("Image blob missing from storage");
      const bytes = await blob.arrayBuffer();
      const contentType = (blob as any).type ?? "image/jpeg";

      const agent = await classifyImage(bytes, contentType, row.lat, row.lng);
      const items = agent.items.map((it) => ({
        label: it.label,
        material: it.material,
        decision: it.decision,
        confidence: clamp01(it.confidence),
        co2Kg: estimateCo2Kg(it.material, it.decision),
        disposalNotes: it.disposalNotes ?? "",
      }));

      let verified = false;
      if (items.length > 0) {
        try {
          verified = await verifyTopItem(agent.items[0]);
        } catch {
          verified = false;
        }
      }

      await ctx.runMutation(internal.classifications.writeResult, {
        id,
        items,
        localRules: agent.localRules,
        citations: agent.citations,
        model: agent.model,
        verified,
      });
    } catch (e: any) {
      await ctx.runMutation(internal.classifications.writeError, {
        id,
        errorMessage: String(e?.message ?? e).slice(0, 500),
      });
      throw e;
    }
  },
});

function clamp01(n: number): number {
  if (Number.isNaN(n)) return 0;
  if (n < 0) return 0;
  if (n > 1) return 1;
  return n;
}
