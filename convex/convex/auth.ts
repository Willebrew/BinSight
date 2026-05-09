import { convexAuth } from "@convex-dev/auth/server";
import { Anonymous } from "@convex-dev/auth/providers/Anonymous";

// Anonymous accounts: every device gets a real Convex user automatically on
// first launch. We can layer Sign In with Apple on top later as an account
// upgrade — Convex Auth supports identity merging.
export const { auth, signIn, signOut, store, isAuthenticated } = convexAuth({
  providers: [Anonymous],
});
