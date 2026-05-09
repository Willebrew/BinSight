import { convexAuth } from "@convex-dev/auth/server";
import { Password } from "@convex-dev/auth/providers/Password";
import type { DataModel } from "./_generated/dataModel";

// Email + password authentication. The user enters email + password on first
// launch; subsequent launches reuse the cached session JWT in iOS Keychain.
//
// Sign In with Apple is intentionally not wired here because it requires a
// paid Apple Developer account. The server-side appleAuth.verifyAppleToken
// action remains as scaffolding for when the team upgrades.
export const { auth, signIn, signOut, store, isAuthenticated } = convexAuth({
  providers: [Password<DataModel>()],
});
