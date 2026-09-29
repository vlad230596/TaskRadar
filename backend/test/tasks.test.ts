import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach, vi } from "vitest";
import type { FastifyInstance } from "fastify";
import type { AuthConfig } from "../src/lib/authConfig";
import type { BuildAppOptions } from "../src/app";
import { inMemoryUsers, tokenFor, USER_A, USER_B } from "./support/users";

/*
 * Tasks, the working set and the history aggregates (F11), through the routes.
 *
 * Same shape as the other route tests here: no database in this environment, so
 * Prisma is a small in-memory fake that actually mutates rows. Two things this
 * file needs that the others did not:
 *
 * - the fake's `$transaction` **rolls back**. It snapshots the tables, runs the
 *   callback, and restores them if the callback throws. That is the one
 *   property the journal's whole value rests on -- an event written outside the
 *   transaction that changed the task would survive a failure and describe a
 *   change that never happened -- and a fake that could not fail would leave it
 *   untested;
 * - the fakes understand only the `where` shapes the routes actually send, and
 *   throw on anything else. A fake that quietly ignored an unknown filter would
 *   answer a future query with every row in the table and let a broken route
 *   pass.
 *
 * Data is separated per user: ownership lives on the scope, and a task is owned
 * through project -> scope -> userId. The fakes EVALUATE those owner filters
 * against the rows (see `ownedBy`) rather than skipping them, and the seed holds
 * a second user's project, tasks and events next to the first user's -- so the
 * unchanged expectations about the first user's data double as proof that
 * nothing of the second user's leaks into it.
 */
const prismaMock = vi.hoisted(() => ({
  project: { findFirst: vi.fn() },
  task: {
    findUnique: vi.fn(),
    findFirst: vi.fn(),
    findMany: vi.fn(),
    aggregate: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
  },
  taskEvent: { findMany: vi.fn(), create: vi.fn() },
  dictationParse: { updateMany: vi.fn() },
  $transaction: vi.fn(),
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));

process.env.DATABASE_URL ??= "postgresql://placeholder:placeholder@localhost:5432/placeholder";

const baseConfig: AuthConfig = {
  email: USER_A.email,
  passwordHash: "$2b$04$zV5VFEALedx8Rfd/ucwUSOrHYSSr8xveuActiCTdzOmCsBSDTbYXO",
  jwtSecret: "test-jwt-secret-".repeat(4),
  cookieSecure: false,
};

type Status = "pending" | "done" | "blocked";

interface TaskRow {
  id: string;
  projectId: string;
  title: string;
  description: string | null;
  status: Status;
  position: number;
  remindAt: Date | null;
  focusedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
}

interface EventRow {
  id: string;
  taskId: string;
  kind: "created" | "status" | "focused" | "unfocused";
  fromStatus: Status | null;
  toStatus: Status | null;
  at: Date;
}

interface ProjectRow {
  id: string;
  scopeId: string;
  name: string;
  archivedAt: Date | null;
}

interface ScopeRow {
  id: string;
  userId: string;
}

interface ParseRow {
  id: string;
  userId: string;
  kind: string;
  linkedAt: Date | null;
  taskId?: string;
  finalTitle?: string | null;
}

/** The clock every expectation below is written against. */
const NOW = new Date("2026-09-21T12:00:00.000Z");
const DAY = 86_400_000;
function at(iso: string): Date {
  return new Date(iso);
}

let scopes: ScopeRow[] = [];
let projects: ProjectRow[] = [];
let parses: ParseRow[] = [];
let tasks: TaskRow[] = [];
let events: EventRow[] = [];
let nextId = 0;

function task(row: Partial<TaskRow> & Pick<TaskRow, "id" | "projectId" | "title">): TaskRow {
  return {
    description: null,
    status: "pending",
    position: 1000,
    remindAt: null,
    focusedAt: null,
    createdAt: NOW,
    updatedAt: NOW,
    ...row,
  };
}

function event(row: Partial<EventRow> & Pick<EventRow, "taskId" | "kind" | "at">): EventRow {
  return { id: `evt-${++nextId}`, fromStatus: null, toStatus: null, ...row };
}

function seed(): void {
  nextId = 0;
  scopes = [
    { id: "scp-a", userId: USER_A.id },
    { id: "scp-b", userId: USER_B.id },
  ];
  projects = [
    { id: "prj-1", scopeId: "scp-a", name: "Дом", archivedAt: null },
    { id: "prj-2", scopeId: "scp-a", name: "Авоська", archivedAt: at("2026-07-01T00:00:00.000Z") },
    // Somebody else's: nothing below may show it to user A, or A's to user B.
    { id: "prj-b", scopeId: "scp-b", name: "Гараж", archivedAt: null },
  ];
  parses = [
    { id: "dp-a", userId: USER_A.id, kind: "task", linkedAt: null },
    { id: "dp-b", userId: USER_B.id, kind: "task", linkedAt: null },
  ];
  tasks = [
    // Waiting since the beginning of the month.
    task({ id: "tsk-1", projectId: "prj-1", title: "Починить кран", createdAt: at("2026-09-01T00:00:00.000Z"), position: 1000 }),
    // The oldest open one, and the one in the working set: blocked since the 5th.
    task({
      id: "tsk-2",
      projectId: "prj-1",
      title: "Купить кабель",
      status: "blocked",
      createdAt: at("2026-08-20T00:00:00.000Z"),
      focusedAt: at("2026-09-20T09:00:00.000Z"),
      position: 2000,
    }),
    // Closed yesterday.
    task({
      id: "tsk-3",
      projectId: "prj-1",
      title: "Старое дело",
      status: "done",
      createdAt: at("2026-09-10T00:00:00.000Z"),
      position: 3000,
    }),
    // Open, but in an archived project: deliberately put down, not stalled.
    task({ id: "tsk-4", projectId: "prj-2", title: "Заброшено", createdAt: at("2026-06-01T00:00:00.000Z"), position: 1000 }),
    // Opened inside the last week.
    task({ id: "tsk-5", projectId: "prj-1", title: "Свежая", createdAt: at("2026-09-19T00:00:00.000Z"), position: 4000 }),
    // User B's: one open and in B's working set, one closed inside the week.
    task({
      id: "tsk-b1",
      projectId: "prj-b",
      title: "Сменить масло",
      createdAt: at("2026-09-18T00:00:00.000Z"),
      focusedAt: at("2026-09-20T08:00:00.000Z"),
    }),
    task({
      id: "tsk-b2",
      projectId: "prj-b",
      title: "Помыть",
      status: "done",
      createdAt: at("2026-09-17T00:00:00.000Z"),
      position: 2000,
    }),
  ];
  events = [
    event({ taskId: "tsk-1", kind: "created", toStatus: "pending", at: at("2026-09-01T00:00:00.000Z") }),
    event({ taskId: "tsk-2", kind: "created", toStatus: "pending", at: at("2026-08-20T00:00:00.000Z") }),
    event({
      taskId: "tsk-2",
      kind: "status",
      fromStatus: "pending",
      toStatus: "blocked",
      at: at("2026-09-05T00:00:00.000Z"),
    }),
    event({ taskId: "tsk-2", kind: "focused", at: at("2026-09-20T09:00:00.000Z") }),
    event({ taskId: "tsk-3", kind: "created", toStatus: "pending", at: at("2026-09-10T00:00:00.000Z") }),
    event({
      taskId: "tsk-3",
      kind: "status",
      fromStatus: "pending",
      toStatus: "done",
      at: at("2026-09-20T10:00:00.000Z"),
    }),
    event({ taskId: "tsk-4", kind: "created", toStatus: "pending", at: at("2026-06-01T00:00:00.000Z") }),
    event({ taskId: "tsk-5", kind: "created", toStatus: "pending", at: at("2026-09-19T00:00:00.000Z") }),
    event({ taskId: "tsk-b1", kind: "created", toStatus: "pending", at: at("2026-09-18T00:00:00.000Z") }),
    event({ taskId: "tsk-b1", kind: "focused", at: at("2026-09-20T08:00:00.000Z") }),
    event({ taskId: "tsk-b2", kind: "created", toStatus: "pending", at: at("2026-09-17T00:00:00.000Z") }),
    event({
      taskId: "tsk-b2",
      kind: "status",
      fromStatus: "pending",
      toStatus: "done",
      at: at("2026-09-20T11:00:00.000Z"),
    }),
  ];
}

/** Does the project belong to this user, through its scope? */
function ownedBy(project: ProjectRow, userId: string): boolean {
  return scopes.find((s) => s.id === project.scopeId)?.userId === userId;
}

/** A project `where` (`{ id?, archivedAt?, scope: { userId } }`), evaluated against a row. */
function projectMatches(project: ProjectRow | undefined, filter: Record<string, unknown>): boolean {
  if (!project) return false;
  for (const [key, value] of Object.entries(filter)) {
    if (key === "id") {
      if (project.id !== value) return false;
    } else if (key === "archivedAt") {
      if (value !== null) throw new Error(`unexpected archivedAt filter ${JSON.stringify(value)}`);
      if (project.archivedAt !== null) return false;
    } else if (key === "scope") {
      const userId = (value as { userId?: unknown }).userId;
      if (typeof userId !== "string") throw new Error(`unexpected scope filter ${JSON.stringify(value)}`);
      if (!ownedBy(project, userId)) return false;
    } else {
      throw new Error(`unexpected project filter key ${key}`);
    }
  }
  return true;
}

/** Evaluates a task `where` against a row. Unknown keys throw, see the top of the file. */
function taskMatches(t: TaskRow, where: Record<string, unknown>): boolean {
  for (const [key, value] of Object.entries(where)) {
    switch (key) {
      case "id":
      case "projectId":
        if (t[key] !== value) return false;
        break;
      case "focusedAt":
        if (JSON.stringify(value) !== '{"not":null}') throw new Error("unexpected focusedAt filter");
        if (t.focusedAt === null) return false;
        break;
      case "status":
        if (JSON.stringify(value) !== '{"not":"done"}') throw new Error("unexpected status filter");
        if (t.status === "done") return false;
        break;
      case "project":
        if (!projectMatches(projects.find((p) => p.id === t.projectId), value as Record<string, unknown>)) {
          return false;
        }
        break;
      default:
        throw new Error(`task where: unexpected key ${key}`);
    }
  }
  return true;
}

let buildApp: (options?: BuildAppOptions) => Promise<FastifyInstance>;
let app: FastifyInstance;
/** User A's token -- what `call` sends unless told otherwise. */
let token: string;
let tokenB: string;

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

afterEach(() => {
  vi.useRealTimers();
});

beforeEach(() => {
  seed();
  for (const fn of Object.values(prismaMock.task)) fn.mockReset();
  for (const fn of Object.values(prismaMock.taskEvent)) fn.mockReset();
  prismaMock.project.findFirst.mockReset();
  prismaMock.dictationParse.updateMany.mockReset();
  prismaMock.$transaction.mockReset();

  prismaMock.project.findFirst.mockImplementation(
    (args: { where: Record<string, unknown> }) =>
      projects.find((p) => projectMatches(p, args.where)) ?? null,
  );

  // Only used for a neighbour in `PATCH /tasks/:id/position`, always by id.
  prismaMock.task.findUnique.mockImplementation(
    (args: { where: { id: string } }) => tasks.find((t) => t.id === args.where.id) ?? null,
  );

  prismaMock.task.findFirst.mockImplementation(
    (args: { where: Record<string, unknown> }) =>
      tasks.find((t) => taskMatches(t, args.where)) ?? null,
  );

  /*
   * Labels the parse rows the way the database would: `where` is evaluated
   * against them, so a parse of another user simply matches nothing.
   */
  prismaMock.dictationParse.updateMany.mockImplementation(
    (args: {
      where: { id: string; userId: string; linkedAt: null; kind: { in: string[] } };
      data: Partial<ParseRow>;
    }) => {
      const hit = parses.filter(
        (p) =>
          p.id === args.where.id &&
          p.userId === args.where.userId &&
          p.linkedAt === null &&
          args.where.kind.in.includes(p.kind),
      );
      for (const p of hit) Object.assign(p, args.data);
      return { count: hit.length };
    },
  );

  /*
   * The `where` shapes the routes send, evaluated against the rows, and a loud
   * failure for anything else -- see the note at the top of this file.
   */
  prismaMock.task.findMany.mockImplementation(
    (args: {
      where: Record<string, unknown>;
      orderBy?: Record<string, string>;
      include?: Record<string, unknown>;
    }) => {
      let rows = tasks.filter((t) => taskMatches(t, args.where ?? {}));

      if (args.orderBy?.position) rows = [...rows].sort((a, b) => a.position - b.position);
      if (args.orderBy?.focusedAt) {
        rows = [...rows].sort((a, b) => a.focusedAt!.getTime() - b.focusedAt!.getTime());
      }

      return rows.map((row) => ({
        ...row,
        ...(args.include?.project
          ? { project: projects.find((p) => p.id === row.projectId)! }
          : {}),
        ...(args.include?.events
          ? {
              events: events
                .filter((e) => e.taskId === row.id)
                .sort((a, b) => a.at.getTime() - b.at.getTime()),
            }
          : {}),
      }));
    },
  );

  prismaMock.task.aggregate.mockImplementation((args: { where: { projectId: string } }) => {
    const positions = tasks.filter((t) => t.projectId === args.where.projectId).map((t) => t.position);
    return { _max: { position: positions.length ? Math.max(...positions) : null } };
  });

  prismaMock.task.create.mockImplementation((args: { data: Partial<TaskRow> }) => {
    const row = task({
      id: `tsk-new-${++nextId}`,
      projectId: args.data.projectId!,
      title: args.data.title!,
      ...args.data,
    });
    tasks.push(row);
    return { ...row };
  });

  prismaMock.task.update.mockImplementation(
    (args: { where: { id: string }; data: Partial<TaskRow> }) => {
      const row = tasks.find((t) => t.id === args.where.id);
      if (!row) throw new Error("update against no row");
      Object.assign(row, args.data, { updatedAt: NOW });
      return { ...row };
    },
  );

  prismaMock.task.delete.mockImplementation((args: { where: { id: string } }) => {
    const index = tasks.findIndex((t) => t.id === args.where.id);
    if (index === -1) throw new Error("delete against no row");
    // The database cascades; the fake has to, or a deleted task's events would
    // keep showing up in the aggregates and nothing here would notice.
    events = events.filter((e) => e.taskId !== args.where.id);
    return tasks.splice(index, 1)[0]!;
  });

  prismaMock.taskEvent.create.mockImplementation((args: { data: Partial<EventRow> }) => {
    const row = event({
      taskId: args.data.taskId!,
      kind: args.data.kind!,
      at: args.data.at ?? new Date(),
      ...args.data,
    });
    events.push(row);
    return { ...row };
  });

  prismaMock.taskEvent.findMany.mockImplementation(
    (args: { where: Record<string, unknown>; select?: Record<string, unknown> }) => {
      const where = args.where ?? {};
      let rows: EventRow[];

      if (typeof where.taskId === "string") {
        rows = events.filter((e) => e.taskId === where.taskId);
      } else if (Array.isArray(where.OR)) {
        const gte = (where.at as { gte?: Date } | undefined)?.gte;
        // The history aggregate is always scoped to one user's tasks.
        const owner = where.task as { project: Record<string, unknown> } | undefined;
        if (!owner) throw new Error("taskEvent.findMany: aggregate without an owner filter");
        rows = events.filter(
          (e) =>
            (e.kind === "created" || (e.kind === "status" && e.toStatus === "done")) &&
            (gte === undefined || e.at.getTime() >= gte.getTime()) &&
            taskMatches(tasks.find((t) => t.id === e.taskId)!, owner),
        );
      } else {
        throw new Error(`taskEvent.findMany: unexpected where ${JSON.stringify(where)}`);
      }

      rows = [...rows].sort((a, b) => a.at.getTime() - b.at.getTime());

      if (!args.select?.task) return rows;
      return rows.map((e) => {
        const owner = tasks.find((t) => t.id === e.taskId)!;
        return {
          ...e,
          task: {
            projectId: owner.projectId,
            project: { name: projects.find((p) => p.id === owner.projectId)!.name },
          },
        };
      });
    },
  );

  /*
   * An interactive transaction that can roll back.
   *
   * The fakes above apply their writes as they are called, so the only way to
   * model "all of it or none of it" is to snapshot the tables before the
   * callback and put them back if it throws. Shallow copies of the rows are
   * enough because every fake replaces or mutates whole rows, and it keeps the
   * restore honest about which rows existed.
   */
  prismaMock.$transaction.mockImplementation(async (run: (tx: unknown) => Promise<unknown>) => {
    const tasksBefore = tasks.map((t) => ({ ...t }));
    const eventsBefore = events.map((e) => ({ ...e }));
    const parsesBefore = parses.map((p) => ({ ...p }));
    try {
      return await run(prismaMock);
    } catch (error) {
      tasks = tasksBefore;
      events = eventsBefore;
      parses = parsesBefore;
      throw error;
    }
  });
});

describe("POST /projects/:projectId/tasks", () => {
  it("links a dictated task to its sample, with a snapshot of what was kept (F14)", async () => {
    prismaMock.dictationParse.updateMany.mockReset();
    prismaMock.dictationParse.updateMany.mockResolvedValue({ count: 1 });

    const res = await call("POST", "/projects/prj-1/tasks", {
      title: "Заказать кабель USB-C",
      description: "Два метра",
      status: "blocked",
      remindAt: "2026-10-02",
      dictationParseId: "dp-7",
    });

    expect(res.statusCode).toBe(201);
    const created = res.json() as { id: string };
    expect(prismaMock.dictationParse.updateMany).toHaveBeenCalledTimes(1);
    const args = prismaMock.dictationParse.updateMany.mock.calls[0]![0] as {
      where: unknown;
      data: Record<string, unknown>;
    };
    // Only a row not linked yet: a retried request must not relabel it. And
    // only of a kind that ends as a new task.
    expect(args.where).toEqual({
      id: "dp-7",
      userId: USER_A.id,
      linkedAt: null,
      kind: { in: ["task", "sandbox", "task_tidy"] },
    });
    expect(args.data).toMatchObject({
      taskId: created.id,
      finalTitle: "Заказать кабель USB-C",
      finalDescription: "Два метра",
    });
    expect(args.data.finalRemindAt).toEqual(new Date("2026-10-02T00:00:00.000Z"));
    expect(args.data.linkedAt).toBeInstanceOf(Date);
  });

  it("touches no sample for a task that was typed", async () => {
    prismaMock.dictationParse.updateMany.mockReset();
    await call("POST", "/projects/prj-1/tasks", { title: "Руками" });
    expect(prismaMock.dictationParse.updateMany).not.toHaveBeenCalled();
  });

  it("starts the task's journal in the same transaction", async () => {
    const res = await call("POST", "/projects/prj-1/tasks", { title: "Новая задача" });

    expect(res.statusCode).toBe(201);
    const created = tasks.find((t) => t.title === "Новая задача")!;
    // The `created` event is what the history mode measures age from -- a task
    // without one is a task it cannot place in time.
    expect(events.filter((e) => e.taskId === created.id)).toMatchObject([
      { kind: "created", fromStatus: null, toStatus: "pending" },
    ]);
    expect(prismaMock.$transaction).toHaveBeenCalledTimes(1);
  });

  it("records the status the task was born in", async () => {
    // Almost always `pending`, but the route accepts a status, and a journal
    // that has to read the task row to know where its first interval began is a
    // journal that cannot be replayed on its own.
    await call("POST", "/projects/prj-1/tasks", { title: "Сразу заблокирована", status: "blocked" });

    const created = tasks.find((t) => t.title === "Сразу заблокирована")!;
    expect(events.find((e) => e.taskId === created.id)!.toStatus).toBe("blocked");
  });

  it("writes nothing at all for an unknown project", async () => {
    const eventsBefore = events.length;
    const res = await call("POST", "/projects/prj-nope/tasks", { title: "Новая задача" });

    expect(res.statusCode).toBe(404);
    expect(prismaMock.$transaction).not.toHaveBeenCalled();
    expect(events).toHaveLength(eventsBefore);
  });
});

describe("PATCH /tasks/:id", () => {
  it("records a status change", async () => {
    const res = await call("PATCH", "/tasks/tsk-1", { status: "blocked" });

    expect(res.statusCode).toBe(200);
    expect(tasks.find((t) => t.id === "tsk-1")!.status).toBe("blocked");
    expect(events.filter((e) => e.taskId === "tsk-1" && e.kind === "status")).toMatchObject([
      { fromStatus: "pending", toStatus: "blocked" },
    ]);
  });

  it("records nothing when only the text changes", async () => {
    await call("PATCH", "/tasks/tsk-1", { title: "Починить смеситель", description: "под мойкой" });

    expect(tasks.find((t) => t.id === "tsk-1")!.title).toBe("Починить смеситель");
    // Correcting a wording is not movement. Journalling it would fill the "life
    // of this task" section with rows that answer no question.
    expect(prismaMock.taskEvent.create).not.toHaveBeenCalled();
  });

  it("records nothing when the status is sent unchanged", async () => {
    // The client sends the whole editable shape on every edit, so this is the
    // common case, not a corner one.
    await call("PATCH", "/tasks/tsk-1", { title: "Починить кран", status: "pending" });

    expect(prismaMock.taskEvent.create).not.toHaveBeenCalled();
  });

  it("takes a finished task out of the working set, and says why", async () => {
    const res = await call("PATCH", "/tasks/tsk-2", { status: "done" });

    expect(res.statusCode).toBe(200);
    expect(tasks.find((t) => t.id === "tsk-2")!.focusedAt).toBeNull();
    expect(
      events.filter((e) => e.taskId === "tsk-2").map((e) => e.kind),
    ).toEqual(["created", "status", "focused", "status", "unfocused"]);
  });

  it("leaves no event behind when the transaction fails", async () => {
    /*
     * THE property the journal rests on. The task write succeeds, the journal
     * write blows up, and what must not survive is a half: neither an event
     * describing a change that was rolled back, nor a changed task with nothing
     * in the journal to explain it.
     */
    prismaMock.taskEvent.create.mockImplementationOnce(() => {
      throw new Error("boom");
    });

    const res = await call("PATCH", "/tasks/tsk-1", { status: "done" });

    expect(res.statusCode).toBe(500);
    expect(tasks.find((t) => t.id === "tsk-1")!.status).toBe("pending");
    expect(events.filter((e) => e.taskId === "tsk-1")).toHaveLength(1);
  });

  it("links a tidied task's sample to the task, with the text as saved (F15)", async () => {
    prismaMock.dictationParse.updateMany.mockReset();
    prismaMock.dictationParse.updateMany.mockResolvedValue({ count: 1 });

    const res = await call("PATCH", "/tasks/tsk-1", {
      title: "Починить кран на кухне",
      description: "Прокладка, 1/2 дюйма",
      dictationParseId: "dp-9",
    });

    expect(res.statusCode).toBe(200);
    expect(tasks.find((t) => t.id === "tsk-1")!.title).toBe("Починить кран на кухне");
    const args = prismaMock.dictationParse.updateMany.mock.calls[0]![0] as {
      where: unknown;
      data: Record<string, unknown>;
    };
    expect(args.where).toEqual({
      id: "dp-9",
      userId: USER_A.id,
      linkedAt: null,
      kind: { in: ["task_tidy"] },
    });
    expect(args.data).toMatchObject({
      taskId: "tsk-1",
      finalTitle: "Починить кран на кухне",
      finalDescription: "Прокладка, 1/2 дюйма",
    });
    expect(args.data.linkedAt).toBeInstanceOf(Date);
  });

  it("touches no sample for an ordinary edit", async () => {
    prismaMock.dictationParse.updateMany.mockReset();
    await call("PATCH", "/tasks/tsk-1", { title: "Руками" });
    expect(prismaMock.dictationParse.updateMany).not.toHaveBeenCalled();
  });

  it("refuses a body that carries only the sample's id", async () => {
    const res = await call("PATCH", "/tasks/tsk-1", { dictationParseId: "dp-9" });
    expect(res.statusCode).toBe(400);
  });
});

describe("GET /tasks/:id/events", () => {
  it("returns one task's journal, oldest first", async () => {
    const res = await call("GET", "/tasks/tsk-2/events");

    expect(res.statusCode).toBe(200);
    expect((res.json() as EventRow[]).map((e) => e.kind)).toEqual(["created", "status", "focused"]);
  });

  it("404s for an unknown task", async () => {
    expect((await call("GET", "/tasks/tsk-nope/events")).statusCode).toBe(404);
  });

  it("requires a session", async () => {
    expect((await call("GET", "/tasks/tsk-2/events", undefined, false)).statusCode).toBe(401);
  });
});

describe("DELETE /tasks/:id", () => {
  it("takes the journal with it", async () => {
    await call("DELETE", "/tasks/tsk-2");

    // The schema cascades: this is the task's own history, not an audit trail.
    expect(events.some((e) => e.taskId === "tsk-2")).toBe(false);
  });
});

describe("the working set", () => {
  it("lists it in the order it was built, with project names", async () => {
    await call("POST", "/tasks/tsk-1/focus");

    const res = await call("GET", "/focus");
    expect(res.statusCode).toBe(200);
    const set = res.json() as { id: string; project: { id: string; name: string } }[];
    // tsk-2 was picked yesterday, tsk-1 a moment ago: the set is worked through
    // in the order it was assembled.
    expect(set.map((t) => t.id)).toEqual(["tsk-2", "tsk-1"]);
    expect(set[0]!.project.name).toBe("Дом");
  });

  it("records entering and leaving", async () => {
    await call("POST", "/tasks/tsk-1/focus");
    await call("DELETE", "/tasks/tsk-1/focus");

    expect(events.filter((e) => e.taskId === "tsk-1").map((e) => e.kind)).toEqual([
      "created",
      "focused",
      "unfocused",
    ]);
    expect(tasks.find((t) => t.id === "tsk-1")!.focusedAt).toBeNull();
  });

  it("does not reorder the set when a task already in it is picked again", async () => {
    // A double tap on a phone, or a retried request, must not move the task the
    // person is in the middle of to the end of the set.
    const before = tasks.find((t) => t.id === "tsk-2")!.focusedAt;

    const res = await call("POST", "/tasks/tsk-2/focus");

    expect(res.statusCode).toBe(200);
    expect(tasks.find((t) => t.id === "tsk-2")!.focusedAt).toEqual(before);
    expect(prismaMock.taskEvent.create).not.toHaveBeenCalled();
  });

  it("shrugs at removing a task that was never in it", async () => {
    const res = await call("DELETE", "/tasks/tsk-1/focus");

    expect(res.statusCode).toBe(200);
    expect(prismaMock.taskEvent.create).not.toHaveBeenCalled();
  });

  it("does not enforce a limit of five", async () => {
    /*
     * Five slots is what the screen draws and what a person can hold. The
     * server has no way to know that, and a 409 here could only restate a
     * layout decision -- a set of six is a screen that scrolls, not a corrupt
     * database.
     */
    for (const id of ["tsk-1", "tsk-3", "tsk-4", "tsk-5"]) {
      expect((await call("POST", `/tasks/${id}/focus`)).statusCode).toBe(200);
    }
    const res = await call("POST", "/projects/prj-1/tasks", { title: "Шестая" });
    const sixth = (res.json() as { id: string }).id;

    expect((await call("POST", `/tasks/${sixth}/focus`)).statusCode).toBe(200);
    expect(tasks.filter((t) => t.focusedAt !== null && t.projectId !== "prj-b")).toHaveLength(6);
  });

  it("404s for an unknown task", async () => {
    expect((await call("POST", "/tasks/tsk-nope/focus")).statusCode).toBe(404);
    expect((await call("DELETE", "/tasks/tsk-nope/focus")).statusCode).toBe(404);
  });

  it("requires a session", async () => {
    expect((await call("GET", "/focus", undefined, false)).statusCode).toBe(401);
    expect((await call("POST", "/tasks/tsk-1/focus", undefined, false)).statusCode).toBe(401);
  });
});

describe("GET /history", () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(NOW);
  });

  interface HistoryBody {
    range: string;
    from: string | null;
    closedByDay: { date: string; count: number }[];
    closedTotal: number;
    projects: { projectId: string; name: string; opened: number; closed: number }[];
    stale: {
      id: string;
      ageMs: number;
      currentForMs: number;
      byStatus: { pending: number; done: number; blocked: number };
    }[];
  }

  it("counts closings per day, with the empty days drawn in", async () => {
    const res = await call("GET", "/history?range=7d");

    expect(res.statusCode).toBe(200);
    const body = res.json() as HistoryBody;
    expect(body.closedByDay).toHaveLength(7);
    expect(body.closedByDay.find((d) => d.date === "2026-09-20")!.count).toBe(1);
    expect(body.closedTotal).toBe(1);
  });

  it("counts what moved in each project", async () => {
    const res = await call("GET", "/history?range=7d");

    // In the last week: one task opened (tsk-5, on the 19th) and one closed
    // (tsk-3, on the 20th). Older events are outside the window.
    expect((res.json() as HistoryBody).projects).toEqual([
      { projectId: "prj-1", name: "Дом", opened: 1, closed: 1 },
    ]);
  });

  it("widens with the range", async () => {
    const body = (await call("GET", "/history?range=all")).json() as HistoryBody;

    expect(body.from).toBeNull();
    // Everything ever: five tasks opened, one of them in the archived project.
    expect(body.projects.find((p) => p.projectId === "prj-1")!.opened).toBe(4);
    expect(body.projects.find((p) => p.projectId === "prj-2")!.opened).toBe(1);
  });

  it("puts the longest-hanging task first, with its time broken down", async () => {
    const body = (await call("GET", "/history?range=7d")).json() as HistoryBody;

    // tsk-2 is the oldest open one: waiting since 20 Aug, blocked since 5 Sep.
    expect(body.stale.map((t) => t.id)).toEqual(["tsk-2", "tsk-1", "tsk-5"]);
    const oldest = body.stale[0]!;
    expect(oldest.byStatus.pending).toBe(16 * DAY);
    expect(oldest.byStatus.blocked).toBe(16 * DAY + DAY / 2);
    expect(oldest.currentForMs).toBe(16 * DAY + DAY / 2);
    expect(oldest.ageMs).toBe(oldest.byStatus.pending + oldest.byStatus.blocked);
  });

  it("leaves out what is not hanging", async () => {
    const body = (await call("GET", "/history?range=7d")).json() as HistoryBody;
    const listed = body.stale.map((t) => t.id);

    // A finished task is not hanging, and a task in an archived project is
    // parked rather than stalled -- a list that fills with work somebody already
    // decided to stop is a list that stops being read.
    expect(listed).not.toContain("tsk-3");
    expect(listed).not.toContain("tsk-4");
  });

  it("honours the client's day boundary", async () => {
    // tsk-3 was closed at 10:00 UTC on the 20th; twelve hours west of UTC that
    // is still the 19th.
    const body = (await call("GET", "/history?range=7d&tzOffsetMinutes=-720")).json() as HistoryBody;

    expect(body.closedByDay.find((d) => d.count === 1)!.date).toBe("2026-09-19");
  });

  it("caps the stale list", async () => {
    const body = (await call("GET", "/history?range=7d&staleLimit=1")).json() as HistoryBody;

    expect(body.stale).toHaveLength(1);
    expect(body.stale[0]!.id).toBe("tsk-2");
  });

  it("refuses a nonsense window", async () => {
    // A bad offset is a 400, not a chart shifted by a year.
    expect((await call("GET", "/history?range=year")).statusCode).toBe(400);
    expect((await call("GET", "/history?tzOffsetMinutes=99999")).statusCode).toBe(400);
    expect((await call("GET", "/history?staleLimit=0")).statusCode).toBe(400);
  });

  it("defaults to a month, in UTC, without a query at all", async () => {
    const body = (await call("GET", "/history")).json() as HistoryBody;

    expect(body.range).toBe("30d");
    expect(body.closedByDay).toHaveLength(30);
  });

  it("requires a session", async () => {
    expect((await call("GET", "/history", undefined, false)).statusCode).toBe(401);
  });
});

describe("one user's tasks are invisible to another", () => {
  /*
   * 404, not 403: a 403 would confirm that the id exists, and ids are all a
   * stranger needs to start guessing. Every attempt below also checks that the
   * data did not move, so a route that answered 404 after writing would fail.
   */
  const asB = (method: string, url: string, payload?: unknown) =>
    call(method, url, payload, true, tokenB);

  it("404s for B on every route of A's task, and changes nothing", async () => {
    const tasksBefore = JSON.stringify(tasks);
    const eventsBefore = JSON.stringify(events);

    const attempts: [string, string, unknown?][] = [
      ["PATCH", "/tasks/tsk-1", { title: "Чужое", status: "done" }],
      ["PATCH", "/tasks/tsk-1/position", { afterTaskId: "tsk-5" }],
      ["GET", "/tasks/tsk-1/events"],
      ["DELETE", "/tasks/tsk-1"],
      ["POST", "/tasks/tsk-1/focus"],
      // tsk-2 is in A's working set: B must not be able to take it out either.
      ["DELETE", "/tasks/tsk-2/focus"],
    ];
    for (const [method, url, payload] of attempts) {
      const res = await asB(method, url, payload);
      expect(res.statusCode, `${method} ${url}`).toBe(404);
    }

    expect(JSON.stringify(tasks)).toBe(tasksBefore);
    expect(JSON.stringify(events)).toBe(eventsBefore);
    expect(prismaMock.$transaction).not.toHaveBeenCalled();
    expect(prismaMock.task.delete).not.toHaveBeenCalled();
  });

  it("404s for A on B's task just the same", async () => {
    expect((await call("GET", "/tasks/tsk-b1/events")).statusCode).toBe(404);
    expect((await call("PATCH", "/tasks/tsk-b1", { title: "Чужое" })).statusCode).toBe(404);
    expect((await call("DELETE", "/tasks/tsk-b1/focus")).statusCode).toBe(404);
    expect(tasks.find((t) => t.id === "tsk-b1")!.focusedAt).not.toBeNull();
  });

  it("will not create or list tasks in someone else's project", async () => {
    const eventsBefore = events.length;

    expect((await asB("POST", "/projects/prj-1/tasks", { title: "Подкинуто" })).statusCode).toBe(404);
    expect((await asB("GET", "/projects/prj-1/tasks")).statusCode).toBe(404);

    expect(tasks.some((t) => t.title === "Подкинуто")).toBe(false);
    expect(events).toHaveLength(eventsBefore);
    expect(prismaMock.$transaction).not.toHaveBeenCalled();
    // ...while the owner still can.
    expect((await call("GET", "/projects/prj-1/tasks")).statusCode).toBe(200);
  });

  it("does not link a sample of another user when a task is created with its id", async () => {
    // B saves a task in B's own project, carrying the id of A's parse.
    const res = await asB("POST", "/projects/prj-b/tasks", { title: "Свой", dictationParseId: "dp-a" });

    expect(res.statusCode).toBe(201);
    expect(prismaMock.dictationParse.updateMany).toHaveBeenCalledTimes(1);
    expect(prismaMock.dictationParse.updateMany.mock.results[0]!.value).toEqual({ count: 0 });
    const parse = parses.find((p) => p.id === "dp-a")!;
    expect(parse.linkedAt).toBeNull();
    expect(parse.taskId).toBeUndefined();
    expect(parse.finalTitle).toBeUndefined();

    // Control: B's own parse is labelled by the same route.
    await asB("POST", "/projects/prj-b/tasks", { title: "Опять свой", dictationParseId: "dp-b" });
    expect(parses.find((p) => p.id === "dp-b")!.finalTitle).toBe("Опять свой");
  });

  it("does not link a sample of another user when a task is edited with its id", async () => {
    // A tidies A's task with B's parse id; the kind is right, the owner is not.
    parses.find((p) => p.id === "dp-b")!.kind = "task_tidy";

    const res = await call("PATCH", "/tasks/tsk-1", { title: "Причёсано", dictationParseId: "dp-b" });

    expect(res.statusCode).toBe(200);
    expect(tasks.find((t) => t.id === "tsk-1")!.title).toBe("Причёсано");
    expect(parses.find((p) => p.id === "dp-b")!.linkedAt).toBeNull();
  });

  it("gives each user only their own working set", async () => {
    const listA = (await call("GET", "/focus")).json() as { id: string }[];
    const listB = (await asB("GET", "/focus")).json() as { id: string; project: { name: string } }[];

    expect(listA.map((t) => t.id)).toEqual(["tsk-2"]);
    expect(listB.map((t) => t.id)).toEqual(["tsk-b1"]);
    expect(listB[0]!.project.name).toBe("Гараж");
  });

  it("builds each user's history from their own events only", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(NOW);
    interface Body {
      closedTotal: number;
      closedByDay: { date: string; count: number }[];
      projects: { projectId: string; opened: number; closed: number }[];
      stale: { id: string }[];
    }

    const b = (await asB("GET", "/history?range=7d")).json() as Body;
    // B opened two tasks and closed one, all in B's project.
    expect(b.projects).toEqual([{ projectId: "prj-b", name: "Гараж", opened: 2, closed: 1 }]);
    expect(b.closedTotal).toBe(1);
    expect(b.closedByDay.find((d) => d.date === "2026-09-20")!.count).toBe(1);
    expect(b.stale.map((t) => t.id)).toEqual(["tsk-b1"]);

    // A's numbers are the ones the history tests above expect, unchanged by B's rows.
    const a = (await call("GET", "/history?range=7d")).json() as Body;
    expect(a.projects).toEqual([{ projectId: "prj-1", name: "Дом", opened: 1, closed: 1 }]);
    expect(a.closedTotal).toBe(1);
    expect(a.stale.map((t) => t.id)).toEqual(["tsk-2", "tsk-1", "tsk-5"]);

    // And over all time: no project of the other user in either list.
    const allA = (await call("GET", "/history?range=all")).json() as Body;
    expect(allA.projects.map((p) => p.projectId).sort()).toEqual(["prj-1", "prj-2"]);
    const allB = (await asB("GET", "/history?range=all")).json() as Body;
    expect(allB.projects.map((p) => p.projectId)).toEqual(["prj-b"]);
  });
});
