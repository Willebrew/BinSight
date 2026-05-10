import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { auth } from "./auth";

const friendshipStatus = v.union(v.literal("pending"), v.literal("accepted"));

/**
 * Sends a friend request to the user with the given email. Creates a pending
 * `friendships` row keyed by sorted (aUserId, bUserId). The recipient sees
 * it in `listIncoming` and can accept or decline.
 */
export const requestByEmail = mutation({
  args: { email: v.string() },
  handler: async (ctx, { email }): Promise<{ status: string; friendshipId?: string }> => {
    const me = await auth.getUserId(ctx);
    if (!me) throw new Error("Not authenticated");
    const normalized = email.trim().toLowerCase();
    if (normalized.length === 0) throw new Error("Email required");

    // Look up by profile.email first (set when user signs up), then fall back
    // to authAccounts where Convex Auth stores the email used to sign in.
    let target = await ctx.db
      .query("profiles")
      .withIndex("by_email", (q) => q.eq("email", normalized))
      .unique();
    let targetUserId = target?.userId ?? null;
    if (!targetUserId) {
      const account = await ctx.db
        .query("authAccounts")
        .withIndex("providerAndAccountId", (q) =>
          q.eq("provider", "password").eq("providerAccountId", normalized),
        )
        .unique();
      targetUserId = account?.userId ?? null;
    }
    if (!targetUserId) return { status: "no_such_user" };
    if (targetUserId === me) return { status: "self" };

    const [a, b] = me < targetUserId ? [me, targetUserId] : [targetUserId, me];
    const existing = await ctx.db
      .query("friendships")
      .withIndex("by_pair", (q) => q.eq("aUserId", a).eq("bUserId", b))
      .unique();
    if (existing) {
      // If the other user already requested us, auto-accept.
      if (existing.status === "pending" && existing.requestedBy !== me) {
        await ctx.db.patch(existing._id, { status: "accepted" });
        return { status: "accepted", friendshipId: existing._id };
      }
      return { status: existing.status, friendshipId: existing._id };
    }
    const friendshipId = await ctx.db.insert("friendships", {
      aUserId: a,
      bUserId: b,
      status: "pending",
      requestedBy: me,
      createdAt: Date.now(),
    });
    return { status: "pending", friendshipId };
  },
});

export const respond = mutation({
  args: { friendshipId: v.id("friendships"), accept: v.boolean() },
  handler: async (ctx, { friendshipId, accept }) => {
    const me = await auth.getUserId(ctx);
    if (!me) throw new Error("Not authenticated");
    const f = await ctx.db.get(friendshipId);
    if (!f) throw new Error("Friend request not found");
    if (f.aUserId !== me && f.bUserId !== me) throw new Error("Not yours");
    if (f.requestedBy === me) throw new Error("You sent this request");
    if (accept) {
      await ctx.db.patch(friendshipId, { status: "accepted" });
    } else {
      await ctx.db.delete(friendshipId);
    }
  },
});

export const remove = mutation({
  args: { friendshipId: v.id("friendships") },
  handler: async (ctx, { friendshipId }) => {
    const me = await auth.getUserId(ctx);
    if (!me) throw new Error("Not authenticated");
    const f = await ctx.db.get(friendshipId);
    if (!f) return;
    if (f.aUserId !== me && f.bUserId !== me) return;
    await ctx.db.delete(friendshipId);
  },
});

/**
 * Headline impact stats for me + each accepted friend, for the
 * Friends comparison list. Computed inline from `classifications`
 * (only `confirmed` items count) so it stays in sync without needing
 * a materialized table. Friend list is small (<~50) so the cost is
 * acceptable for a v1.
 */
export const compareStats = query({
  args: {},
  handler: async (ctx) => {
    const me = await auth.getUserId(ctx);
    if (!me) return null;

    const computeFor = async (userId: string) => {
      const rows = await ctx.db
        .query("classifications")
        .withIndex("by_user_capturedAt", (q) => q.eq("userId", userId as any))
        .filter((q) => q.eq(q.field("status"), "done"))
        .collect();
      let recycled = 0;
      let trashed = 0;
      let co2 = 0;
      const dayKeys = new Set<string>();
      for (const r of rows) {
        let dayHadConfirmed = false;
        for (const it of r.items) {
          if (it.reviewState !== "confirmed") continue;
          dayHadConfirmed = true;
          if (it.decision === "recycle" || it.decision === "compost") recycled += 1;
          else if (it.decision === "trash") trashed += 1;
          co2 += it.co2Kg;
        }
        if (dayHadConfirmed) {
          dayKeys.add(new Date(r.capturedAt).toISOString().slice(0, 10));
        }
      }
      // Streak: consecutive days ending today (UTC) with a confirmed scan.
      let streak = 0;
      const today = new Date();
      const cursor = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()));
      for (;;) {
        const key = cursor.toISOString().slice(0, 10);
        if (dayKeys.has(key)) {
          streak += 1;
          cursor.setUTCDate(cursor.getUTCDate() - 1);
        } else {
          break;
        }
      }
      return {
        userId,
        totalScans: rows.length,
        totalRecycled: recycled,
        totalTrashed: trashed,
        totalCo2Kg: Math.round(co2 * 1000) / 1000,
        streakDays: streak,
      };
    };

    // Find accepted friends (both directions).
    const asA = await ctx.db
      .query("friendships")
      .withIndex("by_aUserId", (q) => q.eq("aUserId", me))
      .collect();
    const asB = await ctx.db
      .query("friendships")
      .withIndex("by_bUserId", (q) => q.eq("bUserId", me))
      .collect();
    const acceptedFriendIds: string[] = [];
    for (const f of [...asA, ...asB]) {
      if (f.status !== "accepted") continue;
      const other = f.aUserId === me ? f.bUserId : f.aUserId;
      acceptedFriendIds.push(other as unknown as string);
    }

    const myStats = await computeFor(me as unknown as string);
    const friends = [];
    for (const fid of acceptedFriendIds) {
      const profile = await ctx.db
        .query("profiles")
        .withIndex("by_userId", (q) => q.eq("userId", fid as any))
        .unique();
      const account = profile?.email ? null : await ctx.db
        .query("authAccounts")
        .withIndex("userIdAndProvider", (q) =>
          q.eq("userId", fid as any).eq("provider", "password"),
        )
        .unique();
      const stats = await computeFor(fid);
      friends.push({
        ...stats,
        displayName: profile?.displayName ?? null,
        email: profile?.email ?? account?.providerAccountId ?? null,
      });
    }
    // Rank by CO2 saved descending so the leaderboard reads top-down.
    friends.sort((a, b) => b.totalCo2Kg - a.totalCo2Kg);
    return { me: myStats, friends };
  },
});

export const list = query({
  args: {},
  handler: async (ctx) => {
    const me = await auth.getUserId(ctx);
    if (!me) return { accepted: [], incoming: [], outgoing: [] };
    const asA = await ctx.db
      .query("friendships")
      .withIndex("by_aUserId", (q) => q.eq("aUserId", me))
      .collect();
    const asB = await ctx.db
      .query("friendships")
      .withIndex("by_bUserId", (q) => q.eq("bUserId", me))
      .collect();
    const all = [...asA, ...asB];

    const decorate = async (f: any) => {
      const otherId = f.aUserId === me ? f.bUserId : f.aUserId;
      const profile = await ctx.db
        .query("profiles")
        .withIndex("by_userId", (q) => q.eq("userId", otherId))
        .unique();
      const account = profile?.email ? null : await ctx.db
        .query("authAccounts")
        .withIndex("userIdAndProvider", (q) =>
          q.eq("userId", otherId).eq("provider", "password"),
        )
        .unique();
      return {
        friendshipId: f._id,
        status: f.status,
        requestedBy: f.requestedBy,
        otherUserId: otherId,
        otherDisplayName: profile?.displayName,
        otherEmail: profile?.email ?? account?.providerAccountId,
      };
    };

    const accepted: any[] = [];
    const incoming: any[] = [];
    const outgoing: any[] = [];
    for (const f of all) {
      const d = await decorate(f);
      if (f.status === "accepted") accepted.push(d);
      else if (f.requestedBy === me) outgoing.push(d);
      else incoming.push(d);
    }
    return { accepted, incoming, outgoing };
  },
});
