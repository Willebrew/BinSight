import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { auth } from "./auth";

function ordered(a: string, b: string): [string, string] {
  return a < b ? [a, b] : [b, a];
}

export const findByPhoneHashes = query({
  args: { hashes: v.array(v.string()) },
  handler: async (ctx, { hashes }) => {
    if (hashes.length === 0) return [];
    const results = await Promise.all(
      hashes.map((h) =>
        ctx.db
          .query("profiles")
          .withIndex("by_phoneHash", (q) => q.eq("phoneHash", h))
          .unique(),
      ),
    );
    return results
      .filter((p): p is NonNullable<typeof p> => !!p)
      .map((p) => ({ profileId: p._id, authUserId: p.authUserId, name: p.name, handle: p.handle }));
  },
});

export const request = mutation({
  args: { otherAuthUserId: v.id("users") },
  handler: async (ctx, { otherAuthUserId }) => {
    const me = await auth.getUserId(ctx);
    if (!me) throw new Error("Not authenticated");
    if (me === otherAuthUserId) throw new Error("Cannot friend yourself");
    const [a, b] = ordered(me, otherAuthUserId);
    const existing = await ctx.db
      .query("friendships")
      .withIndex("by_a_status", (q) => q.eq("a", a as any))
      .filter((q) => q.eq(q.field("b"), b))
      .unique();
    if (existing) return existing._id;
    return await ctx.db.insert("friendships", {
      a: a as any,
      b: b as any,
      status: "pending",
      requestedBy: me,
      createdAt: Date.now(),
    });
  },
});

export const accept = mutation({
  args: { friendshipId: v.id("friendships") },
  handler: async (ctx, { friendshipId }) => {
    const me = await auth.getUserId(ctx);
    if (!me) throw new Error("Not authenticated");
    const f = await ctx.db.get(friendshipId);
    if (!f) throw new Error("Friendship not found");
    if (f.requestedBy === me) throw new Error("Only the recipient can accept");
    if (f.a !== me && f.b !== me) throw new Error("Not your friendship");
    await ctx.db.patch(friendshipId, { status: "accepted" });
  },
});

export const list = query({
  args: {},
  handler: async (ctx) => {
    const me = await auth.getUserId(ctx);
    if (!me) return [];
    const asA = await ctx.db
      .query("friendships")
      .withIndex("by_a_status", (q) => q.eq("a", me as any))
      .collect();
    const asB = await ctx.db
      .query("friendships")
      .withIndex("by_b_status", (q) => q.eq("b", me as any))
      .collect();
    const all = [...asA, ...asB];
    return await Promise.all(
      all.map(async (f) => {
        const otherAuthId = f.a === me ? f.b : f.a;
        const profile = await ctx.db
          .query("profiles")
          .withIndex("by_authUserId", (q) => q.eq("authUserId", otherAuthId))
          .unique();
        return {
          friendshipId: f._id,
          status: f.status,
          requestedBy: f.requestedBy,
          other: profile
            ? { authUserId: otherAuthId, name: profile.name, handle: profile.handle }
            : { authUserId: otherAuthId, name: undefined, handle: undefined },
        };
      }),
    );
  },
});
