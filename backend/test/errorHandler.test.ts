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

/** A string that would be damning if it ever reached a client. */
const SECRET_IN_MESSAGE = "postgresql://taskradar:hunter2@127.0.0.1:5432/taskradar";

/** Test-only routes, registered on the real app so the real error handler runs. */
const ROUTES = {
  /** Takes a body, so an empty/invalid/oversized one is parsed (and rejected) before the handler. */
  echo: "/__test/echo",
  /** Same, with a tiny body limit so the 413 path needs no megabyte payload. */
  tiny: "/__test/tiny-limit",
  /** Throws a plain Error -- the genuinely unexpected failure. */
  boom: "/__test/boom",
  /** Throws an error carrying a `statusCode` supplied by the caller via ?status=. */
  status: "/__test/status",
} as const;

let buildApp: (options?: BuildAppOptions) => Promise<FastifyInstance>;
let app: FastifyInstance;
let token: string;

/** An error shaped like the ones Fastify and its plugins throw. */
class StatusCarryingError extends Error {
  constructor(
    readonly statusCode: unknown,
    message: string,
  ) {
    super(message);
    this.name = "StatusCarryingError";
  }
}

beforeAll(async () => {
  const appModule = await import("../src/app");
  buildApp = appModule.buildApp;
  app = await buildApp({ authConfig: baseConfig, logger: false });

  app.post(ROUTES.echo, async (request) => ({ got: request.body }));
  // 16 bytes is below every payload this suite sends on that route.
  app.post(ROUTES.tiny, { bodyLimit: 16 }, async (request) => ({ got: request.body }));
  app.get(ROUTES.boom, async () => {
    throw new Error(`boom while talking to ${SECRET_IN_MESSAGE}`);
  });
  app.get(ROUTES.status, async (request) => {
    const query = request.query as { status?: string; message?: string };
    const raw = query.status ?? "";
    // `?status=nan` exercises the non-numeric case; anything else is parsed.
    const statusCode: unknown = raw === "nan" ? raw : Number(raw);
    throw new StatusCarryingError(statusCode, query.message ?? "thrown by a plugin");
  });

  await app.ready();

  const login = await app.inject({
    method: "POST",
    url: "/auth/login",
    payload: { email: baseConfig.email, password: TEST_PASSWORD },
  });
  token = (login.json() as { token: string }).token;
});

afterAll(async () => {
  await app?.close();
});

/** Authenticated inject: the guard must be satisfied before the error handler is reachable. */
function authed(
  options: Parameters<FastifyInstance["inject"]>[0],
): ReturnType<FastifyInstance["inject"]> {
  const opts = options as { headers?: Record<string, string> };
  return app.inject({
    ...(options as object),
    headers: { ...(opts.headers ?? {}), authorization: `Bearer ${token}` },
  } as Parameters<FastifyInstance["inject"]>[0]);
}

describe("malformed requests keep their own 4xx status", () => {
  it("answers 400, not 500, for an empty body with Content-Type: application/json", async () => {
    /*
     * The exact request an HTTP client that always sets Content-Type sends to a
     * bodyless route (dio does this on POST /projects/:id/archive). Before the
     * fix this came back 500 and the client concluded the server had crashed.
     */
    const res = await authed({
      method: "POST",
      url: ROUTES.echo,
      headers: { "content-type": "application/json" },
      payload: "",
    });

    expect(res.statusCode).toBe(400);
    expect(res.json()).toEqual({
      error: "BadRequest",
      message: expect.stringContaining("empty"),
    });
  });

  it("answers 400 for the same request against a real bodyless route", async () => {
    // Belt and braces: the routes the Flutter client actually calls, not just a
    // test fixture. POST /auth/logout is public, so no token is involved.
    const res = await app.inject({
      method: "POST",
      url: "/auth/logout",
      headers: { "content-type": "application/json" },
      payload: "",
    });
    expect(res.statusCode).toBe(400);
    expect((res.json() as { error: string }).error).toBe("BadRequest");
  });

  it("answers 400 for a body that is not valid JSON", async () => {
    const res = await authed({
      method: "POST",
      url: ROUTES.echo,
      headers: { "content-type": "application/json" },
      payload: '{"name":',
    });

    expect(res.statusCode).toBe(400);
    expect(res.json()).toEqual({
      error: "BadRequest",
      message: expect.stringContaining("JSON"),
    });
  });

  it("answers 415 for an unsupported Content-Type", async () => {
    const res = await authed({
      method: "POST",
      url: ROUTES.echo,
      headers: { "content-type": "application/xml" },
      payload: "<project/>",
    });

    expect(res.statusCode).toBe(415);
    expect(res.json()).toEqual({
      error: "UnsupportedMediaType",
      message: expect.stringContaining("Unsupported Media Type"),
    });
  });

  it("answers 413 for a body over the limit", async () => {
    const res = await authed({
      method: "POST",
      url: ROUTES.tiny,
      headers: { "content-type": "application/json" },
      payload: JSON.stringify({ name: "x".repeat(64) }),
    });

    expect(res.statusCode).toBe(413);
    expect(res.json()).toEqual({
      error: "PayloadTooLarge",
      message: expect.stringContaining("too large"),
    });
  });

  it("answers in the same `{ error, message }` shape as every other error", async () => {
    // Not Fastify's own `{ statusCode, code, error, message }`: a client parsing
    // error bodies must not need a second code path for framework-raised ones.
    const res = await authed({
      method: "POST",
      url: ROUTES.echo,
      headers: { "content-type": "application/json" },
      payload: "",
    });
    expect(res.statusCode).toBe(400);
    expect(Object.keys(res.json() as object).sort()).toEqual(["error", "message"]);
  });

  it("leaks no framework internals in a 4xx body", async () => {
    const res = await authed({
      method: "POST",
      url: ROUTES.echo,
      headers: { "content-type": "application/json" },
      payload: "",
    });
    expect(res.statusCode).toBe(400);
    // No Fastify error code, no stack, no source paths: the message describes the
    // request, nothing else.
    expect(res.body).not.toMatch(/FST_ERR|stack|node_modules|\bat .*:\d+:\d+/);
  });
});

describe("statusCode passthrough boundaries", () => {
  it("honours an arbitrary mapped 4xx from a thrown error", async () => {
    const res = await authed({ method: "GET", url: `${ROUTES.status}?status=429` });
    expect(res.statusCode).toBe(429);
    expect(res.json()).toEqual({ error: "TooManyRequests", message: "thrown by a plugin" });
  });

  it("falls back to a generic name for an unmapped 4xx", async () => {
    const res = await authed({ method: "GET", url: `${ROUTES.status}?status=418` });
    expect(res.statusCode).toBe(418);
    expect((res.json() as { error: string }).error).toBe("ClientError");
  });

  it("still answers an opaque 500 for an error carrying a 5xx statusCode", async () => {
    // 5xx means the server broke; its message may name a host, a query or a
    // secret, so it must not be forwarded just because a statusCode was present.
    const res = await authed({
      method: "GET",
      url: `${ROUTES.status}?status=503&message=${encodeURIComponent(SECRET_IN_MESSAGE)}`,
    });
    expect(res.statusCode).toBe(500);
    expect(res.json()).toEqual({ error: "InternalServerError", message: "Something went wrong" });
    expect(res.body).not.toContain("hunter2");
  });

  it("still answers an opaque 500 for a non-numeric statusCode", async () => {
    const res = await authed({ method: "GET", url: `${ROUTES.status}?status=nan` });
    expect(res.statusCode).toBe(500);
    expect(res.json()).toEqual({ error: "InternalServerError", message: "Something went wrong" });
  });

  it("still answers an opaque 500 for a nonsensical numeric statusCode", async () => {
    const res = await authed({ method: "GET", url: `${ROUTES.status}?status=399` });
    expect(res.statusCode).toBe(500);
    expect((res.json() as { error: string }).error).toBe("InternalServerError");
  });
});

describe("genuinely unexpected errors stay opaque", () => {
  it("answers 500 with a fixed body and no detail from the error", async () => {
    const res = await authed({ method: "GET", url: ROUTES.boom });

    expect(res.statusCode).toBe(500);
    expect(res.json()).toEqual({ error: "InternalServerError", message: "Something went wrong" });
  });

  it("leaks neither the message, the connection string nor a stack frame", async () => {
    const res = await authed({ method: "GET", url: ROUTES.boom });

    expect(res.body).not.toContain("boom");
    expect(res.body).not.toContain(SECRET_IN_MESSAGE);
    expect(res.body).not.toContain("hunter2");
    expect(res.body).not.toMatch(/stack|node_modules|errorHandler|\bat .*:\d+:\d+/);
  });
});

describe("the existing error classes are unaffected", () => {
  it("still turns a ZodError into a 400 with its issue list", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "owner@example.com" },
    });
    expect(res.statusCode).toBe(400);
    const body = res.json() as { error: string; message: string; details: unknown[] };
    expect(body.error).toBe("ValidationError");
    expect(Array.isArray(body.details)).toBe(true);
  });

  it("still turns an HttpError into its own status", async () => {
    // ZodError has no statusCode and HttpError is matched before the new branch,
    // so neither can be swallowed by the 4xx passthrough.
    const { NotFoundError } = await import("../src/lib/errors");
    const error = new NotFoundError("Project");
    expect(error.statusCode).toBe(404);
    expect(error.name).toBe("NotFoundError");
  });
});

describe("the auth guard's 401 behaviour is untouched", () => {
  it("still answers a flat 401 on an unknown route for an unauthenticated caller", async () => {
    // Deliberate: an unauthenticated caller must not be able to map the route
    // table by watching 404s. The new 4xx branch must not turn this into a 404.
    const res = await app.inject({ method: "GET", url: "/__no_such_route_at_all" });
    expect(res.statusCode).toBe(401);
    expect(res.json()).toEqual({ error: "Unauthorized", message: "Unauthorized" });
  });

  it("still answers 404 on an unknown route once authenticated", async () => {
    const res = await authed({ method: "GET", url: "/__no_such_route_at_all" });
    expect(res.statusCode).toBe(404);
  });

  it("rejects a malformed body request with 401 before parsing it, when unauthenticated", async () => {
    // Order matters: the guard runs onRequest, i.e. before body parsing, so a bad
    // body on a protected route reveals nothing to an anonymous caller.
    const res = await app.inject({
      method: "POST",
      url: ROUTES.echo,
      headers: { "content-type": "application/json" },
      payload: "",
    });
    expect(res.statusCode).toBe(401);
    expect(res.json()).toEqual({ error: "Unauthorized", message: "Unauthorized" });
  });

  it("still answers an opaque 401 for a garbage token", async () => {
    const res = await app.inject({
      method: "POST",
      url: ROUTES.echo,
      headers: { authorization: "Bearer garbage.token.value", "content-type": "application/json" },
      payload: { name: "whatever" },
    });
    expect(res.statusCode).toBe(401);
    expect(res.json()).toEqual({ error: "Unauthorized", message: "Unauthorized" });
  });
});
