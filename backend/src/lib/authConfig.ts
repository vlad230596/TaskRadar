import { z } from "zod";

/**
 * Auth configuration for the single TaskRadar user.
 *
 * There is no users table and no registration: the one and only user is defined
 * entirely by environment variables in the repo-root `.env`, which is the single
 * source of truth for secrets in this repo.
 */

/** Name of the httpOnly cookie carrying the session JWT. */
export const SESSION_COOKIE_NAME = "taskradar_session";

/**
 * The only `sub` value we ever issue. There is exactly one user, so the token
 * needs no identity beyond "this is the owner" -- no id, no email, no roles.
 * Keeping the claim set minimal means the cookie leaks nothing if inspected.
 */
export const OWNER_SUBJECT = "owner";

/**
 * Session lifetime: 30 days.
 *
 * This is a single-user personal tool used daily from both a desktop and a phone.
 * A short expiry (hours) would mean constant re-logins on the phone for no real
 * security gain, since there is only one account and no privileged operations to
 * step up for. An effectively infinite expiry would be worse: with no session
 * table there is no way to revoke an individual token, so the only kill switch is
 * rotating JWT_SECRET (which logs out every device). 30 days keeps a lost or
 * copied cookie from being useful forever while staying out of the user's way.
 *
 * NOTE: numeric `expiresIn` is interpreted in SECONDS by @fastify/jwt (fast-jwt),
 * unlike some other JWT libraries where it means milliseconds.
 */
export const SESSION_TTL_SECONDS = 60 * 60 * 24 * 30; // 2_592_000

/** Shape of a bcrypt hash: `$2<variant>$<cost>$<22-char salt + 31-char digest>`. */
const BCRYPT_HASH_PATTERN = /^\$2[aby]\$\d{2}\$[./A-Za-z0-9]{53}$/;

const authEnvSchema = z.object({
  AUTH_EMAIL: z
    .string()
    .min(1, "AUTH_EMAIL must not be empty")
    .transform((value) => value.trim().toLowerCase()),

  // Guards against someone accidentally putting a plaintext password here: a
  // plaintext value simply will not match the bcrypt format.
  AUTH_PASSWORD_HASH: z
    .string()
    .regex(BCRYPT_HASH_PATTERN, "AUTH_PASSWORD_HASH must be a bcrypt hash (e.g. $2b$12$...)"),

  JWT_SECRET: z.string().min(32, "JWT_SECRET must be at least 32 characters"),

  // Runtime flag, never hardcoded. See the comment in `.env` for why this has to
  // stay false until the app is genuinely served over HTTPS.
  COOKIE_SECURE: z
    .enum(["true", "false"])
    .default("false")
    .transform((value) => value === "true"),
});

export interface AuthConfig {
  /** Expected login email, normalised to trimmed lowercase. */
  readonly email: string;
  /** bcrypt hash of the expected password. */
  readonly passwordHash: string;
  /** Secret used to sign and verify session JWTs. */
  readonly jwtSecret: string;
  /** Whether to set the `Secure` attribute on the session cookie. */
  readonly cookieSecure: boolean;
}

/**
 * Reads and validates the auth environment variables.
 *
 * Throws on invalid or missing configuration so the process fails loudly at
 * startup rather than silently serving an app that can never be logged into.
 * The thrown message lists offending variable NAMES only -- never their values,
 * so a crash log can't leak the secret it was complaining about.
 */
export function loadAuthConfig(env: NodeJS.ProcessEnv = process.env): AuthConfig {
  const result = authEnvSchema.safeParse(env);

  if (!result.success) {
    const problems = result.error.issues
      .map((issue) => `${issue.path.join(".") || "(root)"}: ${issue.message}`)
      .join("; ");
    throw new Error(
      `Invalid auth configuration in the repo-root .env -- ${problems}. ` +
        "Expected AUTH_EMAIL, AUTH_PASSWORD_HASH, JWT_SECRET and COOKIE_SECURE to be set.",
    );
  }

  return {
    email: result.data.AUTH_EMAIL,
    passwordHash: result.data.AUTH_PASSWORD_HASH,
    jwtSecret: result.data.JWT_SECRET,
    cookieSecure: result.data.COOKIE_SECURE,
  };
}
