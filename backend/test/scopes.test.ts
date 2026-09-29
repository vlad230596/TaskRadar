import { describe, it, expect, beforeAll, afterAll, beforeEach, vi } from "vitest";
import type { FastifyInstance } from "fastify";
import type { AuthConfig } from "../src/lib/authConfig";
import type { BuildAppOptions } from "../src/app";
import { inMemoryUsers, tokenFor, USER_A, USER_B } from "./support/users";

/*
 * The scope routes (F7).
 *
 * Same shape as `projects.test.ts`: no database in this environment, so Prisma
 * is a small in-memory fake that actually mutates rows rather than a stub that
 * echoes its input. The questions here -- did the order really change, did the
 * delete refuse *and leave everything alone* -- cannot be answered by a stub.
 */
const prismaMock = vi.hoisted(() => ({
  scope: {
    findMany: vi.fn(),
    findFirst: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
    count: vi.fn(),
  },
  project: { count: vi.fn() },
  $transaction: vi.fn(),
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));

process.env.DATABASE_URL ??= "postgresql://placeholder:placeholder@localhost:5432/placeholder";

/** bcrypt hash of the shared test password at cost 4 (see test/support/users.ts). */
const TEST_HASH = "$2b$04$zV5VFEALedx8Rfd/ucwUSOrHYSSr8xveuActiCTdzOmCsBSDTbYXO";

const baseConfig: AuthConfig = {
  email: "owner@example.com",
  passwordHash: TEST_HASH,
  jwtSecret: "test-jwt-secret-".repeat(4),
  cookieSecure: false,
};

interface ScopeRow {
  id: string;
  userId: string;
  name: string;
  position: number;
  createdAt: Date;
  updatedAt: Date;
}

const T0 = new Date("2026-01-01T00:00:00.000Z");

let scopes: ScopeRow[] = [];
/** How many projects each scope holds, for the delete guard. */
let projectCounts: Record<string, number> = {};

function seed(): void {
  scopes = [
    { id: "s-work", userId: USER_A.id, name: "Работа", position: 1000, createdAt: T0, updatedAt: T0 },
    { id: "s-home", userId: USER_A.id, name: "Личное", position: 2000, createdAt: T0, updatedAt: T0 },
    { id: "s-dacha", userId: USER_A.id, name: "Дача", position: 3000, createdAt: T0, updatedAt: T0 },
    // Somebody else's scope, positioned *between* A's so that a missing owner
    // filter shows up in every ordering, count and neighbour lookup below.
    { id: "s-b-only", userId: USER_B.id, name: "Борис", position: 1500, createdAt: T0, updatedAt: T0 },
  ];
  projectCounts = { "s-work": 2, "s-home": 0, "s-dacha": 0 };
}

/** A's scopes in position order: what the app returns when acting as USER_A. */
function sorted(userId: string = USER_A.id): ScopeRow[] {
  return scopes.filter((s) => s.userId === userId).sort((a, b) => a.position - b.position);
}

/**
 * Evaluates the `where` shapes the scope routes use -- `{ id }`, `{ userId }`
 * and both together -- against the rows. The owner filter is really applied,
 * which is what gives the isolation tests below any meaning. Anything else
 * throws instead of quietly matching everything.
 */
function matches(row: ScopeRow, where: Record<string, unknown> = {}): boolean {
  for (const [key, value] of Object.entries(where)) {
    if (key !== "id" && key !== "userId") throw new Error(`fake: unsupported scope where key "${key}"`);
    if (row[key] !== value) return false;
  }
  return true;
}

let buildApp: (options?: BuildAppOptions) => Promise<FastifyInstance>;
let app: FastifyInstance;
let token: string;
let tokenB: string;

/** Acts as USER_A unless `bearer` says otherwise (pass `tokenB` to act as USER_B). */
function call(method: string, url: string, payload?: unknown, withToken = true, bearer?: string) {
  return app.inject({
    method: method as "GET",
    url,
    headers: withToken ? { authorization: `Bearer ${bearer ?? token}` } : {},
    ...(payload === undefined ? {} : { payload: payload as Record<string, unknown> }),
  });
}

beforeAll(async () => {
  const appModule = await import("../src/app");
  buildApp = appModule.buildApp;
  app = await buildApp({ authConfig: baseConfig, users: inMemoryUsers(), logger: false });
  await app.ready();

  token = await tokenFor(app, USER_A.email);
  tokenB = await tokenFor(app, USER_B.email);
});

afterAll(async () => {
  await app?.close();
});

beforeEach(() => {
  seed();
  for (const fn of Object.values(prismaMock.scope)) fn.mockReset();
  prismaMock.project.count.mockReset();
  prismaMock.$transaction.mockReset();

  prismaMock.scope.findMany.mockImplementation(
    (args?: { where?: Record<string, unknown>; orderBy?: { position: "asc" | "desc" } }) => {
      const rows = scopes.filter((s) => matches(s, args?.where)).sort((a, b) => a.position - b.position);
      return args?.orderBy?.position === "desc" ? rows.reverse() : rows;
    },
  );
  prismaMock.scope.findFirst.mockImplementation(
    (args?: { where?: Record<string, unknown>; orderBy?: { position: "asc" | "desc" } }) => {
      const rows = scopes.filter((s) => matches(s, args?.where)).sort((a, b) => a.position - b.position);
      return (args?.orderBy?.position === "desc" ? rows[rows.length - 1] : rows[0]) ?? null;
    },
  );
  prismaMock.scope.create.mockImplementation((args: { data: { userId: string; name: string; position: number } }) => {
    const row: ScopeRow = {
      id: `s-new-${scopes.length}`,
      userId: args.data.userId,
      name: args.data.name,
      position: args.data.position,
      createdAt: T0,
      updatedAt: T0,
    };
    scopes.push(row);
    return { ...row };
  });
  prismaMock.scope.update.mockImplementation(
    (args: { where: { id: string }; data: Partial<ScopeRow> }) => {
      const row = scopes.find((s) => s.id === args.where.id);
      if (!row) throw new Error("update against no row");
      Object.assign(row, args.data, { updatedAt: new Date(T0.getTime() + 1000) });
      return { ...row };
    },
  );
  prismaMock.scope.delete.mockImplementation((args: { where: { id: string } }) => {
    const index = scopes.findIndex((s) => s.id === args.where.id);
    if (index === -1) throw new Error("delete against no row");
    return scopes.splice(index, 1)[0]!;
  });
  prismaMock.scope.count.mockImplementation(
    (args?: { where?: Record<string, unknown> }) => scopes.filter((s) => matches(s, args?.where)).length,
  );
  prismaMock.project.count.mockImplementation(
    (args: { where: { scopeId: string } }) => projectCounts[args.where.scopeId] ?? 0,
  );
});

describe("GET /scopes", () => {
  it("returns every scope in position order", async () => {
    const res = await call("GET", "/scopes");
    expect(res.statusCode).toBe(200);
    expect((res.json() as ScopeRow[]).map((s) => s.id)).toEqual(["s-work", "s-home", "s-dacha"]);
  });

  it("has no archived flavour: the switcher needs all of them", async () => {
    // A scope is a name and an order; there is nothing in it to archive. This
    // pins that the route ignores query parameters rather than growing a
    // filter nobody implemented.
    const res = await call("GET", "/scopes?archived=true");
    expect(res.statusCode).toBe(200);
    expect((res.json() as ScopeRow[])).toHaveLength(3);
  });

  it("requires a session, like every other data route", async () => {
    const res = await call("GET", "/scopes", undefined, false);
    expect(res.statusCode).toBe(401);
  });

  it("shows a user only their own scopes", async () => {
    const a = await call("GET", "/scopes");
    expect((a.json() as ScopeRow[]).map((s) => s.id)).toEqual(["s-work", "s-home", "s-dacha"]);
    const b = await call("GET", "/scopes", undefined, true, tokenB);
    expect((b.json() as ScopeRow[]).map((s) => s.id)).toEqual(["s-b-only"]);
  });
});

describe("POST /scopes", () => {
  it("creates a scope at the end of the order", async () => {
    const res = await call("POST", "/scopes", { name: "Гараж" });
    expect(res.statusCode).toBe(201);
    const body = res.json() as ScopeRow;
    expect(body.name).toBe("Гараж");
    // Appended, not inserted: a new scope claims no place in an order the user
    // arranged.
    expect(body.position).toBeGreaterThan(3000);
    expect(sorted().map((s) => s.name)).toEqual(["Работа", "Личное", "Дача", "Гараж"]);
  });

  it("trims the name and rejects an empty one", async () => {
    expect(((await call("POST", "/scopes", { name: "  Гараж  " })).json() as ScopeRow).name).toBe("Гараж");
    expect((await call("POST", "/scopes", { name: "   " })).statusCode).toBe(400);
    expect((await call("POST", "/scopes", {})).statusCode).toBe(400);
  });

  it("creates nothing when validation fails", async () => {
    await call("POST", "/scopes", { name: "" });
    expect(prismaMock.scope.create).not.toHaveBeenCalled();
  });

  it("stores the caller as the owner", async () => {
    const a = await call("POST", "/scopes", { name: "Гараж" });
    expect((a.json() as ScopeRow).userId).toBe(USER_A.id);
    const b = await call("POST", "/scopes", { name: "Баня" }, true, tokenB);
    expect((b.json() as ScopeRow).userId).toBe(USER_B.id);
    expect(scopes.find((s) => s.name === "Баня")!.userId).toBe(USER_B.id);
  });

  it("appends after the caller's own last scope, not after somebody else's", async () => {
    // A's last is at 3000; B's only scope is at 1500. If the "last" lookup
    // ignored the owner, B's new scope would land after 3000.
    const b = await call("POST", "/scopes", { name: "Баня" }, true, tokenB);
    const position = (b.json() as ScopeRow).position;
    expect(position).toBeGreaterThan(1500);
    expect(position).toBeLessThan(3000);
  });
});

describe("PATCH /scopes/:id", () => {
  it("renames the scope", async () => {
    const res = await call("PATCH", "/scopes/s-home", { name: "Дом" });
    expect(res.statusCode).toBe(200);
    expect((res.json() as ScopeRow).name).toBe("Дом");
    expect(scopes.find((s) => s.id === "s-home")!.name).toBe("Дом");
  });

  it("writes only the name, never the position", async () => {
    // A rename must not be able to reshuffle the switcher.
    await call("PATCH", "/scopes/s-home", { name: "Дом" });
    const args = prismaMock.scope.update.mock.calls[0]![0] as { data: Record<string, unknown> };
    expect(Object.keys(args.data)).toEqual(["name"]);
  });

  it("answers 404 for a scope that does not exist, without updating", async () => {
    const res = await call("PATCH", "/scopes/s-nope", { name: "Дом" });
    expect(res.statusCode).toBe(404);
    expect(prismaMock.scope.update).not.toHaveBeenCalled();
  });

  it("answers 404, not 403, for another user's scope, and changes nothing", async () => {
    const res = await call("PATCH", "/scopes/s-home", { name: "Чужое" }, true, tokenB);
    expect(res.statusCode).toBe(404);
    // Same body as a scope that does not exist: no way to probe which ids exist.
    const missing = await call("PATCH", "/scopes/s-nope", { name: "Чужое" }, true, tokenB);
    expect(res.json()).toEqual(missing.json());
    expect(prismaMock.scope.update).not.toHaveBeenCalled();
    expect(scopes.find((s) => s.id === "s-home")!.name).toBe("Личное");
  });
});

describe("PATCH /scopes/:id/position", () => {
  it("moves a scope between two neighbours", async () => {
    // Дача to the front: no `before`, `after` is Работа.
    const res = await call("PATCH", "/scopes/s-dacha/position", {
      beforeScopeId: null,
      afterScopeId: "s-work",
    });
    expect(res.statusCode).toBe(200);
    expect(sorted().map((s) => s.id)).toEqual(["s-dacha", "s-work", "s-home"]);
  });

  it("moves a scope to the end", async () => {
    const res = await call("PATCH", "/scopes/s-work/position", {
      beforeScopeId: "s-dacha",
      afterScopeId: null,
    });
    expect(res.statusCode).toBe(200);
    expect(sorted().map((s) => s.id)).toEqual(["s-home", "s-dacha", "s-work"]);
  });

  it("rejects positioning a scope relative to itself", async () => {
    const res = await call("PATCH", "/scopes/s-work/position", { afterScopeId: "s-work" });
    expect(res.statusCode).toBe(400);
  });

  it("rejects an unknown neighbour", async () => {
    const res = await call("PATCH", "/scopes/s-work/position", { afterScopeId: "s-nope" });
    expect(res.statusCode).toBe(400);
  });

  it("requires at least one neighbour", async () => {
    expect((await call("PATCH", "/scopes/s-work/position", {})).statusCode).toBe(400);
  });

  it("rebalances when two neighbours cannot be bisected any further", async () => {
    // The state a few dozen drags into the same gap eventually produces. The
    // route must renumber everything and still land the move, rather than
    // answering 500 -- this is the tasks route's fallback, kept honest here.
    scopes[0]!.position = 1000;
    scopes[1]!.position = 1000 + Number.EPSILON;
    prismaMock.$transaction.mockImplementation((operations: unknown[]) => operations);

    const res = await call("PATCH", "/scopes/s-dacha/position", {
      beforeScopeId: "s-work",
      afterScopeId: "s-home",
    });

    expect(res.statusCode).toBe(200);
    expect(prismaMock.$transaction).toHaveBeenCalled();
    expect(sorted().map((s) => s.id)).toEqual(["s-work", "s-dacha", "s-home"]);
  });

  it("answers 404 for another user's scope, and moves nothing", async () => {
    const res = await call(
      "PATCH",
      "/scopes/s-dacha/position",
      { beforeScopeId: null, afterScopeId: "s-b-only" },
      true,
      tokenB,
    );
    expect(res.statusCode).toBe(404);
    expect(prismaMock.scope.update).not.toHaveBeenCalled();
    expect(scopes.find((s) => s.id === "s-dacha")!.position).toBe(3000);
  });

  it("refuses a neighbour that belongs to another user", async () => {
    // A tries to sort s-dacha next to B's scope; from A's side that scope does
    // not exist, so it is the same 400 as an unknown neighbour.
    for (const body of [{ afterScopeId: "s-b-only" }, { beforeScopeId: "s-b-only" }]) {
      const res = await call("PATCH", "/scopes/s-dacha/position", body);
      expect(res.statusCode, JSON.stringify(body)).toBe(400);
    }
    expect(prismaMock.scope.update).not.toHaveBeenCalled();
    expect(scopes.find((s) => s.id === "s-dacha")!.position).toBe(3000);
  });

  it("rebalances only the caller's scopes", async () => {
    scopes[0]!.position = 1000;
    scopes[1]!.position = 1000 + Number.EPSILON;
    prismaMock.$transaction.mockImplementation((operations: unknown[]) => operations);

    await call("PATCH", "/scopes/s-dacha/position", { beforeScopeId: "s-work", afterScopeId: "s-home" });

    expect(scopes.find((s) => s.id === "s-b-only")!.position).toBe(1500);
  });
});

describe("DELETE /scopes/:id", () => {
  it("deletes an empty scope", async () => {
    const res = await call("DELETE", "/scopes/s-home");
    expect(res.statusCode).toBe(204);
    expect(sorted().map((s) => s.id)).toEqual(["s-work", "s-dacha"]);
  });

  it("refuses a scope that still holds projects, with 409", async () => {
    const res = await call("DELETE", "/scopes/s-work");
    expect(res.statusCode).toBe(409);
    expect((res.json() as { message: string }).message).toMatch(/projects/i);
    expect(prismaMock.scope.delete).not.toHaveBeenCalled();
    expect(sorted()).toHaveLength(3);
  });

  it("counts archived projects too", async () => {
    // The route must not filter on `archivedAt` when counting: an archived
    // project can be unarchived onto a board and needs its scope to still
    // exist. Here the only projects in s-work are archived as far as the route
    // is concerned -- it asked for a plain count.
    await call("DELETE", "/scopes/s-work");
    const args = prismaMock.project.count.mock.calls[0]![0] as { where: Record<string, unknown> };
    expect(Object.keys(args.where)).toEqual(["scopeId"]);
  });

  it("refuses the last scope, with a different message", async () => {
    scopes = scopes.filter((s) => s.id === "s-home" || s.userId === USER_B.id);
    projectCounts = { "s-home": 0 };

    const res = await call("DELETE", "/scopes/s-home");
    expect(res.statusCode).toBe(409);
    expect((res.json() as { message: string }).message).toMatch(/last scope/i);
    expect(sorted()).toHaveLength(1);
  });

  it("answers 404 for a scope that does not exist", async () => {
    const res = await call("DELETE", "/scopes/s-nope");
    expect(res.statusCode).toBe(404);
  });

  it("answers 404, not 403, for another user's scope, and deletes nothing", async () => {
    const res = await call("DELETE", "/scopes/s-home", undefined, true, tokenB);
    expect(res.statusCode).toBe(404);
    expect(prismaMock.scope.delete).not.toHaveBeenCalled();
    expect(scopes.some((s) => s.id === "s-home")).toBe(true);
  });

  it("counts only the caller's scopes for the last-scope guard", async () => {
    // A has three scopes, but B has one: for B that is the last scope.
    const res = await call("DELETE", "/scopes/s-b-only", undefined, true, tokenB);
    expect(res.statusCode).toBe(409);
    expect((res.json() as { message: string }).message).toMatch(/last scope/i);
    expect(scopes.some((s) => s.id === "s-b-only")).toBe(true);
    const args = prismaMock.scope.count.mock.calls[0]![0] as { where: Record<string, unknown> };
    expect(args.where).toEqual({ userId: USER_B.id });
  });

  it("is not blocked by somebody else's scopes when deleting an empty one", async () => {
    const res = await call("DELETE", "/scopes/s-dacha");
    expect(res.statusCode).toBe(204);
    expect(scopes.some((s) => s.id === "s-b-only")).toBe(true);
  });
});
