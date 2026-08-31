import { describe, it, expect } from "vitest";
import { SESSION_TTL_SECONDS, loadAuthConfig } from "../src/lib/authConfig";

const VALID_HASH = "$2b$12$z7Qc2.CvoVgGEjBfsFNQN.BRa5/FbH9mM62TpBkICjtNY46RM4yWi";
const VALID_SECRET = "a".repeat(64);

function env(overrides: Record<string, string | undefined> = {}): NodeJS.ProcessEnv {
  return {
    AUTH_EMAIL: "Owner@Example.com",
    AUTH_PASSWORD_HASH: VALID_HASH,
    JWT_SECRET: VALID_SECRET,
    COOKIE_SECURE: "false",
    ...overrides,
  } as NodeJS.ProcessEnv;
}

describe("loadAuthConfig", () => {
  it("loads a valid configuration and normalises the email", () => {
    const config = loadAuthConfig(env());
    expect(config.email).toBe("owner@example.com");
    expect(config.passwordHash).toBe(VALID_HASH);
    expect(config.jwtSecret).toBe(VALID_SECRET);
  });

  it("parses COOKIE_SECURE=false as false", () => {
    expect(loadAuthConfig(env({ COOKIE_SECURE: "false" })).cookieSecure).toBe(false);
  });

  it("parses COOKIE_SECURE=true as true", () => {
    // Proves the flag is genuinely runtime-driven rather than hardcoded.
    expect(loadAuthConfig(env({ COOKIE_SECURE: "true" })).cookieSecure).toBe(true);
  });

  it("defaults COOKIE_SECURE to false when unset", () => {
    expect(loadAuthConfig(env({ COOKIE_SECURE: undefined })).cookieSecure).toBe(false);
  });

  it("rejects a COOKIE_SECURE value that is neither true nor false", () => {
    expect(() => loadAuthConfig(env({ COOKIE_SECURE: "yes" }))).toThrow(/COOKIE_SECURE/);
  });

  it("rejects a missing AUTH_EMAIL", () => {
    expect(() => loadAuthConfig(env({ AUTH_EMAIL: undefined }))).toThrow(/AUTH_EMAIL/);
  });

  it("rejects a missing AUTH_PASSWORD_HASH", () => {
    expect(() => loadAuthConfig(env({ AUTH_PASSWORD_HASH: undefined }))).toThrow(/AUTH_PASSWORD_HASH/);
  });

  it("rejects a plaintext password accidentally placed in AUTH_PASSWORD_HASH", () => {
    expect(() => loadAuthConfig(env({ AUTH_PASSWORD_HASH: "hunter2" }))).toThrow(/bcrypt/);
  });

  it("rejects a JWT_SECRET that is too short to be meaningful", () => {
    expect(() => loadAuthConfig(env({ JWT_SECRET: "short" }))).toThrow(/JWT_SECRET/);
  });

  it("never includes the offending secret value in the error message", () => {
    const secret = "b".repeat(20); // too short, so it will be reported
    let message = "";
    try {
      loadAuthConfig(env({ JWT_SECRET: secret }));
    } catch (err) {
      message = err instanceof Error ? err.message : String(err);
    }
    expect(message).toMatch(/JWT_SECRET/);
    expect(message).not.toContain(secret);
  });
});

describe("SESSION_TTL_SECONDS", () => {
  it("is 30 days expressed in seconds", () => {
    // @fastify/jwt takes a numeric expiresIn in SECONDS. Passing milliseconds here
    // would silently mint ~30000-day tokens, so pin the unit down in a test.
    expect(SESSION_TTL_SECONDS).toBe(2592000);
    expect(SESSION_TTL_SECONDS / 60 / 60 / 24).toBe(30);
  });
});
