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
  taskEvent: { create: vi.fn() },
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
  captureKey?: string | null;
  createdAt: Date;
  updatedAt: Date;
}

interface TaskRow {
  id: string;
  projectId: string;
  title: string;
  position: number;
  status: "pending" | "done" | "blocked";
}

/** A row in the task journal (F11). */
interface EventRow {
  taskId: string;
  kind: string;
  toStatus?: string | null;
}

const T0 = new Date("2026-01-01T00:00:00.000Z");

let items: InboxRow[] = [];
let tasks: TaskRow[] = [];
let events: EventRow[] = [];
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
  tasks = [{ id: "tsk-1", projectId: "prj-1", title: "Уже есть", position: 1000, status: "pending" }];
  events = [];
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
  prismaMock.taskEvent.create.mockReset();
  prismaMock.$transaction.mockReset();

  prismaMock.inboxItem.findMany.mockImplementation(() =>
    [...items].sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime()),
  );
  // `where` is either `{ id }` or -- since F8.1 -- `{ captureKey }`, and the
  // fake has to answer both, because the idempotent capture path is a lookup by
  // key followed by a create.
  prismaMock.inboxItem.findUnique.mockImplementation(
    (args: { where: { id?: string; captureKey?: string } }) =>
      items.find((i) =>
        args.where.id === undefined
          ? i.captureKey === args.where.captureKey
          : i.id === args.where.id,
      ) ?? null,
  );
  prismaMock.inboxItem.create.mockImplementation(
    (args: { data: { text: string; captureKey?: string } }) => {
      // The unique index on `captureKey`, which is the only thing standing
      // between a retried capture and a duplicate line. Modelled here because
      // the route has a branch that exists purely for losing that race.
      if (
        args.data.captureKey !== undefined &&
        items.some((i) => i.captureKey === args.data.captureKey)
      ) {
        throw Object.assign(new Error("Unique constraint failed"), {
          code: "P2002",
          meta: { target: ["captureKey"] },
        });
      }

      const row: InboxRow = {
        id: `inb-new-${++nextId}`,
        text: args.data.text,
        captureKey: args.data.captureKey ?? null,
        createdAt: new Date(T0.getTime() + 3_600_000),
        updatedAt: new Date(T0.getTime() + 3_600_000),
      };
      items.push(row);
      return { ...row };
    },
  );
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
      const row: TaskRow = { id: `tsk-new-${++nextId}`, status: "pending", ...args.data };
      tasks.push(row);
      return { ...row };
    },
  );
  prismaMock.taskEvent.create.mockImplementation((args: { data: EventRow }) => {
    events.push({ ...args.data });
    return { id: `evt-${++nextId}`, ...args.data };
  });
  /*
   * Filing runs as an interactive transaction since F11 -- the journal row for
   * the new task needs the id of the task created a statement earlier, which
   * the array form cannot express -- so the fake runs the callback against
   * itself and hands back what it returned.
   *
   * The fakes apply their changes as they are called, which is a simplification
   * of the real client and the right one here: what this test can honestly
   * check is that all three writes are issued inside **one** transaction.
   * Whether Postgres then rolls them back together is Postgres's job, not this
   * fake's -- the rollback itself is modelled in tasks.test.ts, where the
   * question is whether a failed write can leave an event behind.
   */
  prismaMock.$transaction.mockImplementation((run: (tx: unknown) => unknown) => run(prismaMock));
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

/*
 * Offline capture (F8.1): the phone queues lines with no network and replays
 * them later, so the same capture can arrive twice and must land once.
 */
describe("POST /inbox with a capture key", () => {
  const KEY = "8f14e45f-ceea-467a-a4c1-0f1b2c3d4e5f";

  it("stores the key with the line", async () => {
    const res = await call("POST", "/inbox", { text: "Купить кабель", captureKey: KEY });

    expect(res.statusCode).toBe(201);
    expect(items.find((i) => i.text === "Купить кабель")!.captureKey).toBe(KEY);
  });

  it("answers a replay with the same row, and creates nothing", async () => {
    const first = await call("POST", "/inbox", { text: "Купить кабель", captureKey: KEY });
    const replay = await call("POST", "/inbox", { text: "Купить кабель", captureKey: KEY });

    // 200 rather than 201: the line is not new here. Nothing in the client
    // branches on it, which is exactly why the server can afford to be honest.
    expect(replay.statusCode).toBe(200);
    expect((replay.json() as InboxRow).id).toBe((first.json() as InboxRow).id);
    expect(items.filter((i) => i.text === "Купить кабель")).toHaveLength(1);
  });

  it("does not let a late replay undo an edit", async () => {
    // The order that matters: captured, sent, corrected on the phone, and only
    // then the original request is retried because its answer was lost. The
    // retry carries the *old* text, and applying it would be a write travelling
    // backwards in time.
    await call("POST", "/inbox", { text: "Купить кабель", captureKey: KEY });
    const stored = items.find((i) => i.captureKey === KEY)!;
    await call("PATCH", `/inbox/${stored.id}`, { text: "Купить кабель USB-C" });

    const replay = await call("POST", "/inbox", { text: "Купить кабель", captureKey: KEY });

    expect((replay.json() as InboxRow).text).toBe("Купить кабель USB-C");
    expect(items.find((i) => i.captureKey === KEY)!.text).toBe("Купить кабель USB-C");
  });

  it("survives two copies of the same retry racing each other", async () => {
    // Both requests find no row, both try to create, and the unique index
    // rejects the loser. That must read as a replay, not as a 500.
    const [a, b] = await Promise.all([
      call("POST", "/inbox", { text: "Купить кабель", captureKey: KEY }),
      call("POST", "/inbox", { text: "Купить кабель", captureKey: KEY }),
    ]);

    expect([a.statusCode, b.statusCode].sort()).toEqual([200, 201]);
    expect((a.json() as InboxRow).id).toBe((b.json() as InboxRow).id);
    expect(items.filter((i) => i.captureKey === KEY)).toHaveLength(1);
  });

  it("keeps different keys apart", async () => {
    await call("POST", "/inbox", { text: "Одно и то же", captureKey: KEY });
    await call("POST", "/inbox", { text: "Одно и то же", captureKey: `${KEY}-2` });

    // Same text is not the same capture: writing a thought down twice on
    // purpose is something a person does, and only the key can tell the two
    // apart.
    expect(items.filter((i) => i.text === "Одно и то же")).toHaveLength(2);
  });

  it("refuses a key too short to be one", async () => {
    const res = await call("POST", "/inbox", { text: "Купить кабель", captureKey: "abc" });

    expect(res.statusCode).toBe(400);
    expect(prismaMock.inboxItem.create).not.toHaveBeenCalled();
  });

  it("still takes a line with no key at all", async () => {
    // curl, and the browser client that has no queue behind it.
    const res = await call("POST", "/inbox", { text: "С рабочего стола" });

    expect(res.statusCode).toBe(201);
    expect(items.find((i) => i.text === "С рабочего стола")!.captureKey).toBeNull();
    // No lookup: with no key there is nothing to look up, and a findUnique on
    // `{ captureKey: undefined }` would match an arbitrary row.
    expect(prismaMock.inboxItem.findUnique).not.toHaveBeenCalled();
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
    expect(prismaMock.task.create).toHaveBeenCalledTimes(1);
    expect(prismaMock.inboxItem.delete).toHaveBeenCalledTimes(1);
  });

  it("starts the new task's journal in the same transaction (F11)", async () => {
    await call("POST", "/inbox/inb-1/file", { projectId: "prj-1" });

    const created = tasks.find((t) => t.title === "Спросить про кабель")!;
    // A task filed from the sandbox is a task like any other, and a task with
    // no `created` event is one the history mode cannot place in time.
    expect(events).toEqual([{ taskId: created.id, kind: "created", toStatus: "pending" }]);
    expect(prismaMock.$transaction).toHaveBeenCalledTimes(1);
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
