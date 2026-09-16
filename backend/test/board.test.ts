import { describe, it, expect, beforeAll, afterAll, beforeEach, vi } from "vitest";
import type { FastifyInstance } from "fastify";
// Type-only imports are erased at compile time, so these do NOT load the modules
// (and therefore do not construct a Prisma client) before the mock below is in place.
import type { AuthConfig } from "../src/lib/authConfig";
import type { BuildAppOptions } from "../src/app";

/*
 * There is no database in this environment (and no repo-root `.env`), so the
 * Prisma client is replaced wholesale rather than pointed at a real server.
 *
 * `findMany` is not a stub that echoes a canned array: it is a tiny fake that
 * actually honours the `where`, `orderBy` and `include` it is handed. That is
 * what makes these tests worth anything -- a stub ignoring the query would pass
 * even if the route filtered on the wrong column or forgot to order tasks at
 * all, which are precisely the mistakes this endpoint can make. What the fake
 * cannot prove is that Postgres agrees with it; see the note at the bottom.
 */
const prismaMock = vi.hoisted(() => ({
  project: { findMany: vi.fn(), findUnique: vi.fn() },
  task: { findMany: vi.fn() },
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

// ---- Fixture rows, deliberately stored in the "wrong" order ----

interface TaskRow {
  id: string;
  projectId: string;
  title: string;
  description: string | null;
  status: "pending" | "done" | "blocked";
  position: number;
  remindAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
}

interface ProjectRow {
  id: string;
  name: string;
  archivedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
}

const T0 = new Date("2026-01-01T00:00:00.000Z");

function task(
  id: string,
  projectId: string,
  status: TaskRow["status"],
  position: number,
  remindAt: Date | null = null,
): TaskRow {
  return {
    id,
    projectId,
    title: `task ${id}`,
    description: null,
    status,
    position,
    remindAt,
    createdAt: T0,
    updatedAt: T0,
  };
}

/** Insertion order here is scrambled on purpose, so ordering cannot pass by luck. */
const PROJECTS: ProjectRow[] = [
  { id: "p-second", name: "Second", archivedAt: null, createdAt: new Date("2026-02-01T00:00:00.000Z"), updatedAt: T0 },
  { id: "p-first", name: "First", archivedAt: null, createdAt: new Date("2026-01-01T00:00:00.000Z"), updatedAt: T0 },
  {
    id: "p-archived",
    name: "Archived",
    archivedAt: new Date("2026-03-01T00:00:00.000Z"),
    createdAt: new Date("2026-01-15T00:00:00.000Z"),
    updatedAt: T0,
  },
];

const TASKS: TaskRow[] = [
  // p-first: the first task by position is done, the second is blocked, so the
  // third one (position 30) is the current one -- a case a naive "first row wins"
  // implementation gets wrong.
  // The last task by position is listed first, so anything that forgets to sort
  // picks t-first-4 as current instead of t-first-3.
  task("t-first-4", "p-first", "pending", 40),
  task("t-first-1", "p-first", "done", 10),
  task("t-first-3", "p-first", "pending", 30),
  task("t-first-2", "p-first", "blocked", 20, new Date("2026-05-01T00:00:00.000Z")),
  // p-second: nothing pending at all, so no task is current.
  task("t-second-2", "p-second", "blocked", 20),
  task("t-second-1", "p-second", "done", 10),
  // p-archived has one task, to prove archived projects carry theirs too.
  task("t-arch-1", "p-archived", "pending", 10),
];

/**
 * The subset of Prisma's `findMany` semantics this route depends on. Anything
 * the route does not use is intentionally unimplemented: if a future change
 * starts relying on it, this throws rather than quietly returning wrong data.
 */
interface FindManyArgs {
  where?: { archivedAt?: null | { not: null } };
  orderBy?: { createdAt?: "asc" | "desc" };
  include?: { tasks?: { orderBy?: { position?: "asc" | "desc" } } };
}

function fakeFindMany(args: FindManyArgs = {}): unknown[] {
  const wantsArchived = args.where?.archivedAt !== null && args.where?.archivedAt !== undefined;

  let rows = PROJECTS.filter((p) => (wantsArchived ? p.archivedAt !== null : p.archivedAt === null));

  if (args.orderBy?.createdAt === "asc") {
    rows = [...rows].sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime());
  } else if (args.orderBy?.createdAt === "desc") {
    rows = [...rows].sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
  }

  const includeTasks = args.include?.tasks;
  if (includeTasks === undefined) {
    // No `include` means Prisma returns bare project rows, with no `tasks` key --
    // exactly what `GET /projects` must keep doing.
    return rows;
  }

  return rows.map((project) => {
    let tasks = TASKS.filter((t) => t.projectId === project.id);
    if (includeTasks.orderBy?.position === "asc") {
      tasks = [...tasks].sort((a, b) => a.position - b.position);
    }
    return { ...project, tasks };
  });
}

/*
 * The two calls the per-project tasks route makes. They exist so `GET /board` can
 * be compared against `GET /projects/:projectId/tasks` for real, through the HTTP
 * layer, instead of against a second hand-written expectation that could drift
 * from the route in the same direction as the bug.
 */
function fakeProjectFindUnique(args: { where: { id: string } }): ProjectRow | null {
  return PROJECTS.find((p) => p.id === args.where.id) ?? null;
}

function fakeTaskFindMany(args: {
  where: { projectId: string };
  orderBy?: { position?: "asc" | "desc" };
}): TaskRow[] {
  const rows = TASKS.filter((t) => t.projectId === args.where.projectId);
  if (args.orderBy?.position === "asc") {
    return [...rows].sort((a, b) => a.position - b.position);
  }
  return rows;
}

let buildApp: (options?: BuildAppOptions) => Promise<FastifyInstance>;
let app: FastifyInstance;
let token: string;

interface BoardTask {
  id: string;
  position: number;
  status: string;
  isCurrent: boolean;
}
interface BoardProject {
  id: string;
  name: string;
  archivedAt: string | null;
  tasks: BoardTask[];
}

/** Calls GET /board as the native client would: token in an Authorization header. */
async function getBoard(query = ""): Promise<{ statusCode: number; body: BoardProject[] }> {
  const res = await app.inject({
    method: "GET",
    url: `/board${query}`,
    headers: { authorization: `Bearer ${token}` },
  });
  return { statusCode: res.statusCode, body: res.statusCode === 200 ? (res.json() as BoardProject[]) : [] };
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
  prismaMock.project.findMany.mockReset();
  prismaMock.project.findUnique.mockReset();
  prismaMock.task.findMany.mockReset();
  prismaMock.project.findMany.mockImplementation(fakeFindMany);
  prismaMock.project.findUnique.mockImplementation(fakeProjectFindUnique);
  prismaMock.task.findMany.mockImplementation(fakeTaskFindMany);
});

describe("GET /board -- access", () => {
  it("requires a session like every other data route", async () => {
    const res = await app.inject({ method: "GET", url: "/board" });
    expect(res.statusCode).toBe(401);
    // Rejected by the guard before the handler, so the database is never touched.
    expect(prismaMock.project.findMany).not.toHaveBeenCalled();
  });

  it("accepts the session cookie as well, for the web client", async () => {
    const login = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: baseConfig.email, password: TEST_PASSWORD },
    });
    const cookie = login.cookies.find((c) => c.name === "taskradar_session");
    const res = await app.inject({
      method: "GET",
      url: "/board",
      cookies: { taskradar_session: cookie?.value ?? "" },
    });
    expect(res.statusCode).toBe(200);
  });
});

describe("GET /board -- response shape", () => {
  it("returns a bare array of projects, each carrying its tasks", async () => {
    const { statusCode, body } = await getBoard();
    expect(statusCode).toBe(200);
    expect(Array.isArray(body)).toBe(true);
    expect(body.map((p) => p.id)).toEqual(["p-first", "p-second"]);
    expect(body.every((p) => Array.isArray(p.tasks))).toBe(true);
  });

  it("gives each project exactly the fields GET /projects gives, plus tasks", async () => {
    const { body } = await getBoard();
    const project = body[0]!;
    expect(Object.keys(project).sort()).toEqual(["archivedAt", "createdAt", "id", "name", "tasks", "updatedAt"]);
  });

  it("gives each task exactly the fields the tasks route gives, isCurrent included", async () => {
    const { body } = await getBoard();
    const task = body[0]!.tasks[0]!;
    expect(Object.keys(task).sort()).toEqual([
      "createdAt",
      "description",
      "id",
      "isCurrent",
      "position",
      "projectId",
      "remindAt",
      "status",
      "title",
      "updatedAt",
    ]);
  });

  it("serves byte-identical tasks to GET /projects/:projectId/tasks", async () => {
    // The point of the endpoint is fewer requests, not a different data model:
    // the client must be able to refresh one project in place from the per-project
    // route without reconciling two shapes. Compared through HTTP against the real
    // other route, so this catches ordering, field and isCurrent divergence alike.
    const { body } = await getBoard();
    const fromBoard = body.find((p) => p.id === "p-first")!.tasks;

    const perProject = await app.inject({
      method: "GET",
      url: "/projects/p-first/tasks",
      headers: { authorization: `Bearer ${token}` },
    });
    expect(perProject.statusCode).toBe(200);
    expect(JSON.stringify(fromBoard)).toBe(perProject.body);
  });

  it("returns a project with no tasks as an empty array, not a missing key", async () => {
    prismaMock.project.findMany.mockImplementation(() => [
      { id: "p-empty", name: "Empty", archivedAt: null, createdAt: T0, updatedAt: T0, tasks: [] },
    ]);
    const { body } = await getBoard();
    expect(body[0]!.tasks).toEqual([]);
  });
});

describe("GET /board -- ordering", () => {
  it("orders projects by createdAt ascending, exactly like GET /projects", async () => {
    const { body } = await getBoard();
    expect(body.map((p) => p.name)).toEqual(["First", "Second"]);

    const args = prismaMock.project.findMany.mock.calls[0]![0] as FindManyArgs;
    expect(args.orderBy).toEqual({ createdAt: "asc" });
  });

  it("orders tasks within a project by position ascending", async () => {
    const { body } = await getBoard();
    const positions = body.find((p) => p.id === "p-first")!.tasks.map((t) => t.position);
    expect(positions).toEqual([10, 20, 30, 40]);
  });

  it("asks the database for that task order rather than sorting in memory", async () => {
    // Ordering must be part of the query: sorting a page of rows after the fact
    // would silently break the moment this endpoint grows a LIMIT.
    await getBoard();
    const args = prismaMock.project.findMany.mock.calls[0]![0] as FindManyArgs;
    expect(args.include?.tasks?.orderBy).toEqual({ position: "asc" });
  });
});

describe("GET /board -- isCurrent", () => {
  it("marks the first pending task, skipping done and blocked ones before it", async () => {
    const { body } = await getBoard();
    const tasks = body.find((p) => p.id === "p-first")!.tasks;
    expect(tasks.filter((t) => t.isCurrent).map((t) => t.id)).toEqual(["t-first-3"]);
  });

  it("marks no task current in a project with nothing pending", async () => {
    const { body } = await getBoard();
    const tasks = body.find((p) => p.id === "p-second")!.tasks;
    expect(tasks.some((t) => t.isCurrent)).toBe(false);
  });

  it("computes isCurrent per project, not once across the whole board", async () => {
    const { body } = await getBoard("?archived=true");
    // The archived project's own pending task is current in its own project.
    expect(body[0]!.tasks.filter((t) => t.isCurrent).map((t) => t.id)).toEqual(["t-arch-1"]);
  });

  it("puts isCurrent on every task, true or false, never leaves it undefined", async () => {
    const { body } = await getBoard();
    for (const project of body) {
      for (const t of project.tasks) {
        expect(typeof t.isCurrent).toBe("boolean");
      }
    }
  });
});

describe("GET /board -- archived filter", () => {
  it("returns only active projects by default", async () => {
    const { body } = await getBoard();
    expect(body.map((p) => p.id)).toEqual(["p-first", "p-second"]);

    const args = prismaMock.project.findMany.mock.calls[0]![0] as FindManyArgs;
    expect(args.where).toEqual({ archivedAt: null });
  });

  it("treats archived=false the same as omitting it", async () => {
    const { body } = await getBoard("?archived=false");
    expect(body.map((p) => p.id)).toEqual(["p-first", "p-second"]);
  });

  it("returns only archived projects for archived=true", async () => {
    const { body } = await getBoard("?archived=true");
    expect(body.map((p) => p.id)).toEqual(["p-archived"]);

    const args = prismaMock.project.findMany.mock.calls[0]![0] as FindManyArgs;
    expect(args.where).toEqual({ archivedAt: { not: null } });
  });

  it("rejects any other value with 400, exactly like GET /projects", async () => {
    for (const value of ["yes", "1", "TRUE", ""]) {
      const board = await app.inject({
        method: "GET",
        url: `/board?archived=${value}`,
        headers: { authorization: `Bearer ${token}` },
      });
      const projects = await app.inject({
        method: "GET",
        url: `/projects?archived=${value}`,
        headers: { authorization: `Bearer ${token}` },
      });
      expect(board.statusCode, `archived=${value}`).toBe(400);
      expect(board.statusCode).toBe(projects.statusCode);
    }
  });
});

describe("GET /board -- one database round-trip", () => {
  it("issues a single findMany for the whole board, not one per project", async () => {
    // If this ever becomes N+1 on the server, the endpoint has bought nothing:
    // the round-trips just moved from the phone's network to the database.
    await getBoard();
    expect(prismaMock.project.findMany).toHaveBeenCalledTimes(1);
  });

  it("fetches the tasks through an include rather than a second query", async () => {
    await getBoard();
    const args = prismaMock.project.findMany.mock.calls[0]![0] as FindManyArgs;
    expect(args.include?.tasks).toBeDefined();
  });
});

describe("no regression in the existing routes", () => {
  it("leaves GET /projects returning bare projects with no tasks attached", async () => {
    const res = await app.inject({
      method: "GET",
      url: "/projects",
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json() as Record<string, unknown>[];
    expect(body.map((p) => p.id)).toEqual(["p-first", "p-second"]);
    expect(body.every((p) => !("tasks" in p))).toBe(true);
  });

  it("leaves GET /projects/:projectId/tasks working unchanged", async () => {
    const res = await app.inject({
      method: "GET",
      url: "/projects/p-second/tasks",
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json() as BoardTask[];
    expect(body.map((t) => t.id)).toEqual(["t-second-1", "t-second-2"]);
    expect(body.some((t) => t.isCurrent)).toBe(false);
  });

  it("leaves GET /projects asking for no include at all", async () => {
    await app.inject({ method: "GET", url: "/projects", headers: { authorization: `Bearer ${token}` } });
    const args = prismaMock.project.findMany.mock.calls[0]![0] as FindManyArgs;
    expect(args.include).toBeUndefined();
  });
});

/*
 * NOT covered here, and deliberately so: that PostgreSQL actually returns the
 * rows this fake promises. The route's contract with the database -- the `where`,
 * both `orderBy`s and the `include` -- is asserted against the query object the
 * route hands to Prisma, and the mapping on top of the result is asserted against
 * real data. What is left is Prisma's and Postgres's own behaviour, which needs a
 * live database to exercise and which no route test in this repo covers today.
 */
