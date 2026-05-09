import { v } from "convex/values";
import { mutation, query, internalMutation } from "./_generated/server";
import { auth } from "./auth";

/**
 * Per-user profile. Holds display name, optional Apple linkage, and any
 * future fields we want to attach to a Convex user without touching the
 * auth-managed `users` table.
 */
export const me = query({
  args: {},
  handler: async (ctx) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) return null;
    const profile = await ctx.db
      .query("profiles")
      .withIndex("by_userId", (q) => q.eq("userId", userId))
      .unique();
    return {
      userId,
      displayName: profile?.displayName,
      email: profile?.email,
      appleSub: profile?.appleSub,
      isAppleLinked: profile?.appleSub !== undefined,
    };
  },
});

export const setEmail = mutation({
  args: { email: v.string() },
  handler: async (ctx, { email }) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) throw new Error("Not authenticated");
    const trimmed = email.trim().toLowerCase();
    const existing = await ctx.db
      .query("profiles")
      .withIndex("by_userId", (q) => q.eq("userId", userId))
      .unique();
    if (existing) {
      await ctx.db.patch(existing._id, { email: trimmed });
    } else {
      await ctx.db.insert("profiles", {
        userId,
        email: trimmed,
        createdAt: Date.now(),
      });
    }
  },
});

export const setDisplayName = mutation({
  args: { name: v.string() },
  handler: async (ctx, { name }) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) throw new Error("Not authenticated");
    const trimmed = name.trim().slice(0, 60);
    const existing = await ctx.db
      .query("profiles")
      .withIndex("by_userId", (q) => q.eq("userId", userId))
      .unique();
    if (existing) {
      await ctx.db.patch(existing._id, { displayName: trimmed });
    } else {
      await ctx.db.insert("profiles", {
        userId,
        displayName: trimmed,
        createdAt: Date.now(),
      });
    }
  },
});

export const linkAppleIdentity = internalMutation({
  args: {
    appleSub: v.string(),
    email: v.optional(v.string()),
    fullName: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) throw new Error("Not authenticated");
    const existing = await ctx.db
      .query("profiles")
      .withIndex("by_userId", (q) => q.eq("userId", userId))
      .unique();
    const patch = {
      appleSub: args.appleSub,
      email: args.email ?? existing?.email,
      displayName: args.fullName ?? existing?.displayName,
    };
    if (existing) {
      await ctx.db.patch(existing._id, patch);
    } else {
      await ctx.db.insert("profiles", {
        userId,
        ...patch,
        createdAt: Date.now(),
      });
    }
  },
});
