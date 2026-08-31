import { describe, it, expect, beforeAll, afterAll } from "vitest";
import type { FastifyInstance } from "fastify";
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
    // Corrupt the final signature character.
    const lastChar = token.slice(-1);
    const tampered = token.slice(0, -1) + (lastChar === "A" ? "B" : "A");

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
    expect(res.json()).toEqual({ ok: true });

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
    const lastChar = token.slice(-1);
    const tampered = token.slice(0, -1) + (lastChar === "A" ? "B" : "A");
    expect(() => app.jwt.verify(tampered)).toThrow();
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
