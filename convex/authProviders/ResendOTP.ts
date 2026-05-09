import Resend from "@auth/core/providers/resend";
import { Resend as ResendAPI } from "resend";
import { alphabet, generateRandomString } from "oslo/crypto";

// 6-digit numeric OTP delivered by email via Resend.
// Configure with `npx convex env set AUTH_RESEND_KEY <key>`.
export const ResendOTP = Resend({
  id: "resend-otp",
  apiKey: process.env.AUTH_RESEND_KEY,
  async generateVerificationToken() {
    return generateRandomString(6, alphabet("0-9"));
  },
  async sendVerificationRequest({ identifier: email, provider, token }) {
    const resend = new ResendAPI(provider.apiKey);
    const { error } = await resend.emails.send({
      from: process.env.AUTH_EMAIL_FROM ?? "BinSight <onboarding@resend.dev>",
      to: [email],
      subject: `Your BinSight code: ${token}`,
      text: `Your BinSight verification code is ${token}. It expires in 10 minutes.`,
    });
    if (error) {
      throw new Error(JSON.stringify(error));
    }
  },
});
