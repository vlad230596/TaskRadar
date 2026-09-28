import bcrypt from "bcrypt";
import { createHash, timingSafeEqual } from "node:crypto";

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
 * A well-formed bcrypt hash nobody has the password for. Compared against when
 * the email is unknown or the account is disabled, so those cost the same
 * ~250ms as a wrong password.
 */
const UNMATCHABLE_HASH = "$2b$12$56KpwF2fp9APK26Md/R0PuFXF6Nky8.L1sQDDImm3oXfyGoxwtUZW";

/**
 * Checks a submitted password against the user found for the submitted email
 * (`null` when there is none).
 *
 * Deliberately does NOT short-circuit when there is no user: the bcrypt compare
 * always runs, so an unknown email costs the same as a wrong password.
 * Short-circuiting would make the two measurably different and hand an attacker
 * the very distinction that the generic 401 message exists to hide. A disabled
 * account is treated exactly like an unknown one.
 *
 * Returns the user's id on success and `null` otherwise -- callers get no way
 * to tell which half failed, so a route handler can't accidentally leak it.
 */
export async function verifyCredentials(
  user: { id: string; passwordHash: string; disabledAt: Date | null } | null,
  submittedPassword: string,
): Promise<string | null> {
  const usable = user !== null && user.disabledAt === null;
  const passwordMatches = await verifyPassword(
    submittedPassword,
    usable ? user.passwordHash : UNMATCHABLE_HASH,
  );
  return usable && passwordMatches ? user.id : null;
}
