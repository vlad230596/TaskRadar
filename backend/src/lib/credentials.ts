import bcrypt from "bcrypt";
import { createHash, timingSafeEqual } from "node:crypto";
import type { AuthConfig } from "./authConfig";

/** Normalises a submitted email the same way `loadAuthConfig` normalises the expected one. */
export function normaliseEmail(email: string): string {
  return email.trim().toLowerCase();
}

/**
 * Length-independent constant-time string comparison.
 *
 * `timingSafeEqual` throws when the two buffers differ in length (and comparing
 * raw strings would leak length through timing), so both sides are hashed to a
 * fixed 32 bytes first and the digests are compared instead.
 */
export function constantTimeEquals(a: string, b: string): boolean {
  const digestA = createHash("sha256").update(a, "utf8").digest();
  const digestB = createHash("sha256").update(b, "utf8").digest();
  return timingSafeEqual(digestA, digestB);
}

/** Verifies a plaintext password against a bcrypt hash. */
export function verifyPassword(plaintext: string, passwordHash: string): Promise<boolean> {
  return bcrypt.compare(plaintext, passwordHash);
}

/**
 * Checks a submitted email + password pair against the configured single user.
 *
 * Deliberately does NOT short-circuit when the email is wrong: the bcrypt compare
 * always runs, so a request with a wrong email costs the same ~250ms as one with a
 * wrong password. Short-circuiting would make "unknown email" measurably faster
 * than "wrong password" and hand an attacker the very distinction that the generic
 * 401 message exists to hide.
 *
 * Returns a single boolean -- callers get no way to tell which half failed, so a
 * route handler can't accidentally leak it.
 */
export async function verifyCredentials(
  submittedEmail: string,
  submittedPassword: string,
  config: AuthConfig,
): Promise<boolean> {
  const emailMatches = constantTimeEquals(normaliseEmail(submittedEmail), config.email);
  const passwordMatches = await verifyPassword(submittedPassword, config.passwordHash);

  // Both operands are already evaluated above; `&&` here does not skip work.
  return emailMatches && passwordMatches;
}
