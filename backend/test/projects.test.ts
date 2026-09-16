import { describe, it, expect, beforeAll, afterAll, beforeEach, vi } from "vitest";
import type { FastifyInstance } from "fastify";
// Type-only imports are erased at compile time, so these do NOT load the modules
// (and therefore do not construct a Prisma client) before the mock below is in place.
import type { AuthConfig } from "../src/lib/authConfig";
import type { BuildAppOptions } from "../src/app";

/*
 * No database in this environment, so Prisma is replaced wholesale. `update` is
 * a small fake that mutates the fixture rows rather than a stub returning a
 * canned object: the questions this file asks -- did the name actually change,
 * did `archivedAt` survive it, did a rejected request change anything at all --
 * are unanswerable against a stub that echoes whatever it is handed.
 */
const prismaMock = vi.hoisted(() => ({
  project: { findUnique: vi.fn(), update: vi.fn(), create: vi.fn() },
  // F7: creating a project resolves its scope, and moving one checks that the
  // target exists. Both are plain lookups, so a pair of fakes over the same
  // fixture rows is enough.
  scope: { findUnique: vi.fn(), findFirst: vi.fn() },
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));

// Belt and braces: if the mock above ever stops matching the module id, the real
// client is constructed instead, and it demands DATABASE_URL at import time.
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

interface ProjectRow {
  id: string;
  name: string;
  scopeId: string;
  archivedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
}

interface ScopeRow {
  id: string;
  name: string;
  position: number;
}

const T0 = new Date("2026-01-01T00:00:00.000Z");
const ARCHIVED_AT = new Date("2026-03-01T00:00:00.000Z");

let rows: ProjectRow[] = [];
let scopeRows: ScopeRow[] = [];

function seed(): void {
  rows = [
    { id: "p-active", name: "Active", scopeId: "s-first", archivedAt: null, createdAt: T0, updatedAt: T0 },
    { id: "p-archived", name: "Archived", scopeId: "s-first", archivedAt: ARCHIVED_AT, createdAt: T0, updatedAt: T0 },
  ];
  scopeRows = [
    { id: "s-first", name: "Первый", position: 1000 },
    { id: "s-second", name: "Второй", position: 2000 },
  ];
}

function fakeFindUnique(args: { where: { id: string } }): ProjectRow | null {
  return rows.find((p) => p.id === args.where.id) ?? null;
}

function fakeUpdate(args: { where: { id: string }; data: Partial<ProjectRow> }): ProjectRow {
  const row = rows.find((p) => p.id === args.where.id);
  if (!row) {
    // Prisma's own behaviour for an update matching no row. The route is
    // supposed to have ruled this out already; if it ever stops doing so, this
    // throw is what makes the test fail instead of quietly inventing a row.
    const error = new Error("An operation failed because it depends on one or more records that were required but not found.");
    error.name = "PrismaClientKnownRequestError";
    (error as { code?: string }).code = "P2025";
    throw error;
  }
  Object.assign(row, args.data, { updatedAt: new Date(T0.getTime() + 1000) });
  return { ...row };
}

let buildApp: (options?: BuildAppOptions) => Promise<FastifyInstance>;
let app: FastifyInstance;
let token: string;

/** Calls PATCH /projects/:id as the native client would: token in a header. */
async function rename(id: string, payload: unknown, withToken = true) {
  return app.inject({
    method: "PATCH",
    url: `/projects/${id}`,
    headers: withToken ? { authorization: `Bearer ${token}` } : {},
    payload: payload as Record<string, unknown>,
  });
}

beforeAll(async () => {
  const appModule = await import("../src/app");
  buildApp = appModule.buildApp;
  app = await buildApp({ authConfig: baseConfig, logger: false });
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

beforeEach(() => {
  seed();
  prismaMock.project.findUnique.mockReset();
  prismaMock.project.update.mockReset();
  prismaMock.project.create.mockReset();
  prismaMock.scope.findUnique.mockReset();
  prismaMock.scope.findFirst.mockReset();

  prismaMock.project.findUnique.mockImplementation(fakeFindUnique);
  prismaMock.project.update.mockImplementation(fakeUpdate);
  prismaMock.project.create.mockImplementation(
    (args: { data: { name: string; scopeId: string } }) => {
      const row: ProjectRow = {
        id: "p-new-" + rows.length,
        name: args.data.name,
        scopeId: args.data.scopeId,
        archivedAt: null,
        createdAt: T0,
        updatedAt: T0,
      };
      rows.push(row);
      return { ...row };
    },
  );
  prismaMock.scope.findUnique.mockImplementation(
    (args: { where: { id: string } }) => scopeRows.find((s) => s.id === args.where.id) ?? null,
  );
  // "First by position" is the route's own definition of the default scope.
  prismaMock.scope.findFirst.mockImplementation(
    () => [...scopeRows].sort((a, b) => a.position - b.position)[0] ?? null,
  );
});

describe("PATCH /projects/:id -- renaming", () => {
  it("renames the project and answers 200 with the updated row", async () => {
    const res = await rename("p-active", { name: "Renamed" });
    expect(res.statusCode).toBe(200);
    const body = res.json() as ProjectRow;
    expect(body.id).toBe("p-active");
    expect(body.name).toBe("Renamed");
    expect(rows.find((p) => p.id === "p-active")!.name).toBe("Renamed");
  });

  it("returns exactly the shape GET /projects/:id returns", async () => {
    // The client keeps one Project model; a rename that answered with a
    // differently shaped object would force a second parser for no reason.
    const renamed = await rename("p-active", { name: "Renamed" });
    const fetched = await app.inject({
      method: "GET",
      url: "/projects/p-active",
      headers: { authorization: `Bearer ${token}` },
    });
    expect(fetched.statusCode).toBe(200);
    expect(Object.keys(renamed.json() as object).sort()).toEqual(Object.keys(fetched.json() as object).sort());
    expect(Object.keys(renamed.json() as object).sort()).toEqual([
      "archivedAt",
      "createdAt",
      "id",
      "name",
      // F7 added this one, and the pairing above is what keeps the two routes
      // from drifting apart when the next field arrives.
      "scopeId",
      "updatedAt",
    ]);
  });

  it("writes only the name, never archivedAt", async () => {
    // A rename must not be able to resurrect or archive a project as a side
    // effect; /archive and /unarchive stay the only routes that move it.
    await rename("p-active", { name: "Renamed" });
    const args = prismaMock.project.update.mock.calls[0]![0] as { data: Record<string, unknown> };
    expect(Object.keys(args.data)).toEqual(["name"]);
  });

  it("trims surrounding whitespace, exactly like creation does", async () => {
    // Same schema object as POST /projects, so the trim cannot drift; what is
    // asserted here is that the trimmed value is what actually gets stored.
    const res = await rename("p-active", { name: "  Padded  " });
    expect(res.statusCode).toBe(200);
    expect((res.json() as ProjectRow).name).toBe("Padded");
  });

  it("accepts a non-ASCII name unchanged", async () => {
    // The names in this tool are Russian in practice; a rename that mangled them
    // would be found by the owner, not by a test.
    const res = await rename("p-active", { name: "Ремонт квартиры" });
    expect((res.json() as ProjectRow).name).toBe("Ремонт квартиры");
  });

  it("is idempotent: renaming to the same name is a normal 200", async () => {
    const res = await rename("p-active", { name: "Active" });
    expect(res.statusCode).toBe(200);
    expect((res.json() as ProjectRow).name).toBe("Active");
  });
});

describe("PATCH /projects/:id -- archived projects", () => {
  /*
   * The decision, argued in full in src/routes/projects.ts: an archived project
   * CAN be renamed. Archiving is the reversible half of the Trello-style pair
   * (reversible archive, irreversible delete behind it), the row stays live, and
   * every other route already works on archived projects. These tests are what
   * make that a contract instead of an accident of implementation.
   */
  it("renames an archived project", async () => {
    const res = await rename("p-archived", { name: "Archived, renamed" });
    expect(res.statusCode).toBe(200);
    expect((res.json() as ProjectRow).name).toBe("Archived, renamed");
  });

  it("leaves the project archived afterwards", async () => {
    const res = await rename("p-archived", { name: "Archived, renamed" });
    expect((res.json() as ProjectRow).archivedAt).toBe(ARCHIVED_AT.toISOString());
    expect(rows.find((p) => p.id === "p-archived")!.archivedAt).toEqual(ARCHIVED_AT);
  });

  it("treats active and archived projects identically", async () => {
    const active = await rename("p-active", { name: "X" });
    const archived = await rename("p-archived", { name: "X" });
    expect(archived.statusCode).toBe(active.statusCode);
  });
});

describe("PATCH /projects/:id -- validation", () => {
  it("rejects an empty name with 400", async () => {
    const res = await rename("p-active", { name: "" });
    expect(res.statusCode).toBe(400);
    expect((res.json() as { error: string }).error).toBe("ValidationError");
  });

  it("rejects a whitespace-only name with 400", async () => {
    // Trim happens before the length check, so "   " is empty, not length 3.
    const res = await rename("p-active", { name: "   " });
    expect(res.statusCode).toBe(400);
  });

  it("rejects a missing name with 400", async () => {
    expect((await rename("p-active", {})).statusCode).toBe(400);
  });

  it("rejects a non-string name with 400", async () => {
    for (const name of [42, null, true, ["a"], { a: 1 }]) {
      expect((await rename("p-active", { name })).statusCode, JSON.stringify(name)).toBe(400);
    }
  });

  it("rejects the same names POST /projects rejects", async () => {
    // The two schemas stopped being the same object in F7: a project can now be
    // moved between scopes, so PATCH takes two optional fields while POST takes
    // a required name. The rule they still share -- what counts as an acceptable
    // name -- is therefore worth observing rather than assuming.
    for (const name of ["", "   ", undefined]) {
      const patch = await rename("p-active", { name });
      const post = await app.inject({
        method: "POST",
        url: "/projects",
        headers: { authorization: `Bearer ${token}` },
        payload: { name },
      });
      expect(patch.statusCode, JSON.stringify(name)).toBe(400);
      expect(post.statusCode, JSON.stringify(name)).toBe(400);
    }
  });

  it("changes nothing when validation fails", async () => {
    await rename("p-active", { name: "  " });
    expect(prismaMock.project.update).not.toHaveBeenCalled();
    expect(rows.find((p) => p.id === "p-active")!.name).toBe("Active");
  });
});

describe("PATCH /projects/:id -- missing project", () => {
  it("answers 404 for an id that does not exist", async () => {
    const res = await rename("p-nope", { name: "Renamed" });
    expect(res.statusCode).toBe(404);
    expect(res.json()).toEqual({ error: "NotFoundError", message: "Project not found" });
  });

  it("checks existence before updating, so Prisma never raises P2025", async () => {
    // Letting the update run against no rows would surface as an opaque 500
    // instead of a 404, which is the difference between "you asked for the wrong
    // project" and "the server is broken".
    await rename("p-nope", { name: "Renamed" });
    expect(prismaMock.project.update).not.toHaveBeenCalled();
  });

  it("answers 404 with the same body a plain GET of that project gives", async () => {
    const patch = await rename("p-nope", { name: "Renamed" });
    const get = await app.inject({
      method: "GET",
      url: "/projects/p-nope",
      headers: { authorization: `Bearer ${token}` },
    });
    expect(patch.statusCode).toBe(get.statusCode);
    expect(patch.json()).toEqual(get.json());
  });
});

describe("PATCH /projects/:id -- access", () => {
  it("requires a session like every other data route", async () => {
    const res = await rename("p-active", { name: "Renamed" }, false);
    expect(res.statusCode).toBe(401);
    expect(res.json()).toEqual({ error: "Unauthorized", message: "Unauthorized" });
    // Rejected by the guard before the handler, so the database is never touched.
    expect(prismaMock.project.findUnique).not.toHaveBeenCalled();
    expect(prismaMock.project.update).not.toHaveBeenCalled();
  });

  it("rejects an unauthenticated rename of a project that does not exist, without saying so", async () => {
    // Same 401 as for a real project: the rename route must not become a way to
    // probe which project ids exist.
    const real = await rename("p-active", { name: "Renamed" }, false);
    const fake = await rename("p-nope", { name: "Renamed" }, false);
    expect(real.statusCode).toBe(401);
    expect(fake.body).toBe(real.body);
  });

  it("accepts the session cookie as well, for the web client", async () => {
    const login = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: baseConfig.email, password: TEST_PASSWORD },
    });
    const cookie = login.cookies.find((c) => c.name === "taskradar_session");
    const res = await app.inject({
      method: "PATCH",
      url: "/projects/p-active",
      cookies: { taskradar_session: cookie?.value ?? "" },
      payload: { name: "Renamed via cookie" },
    });
    expect(res.statusCode).toBe(200);
  });
});

describe("no regression in the existing project routes", () => {
  it("leaves GET /projects/:id unchanged", async () => {
    const res = await app.inject({
      method: "GET",
      url: "/projects/p-active",
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(200);
    expect((res.json() as ProjectRow).name).toBe("Active");
    expect(prismaMock.project.update).not.toHaveBeenCalled();
  });

  it("leaves archive/unarchive as the only routes that touch archivedAt", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/projects/p-active/archive",
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(200);
    const args = prismaMock.project.update.mock.calls[0]![0] as { data: Record<string, unknown> };
    expect(Object.keys(args.data)).toEqual(["archivedAt"]);
  });
});

describe("POST /projects -- which scope it lands in (F7)", () => {
  async function create(payload: unknown) {
    return app.inject({
      method: "POST",
      url: "/projects",
      headers: { authorization: "Bearer " + token },
      payload: payload as Record<string, unknown>,
    });
  }

  it("puts the project in the scope the client named", async () => {
    const res = await create({ name: "\u041d\u043e\u0432\u044b\u0439", scopeId: "s-second" });
    expect(res.statusCode).toBe(201);
    expect((res.json() as ProjectRow).scopeId).toBe("s-second");
  });

  it("falls back to the first scope when the client names none", async () => {
    // Keeps `POST /projects {name}` -- a curl one-liner, a seed script, anything
    // written before scopes existed -- working, and lands the project where the
    // board opens.
    const res = await create({ name: "\u041d\u043e\u0432\u044b\u0439" });
    expect(res.statusCode).toBe(201);
    expect((res.json() as ProjectRow).scopeId).toBe("s-first");
  });

  it("answers 404 for a scope that does not exist, and creates nothing", async () => {
    // Not a 500 from a foreign key violation, which is what leaving this to the
    // database would produce.
    const res = await create({ name: "\u041d\u043e\u0432\u044b\u0439", scopeId: "s-nope" });
    expect(res.statusCode).toBe(404);
    expect((res.json() as { message: string }).message).toMatch(/scope/i);
    expect(prismaMock.project.create).not.toHaveBeenCalled();
  });
});

describe("PATCH /projects/:id -- moving between scopes (F7)", () => {
  it("moves the project and answers with the updated row", async () => {
    const res = await rename("p-active", { scopeId: "s-second" });
    expect(res.statusCode).toBe(200);
    expect((res.json() as ProjectRow).scopeId).toBe("s-second");
    expect(rows.find((p) => p.id === "p-active")!.scopeId).toBe("s-second");
  });

  it("does not require a name in order to move", async () => {
    // The whole reason updateProjectSchema stopped being an alias of
    // createProjectSchema: demanding a name here would make every move rewrite
    // the name too.
    const res = await rename("p-active", { scopeId: "s-second" });
    expect(res.statusCode).toBe(200);
    expect(rows.find((p) => p.id === "p-active")!.name).toBe("Active");
  });

  it("writes only the fields that were sent", async () => {
    await rename("p-active", { scopeId: "s-second" });
    const args = prismaMock.project.update.mock.calls[0]![0] as { data: Record<string, unknown> };
    expect(Object.keys(args.data)).toEqual(["scopeId"]);
  });

  it("renames and moves in one request", async () => {
    const res = await rename("p-active", { name: "Renamed", scopeId: "s-second" });
    expect(res.statusCode).toBe(200);
    const body = res.json() as ProjectRow;
    expect(body.name).toBe("Renamed");
    expect(body.scopeId).toBe("s-second");
  });

  it("answers 404 for an unknown scope, and changes nothing", async () => {
    const res = await rename("p-active", { scopeId: "s-nope" });
    expect(res.statusCode).toBe(404);
    expect(prismaMock.project.update).not.toHaveBeenCalled();
    expect(rows.find((p) => p.id === "p-active")!.scopeId).toBe("s-first");
  });

  it("moves an archived project without unarchiving it", async () => {
    // Same argument as renaming one: the archive is reversible, not frozen, and
    // sorting old projects into scopes is exactly what the archive screen is
    // for.
    const res = await rename("p-archived", { scopeId: "s-second" });
    expect(res.statusCode).toBe(200);
    expect((res.json() as ProjectRow).archivedAt).not.toBeNull();
    expect(rows.find((p) => p.id === "p-archived")!.archivedAt).toEqual(ARCHIVED_AT);
  });

  it("rejects an empty scopeId with 400", async () => {
    expect((await rename("p-active", { scopeId: "" })).statusCode).toBe(400);
    expect(prismaMock.project.update).not.toHaveBeenCalled();
  });
});
