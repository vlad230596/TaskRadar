import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach, vi } from "vitest";
import type { FastifyInstance } from "fastify";
// Type-only imports are erased at compile time, so these do NOT load the modules
// (and therefore do not construct a Prisma client) before the mock below is in place.
import type { AuthConfig } from "../src/lib/authConfig";
import type { BuildAppOptions } from "../src/app";

/*
 * There is no database in this environment, so the Prisma client is replaced
 * wholesale. `$queryRaw` is the only member these routes touch, and having it be
 * a mock is the entire point of this file: the interesting half of `/ready` is
 * the branch where the database is *unreachable*, and that branch is unreachable
 * in a test any other way. Dropping the real PostgreSQL to exercise it is not an
 * option -- it is a shared service.
 */
const prismaMock = vi.hoisted(() => ({
  $queryRaw: vi.fn(),
  project: { findMany: vi.fn(), findUnique: vi.fn() },
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));

// Belt and braces: if the mock above ever stops matching the module id, the real
// client is constructed instead, and it demands DATABASE_URL at import time.
process.env.DATABASE_URL ??= "postgresql://placeholder:placeholder@localhost:5432/placeholder";

/*
 * A real bcrypt hash (of an unrelated throwaway password, at cost 4) rather than
 * a placeholder string: `loadAuthConfig` is bypassed here, but the app still
 * registers the login route against this value at boot. No test in this file
 * logs in -- the whole point is that these three routes need no credentials.
 */
const TEST_HASH = "$2b$04$zV5VFEALedx8Rfd/ucwUSOrHYSSr8xveuActiCTdzOmCsBSDTbYXO";

const baseConfig: AuthConfig = {
  email: "owner@example.com",
  passwordHash: TEST_HASH,
  jwtSecret: "test-jwt-secret-".repeat(4),
  cookieSecure: false,
};

/**
 * A driver error shaped like the real thing: Prisma's connection failures put
 * the host, the port and the database name straight into `message`. The whole
 * reason `/ready` catches instead of rethrowing is that this string must not
 * reach the client, so the fixture has to actually contain the secret it is
 * asserted not to leak.
 */
const SECRET_HOST = "db.internal.example";
const SECRET_URL = `postgresql://taskradar:hunter2@${SECRET_HOST}:5432/taskradar`;
function driverFailure(): Error {
  const error = new Error(
    `Can't reach database server at \`${SECRET_HOST}:5432\`. ` +
      `Please make sure your database server is running at \`${SECRET_URL}\`.`,
  );
  error.name = "PrismaClientInitializationError";
  (error as { errorCode?: string }).errorCode = "P1001";
  (error as { clientVersion?: string }).clientVersion = "6.19.3";
  return error;
}

let buildApp: (options?: BuildAppOptions) => Promise<FastifyInstance>;
let app: FastifyInstance;

const ORIGINAL_APP_VERSION = process.env.APP_VERSION;
const ORIGINAL_BUILD_DATE = process.env.BUILD_DATE;

beforeAll(async () => {
  const appModule = await import("../src/app");
  buildApp = appModule.buildApp;
  app = await buildApp({ authConfig: baseConfig, logger: false });
  await app.ready();
});

afterAll(async () => {
  await app?.close();
});

beforeEach(() => {
  prismaMock.$queryRaw.mockReset();
  prismaMock.$queryRaw.mockResolvedValue([{ "?column?": 1 }]);
});

afterEach(() => {
  // These are process-wide, so leaking one would silently rewrite what a later
  // test (or a later file, sharing the worker) sees.
  if (ORIGINAL_APP_VERSION === undefined) delete process.env.APP_VERSION;
  else process.env.APP_VERSION = ORIGINAL_APP_VERSION;
  if (ORIGINAL_BUILD_DATE === undefined) delete process.env.BUILD_DATE;
  else process.env.BUILD_DATE = ORIGINAL_BUILD_DATE;
});

describe("GET /health -- liveness", () => {
  it("answers 200 with the exact body the deploy script greps for", async () => {
    const res = await app.inject({ method: "GET", url: "/health" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ status: "ok" });
    // scripts/deploy-production.sh matches on this substring, not on parsed JSON.
    expect(res.body).toContain('"status":"ok"');
  });

  it("never touches the database, so it keeps answering during an outage", async () => {
    prismaMock.$queryRaw.mockRejectedValue(driverFailure());
    const res = await app.inject({ method: "GET", url: "/health" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ status: "ok" });
    expect(prismaMock.$queryRaw).not.toHaveBeenCalled();
  });

  it("is reachable without a token", async () => {
    expect((await app.inject({ method: "GET", url: "/health" })).statusCode).toBe(200);
  });
});

describe("GET /ready -- readiness", () => {
  it("answers 200 after a successful database round-trip", async () => {
    const res = await app.inject({ method: "GET", url: "/ready" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ status: "ready" });
    expect(prismaMock.$queryRaw).toHaveBeenCalledTimes(1);
  });

  it("really asks the database rather than reporting a cached verdict", async () => {
    // A probe that answers from memory is worse than none: it would report the
    // state of some earlier request instead of the state right now.
    await app.inject({ method: "GET", url: "/ready" });
    await app.inject({ method: "GET", url: "/ready" });
    expect(prismaMock.$queryRaw).toHaveBeenCalledTimes(2);
  });

  it("probes with a statement that touches no table", async () => {
    // `SELECT 1` works before the first migration and cannot get slower as data
    // grows. A probe that read a real table would fail an empty new deployment.
    await app.inject({ method: "GET", url: "/ready" });
    const [strings] = prismaMock.$queryRaw.mock.calls[0] as [TemplateStringsArray];
    expect(strings.join("").trim()).toBe("SELECT 1");
  });

  it("answers 503, not 500, when the database is unreachable", async () => {
    prismaMock.$queryRaw.mockRejectedValue(driverFailure());
    const res = await app.inject({ method: "GET", url: "/ready" });
    expect(res.statusCode).toBe(503);
  });

  it("answers 503 for a rejection that is not an Error either", async () => {
    // Nothing guarantees a driver rejects with an Error; a non-Error must not
    // fall past the catch and become an opaque 500.
    prismaMock.$queryRaw.mockRejectedValue("connection reset");
    expect((await app.inject({ method: "GET", url: "/ready" })).statusCode).toBe(503);
  });

  it("leaks neither the connection string nor any driver detail", async () => {
    prismaMock.$queryRaw.mockRejectedValue(driverFailure());
    const res = await app.inject({ method: "GET", url: "/ready" });

    expect(res.body).not.toContain(SECRET_HOST);
    expect(res.body).not.toContain("hunter2");
    expect(res.body).not.toContain("postgresql://");
    expect(res.body).not.toContain("P1001");
    expect(res.body).not.toContain("6.19.3");
    expect(res.body).not.toContain("PrismaClientInitializationError");
    expect(res.body.toLowerCase()).not.toContain("stack");
  });

  it("sends exactly { error, message } and nothing more", async () => {
    prismaMock.$queryRaw.mockRejectedValue(driverFailure());
    const res = await app.inject({ method: "GET", url: "/ready" });
    const body = res.json() as Record<string, unknown>;
    expect(Object.keys(body).sort()).toEqual(["error", "message"]);
    expect(body).toEqual({ error: "ServiceUnavailable", message: "Database unavailable" });
  });

  it("recovers on its own once the database comes back", async () => {
    prismaMock.$queryRaw.mockRejectedValueOnce(driverFailure());
    expect((await app.inject({ method: "GET", url: "/ready" })).statusCode).toBe(503);
    expect((await app.inject({ method: "GET", url: "/ready" })).statusCode).toBe(200);
  });

  it("is reachable without a token", async () => {
    const res = await app.inject({ method: "GET", url: "/ready" });
    expect(res.statusCode).toBe(200);
  });

  it("stays reachable without a token even while failing", async () => {
    // The failure path must be a 503 for an anonymous caller, not a 401: a probe
    // that cannot tell "not ready" from "not allowed" is useless.
    prismaMock.$queryRaw.mockRejectedValue(driverFailure());
    expect((await app.inject({ method: "GET", url: "/ready" })).statusCode).toBe(503);
  });
});

describe("GET /version", () => {
  it("reports the version baked into the image", async () => {
    process.env.APP_VERSION = "1.4.2";
    process.env.BUILD_DATE = "2026-09-16T08:00:00Z";
    const res = await app.inject({ method: "GET", url: "/version" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ version: "1.4.2", buildDate: "2026-09-16T08:00:00Z" });
  });

  it("falls back to dev/unknown when the variables are absent", async () => {
    delete process.env.APP_VERSION;
    delete process.env.BUILD_DATE;
    const res = await app.inject({ method: "GET", url: "/version" });
    expect(res.statusCode).toBe(200);
    // Same strings compose.prod.yaml defaults to, so a dev run and an unversioned
    // container describe themselves identically.
    expect(res.json()).toEqual({ version: "dev", buildDate: "unknown" });
  });

  it("treats an empty variable as absent rather than reporting an empty version", async () => {
    // Compose and shell pipelines produce empty strings, not unset variables, far
    // more often than anyone expects; `""` as a version is a worse answer than "dev".
    process.env.APP_VERSION = "";
    process.env.BUILD_DATE = "";
    expect((await app.inject({ method: "GET", url: "/version" })).json()).toEqual({
      version: "dev",
      buildDate: "unknown",
    });
  });

  it("reflects a change without a restart", async () => {
    process.env.APP_VERSION = "2.0.0";
    expect(((await app.inject({ method: "GET", url: "/version" })).json() as { version: string }).version).toBe("2.0.0");
    process.env.APP_VERSION = "2.0.1";
    expect(((await app.inject({ method: "GET", url: "/version" })).json() as { version: string }).version).toBe("2.0.1");
  });

  it("exposes those two fields and nothing else", async () => {
    const body = (await app.inject({ method: "GET", url: "/version" })).json() as Record<string, unknown>;
    expect(Object.keys(body).sort()).toEqual(["buildDate", "version"]);
  });

  it("discloses no environment, path or dependency detail", async () => {
    process.env.APP_VERSION = "1.4.2";
    const res = await app.inject({ method: "GET", url: "/version" });
    for (const forbidden of ["node", "prisma", "fastify", "/app", "NODE_ENV", "production", "DATABASE_URL"]) {
      expect(res.body.toLowerCase()).not.toContain(forbidden.toLowerCase());
    }
  });

  it("never touches the database", async () => {
    await app.inject({ method: "GET", url: "/version" });
    expect(prismaMock.$queryRaw).not.toHaveBeenCalled();
  });

  it("is reachable without a token", async () => {
    expect((await app.inject({ method: "GET", url: "/version" })).statusCode).toBe(200);
  });
});

describe("the new public routes do not weaken route enumeration", () => {
  /*
   * The guard answers 401 for a path that resolved to no route, precisely so an
   * unauthenticated caller cannot tell an existing route from a missing one.
   * Three more allowlist entries must not turn into three more oracles.
   */
  it("still answers 401, not 404, for unknown paths near the new routes", async () => {
    const paths = [
      "/readyz",
      "/ready/",
      "/readiness",
      "/ready/db",
      "/versions",
      "/version/",
      "/version/backend",
      "/healthz",
      "/nope",
      "/.env",
    ];
    for (const url of paths) {
      const res = await app.inject({ method: "GET", url });
      expect(res.statusCode, url).toBe(401);
      expect(res.json(), url).toEqual({ error: "Unauthorized", message: "Unauthorized" });
    }
  });

  it("opens only the GET method on each new route", async () => {
    for (const method of ["POST", "PUT", "PATCH", "DELETE"] as const) {
      for (const url of ["/ready", "/version", "/health"]) {
        const res = await app.inject({ method, url });
        // No handler is registered for these, so they are unresolved routes and
        // land in exactly the same 401 bucket as any other unknown path.
        expect(res.statusCode, `${method} ${url}`).toBe(401);
      }
    }
  });

  it("gives an unauthenticated caller the same answer for a real and a fake route", async () => {
    const real = await app.inject({ method: "GET", url: "/projects" });
    const fake = await app.inject({ method: "GET", url: "/projects-that-do-not-exist" });
    expect(real.statusCode).toBe(401);
    expect(fake.statusCode).toBe(401);
    expect(real.body).toBe(fake.body);
  });

  it("leaves the data routes closed", async () => {
    for (const url of ["/projects", "/board"]) {
      expect((await app.inject({ method: "GET", url })).statusCode, url).toBe(401);
    }
    const patch = await app.inject({
      method: "PATCH",
      url: "/projects/whatever",
      payload: { name: "renamed without a token" },
    });
    expect(patch.statusCode).toBe(401);
    // Rejected by the guard before the handler, so the database is never touched.
    expect(prismaMock.project.findUnique).not.toHaveBeenCalled();
  });
});

/*
 * NOT covered here, and deliberately so: that a real PostgreSQL outage produces
 * the rejection this file fakes. The mapping "rejection -> 503, no details" is
 * asserted; what Prisma actually throws when the server disappears, and how long
 * it takes to decide, needs a live database that can be taken down, which this
 * repo has no harness for.
 */
