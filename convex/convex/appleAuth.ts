"use node";

import { v } from "convex/values";
import { action } from "./_generated/server";
import { internal } from "./_generated/api";
import { createRemoteJWKSet, jwtVerify } from "jose";

const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";
const APPLE_ISSUER = "https://appleid.apple.com";
const BUNDLE_ID = "NeuroQuest-Labs.BinSight";

// Lazy-initialized at module scope so the JWKS is fetched once per cold start.
const jwks = createRemoteJWKSet(new URL(APPLE_JWKS_URL));

/**
 * Verifies an Apple identity token (the JWT from ASAuthorizationController on
 * the device) and links the Apple identity to the current authenticated user.
 *
 * Returns the canonical Apple `sub` (stable per-user identifier) and an
 * optional email if Apple included it.
 */
export const verifyAppleToken = action({
  args: {
    identityToken: v.string(),
    fullName: v.optional(v.string()),
  },
  handler: async (ctx, { identityToken, fullName }): Promise<{
    sub: string;
    email?: string;
    fullName?: string;
  }> => {
    const { payload } = await jwtVerify(identityToken, jwks, {
      issuer: APPLE_ISSUER,
      audience: BUNDLE_ID,
    });
    const sub = payload.sub;
    if (!sub) throw new Error("Apple token missing sub claim");
    const email = typeof payload.email === "string" ? payload.email : undefined;

    // Persist the Apple identity on the current user's profile (if signed in).
    await ctx.runMutation(internal.profiles.linkAppleIdentity, {
      appleSub: sub,
      email,
      fullName,
    });

    return { sub, email, fullName };
  },
});
