import { v } from "convex/values";
import { mutation, query, QueryCtx, MutationCtx } from "./_generated/server";
import { auth } from "./auth";

export async function getProfileByAuth(
  ctx: QueryCtx | MutationCtx,
  authUserId: string,
) {
  return await ctx.db
    .query("profiles")
    .withIndex("by_authUserId", (q) => q.eq("authUserId", authUserId as any))
    .unique();
}

/** Returns the signed-in user's profile, creating it on first call. */
export const me = query({
  args: {},
  handler: async (ctx) => {
    const authUserId = await auth.getUserId(ctx);
    if (!authUserId) return null;
    const profile = await getProfileByAuth(ctx, authUserId);
    if (!profile) return null;
    const authUser = await ctx.db.get(authUserId);
    return {
      _id: profile._id,
      authUserId,
      email: profile.email ?? authUser?.email,
      name: profile.name ?? authUser?.name,
      handle: profile.handle,
      phoneHash: profile.phoneHash,
      privacy: profile.privacy,
      createdAt: profile.createdAt,
    };
  },
});

export const ensureProfile = mutation({
  args: {},
  handler: async (ctx) => {
    const authUserId = await auth.getUserId(ctx);
    if (!authUserId) throw new Error("Not authenticated");
    const existing = await getProfileByAuth(ctx, authUserId);
    if (existing) return existing._id;
    const authUser = await ctx.db.get(authUserId);
    return await ctx.db.insert("profiles", {
      authUserId,
      email: authUser?.email,
      name: authUser?.name,
      privacy: { mapOptIn: true, contactsOptIn: false },
      createdAt: Date.now(),
    });
  },
});

export const updateProfile = mutation({
  args: {
    name: v.optional(v.string()),
    handle: v.optional(v.string()),
    phoneHash: v.optional(v.string()),
    mapOptIn: v.optional(v.boolean()),
    contactsOptIn: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const authUserId = await auth.getUserId(ctx);
    if (!authUserId) throw new Error("Not authenticated");
    const profile = await getProfileByAuth(ctx, authUserId);
    if (!profile) throw new Error("Profile not initialized; call ensureProfile first");
    const next = {
      ...profile,
      name: args.name ?? profile.name,
      handle: args.handle ?? profile.handle,
      phoneHash: args.phoneHash ?? profile.phoneHash,
      privacy: {
        mapOptIn: args.mapOptIn ?? profile.privacy.mapOptIn,
        contactsOptIn: args.contactsOptIn ?? profile.privacy.contactsOptIn,
      },
    };
    await ctx.db.patch(profile._id, {
      name: next.name,
      handle: next.handle,
      phoneHash: next.phoneHash,
      privacy: next.privacy,
    });
    return profile._id;
  },
});

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
      .map((p) => ({ _id: p._id, name: p.name, handle: p.handle }));
  },
});
