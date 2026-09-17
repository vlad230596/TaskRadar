import { describe, it, expect, beforeAll, afterAll, beforeEach, vi } from "vitest";
import type { FastifyInstance } from "fastify";
import type { AuthConfig } from "../src/lib/authConfig";
import type { BuildAppOptions } from "../src/app";

/*
 * The sandbox routes (F8).
 *
 * Same shape as the other route tests here: no database in this environment, so
 * Prisma is a small in-memory fake that actually mutates rows. That matters
 * most for filing, which is the one operation in this app that writes two
 * tables at once -- a stub that echoed its input could not tell "the task was
 * created and the item is gone" from either half of it.
 */
const prismaMock = vi.hoisted(() => ({
  inboxItem: {
    findMany: vi.fn(),
    findUnique: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
  },
  project: { findUnique: vi.fn() },
  task: { aggregate: vi.fn(), create: vi.fn() },
  $transaction: vi.fn(),
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));

process.env.DATABASE_URL ??= "postgresql://placeholder:placeholder@localhost:5432/placeholder";

const TEST_PASSWORD = "test-password-not-the-real-one";
/** bcrypt hash of TEST_PASSWORD at cost 4. */
const TEST_HASH = "$2b$04$zV5VFEALedx8Rfd/ucwUSOrHYSSr8xveuActiCTdzOmCsBSDTbYXO";

const baseConfig: AuthConfig = {
  email: "owner@example.com",
  passwordHash: TEST_HASH,
  jwtSecret: "test-jwt-secret-".repeat(4),
  cookieSecure: false,
};

interface InboxRow {
  id: string;
  text: string;
  createdAt: Date;
  updatedAt: Date;
}

interface TaskRow {
  id: string;
  projectId: string;
  title: string;
  position: number;
}

const T0 = new Date("2026-01-01T00:00:00.000Z");

let items: InboxRow[] = [];
let tasks: TaskRow[] = [];
let projects: string[] = [];
let nextId = 0;

function seed(): void {
  nextId = 0;
  items = [
    { id: "inb-1", text: "Спросить про кабель", createdAt: T0, updatedAt: T0 },
    {
      id: "inb-2",
      text: "Посмотреть налоги",
      createdAt: new Date(T0.getTime() + 60_000),
      updatedAt: T0,
    },
  ];
  tasks = [{ id: "tsk-1", projectId: "prj-1", title: "Уже есть", position: 1000 }];
  projects = ["prj-1"];
}

let buildApp: (options?: BuildAppOptions) => Promise<FastifyInstance>;
let app: FastifyInstance;
let token: string;

function call(method: string, url: string, payload?: unknown, withToken = true) {
  return app.inject({
    method: method as "GET",
    url,
    headers: withToken ? { authorization: `Bearer ${token}` } : {},
    ...(payload === undefined ? {} : { payload: payload as Record<string, unknown> }),
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
  for (const fn of Object.values(prismaMock.inboxItem)) fn.mockReset();
  prismaMock.project.findUnique.mockReset();
  prismaMock.task.aggregate.mockReset();
  prismaMock.task.create.mockReset();
  prismaMock.$transaction.mockReset();

  prismaMock.inboxItem.findMany.mockImplementation(() =>
    [...items].sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime()),
  );
  prismaMock.inboxItem.findUnique.mockImplementation(
    (args: { where: { id: string } }) => items.find((i) => i.id === args.where.id) ?? null,
  );
  prismaMock.inboxItem.create.mockImplementation((args: { data: { text: string } }) => {
    const row: InboxRow = {
      id: `inb-new-${++nextId}`,
      text: args.data.text,
      createdAt: new Date(T0.getTime() + 3_600_000),
      updatedAt: new Date(T0.getTime() + 3_600_000),
    };
    items.push(row);
    return { ...row };
  });
  prismaMock.inboxItem.update.mockImplementation(
    (args: { where: { id: string }; data: Partial<InboxRow> }) => {
      const row = items.find((i) => i.id === args.where.id);
      if (!row) throw new Error("update against no row");
      Object.assign(row, args.data, { updatedAt: new Date(T0.getTime() + 1000) });
      return { ...row };
    },
  );
  prismaMock.inboxItem.delete.mockImplementation((args: { where: { id: string } }) => {
    const index = items.findIndex((i) => i.id === args.where.id);
    if (index === -1) throw new Error("delete against no row");
    return items.splice(index, 1)[0]!;
  });

  prismaMock.project.findUnique.mockImplementation((args: { where: { id: string } }) =>
    projects.includes(args.where.id)
      ? { id: args.where.id, name: "Проект", scopeId: "scope_main", archivedAt: null }
      : null,
  );
  prismaMock.task.aggregate.mockImplementation((args: { where: { projectId: string } }) => {
    const positions = tasks
      .filter((t) => t.projectId === args.where.projectId)
      .map((t) => t.position);
    return { _max: { position: positions.length ? Math.max(...positions) : null } };
  });
  prismaMock.task.create.mockImplementation(
    (args: { data: { projectId: string; title: string; position: number } }) => {
      const row: TaskRow = { id: `tsk-new-${++nextId}`, ...args.data };
      tasks.push(row);
      return { ...row };
    },
  );
  /*
   * The fakes above apply their change when they are called, so by the time
   * `$transaction` receives the array both halves have happened and it only has
   * to hand the results back. That is a simplification of the real client --
   * Prisma's operations are lazy promises and the transaction is what executes
   * them -- and it is the right one here: what these tests can honestly check
   * is that the route sends **both** operations in **one** transaction, which
   * is asserted on the argument. Whether Postgres then rolls them back together
   * is Postgres's job, not this fake's.
   */
  prismaMock.$transaction.mockImplementation((operations: unknown[]) => operations);
});

describe("GET /inbox", () => {
  it("lists items oldest first", async () => {
    const res = await call("GET", "/inbox");
    expect(res.statusCode).toBe(200);
    // The pile is processed from the top, and the item at risk of rotting is
    // the one that has waited longest.
    expect((res.json() as InboxRow[]).map((i) => i.id)).toEqual(["inb-1", "inb-2"]);
  });

  it("requires a session", async () => {
    expect((await call("GET", "/inbox", undefined, false)).statusCode).toBe(401);
  });
});

describe("POST /inbox", () => {
  it("captures a line of text", async () => {
    const res = await call("POST", "/inbox", { text: "  Позвонить в банк  " });
    expect(res.statusCode).toBe(201);
    expect((res.json() as InboxRow).text).toBe("Позвонить в банк");
    expect(items.map((i) => i.text)).toContain("Позвонить в банк");
  });

  it("refuses an empty one", async () => {
    for (const text of ["", "   ", undefined, 42]) {
      const res = await call("POST", "/inbox", { text });
      expect(res.statusCode, JSON.stringify(text)).toBe(400);
    }
    expect(prismaMock.inboxItem.create).not.toHaveBeenCalled();
  });

  it("accepts nothing but the text", async () => {
    // Not a second way to create work: an item with a status or a reminder date
    // is a task that never reaches a project.
    await call("POST", "/inbox", {
      text: "Купить кабель",
      status: "blocked",
      remindAt: "2026-10-01T00:00:00.000Z",
      projectId: "prj-1",
    });

    const args = prismaMock.inboxItem.create.mock.calls[0]![0] as {
      data: Record<string, unknown>;
    };
    expect(Object.keys(args.data)).toEqual(["text"]);
  });
});

describe("PATCH /inbox/:id", () => {
  it("edits the text", async () => {
    const res = await call("PATCH", "/inbox/inb-1", { text: "Спросить про кабель у Пети" });
    expect(res.statusCode).toBe(200);
    expect(items[0]!.text).toBe("Спросить про кабель у Пети");
  });

  it("404s for an unknown item, without writing", async () => {
    const res = await call("PATCH", "/inbox/inb-nope", { text: "что-то" });
    expect(res.statusCode).toBe(404);
    expect(prismaMock.inboxItem.update).not.toHaveBeenCalled();
  });
});

describe("DELETE /inbox/:id", () => {
  it("throws the item away, with no archive step", async () => {
    // Unlike a project, which must be archived first: that guard exists because
    // a project holds months of work. This holds a sentence.
    const res = await call("DELETE", "/inbox/inb-1");
    expect(res.statusCode).toBe(204);
    expect(items.map((i) => i.id)).toEqual(["inb-2"]);
  });

  it("404s for an unknown item", async () => {
    expect((await call("DELETE", "/inbox/inb-nope")).statusCode).toBe(404);
  });
});

describe("POST /inbox/:id/file", () => {
  it("creates the task and removes the item, in one transaction", async () => {
    const res = await call("POST", "/inbox/inb-1/file", { projectId: "prj-1" });

    expect(res.statusCode).toBe(201);
    const task = res.json() as TaskRow;
    expect(task.title).toBe("Спросить про кабель");
    expect(task.projectId).toBe("prj-1");

    // Both halves happened...
    expect(tasks.map((t) => t.title)).toContain("Спросить про кабель");
    expect(items.map((i) => i.id)).toEqual(["inb-2"]);
    // ...and they happened together. Two requests from a phone on a train
    // produce two ways to be half-done: filed twice, or lost.
    expect(prismaMock.$transaction).toHaveBeenCalledTimes(1);
    const operations = prismaMock.$transaction.mock.calls[0]![0] as unknown[];
    expect(operations).toHaveLength(2);
  });

  it("appends the task to the end of the project", async () => {
    await call("POST", "/inbox/inb-1/file", { projectId: "prj-1" });

    const created = tasks.find((t) => t.title === "Спросить про кабель")!;
    // The item has no order of its own; dropping it into the middle of a
    // project's list would be inventing one.
    expect(created.position).toBeGreaterThan(1000);
  });

  it("answers with the raw task row, with no isCurrent", async () => {
    // Same contract as POST /projects/:id/tasks: `isCurrent` is a property of
    // the project's whole ordered list, and this response carries one row.
    const res = await call("POST", "/inbox/inb-1/file", { projectId: "prj-1" });
    expect(Object.keys(res.json() as object)).not.toContain("isCurrent");
  });

  it("404s for an unknown project, and files nothing", async () => {
    const res = await call("POST", "/inbox/inb-1/file", { projectId: "prj-nope" });
    expect(res.statusCode).toBe(404);
    expect((res.json() as { message: string }).message).toMatch(/project/i);
    expect(items).toHaveLength(2);
    expect(prismaMock.$transaction).not.toHaveBeenCalled();
  });

  it("404s for an unknown item, and creates no task", async () => {
    const res = await call("POST", "/inbox/inb-nope/file", { projectId: "prj-1" });
    expect(res.statusCode).toBe(404);
    expect(tasks).toHaveLength(1);
    expect(prismaMock.$transaction).not.toHaveBeenCalled();
  });

  it("requires a project to file into", async () => {
    expect((await call("POST", "/inbox/inb-1/file", {})).statusCode).toBe(400);
    expect((await call("POST", "/inbox/inb-1/file", { projectId: "" })).statusCode).toBe(400);
    expect(items).toHaveLength(2);
  });

  it("requires a session", async () => {
    const res = await call("POST", "/inbox/inb-1/file", { projectId: "prj-1" }, false);
    expect(res.statusCode).toBe(401);
    expect(items).toHaveLength(2);
  });
});
