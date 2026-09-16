import { describe, it, expect, beforeAll, afterAll } from "vitest";
import type { FastifyInstance } from "fastify";
// Pure helper over a static allowlist -- importing it loads no route module and
// therefore no Prisma client.
import { isPublicRoute } from "../src/lib/authGuard";
// Type-only imports are erased at compile time, so these do NOT load the modules
// (and therefore do not construct a Prisma client) before DATABASE_URL is set below.
import type { AuthConfig } from "../src/lib/authConfig";
import type { BuildAppOptions } from "../src/app";

/*
 * The route modules construct a Prisma client at import time, which requires
 * DATABASE_URL to be present even though none of these tests touch the database.
 * Set a placeholder before `src/app` is imported (below, dynamically) so the suite
 * runs on a machine with no database configured.
 */
process.env.DATABASE_URL ??= "postgresql://placeholder:placeholder@localhost:5432/placeholder";

const TEST_PASSWORD = "test-password-not-the-real-one";
/** bcrypt hash of TEST_PASSWORD at cost 4 -- fast, since these tests log in repeatedly. */
const TEST_HASH = "$2b$04$zV5VFEALedx8Rfd/ucwUSOrHYSSr8xveuActiCTdzOmCsBSDTbYXO";

const baseConfig: AuthConfig = {
  email: "owner@example.com",
  passwordHash: TEST_HASH,
  jwtSecret: "test-jwt-secret-".repeat(4),
  cookieSecure: false,
};

/** A protected route that touches no database, so the guard can be tested in isolation. */
const PROTECTED_TEST_ROUTE = "/__test/protected";

let buildApp: (options?: BuildAppOptions) => Promise<FastifyInstance>;
let SESSION_COOKIE_NAME: string;
let app: FastifyInstance;

/** Builds an app with a test-only protected route registered alongside the real ones. */
async function buildTestApp(config: AuthConfig): Promise<FastifyInstance> {
  const instance = await buildApp({ authConfig: config, logger: false });
  instance.get(PROTECTED_TEST_ROUTE, async () => ({ reached: true }));
  await instance.ready();
  return instance;
}

/** Logs in and returns the token as the native client would read it: from the body. */
async function loginForBodyToken(instance: FastifyInstance): Promise<string> {
  const res = await instance.inject({
    method: "POST",
    url: "/auth/login",
    payload: { email: "owner@example.com", password: TEST_PASSWORD },
  });
  expect(res.statusCode).toBe(200);
  const body = res.json() as { token?: unknown };
  if (typeof body.token !== "string") {
    throw new Error("login response did not carry a token in the body");
  }
  return body.token;
}

/**
 * Returns `token` with its signature corrupted, guaranteeing that the bytes the
 * verifier compares really did change.
 *
 * The obvious version of this -- "replace the last character of the token" -- is
 * silently broken, and was the cause of this suite failing at random. An HS256
 * signature is 32 bytes = 256 bits, but its base64url form is 43 characters =
 * 258 bits: the final character carries only 4 significant bits plus 2 bits of
 * padding. Characters whose indices share those top 4 bits therefore decode to
 * the very same signature -- "...A" and "...B" are byte-identical -- and fast-jwt
 * compares the decoded bytes, not the text. Canonical encoders only ever emit the
 * first character of each group, so swapping a trailing "A" for a "B" produced a
 * perfectly valid token about 1 token in 16, depending on the token's `iat`.
 *
 * Flipping a bit inside the decoded bytes side-steps the padding entirely and is
 * deterministic; the assertion below states that guarantee rather than trusting it.
 */
function tamperWithSignature(token: string): string {
  const parts = token.split(".");
  if (parts.length !== 3) {
    throw new Error(`expected a three-part JWT, got ${parts.length} part(s)`);
  }
  const [header, payload, signature] = parts as [string, string, string];

  const bytes = Buffer.from(signature, "base64url");
  // First byte, lowest bit: no padding lives there, so the value is certain to move.
  bytes[0] ^= 0x01;
  const tamperedSignature = bytes.toString("base64url");

  // The property the test actually depends on. If a future change to this helper
  // (or to Node's base64url handling) ever made the tampering a no-op again, this
  // fails loudly here instead of turning into a flaky assertion further down.
  expect(Buffer.from(tamperedSignature, "base64url").equals(bytes)).toBe(true);
  expect(bytes.equals(Buffer.from(signature, "base64url"))).toBe(false);

  return `${header}.${payload}.${tamperedSignature}`;
}

/** Logs in and returns the raw session cookie value. */
async function login(
  instance: FastifyInstance,
  password: string = TEST_PASSWORD,
  email: string = "owner@example.com",
): Promise<string> {
  const res = await instance.inject({
    method: "POST",
    url: "/auth/login",
    payload: { email, password },
  });
  expect(res.statusCode).toBe(200);
  const cookie = res.cookies.find((c) => c.name === SESSION_COOKIE_NAME);
  if (cookie === undefined) {
    throw new Error("login response did not set a session cookie");
  }
  return cookie.value;
}

beforeAll(async () => {
  const appModule = await import("../src/app");
  const configModule = await import("../src/lib/authConfig");
  buildApp = appModule.buildApp;
  SESSION_COOKIE_NAME = configModule.SESSION_COOKIE_NAME;
  app = await buildTestApp(baseConfig);
});

afterAll(async () => {
  await app?.close();
});

describe("public routes", () => {
  it("serves GET /health with no cookie at all", async () => {
    const res = await app.inject({ method: "GET", url: "/health" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ status: "ok" });
  });

  it("accepts POST /auth/login with no cookie at all", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "owner@example.com", password: TEST_PASSWORD },
    });
    expect(res.statusCode).toBe(200);
  });

  it("accepts POST /auth/logout with no cookie at all", async () => {
    const res = await app.inject({ method: "POST", url: "/auth/logout" });
    expect(res.statusCode).toBe(200);
  });
});

describe("auth guard", () => {
  it("rejects a protected route with no cookie", async () => {
    const res = await app.inject({ method: "GET", url: PROTECTED_TEST_ROUTE });
    expect(res.statusCode).toBe(401);
  });

  it("rejects a real protected route (GET /projects) with no cookie", async () => {
    const res = await app.inject({ method: "GET", url: "/projects" });
    expect(res.statusCode).toBe(401);
  });

  it("protects every existing projects/tasks/notes route", async () => {
    const routes: Array<[string, string]> = [
      ["GET", "/projects"],
      ["POST", "/projects"],
      ["GET", "/projects/some-id"],
      ["POST", "/projects/some-id/archive"],
      ["POST", "/projects/some-id/unarchive"],
      ["DELETE", "/projects/some-id"],
      ["GET", "/projects/some-id/tasks"],
      ["POST", "/projects/some-id/tasks"],
      ["PATCH", "/tasks/some-id"],
      ["DELETE", "/tasks/some-id"],
      ["GET", "/projects/some-id/notes"],
      ["POST", "/projects/some-id/notes"],
      ["PATCH", "/notes/some-id"],
      ["DELETE", "/notes/some-id"],
    ];

    for (const [method, url] of routes) {
      const res = await app.inject({ method: method as "GET", url, payload: {} });
      // 401 before any handler runs, so no database call and no validation error.
      expect(res.statusCode, `${method} ${url}`).toBe(401);
    }
  });

  it("rejects a garbage cookie", async () => {
    const res = await app.inject({
      method: "GET",
      url: PROTECTED_TEST_ROUTE,
      cookies: { [SESSION_COOKIE_NAME]: "garbage.token.value" },
    });
    expect(res.statusCode).toBe(401);
  });

  it("rejects an empty cookie value", async () => {
    const res = await app.inject({
      method: "GET",
      url: PROTECTED_TEST_ROUTE,
      cookies: { [SESSION_COOKIE_NAME]: "" },
    });
    expect(res.statusCode).toBe(401);
  });

  it("rejects a structurally valid token signed with the wrong secret", async () => {
    const otherApp = await buildTestApp({ ...baseConfig, jwtSecret: "a-completely-different-secret-value-x" });
    const foreignToken = otherApp.jwt.sign({ sub: "owner" }, { expiresIn: 3600 });
    await otherApp.close();

    const res = await app.inject({
      method: "GET",
      url: PROTECTED_TEST_ROUTE,
      cookies: { [SESSION_COOKIE_NAME]: foreignToken },
    });
    expect(res.statusCode).toBe(401);
  });

  it("rejects a tampered token", async () => {
    const token = await login(app);
    const tampered = tamperWithSignature(token);

    const res = await app.inject({
      method: "GET",
      url: PROTECTED_TEST_ROUTE,
      cookies: { [SESSION_COOKIE_NAME]: tampered },
    });
    expect(res.statusCode).toBe(401);
  });

  it("rejects an expired token", async () => {
    const expired = app.jwt.sign({ sub: "owner" }, { expiresIn: -60 });
    const res = await app.inject({
      method: "GET",
      url: PROTECTED_TEST_ROUTE,
      cookies: { [SESSION_COOKIE_NAME]: expired },
    });
    expect(res.statusCode).toBe(401);
  });

  it("lets a valid cookie through to the route handler", async () => {
    const token = await login(app);
    const res = await app.inject({
      method: "GET",
      url: PROTECTED_TEST_ROUTE,
      cookies: { [SESSION_COOKIE_NAME]: token },
    });
    expect(res.statusCode).not.toBe(401);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ reached: true });
  });

  it("returns an opaque 401 body with no internal detail", async () => {
    const res = await app.inject({
      method: "GET",
      url: PROTECTED_TEST_ROUTE,
      cookies: { [SESSION_COOKIE_NAME]: "garbage.token.value" },
    });
    expect(res.json()).toEqual({ error: "Unauthorized", message: "Unauthorized" });
    // No stack trace, no library error code, no hint about which check failed.
    expect(res.body).not.toMatch(/stack|FAST_JWT|jwt|token|cookie|signature/i);
  });

  it("returns 401 rather than 404 for unknown routes when unauthenticated", async () => {
    // Prevents route enumeration by an unauthenticated caller.
    const res = await app.inject({ method: "GET", url: "/__no_such_route" });
    expect(res.statusCode).toBe(401);
  });

  it("returns a normal 404 for unknown routes once authenticated", async () => {
    const token = await login(app);
    const res = await app.inject({
      method: "GET",
      url: "/__no_such_route",
      cookies: { [SESSION_COOKIE_NAME]: token },
    });
    expect(res.statusCode).toBe(404);
  });
});

describe("POST /auth/login", () => {
  it("issues a session cookie on correct credentials", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "owner@example.com", password: TEST_PASSWORD },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      ok: true,
      token: expect.any(String),
      expiresIn: 2592000,
    });

    const setCookie = res.headers["set-cookie"];
    expect(setCookie).toBeDefined();
    const header = Array.isArray(setCookie) ? setCookie.join("; ") : String(setCookie);
    expect(header).toContain(`${SESSION_COOKIE_NAME}=`);
    expect(header).toContain("HttpOnly");
    expect(header).toContain("SameSite=Lax");
    expect(header).toContain("Path=/");
    expect(header).toContain(`Max-Age=2592000`);
  });

  it("accepts the email case-insensitively and with surrounding whitespace", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "  OWNER@Example.COM  ", password: TEST_PASSWORD },
    });
    expect(res.statusCode).toBe(200);
  });

  it("rejects a wrong password with 401", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "owner@example.com", password: "wrong-password" },
    });
    expect(res.statusCode).toBe(401);
    expect(res.headers["set-cookie"]).toBeUndefined();
  });

  it("rejects a wrong email with 401", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "intruder@example.com", password: TEST_PASSWORD },
    });
    expect(res.statusCode).toBe(401);
    expect(res.headers["set-cookie"]).toBeUndefined();
  });

  it("returns a byte-identical body for wrong email and wrong password", async () => {
    // The whole point of the generic message: the response must not reveal which
    // of the two fields was wrong.
    const wrongPassword = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "owner@example.com", password: "wrong-password" },
    });
    const wrongEmail = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "intruder@example.com", password: TEST_PASSWORD },
    });

    expect(wrongPassword.statusCode).toBe(wrongEmail.statusCode);
    expect(wrongPassword.body).toBe(wrongEmail.body);
  });

  it("rejects a malformed body with 400 and issues no cookie", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "owner@example.com" },
    });
    expect(res.statusCode).toBe(400);
    expect(res.headers["set-cookie"]).toBeUndefined();
  });

  it("does not leak the configured email or hash in a failure response", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "intruder@example.com", password: "wrong-password" },
    });
    expect(res.body).not.toContain(baseConfig.email);
    expect(res.body).not.toContain(baseConfig.passwordHash);
    expect(res.body).not.toContain(baseConfig.jwtSecret);
  });

  it("omits the Secure attribute when COOKIE_SECURE is false", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "owner@example.com", password: TEST_PASSWORD },
    });
    const header = String(res.headers["set-cookie"]);
    expect(header).not.toContain("Secure");
  });

  it("sets the Secure attribute when COOKIE_SECURE is true", async () => {
    // Proves the flag is runtime-driven rather than hardcoded either way.
    const secureApp = await buildTestApp({ ...baseConfig, cookieSecure: true });
    const res = await secureApp.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "owner@example.com", password: TEST_PASSWORD },
    });
    const header = String(res.headers["set-cookie"]);
    expect(header).toContain("Secure");
    await secureApp.close();
  });
});

describe("POST /auth/login -- token in the response body (native clients)", () => {
  it("returns the token and its lifetime alongside ok", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "owner@example.com", password: TEST_PASSWORD },
    });

    expect(res.statusCode).toBe(200);
    const body = res.json() as { ok: boolean; token: string; expiresIn: number };
    expect(body.ok).toBe(true);
    expect(typeof body.token).toBe("string");
    // Seconds, matching the cookie's Max-Age and the JWT's own expiry.
    expect(body.expiresIn).toBe(2592000);
  });

  it("still sets the httpOnly cookie, so the web client is untouched", async () => {
    // The body copy is additive: dropping the cookie would silently log out the
    // existing React frontend, which has no way to read the body token.
    const res = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "owner@example.com", password: TEST_PASSWORD },
    });

    const cookie = res.cookies.find((c) => c.name === SESSION_COOKIE_NAME);
    expect(cookie?.value).toBeTruthy();
    expect(String(res.headers["set-cookie"])).toContain("HttpOnly");
  });

  it("hands out the very same token in the cookie and in the body", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "owner@example.com", password: TEST_PASSWORD },
    });
    const cookie = res.cookies.find((c) => c.name === SESSION_COOKIE_NAME);
    expect((res.json() as { token: string }).token).toBe(cookie?.value);
  });

  it("issues a body token that a protected route accepts as a Bearer header", async () => {
    // The whole point of B1: @fastify/jwt reads `Authorization: Bearer` before it
    // looks at the cookie, so a native client never needs a cookie jar and
    // `authGuard` needs no Bearer handling of its own.
    const token = await loginForBodyToken(app);

    const res = await app.inject({
      method: "GET",
      url: PROTECTED_TEST_ROUTE,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ reached: true });
  });

  it("prefers a valid Bearer header over a garbage cookie", async () => {
    // Pins the precedence the plan relies on: header first, cookie only as a
    // fallback. If a future @fastify/jwt flipped that order, this fails loudly.
    const token = await loginForBodyToken(app);

    const res = await app.inject({
      method: "GET",
      url: PROTECTED_TEST_ROUTE,
      headers: { authorization: `Bearer ${token}` },
      cookies: { [SESSION_COOKIE_NAME]: "garbage.token.value" },
    });
    expect(res.statusCode).toBe(200);
  });

  it("rejects a forged Bearer header", async () => {
    const res = await app.inject({
      method: "GET",
      url: PROTECTED_TEST_ROUTE,
      headers: { authorization: "Bearer garbage.token.value" },
    });
    expect(res.statusCode).toBe(401);
  });

  it("returns no token at all on a wrong password", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "owner@example.com", password: "wrong-password" },
    });
    expect(res.statusCode).toBe(401);
    expect(res.json()).toEqual({ error: "Unauthorized", message: "Invalid email or password" });
    expect(res.body).not.toContain("token");
  });
});

describe("GET /auth/me", () => {
  it("rejects a request with no credentials at all", async () => {
    const res = await app.inject({ method: "GET", url: "/auth/me" });
    expect(res.statusCode).toBe(401);
  });

  it("is protected rather than public", () => {
    // Guards against someone "fixing" a 401 by adding it to PUBLIC_ROUTES: a
    // public /auth/me would answer 200 for everyone and mean nothing.
    expect(isPublicRoute("GET", "/auth/me")).toBe(false);
  });

  it("answers 200 for a token supplied as a Bearer header", async () => {
    const token = await loginForBodyToken(app);
    const res = await app.inject({
      method: "GET",
      url: "/auth/me",
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true });
  });

  it("answers 200 for a token supplied as the session cookie", async () => {
    const token = await login(app);
    const res = await app.inject({
      method: "GET",
      url: "/auth/me",
      cookies: { [SESSION_COOKIE_NAME]: token },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true });
  });

  it("rejects an expired token", async () => {
    const expired = app.jwt.sign({ sub: "owner" }, { expiresIn: -60 });
    const res = await app.inject({
      method: "GET",
      url: "/auth/me",
      headers: { authorization: `Bearer ${expired}` },
    });
    expect(res.statusCode).toBe(401);
  });

  it("leaks no identity in the body", async () => {
    // The token carries a deliberately minimal claim set; the probe must not
    // undo that by echoing the configured email back to whoever holds a token.
    const token = await loginForBodyToken(app);
    const res = await app.inject({
      method: "GET",
      url: "/auth/me",
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.body).not.toContain(baseConfig.email);
    expect(res.body).not.toContain("owner");
  });
});

describe("POST /auth/logout", () => {
  it("clears the session cookie", async () => {
    const res = await app.inject({ method: "POST", url: "/auth/logout" });
    expect(res.statusCode).toBe(200);

    const header = String(res.headers["set-cookie"]);
    expect(header).toContain(`${SESSION_COOKIE_NAME}=;`);
    expect(header).toContain("Max-Age=0");
    expect(header).toContain("Path=/");
  });

  it("leaves a protected route unreachable with the cleared cookie value", async () => {
    const logout = await app.inject({ method: "POST", url: "/auth/logout" });
    const cleared = logout.cookies.find((c) => c.name === SESSION_COOKIE_NAME);
    expect(cleared?.value).toBe("");

    const res = await app.inject({
      method: "GET",
      url: PROTECTED_TEST_ROUTE,
      cookies: { [SESSION_COOKIE_NAME]: cleared?.value ?? "" },
    });
    expect(res.statusCode).toBe(401);
  });
});

describe("session token round-trip", () => {
  it("signs and verifies a token with the configured secret", async () => {
    const token = app.jwt.sign({ sub: "owner" }, { expiresIn: 3600 });
    const payload = app.jwt.verify<{ sub: string; iat: number; exp: number }>(token);
    expect(payload.sub).toBe("owner");
    expect(payload.exp - payload.iat).toBe(3600);
  });

  it("issues login tokens that expire in exactly 30 days", async () => {
    const token = await login(app);
    const payload = app.jwt.verify<{ sub: string; iat: number; exp: number }>(token);
    expect(payload.sub).toBe("owner");
    expect(payload.exp - payload.iat).toBe(2592000);
  });

  it("carries no claims beyond the minimal subject and timestamps", async () => {
    const token = await login(app);
    const payload = app.jwt.verify<Record<string, unknown>>(token);
    // No email, no hash, no roles -- nothing sensitive rides in the cookie.
    expect(Object.keys(payload).sort()).toEqual(["exp", "iat", "sub"]);
  });

  it("fails to verify a tampered token", async () => {
    const token = app.jwt.sign({ sub: "owner" }, { expiresIn: 3600 });
    const tampered = tamperWithSignature(token);
    expect(() => app.jwt.verify(tampered)).toThrow();
  });

  it("detects tampering even on a signature ending in the padded 'A'", async () => {
    /*
     * Pins the exact case that used to make "fails to verify a tampered token"
     * flaky, so the old character-swap cannot quietly come back. Roughly one
     * signature in sixteen ends in "A"; 500 attempts find one with certainty.
     */
    let token: string | undefined;
    for (let nonce = 0; nonce < 500 && token === undefined; nonce++) {
      const candidate = app.jwt.sign({ sub: "owner", nonce }, { expiresIn: 3600 });
      if (candidate.endsWith("A")) {
        token = candidate;
      }
    }
    if (token === undefined) {
      throw new Error("no signature ending in 'A' produced in 500 attempts");
    }

    // The old tampering was a no-op here: "...A" and "...B" decode to identical
    // signature bytes, so the "corrupted" token verifies -- correctly.
    expect(() => app.jwt.verify(`${token.slice(0, -1)}B`)).not.toThrow();
    // The byte-level tampering is not fooled by the padding.
    expect(() => app.jwt.verify(tamperWithSignature(token))).toThrow();
  });

  it("fails to verify an expired token", async () => {
    const expired = app.jwt.sign({ sub: "owner" }, { expiresIn: -60 });
    expect(() => app.jwt.verify(expired)).toThrow();
  });

  it("fails to verify a token signed with a different secret", async () => {
    const otherApp = await buildTestApp({ ...baseConfig, jwtSecret: "yet-another-distinct-secret-value-abc" });
    const foreignToken = otherApp.jwt.sign({ sub: "owner" }, { expiresIn: 3600 });
    await otherApp.close();

    expect(() => app.jwt.verify(foreignToken)).toThrow();
  });
});
