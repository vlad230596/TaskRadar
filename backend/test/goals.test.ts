import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach, vi } from "vitest";
import type { FastifyInstance } from "fastify";
import { Prisma } from "@prisma/client";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import type { AuthConfig } from "../src/lib/authConfig";
import { inMemoryUsers, tokenFor, USER_A, USER_B } from "./support/users";
import {
  extendedWindowEnd,
  goalState,
  goalView,
  nextStepOf,
  windowEnd,
  type GoalRow,
} from "../src/domain/goals";

/*
 * Goals, contours and ideas (design/goals-ideas-contract.md): the routes, the
 * idea-to-task conversion, the task view's crown, and the MCP tools.
 *
 * Same approach as the other route tests: no database here, Prisma is an
 * in-memory fake that mutates rows. This one is a little more general than
 * the others, because a goal reads across five tables: `where` is EVALUATED
 * against the rows -- columns, `null`, `{ not }`, `{ in }`, `OR`, and the
 * relations the routes filter through (task -> project -> scope -> userId,
 * goal link -> goal) -- and any key the fake does not know throws, so an
 * owner filter that went missing or got misspelt fails loudly instead of
 * handing everyone's rows to everyone. The seed holds a second user's scope,
 * project, task, idea and contour, so every "own" expectation is also a proof
 * that the other user's rows do not leak.
 *
 * `$transaction` rolls back, as in tasks.test.ts: a refused slot must leave
 * no half-made goal behind, and that is only testable with a fake that can
 * fail.
 */

const prismaMock = vi.hoisted(() => {
  const fns = () => ({
    findFirst: vi.fn(),
    findMany: vi.fn(),
    findUnique: vi.fn(),
    findUniqueOrThrow: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    updateMany: vi.fn(),
    delete: vi.fn(),
    deleteMany: vi.fn(),
    count: vi.fn(),
    aggregate: vi.fn(),
  });
  return {
    user: fns(),
    scope: fns(),
    project: fns(),
    task: fns(),
    note: fns(),
    contour: fns(),
    goal: fns(),
    goalTask: fns(),
    goalIdea: fns(),
    taskEvent: fns(),
    taskCategory: fns(),
    $transaction: vi.fn(),
  };
});

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));

process.env.DATABASE_URL ??= "postgresql://placeholder:placeholder@localhost:5432/placeholder";

const config: AuthConfig = {
  email: USER_A.email,
  passwordHash: "$2b$04$zV5VFEALedx8Rfd/ucwUSOrHYSSr8xveuActiCTdzOmCsBSDTbYXO",
  jwtSecret: "test-jwt-secret-".repeat(4),
  cookieSecure: false,
};

const NOW = new Date("2026-11-24T09:00:00.000Z");
const DAY = 24 * 60 * 60 * 1000;

// ---- the fake ----

/* eslint-disable @typescript-eslint/no-explicit-any */
type Row = Record<string, any>;
type ModelName = Exclude<keyof typeof prismaMock, "$transaction">;

let db: Record<ModelName, Row[]>;
let seq = 0;

/** Every column of each model, with its default: a `where` on anything else throws. */
const COLUMNS: Record<ModelName, Row> = {
  user: { id: null, activeContourId: null, activeContourUntil: null },
  scope: { id: null, userId: null, name: "", position: 0 },
  project: { id: null, name: "", scopeId: null, archivedAt: null },
  task: {
    id: null,
    projectId: null,
    title: "",
    description: null,
    status: "pending",
    position: 0,
    categoryId: null,
    remindAt: null,
    remindTime: null,
    focusedAt: null,
    focusContourId: null,
    aiSource: null,
    aiKind: null,
    aiResult: null,
    createKey: null,
    checklist: null,
    locLat: null,
    locLng: null,
    locRadius: null,
    locLabel: null,
    createdAt: null,
    updatedAt: null,
  },
  note: { id: null, projectId: null, title: "", content: "", aiSource: null, createdAt: null, updatedAt: null },
  contour: {
    id: null,
    userId: null,
    name: "",
    slots: 2,
    windowDays: 7,
    schedule: null,
    position: 0,
    createdAt: null,
    updatedAt: null,
  },
  goal: {
    id: null,
    userId: null,
    contourId: null,
    title: "",
    why: null,
    slottedAt: null,
    windowDays: null,
    windowEndsAt: null,
    achievedAt: null,
    position: 0,
    createdAt: null,
    updatedAt: null,
  },
  goalTask: { goalId: null, taskId: null, position: 0, createdAt: null },
  goalIdea: { goalId: null, noteId: null, createdAt: null },
  taskEvent: { id: null, taskId: null, kind: null, fromStatus: null, toStatus: null, at: null },
  taskCategory: { id: null, projectId: null, name: "" },
};

const byId = (model: ModelName, id: unknown) => db[model].find((r) => r.id === id);

/** The relations a `where` / `orderBy` may go through: [target model, lookup]. */
const RELATIONS: Partial<Record<ModelName, Record<string, [ModelName, (row: Row) => Row | undefined]>>> = {
  task: { project: ["project", (r) => byId("project", r.projectId)] },
  project: { scope: ["scope", (r) => byId("scope", r.scopeId)] },
  note: { project: ["project", (r) => byId("project", r.projectId)] },
  goal: { contour: ["contour", (r) => byId("contour", r.contourId)] },
  goalTask: {
    goal: ["goal", (r) => byId("goal", r.goalId)],
    task: ["task", (r) => byId("task", r.taskId)],
  },
};

const COMPOUND_KEYS: Record<string, string[]> = {
  goalId_taskId: ["goalId", "taskId"],
  goalId_noteId: ["goalId", "noteId"],
};

function condOk(value: unknown, cond: unknown): boolean {
  if (cond === null) return value === null || value === undefined;
  if (cond instanceof Date) return value instanceof Date && value.getTime() === cond.getTime();
  if (typeof cond !== "object") return value === cond;
  for (const [op, arg] of Object.entries(cond as Row)) {
    if (op === "not") {
      if (arg === null ? value === null || value === undefined : value === arg) return false;
    } else if (op === "in") {
      if (!(arg as unknown[]).includes(value)) return false;
    } else {
      throw new Error(`fake: unknown operator ${op}`);
    }
  }
  return true;
}

function matches(model: ModelName, row: Row, where: Row = {}): boolean {
  for (const [key, cond] of Object.entries(where)) {
    if (cond === undefined) continue;
    if (key === "OR") {
      if (!(cond as Row[]).some((one) => matches(model, row, one))) return false;
      continue;
    }
    if (COMPOUND_KEYS[key]) {
      for (const column of COMPOUND_KEYS[key]) if (row[column] !== (cond as Row)[column]) return false;
      continue;
    }
    const relation = RELATIONS[model]?.[key];
    if (relation) {
      const target = relation[1](row);
      if (!target || !matches(relation[0], target, cond as Row)) return false;
      continue;
    }
    if (!(key in COLUMNS[model])) throw new Error(`fake ${model}: unsupported where key ${key}`);
    if (!condOk(row[key], cond)) return false;
  }
  return true;
}

function compare(x: unknown, y: unknown): number {
  const a = x instanceof Date ? x.getTime() : (x as number);
  const b = y instanceof Date ? y.getTime() : (y as number);
  return a < b ? -1 : a > b ? 1 : 0;
}

function sortRows(model: ModelName, rows: Row[], orderBy: unknown): Row[] {
  const list = (orderBy === undefined ? [] : Array.isArray(orderBy) ? orderBy : [orderBy]) as Row[];
  return [...rows].sort((a, b) => {
    for (const one of list) {
      const [key, dir] = Object.entries(one)[0]!;
      let x: unknown;
      let y: unknown;
      let direction = dir as string;
      if (typeof dir === "object") {
        const [[field, nested]] = Object.entries(dir as Row) as [[string, string]];
        const relation = RELATIONS[model]![key]!;
        x = relation[1](a)?.[field];
        y = relation[1](b)?.[field];
        direction = nested;
      } else {
        x = a[key];
        y = b[key];
      }
      const c = compare(x, y);
      if (c !== 0) return direction === "desc" ? -c : c;
    }
    return 0;
  });
}

/** A row in the shape an `include` asks for (the includes the code sends). */
function shape(model: ModelName, row: Row, args: Row = {}): Row {
  const include = args.include as Row | undefined;
  const out: Row = { ...row };
  if (include === undefined) return out;
  if (model === "task") {
    if (include.attachments) out.attachments = [];
    if (include.project) {
      const p = byId("project", row.projectId)!;
      out.project = { id: p.id, name: p.name };
    }
    if (include.goalLinks) {
      out.goalLinks = sortRows(
        "goalTask",
        db.goalTask.filter((l) => l.taskId === row.id && matches("goalTask", l, include.goalLinks.where)),
        include.goalLinks.orderBy,
      ).map((l) => {
        const g = byId("goal", l.goalId)!;
        return { goal: { id: g.id, title: g.title, contourId: g.contourId } };
      });
    }
  } else if (model === "goal") {
    out.contour = { windowDays: byId("contour", row.contourId)!.windowDays };
    out.tasks = sortRows(
      "goalTask",
      db.goalTask.filter((l) => l.goalId === row.id),
      include.tasks.orderBy,
    ).map((l) => {
      const t = byId("task", l.taskId)!;
      return { position: l.position, task: { ...t, project: { name: byId("project", t.projectId)!.name } } };
    });
    out.ideas = sortRows(
      "goalIdea",
      db.goalIdea.filter((l) => l.goalId === row.id),
      include.ideas.orderBy,
    ).map((l) => {
      const n = byId("note", l.noteId)!;
      return { note: { ...n, project: { name: byId("project", n.projectId)!.name } } };
    });
  } else if (model === "note") {
    if (include.goalLinks) {
      out.goalLinks = db.goalIdea
        .filter((l) => l.noteId === row.id)
        .map((l) => {
          const g = byId("goal", l.goalId)!;
          return { goal: { id: g.id, title: g.title, contourId: g.contourId } };
        });
    }
  } else {
    throw new Error(`fake: include on ${model}`);
  }
  return out;
}

function unique(model: ModelName, where: Row): Row | undefined {
  return db[model].find((r) => matches(model, r, where));
}

/** What Prisma writes for a value: `Prisma.DbNull` is SQL NULL. */
function stored(data: Row): Row {
  const out: Row = {};
  for (const [key, value] of Object.entries(data)) {
    if (value === undefined) continue;
    out[key] = value === Prisma.DbNull ? null : value;
  }
  return out;
}

function cascadeDelete(model: ModelName, row: Row): void {
  if (model === "goal") {
    db.goalTask = db.goalTask.filter((l) => l.goalId !== row.id);
    db.goalIdea = db.goalIdea.filter((l) => l.goalId !== row.id);
  } else if (model === "note") {
    db.goalIdea = db.goalIdea.filter((l) => l.noteId !== row.id);
  } else if (model === "contour") {
    if (db.goal.some((g) => g.contourId === row.id)) {
      throw new Error("fake: goals_contourId_fkey (Restrict)");
    }
    for (const t of db.task) if (t.focusContourId === row.id) t.focusContourId = null;
    for (const u of db.user) if (u.activeContourId === row.id) u.activeContourId = null;
  }
}

function wireFakes(): void {
  for (const model of Object.keys(COLUMNS) as ModelName[]) {
    const m = prismaMock[model];
    for (const fn of Object.values(m)) fn.mockReset();
    m.findFirst.mockImplementation(async (args: Row = {}) => {
      const row = sortRows(model, db[model].filter((r) => matches(model, r, args.where)), args.orderBy)[0];
      return row === undefined ? null : shape(model, row, args);
    });
    m.findMany.mockImplementation(async (args: Row = {}) =>
      sortRows(model, db[model].filter((r) => matches(model, r, args.where)), args.orderBy).map((r) =>
        shape(model, r, args),
      ),
    );
    m.findUnique.mockImplementation(async (args: Row) => {
      const row = unique(model, args.where);
      return row === undefined ? null : shape(model, row, args);
    });
    m.findUniqueOrThrow.mockImplementation(async (args: Row) => {
      const row = unique(model, args.where);
      if (row === undefined) throw new Error(`fake ${model}: findUniqueOrThrow found nothing`);
      return shape(model, row, args);
    });
    m.create.mockImplementation(async (args: Row) => {
      const data = stored(args.data);
      if (model === "goalTask" && unique(model, { goalId: data.goalId, taskId: data.taskId })) {
        throw Object.assign(new Error("Unique constraint failed"), { code: "P2002" });
      }
      if (model === "goalIdea" && unique(model, { goalId: data.goalId, noteId: data.noteId })) {
        throw Object.assign(new Error("Unique constraint failed"), { code: "P2002" });
      }
      const row: Row = { ...COLUMNS[model], id: `${model}-${++seq}`, createdAt: new Date(), ...data };
      if ("updatedAt" in COLUMNS[model]) row.updatedAt = new Date();
      if ("at" in COLUMNS[model] && row.at === null) row.at = new Date();
      if (!("id" in COLUMNS[model])) delete row.id;
      db[model].push(row);
      return shape(model, row, args);
    });
    m.update.mockImplementation(async (args: Row) => {
      const row = unique(model, args.where);
      if (row === undefined) throw new Error(`fake ${model}: update against no row`);
      Object.assign(row, stored(args.data));
      if ("updatedAt" in COLUMNS[model]) row.updatedAt = new Date();
      return shape(model, row, args);
    });
    m.updateMany.mockImplementation(async (args: Row) => {
      const rows = db[model].filter((r) => matches(model, r, args.where));
      for (const row of rows) Object.assign(row, stored(args.data));
      return { count: rows.length };
    });
    m.delete.mockImplementation(async (args: Row) => {
      const row = unique(model, args.where);
      if (row === undefined) throw new Error(`fake ${model}: delete against no row`);
      cascadeDelete(model, row);
      db[model] = db[model].filter((r) => r !== row);
      return row;
    });
    m.deleteMany.mockImplementation(async (args: Row) => {
      const rows = db[model].filter((r) => matches(model, r, args.where));
      for (const row of rows) cascadeDelete(model, row);
      db[model] = db[model].filter((r) => !rows.includes(r));
      return { count: rows.length };
    });
    m.count.mockImplementation(
      async (args: Row = {}) => db[model].filter((r) => matches(model, r, args.where)).length,
    );
    m.aggregate.mockImplementation(async (args: Row) => {
      const positions = db[model].filter((r) => matches(model, r, args.where)).map((r) => r.position);
      return { _max: { position: positions.length > 0 ? Math.max(...positions) : null } };
    });
  }

  prismaMock.$transaction.mockReset();
  prismaMock.$transaction.mockImplementation(async (run: unknown) => {
    if (typeof run !== "function") throw new Error("fake: array transactions are not used here");
    const snapshot = Object.fromEntries(
      Object.entries(db).map(([model, rows]) => [model, rows.map((r) => ({ ...r }))]),
    ) as typeof db;
    try {
      return await (run as (tx: unknown) => Promise<unknown>)(prismaMock);
    } catch (error) {
      db = snapshot;
      throw error;
    }
  });
}
/* eslint-enable @typescript-eslint/no-explicit-any */

function seed(): void {
  seq = 0;
  const T0 = new Date("2026-11-01T10:00:00.000Z");
  const task = (row: Row): Row => ({ ...COLUMNS.task, createdAt: T0, updatedAt: T0, ...row });
  db = {
    user: [
      { id: USER_A.id, activeContourId: null, activeContourUntil: null },
      { id: USER_B.id, activeContourId: null, activeContourUntil: null },
    ],
    scope: [
      { id: "s-a", userId: USER_A.id, name: "Жизнь", position: 1000 },
      { id: "s-b", userId: USER_B.id, name: "Чужое", position: 1000 },
    ],
    project: [
      { id: "p-home", name: "Дом", scopeId: "s-a", archivedAt: null },
      { id: "p-work", name: "Работа", scopeId: "s-a", archivedAt: null },
      { id: "p-b", name: "B secret", scopeId: "s-b", archivedAt: null },
    ],
    task: [
      task({ id: "t-1", projectId: "p-home", title: "Позвонить газовщику", position: 1000 }),
      task({ id: "t-2", projectId: "p-work", title: "Справка с работы", position: 1000 }),
      task({ id: "t-3", projectId: "p-home", title: "Замерить", position: 2000, status: "done" }),
      task({ id: "t-4", projectId: "p-home", title: "Ждать мастера", position: 3000, status: "blocked" }),
      task({ id: "t-b", projectId: "p-b", title: "B private", position: 1000 }),
    ],
    note: [
      {
        ...COLUMNS.note,
        id: "n-1",
        projectId: "p-home",
        title: "Купить котёл",
        content: "газовый, двухконтурный",
        createdAt: T0,
        updatedAt: T0,
      },
      { ...COLUMNS.note, id: "n-b", projectId: "p-b", title: "B idea", createdAt: T0, updatedAt: T0 },
    ],
    contour: [
      { ...COLUMNS.contour, id: "c-main", userId: USER_A.id, name: "Работа", position: 1000, createdAt: T0, updatedAt: T0 },
      {
        ...COLUMNS.contour,
        id: "c-home",
        userId: USER_A.id,
        name: "Личное",
        slots: 1,
        windowDays: 3,
        position: 2000,
        createdAt: T0,
        updatedAt: T0,
      },
      { ...COLUMNS.contour, id: "c-b", userId: USER_B.id, name: "Чужой", position: 1000, createdAt: T0, updatedAt: T0 },
    ],
    goal: [],
    goalTask: [],
    goalIdea: [],
    taskEvent: [],
    taskCategory: [],
  };
}

// ---- helpers ----

let app: FastifyInstance;
let token: string;
let tokenB: string;

function call(method: string, url: string, payload?: unknown, bearer?: string) {
  return app.inject({
    method: method as "POST",
    url,
    headers: { authorization: `Bearer ${bearer ?? token}` },
    ...(payload === undefined ? {} : { payload: payload as Record<string, unknown> }),
  });
}

interface GoalBody {
  id: string;
  contourId: string;
  state: string;
  windowDays: number;
  windowEndsAt: string | null;
  windowExpired: boolean;
  achievedAt: string | null;
  tasks: { id: string; status: string; projectName: string }[];
  nextStep: { id: string } | null;
  ideas: { id: string; projectName: string }[];
  progress: { done: number; total: number };
}

async function createGoal(body: Record<string, unknown>, bearer?: string): Promise<GoalBody> {
  const res = await call("POST", "/goals", body, bearer);
  expect(res.statusCode).toBe(201);
  return res.json() as GoalBody;
}

beforeAll(async () => {
  const { buildApp } = await import("../src/app");
  app = await buildApp({ authConfig: config, users: inMemoryUsers(), logger: false, dictation: null });
  await app.ready();
  token = await tokenFor(app, USER_A.email);
  tokenB = await tokenFor(app, USER_B.email);
});

afterAll(async () => {
  await app?.close();
});

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(NOW);
  seed();
  wireFakes();
});

afterEach(() => {
  vi.useRealTimers();
});

// ---- the rules without a database ----

describe("goal rules", () => {
  const row = (over: Partial<GoalRow> = {}): GoalRow =>
    ({
      id: "g",
      userId: "u",
      contourId: "c",
      title: "Цель",
      why: null,
      slottedAt: null,
      windowDays: null,
      windowEndsAt: null,
      achievedAt: null,
      position: 1000,
      createdAt: NOW,
      updatedAt: NOW,
      contour: { windowDays: 7 },
      tasks: [],
      ideas: [],
      ...over,
    }) as GoalRow;

  it("derives the state, achieved first", () => {
    expect(goalState({ slottedAt: null, achievedAt: null })).toBe("bench");
    expect(goalState({ slottedAt: NOW, achievedAt: null })).toBe("slot");
    expect(goalState({ slottedAt: NOW, achievedAt: NOW })).toBe("achieved");
  });

  it("takes the first pending task as the next step, past done and blocked ones", () => {
    expect(
      nextStepOf([
        { id: "a", status: "done" as const },
        { id: "b", status: "blocked" as const },
        { id: "c", status: "pending" as const },
        { id: "d", status: "pending" as const },
      ])?.id,
    ).toBe("c");
    expect(nextStepOf([{ id: "b", status: "blocked" as const }])).toBeNull();
    expect(nextStepOf([])).toBeNull();
  });

  it("extends from the end while the window runs, from now once it ran out", () => {
    const end = new Date(NOW.getTime() + 2 * DAY);
    expect(extendedWindowEnd(NOW, end, 7).getTime()).toBe(end.getTime() + 7 * DAY);
    const past = new Date(NOW.getTime() - 10 * DAY);
    expect(extendedWindowEnd(NOW, past, 7).getTime()).toBe(NOW.getTime() + 7 * DAY);
    expect(windowEnd(NOW, 3).getTime()).toBe(NOW.getTime() + 3 * DAY);
  });

  it("calls a slotted goal's window expired at its end, and only in a slot", () => {
    const ended = new Date(NOW.getTime() - 1);
    expect(goalView(row({ slottedAt: NOW, windowEndsAt: ended }), NOW).windowExpired).toBe(true);
    expect(goalView(row({ slottedAt: NOW, windowEndsAt: NOW }), NOW).windowExpired).toBe(true);
    expect(
      goalView(row({ slottedAt: NOW, windowEndsAt: new Date(NOW.getTime() + 1) }), NOW).windowExpired,
    ).toBe(false);
    expect(goalView(row({ windowEndsAt: ended }), NOW).windowExpired).toBe(false);
  });

  it("shows the window that applies: the goal's own, else the contour's", () => {
    expect(goalView(row(), NOW).windowDays).toBe(7);
    expect(goalView(row({ windowDays: 14 }), NOW).windowDays).toBe(14);
  });
});

// ---- contours ----

describe("contours", () => {
  it("lists the user's own contours in order, with the manual choice as stored", async () => {
    const res = await call("GET", "/contours");
    expect(res.statusCode).toBe(200);
    const body = res.json() as { contours: { id: string }[]; active: unknown };
    expect(body.contours.map((c) => c.id)).toEqual(["c-main", "c-home"]);
    expect(body.active).toEqual({ contourId: null, until: null });
  });

  it("gives a user with no contour «Основной» rather than an empty list", async () => {
    db.contour = db.contour.filter((c) => c.userId !== USER_A.id);
    const body = (await call("GET", "/contours")).json() as {
      contours: { name: string; slots: number; windowDays: number }[];
    };
    expect(body.contours).toEqual([
      expect.objectContaining({ name: "Основной", slots: 2, windowDays: 7 }),
    ]);
  });

  it("creates one at the end, with defaults, and validates the schedule", async () => {
    const res = await call("POST", "/contours", {
      name: "Дача",
      schedule: { days: [7, 6, 6], from: "10:00", to: "18:00" },
    });
    expect(res.statusCode).toBe(201);
    const body = res.json() as { position: number; slots: number; windowDays: number; schedule: unknown };
    expect(body.position).toBeGreaterThan(2000);
    expect(body).toMatchObject({ slots: 2, windowDays: 7, schedule: { days: [6, 7] } });

    for (const bad of [
      { name: "X", slots: 6 },
      { name: "X", windowDays: 91 },
      { name: "X", schedule: { days: [1], from: "18:00", to: "09:00" } },
      { name: "X", schedule: { days: [], from: "09:00", to: "18:00" } },
      { name: "" },
    ]) {
      expect((await call("POST", "/contours", bad)).statusCode).toBe(400);
    }
  });

  it("edits one of the user's own, clears a schedule with null, and 404s someone else's", async () => {
    await call("PATCH", "/contours/c-home", { schedule: { days: [1], from: "09:00", to: "18:00" } });
    const res = await call("PATCH", "/contours/c-home", { name: "Дом", slots: 3, schedule: null });
    expect(res.statusCode).toBe(200);
    expect(db.contour.find((c) => c.id === "c-home")).toMatchObject({ name: "Дом", slots: 3, schedule: null });
    expect((await call("PATCH", "/contours/c-b", { name: "Моё" })).statusCode).toBe(404);
  });

  it("refuses to delete the last contour and one with goals (achieved too)", async () => {
    const goal = await createGoal({ contourId: "c-home", title: "Котёл" });
    await call("POST", `/goals/${goal.id}/achieve`);
    expect((await call("DELETE", "/contours/c-home")).statusCode).toBe(409);
    expect((await call("DELETE", "/contours/c-b", undefined, tokenB)).statusCode).toBe(409);
    expect(db.contour).toHaveLength(3);
  });

  it("deletes an empty one, moving its working set to the default contour", async () => {
    db.task.find((t) => t.id === "t-1")!.focusedAt = NOW;
    db.task.find((t) => t.id === "t-1")!.focusContourId = "c-home";
    db.user.find((u) => u.id === USER_A.id)!.activeContourId = "c-home";

    expect((await call("DELETE", "/contours/c-home")).statusCode).toBe(204);

    expect(db.contour.map((c) => c.id)).toEqual(["c-main", "c-b"]);
    expect(db.task.find((t) => t.id === "t-1")!.focusContourId).toBe("c-main");
    expect(db.user.find((u) => u.id === USER_A.id)!.activeContourId).toBeNull();
    expect((await call("DELETE", "/contours/c-b")).statusCode).toBe(404);
  });

  it("stores the manual choice for the other devices, and refuses someone else's contour", async () => {
    const until = "2026-11-24T18:00:00.000Z";
    const res = await call("PUT", "/contours/active", { contourId: "c-home", until });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ contourId: "c-home", until });
    const listed = (await call("GET", "/contours")).json() as { active: unknown };
    expect(listed.active).toEqual({ contourId: "c-home", until });

    const cleared = await call("PUT", "/contours/active", { contourId: null, until });
    expect(cleared.json()).toEqual({ contourId: null, until: null });

    expect((await call("PUT", "/contours/active", { contourId: "c-b", until: null })).statusCode).toBe(400);
  });
});

// ---- goals ----

describe("goals", () => {
  it("creates a goal on the bench, last in its contour", async () => {
    const first = await createGoal({ contourId: "c-main", title: "Отопление", why: "  зима  " });
    const second = await createGoal({ contourId: "c-main", title: "Отчёт", why: "" });
    expect(first).toMatchObject({ state: "bench", windowEndsAt: null, windowDays: 7, progress: { done: 0, total: 0 } });
    expect(db.goal.find((g) => g.id === first.id)!.why).toBe("зима");
    expect(db.goal.find((g) => g.id === second.id)!.why).toBeNull();
    expect(db.goal.find((g) => g.id === second.id)!.position).toBeGreaterThan(
      db.goal.find((g) => g.id === first.id)!.position,
    );
  });

  it("refuses a contour that is not the user's", async () => {
    expect((await call("POST", "/goals", { contourId: "c-b", title: "Чужое" })).statusCode).toBe(400);
    expect(db.goal).toHaveLength(0);
  });

  it("puts a new goal straight into a slot with a window, and answers slots_full when taken", async () => {
    const slotted = await createGoal({ contourId: "c-home", title: "Котёл", slot: true });
    expect(slotted.state).toBe("slot");
    // c-home: one slot, a 3-day window.
    expect(slotted.windowEndsAt).toBe(new Date(NOW.getTime() + 3 * DAY).toISOString());

    const res = await call("POST", "/goals", { contourId: "c-home", title: "Ещё", slot: true });
    expect(res.statusCode).toBe(409);
    expect(res.json()).toMatchObject({ error: "slots_full", details: { slots: 1 } });
    // Refused whole: nothing half-made.
    expect(db.goal).toHaveLength(1);
  });

  it("slots a benched goal only while a slot is free, and keeps the window on a repeat", async () => {
    const a = await createGoal({ contourId: "c-home", title: "A" });
    const b = await createGoal({ contourId: "c-home", title: "B" });
    const slotted = (await call("POST", `/goals/${a.id}/slot`, { windowDays: 10 })).json() as GoalBody;
    expect(slotted).toMatchObject({ state: "slot", windowDays: 10 });
    expect(slotted.windowEndsAt).toBe(new Date(NOW.getTime() + 10 * DAY).toISOString());

    const full = await call("POST", `/goals/${b.id}/slot`);
    expect(full.statusCode).toBe(409);
    expect((full.json() as { error: string }).error).toBe("slots_full");

    vi.setSystemTime(new Date(NOW.getTime() + DAY));
    const again = (await call("POST", `/goals/${a.id}/slot`)).json() as GoalBody;
    expect(again.windowEndsAt).toBe(slotted.windowEndsAt);

    await call("POST", `/goals/${a.id}/bench`);
    expect((await call("POST", `/goals/${b.id}/slot`)).statusCode).toBe(200);
  });

  it("extends from the window's end, and only a goal in a slot", async () => {
    const goal = await createGoal({ contourId: "c-main", title: "A", slot: true });
    const extended = (await call("POST", `/goals/${goal.id}/extend`)).json() as GoalBody;
    expect(extended.windowEndsAt).toBe(new Date(NOW.getTime() + 14 * DAY).toISOString());

    // Ran out six days ago: one window from now, and no longer "expired".
    vi.setSystemTime(new Date(NOW.getTime() + 20 * DAY));
    const expired = (await call("GET", `/goals/${goal.id}`)).json() as GoalBody;
    expect(expired.windowExpired).toBe(true);
    const renewed = (await call("POST", `/goals/${goal.id}/extend`)).json() as GoalBody;
    expect(renewed.windowEndsAt).toBe(new Date(NOW.getTime() + 27 * DAY).toISOString());
    expect(renewed.windowExpired).toBe(false);

    await call("POST", `/goals/${goal.id}/bench`);
    expect((await call("POST", `/goals/${goal.id}/extend`)).statusCode).toBe(409);
  });

  it("achieves by hand, leaves the slot, keeps the first date; reopens onto the bench", async () => {
    const goal = await createGoal({ contourId: "c-home", title: "A", slot: true });
    const done = (await call("POST", `/goals/${goal.id}/achieve`)).json() as GoalBody;
    expect(done).toMatchObject({ state: "achieved", windowEndsAt: null, achievedAt: NOW.toISOString() });
    vi.setSystemTime(new Date(NOW.getTime() + DAY));
    expect(((await call("POST", `/goals/${goal.id}/achieve`)).json() as GoalBody).achievedAt).toBe(
      NOW.toISOString(),
    );
    // The slot is free again.
    await createGoal({ contourId: "c-home", title: "B", slot: true });
    // Achieved goals are not slotted by a stray button.
    expect((await call("POST", `/goals/${goal.id}/slot`)).statusCode).toBe(409);

    const reopened = (await call("POST", `/goals/${goal.id}/reopen`)).json() as GoalBody;
    expect(reopened).toMatchObject({ state: "bench", achievedAt: null });
  });

  it("lists slots and bench by default, achieved on request, ordered by contour then position", async () => {
    const home = await createGoal({ contourId: "c-home", title: "Дом" });
    const work2 = await createGoal({ contourId: "c-main", title: "Работа 2" });
    const work1 = await createGoal({ contourId: "c-main", title: "Работа 1", slot: true });
    await call("PATCH", `/goals/${work1.id}`, { position: 1 });
    const old = await createGoal({ contourId: "c-main", title: "Старое" });
    await call("POST", `/goals/${old.id}/achieve`);
    await createGoal({ contourId: "c-b", title: "Чужая" }, tokenB);

    const listed = (await call("GET", "/goals")).json() as GoalBody[];
    expect(listed.map((g) => g.id)).toEqual([work1.id, work2.id, home.id]);
    const achieved = (await call("GET", "/goals?state=achieved")).json() as GoalBody[];
    expect(achieved.map((g) => g.id)).toEqual([old.id]);
    const slots = (await call("GET", "/goals?state=slot&contourId=c-main")).json() as GoalBody[];
    expect(slots.map((g) => g.id)).toEqual([work1.id]);
    expect((await call("GET", "/goals?state=done")).statusCode).toBe(400);
  });

  it("404s someone else's goal on every route", async () => {
    const theirs = await createGoal({ contourId: "c-b", title: "Чужая" }, tokenB);
    for (const [method, url] of [
      ["GET", `/goals/${theirs.id}`],
      ["PATCH", `/goals/${theirs.id}`],
      ["POST", `/goals/${theirs.id}/slot`],
      ["POST", `/goals/${theirs.id}/achieve`],
      ["DELETE", `/goals/${theirs.id}`],
      ["PUT", `/goals/${theirs.id}/tasks/t-1`],
      ["PUT", `/goals/${theirs.id}/ideas/n-1`],
    ] as const) {
      const res = await call(method, url, method === "PATCH" ? { title: "x" } : undefined);
      expect(res.statusCode, `${method} ${url}`).toBe(404);
    }
    expect(db.goal.find((g) => g.id === theirs.id)!.achievedAt).toBeNull();
  });

  it("moves to another contour: keeps the state, needs a free slot there, goes last", async () => {
    const homeGoal = await createGoal({ contourId: "c-home", title: "Дом", slot: true });
    await createGoal({ contourId: "c-main", title: "W1", slot: true });
    await createGoal({ contourId: "c-main", title: "W2", slot: true });

    const blocked = await call("PATCH", `/goals/${homeGoal.id}`, { contourId: "c-main" });
    expect(blocked.statusCode).toBe(409);
    expect(db.goal.find((g) => g.id === homeGoal.id)!.contourId).toBe("c-home");

    await call("POST", `/goals/${homeGoal.id}/bench`);
    const moved = (await call("PATCH", `/goals/${homeGoal.id}`, { contourId: "c-main", windowDays: null })).json() as GoalBody;
    expect(moved).toMatchObject({ contourId: "c-main", state: "bench", windowDays: 7 });
    expect(db.goal.find((g) => g.id === homeGoal.id)!.position).toBe(3000);
    expect((await call("PATCH", `/goals/${homeGoal.id}`, { contourId: "c-b" })).statusCode).toBe(400);
  });

  it("deletes a goal and its links, never the tasks or ideas", async () => {
    const goal = await createGoal({ contourId: "c-main", title: "A" });
    await call("PUT", `/goals/${goal.id}/tasks/t-1`);
    await call("PUT", `/goals/${goal.id}/ideas/n-1`);
    expect((await call("DELETE", `/goals/${goal.id}`)).statusCode).toBe(204);
    expect(db.goal).toHaveLength(0);
    expect(db.goalTask).toHaveLength(0);
    expect(db.goalIdea).toHaveLength(0);
    expect(db.task.some((t) => t.id === "t-1")).toBe(true);
    expect(db.note.some((n) => n.id === "n-1")).toBe(true);
  });
});

// ---- tasks and ideas in a goal ----

describe("a goal's tasks and ideas", () => {
  it("links tasks from any own project, idempotently, and refuses someone else's task", async () => {
    const goal = await createGoal({ contourId: "c-main", title: "Котёл" });
    await call("PUT", `/goals/${goal.id}/tasks/t-1`);
    await call("PUT", `/goals/${goal.id}/tasks/t-2`);
    const again = (await call("PUT", `/goals/${goal.id}/tasks/t-1`)).json() as GoalBody;
    expect(again.tasks.map((t) => [t.id, t.projectName])).toEqual([
      ["t-1", "Дом"],
      ["t-2", "Работа"],
    ]);
    expect((await call("PUT", `/goals/${goal.id}/tasks/t-b`)).statusCode).toBe(404);
    expect(db.goalTask).toHaveLength(2);
  });

  it("takes the first pending task as the next step, in the goal's order", async () => {
    const goal = await createGoal({ contourId: "c-main", title: "Котёл" });
    for (const id of ["t-3", "t-4", "t-1", "t-2"]) await call("PUT", `/goals/${goal.id}/tasks/${id}`);
    let view = (await call("GET", `/goals/${goal.id}`)).json() as GoalBody;
    // t-3 is done, t-4 blocked: the step is t-1.
    expect(view.nextStep?.id).toBe("t-1");
    expect(view.progress).toEqual({ done: 1, total: 4 });

    // Put t-2 first: it becomes the step.
    const moved = await call("POST", `/goals/${goal.id}/tasks/t-2/move`, { beforeTaskId: null, afterTaskId: "t-3" });
    expect(moved.statusCode).toBe(200);
    view = moved.json() as GoalBody;
    expect(view.tasks.map((t) => t.id)).toEqual(["t-2", "t-3", "t-4", "t-1"]);
    expect(view.nextStep?.id).toBe("t-2");

    // Between two neighbours.
    view = (await call("POST", `/goals/${goal.id}/tasks/t-1/move`, { beforeTaskId: "t-2", afterTaskId: "t-3" })).json() as GoalBody;
    expect(view.tasks.map((t) => t.id)).toEqual(["t-2", "t-1", "t-3", "t-4"]);

    // Nothing pending left: no step.
    await call("DELETE", `/goals/${goal.id}/tasks/t-1`);
    view = (await call("DELETE", `/goals/${goal.id}/tasks/t-2`)).json() as GoalBody;
    expect(view.nextStep).toBeNull();
    expect(view.tasks.map((t) => t.id)).toEqual(["t-3", "t-4"]);
  });

  it("refuses a move against a task that is not in the goal", async () => {
    const goal = await createGoal({ contourId: "c-main", title: "Котёл" });
    await call("PUT", `/goals/${goal.id}/tasks/t-1`);
    expect((await call("POST", `/goals/${goal.id}/tasks/t-1/move`, { afterTaskId: "t-2" })).statusCode).toBe(400);
    expect((await call("POST", `/goals/${goal.id}/tasks/t-2/move`, { afterTaskId: "t-1" })).statusCode).toBe(404);
    expect((await call("POST", `/goals/${goal.id}/tasks/t-1/move`, { afterTaskId: "t-1" })).statusCode).toBe(400);
  });

  it("keeps own ideas next to a goal, and refuses someone else's", async () => {
    const goal = await createGoal({ contourId: "c-main", title: "Котёл" });
    await call("PUT", `/goals/${goal.id}/ideas/n-1`);
    const view = (await call("PUT", `/goals/${goal.id}/ideas/n-1`)).json() as GoalBody;
    expect(view.ideas).toEqual([{ id: "n-1", title: "Купить котёл", projectId: "p-home", projectName: "Дом" }]);
    expect((await call("PUT", `/goals/${goal.id}/ideas/n-b`)).statusCode).toBe(404);
    const removed = (await call("DELETE", `/goals/${goal.id}/ideas/n-1`)).json() as GoalBody;
    expect(removed.ideas).toEqual([]);
  });

  it("shows a task's goals (the crown) everywhere, achieved ones left out", async () => {
    const a = await createGoal({ contourId: "c-main", title: "Котёл" });
    const b = await createGoal({ contourId: "c-home", title: "Дача" });
    await call("PUT", `/goals/${a.id}/tasks/t-1`);
    await call("PUT", `/goals/${b.id}/tasks/t-1`);
    await call("POST", "/tasks/t-1/focus", { contourId: "c-home" });

    const shown = (await call("GET", "/tasks/t-1")).json() as {
      goals: unknown[];
      focusContourId: string;
    };
    expect(shown.goals).toEqual([
      { id: a.id, title: "Котёл", contourId: "c-main" },
      { id: b.id, title: "Дача", contourId: "c-home" },
    ]);
    expect(shown.focusContourId).toBe("c-home");

    await call("POST", `/goals/${b.id}/achieve`);
    const after = (await call("GET", "/tasks/t-1")).json() as { goals: { id: string }[] };
    expect(after.goals.map((g) => g.id)).toEqual([a.id]);
    expect((await call("GET", "/tasks/t-b")).statusCode).toBe(404);
  });
});

// ---- idea -> task ----

describe("POST /notes/:id/to-task", () => {
  it("makes the idea a task at the end of its project, carrying its goals, and removes the idea", async () => {
    const a = await createGoal({ contourId: "c-main", title: "Котёл" });
    const b = await createGoal({ contourId: "c-home", title: "Дача" });
    await call("PUT", `/goals/${a.id}/tasks/t-2`);
    await call("PUT", `/goals/${a.id}/ideas/n-1`);
    await call("PUT", `/goals/${b.id}/ideas/n-1`);

    const res = await call("POST", "/notes/n-1/to-task");

    expect(res.statusCode).toBe(201);
    const task = res.json() as {
      id: string;
      projectId: string;
      title: string;
      description: string;
      status: string;
      position: number;
      goals: { id: string }[];
    };
    expect(task).toMatchObject({
      projectId: "p-home",
      title: "Купить котёл",
      description: "газовый, двухконтурный",
      status: "pending",
      position: 4000,
    });
    expect(task.goals.map((g) => g.id)).toEqual([a.id, b.id]);
    expect(db.note.some((n) => n.id === "n-1")).toBe(false);
    expect(db.goalIdea).toHaveLength(0);
    expect(db.taskEvent).toEqual([expect.objectContaining({ taskId: task.id, kind: "created", toStatus: "pending" })]);
    // At the end of the goal it was kept next to.
    const view = (await call("GET", `/goals/${a.id}`)).json() as GoalBody;
    expect(view.tasks.map((t) => t.id)).toEqual(["t-2", task.id]);
    expect(view.ideas).toEqual([]);
  });

  it("gives an idea with no text a task with no description", async () => {
    db.note.find((n) => n.id === "n-1")!.content = "  ";
    const task = (await call("POST", "/notes/n-1/to-task")).json() as { description: unknown; goals: unknown[] };
    expect(task.description).toBeNull();
    expect(task.goals).toEqual([]);
  });

  it("404s someone else's idea and changes nothing", async () => {
    expect((await call("POST", "/notes/n-b/to-task")).statusCode).toBe(404);
    expect(db.note).toHaveLength(2);
    expect(db.task).toHaveLength(5);
  });
});

// ---- MCP ----

describe("MCP goal tools", () => {
  let client: Client;

  /** The real tool set, as user A, writing through the app's own routes. */
  async function connect(bearer: string, userId: string): Promise<Client> {
    const { createTaskRadarMcpServer } = await import("../src/mcp/taskradarMcp");
    const server = createTaskRadarMcpServer({
      userId,
      async callApi(method, url, payload) {
        const res = await call(method, url, payload, bearer);
        return { status: res.statusCode, body: res.body === "" ? null : res.json() };
      },
      async fetchBytes() {
        return { status: 404, body: Buffer.alloc(0) };
      },
    });
    const [clientSide, serverSide] = InMemoryTransport.createLinkedPair();
    const c = new Client({ name: "test", version: "0" });
    await Promise.all([server.connect(serverSide), c.connect(clientSide)]);
    return c;
  }

  async function tool<T = Record<string, unknown>>(name: string, args: Record<string, unknown> = {}): Promise<T> {
    const result = (await client.callTool({ name, arguments: args })) as {
      isError?: boolean;
      content: { text: string }[];
    };
    if (result.isError) throw new Error(`tool error: ${result.content[0]?.text}`);
    return JSON.parse(result.content[0]!.text) as T;
  }

  async function toolError(name: string, args: Record<string, unknown>): Promise<string> {
    const result = (await client.callTool({ name, arguments: args })) as {
      isError?: boolean;
      content: { text: string }[];
    };
    expect(result.isError).toBe(true);
    return result.content[0]!.text;
  }

  beforeEach(async () => {
    client = await connect(token, USER_A.id);
  });

  afterEach(async () => {
    await client.close();
  });

  it("lists contours with slots in use and the manual choice", async () => {
    await createGoal({ contourId: "c-home", title: "Котёл", slot: true });
    db.user.find((u) => u.id === USER_A.id)!.activeContourId = "c-home";
    const out = await tool<{ contours: Record<string, unknown>[]; manualActive: unknown }>("list_contours");
    expect(out.contours).toEqual([
      { id: "c-main", name: "Работа", slots: 2, slotsUsed: 0, windowDays: 7 },
      { id: "c-home", name: "Личное", slots: 1, slotsUsed: 1, windowDays: 3 },
    ]);
    expect(out.manualActive).toEqual({ contourId: "c-home", until: null });
  });

  it("creates a goal in the default contour, slots it, and reports slots_full by name", async () => {
    const created = await tool("create_goal", { title: "Отчёт", why: "дедлайн" });
    expect(created).toMatchObject({ contourId: "c-main", state: "bench", why: "дедлайн", nextStep: null });

    const slotted = await tool("update_goal", { goalId: created.id, title: "Сдать отчёт", action: "slot" });
    expect(slotted).toMatchObject({ title: "Сдать отчёт", state: "slot" });

    await tool("create_goal", { title: "Второй", contourId: "c-main", slot: true });
    const third = await tool("create_goal", { title: "Третий" });
    expect(await toolError("update_goal", { goalId: third.id, action: "slot" })).toMatch(/^409 slots_full: /);
    expect(await toolError("create_goal", { title: "Чужой", contourId: "c-b" })).toMatch(/^400/);
  });

  it("links and unlinks tasks, and get_goal / list_goals show the next step", async () => {
    const goal = await tool("create_goal", { title: "Котёл", slot: true });
    await tool("link_goal_task", { goalId: goal.id, taskId: "t-3" });
    const linked = await tool<{ tasks: { id: string }[]; nextStep: unknown; progress: unknown }>(
      "link_goal_task",
      { goalId: goal.id, taskId: "t-1" },
    );
    expect(linked.tasks.map((t) => t.id)).toEqual(["t-3", "t-1"]);
    expect(linked.nextStep).toEqual({ id: "t-1", title: "Позвонить газовщику", project: "Дом" });
    expect(linked.progress).toEqual({ done: 1, total: 2 });

    const listed = await tool<{ goals: Record<string, unknown>[] }>("list_goals", { state: ["slot"] });
    expect(listed.goals).toHaveLength(1);
    expect(listed.goals[0]).not.toHaveProperty("tasks");
    expect(listed.goals[0]).toMatchObject({ nextStep: { id: "t-1" } });

    const unlinked = await tool<{ tasks: unknown[] }>("unlink_goal_task", { goalId: goal.id, taskId: "t-1" });
    expect(unlinked.tasks).toHaveLength(1);
    expect(await toolError("link_goal_task", { goalId: goal.id, taskId: "t-b" })).toMatch(/^404/);
    expect(await toolError("get_goal", { goalId: "nope" })).toBe("Goal not found");
  });

  it("achieves and reopens through update_goal; list_goals filters by state", async () => {
    const goal = await tool("create_goal", { title: "Котёл" });
    await tool("update_goal", { goalId: goal.id, action: "achieve" });
    expect((await tool<{ goals: unknown[] }>("list_goals")).goals).toHaveLength(0);
    const achieved = await tool<{ goals: { state: string }[] }>("list_goals", { state: ["achieved"] });
    expect(achieved.goals.map((g) => g.state)).toEqual(["achieved"]);
    const reopened = await tool("update_goal", { goalId: goal.id, action: "reopen" });
    expect(reopened.state).toBe("bench");
  });

  it("shows a task's goals in get_task, and list_ideas is list_notes with goals", async () => {
    const goal = await tool("create_goal", { title: "Котёл" });
    await tool("link_goal_task", { goalId: goal.id, taskId: "t-1" });
    await call("PUT", `/goals/${goal.id as string}/ideas/n-1`);

    const task = await tool<{ goals: unknown[] }>("get_task", { taskId: "t-1", pictures: false });
    expect(task.goals).toEqual([{ id: goal.id, title: "Котёл", contourId: "c-main" }]);

    const ideas = await tool<{ id: string; goals: unknown[] }[]>("list_ideas", { projectId: "p-home" });
    expect(ideas).toEqual([expect.objectContaining({ id: "n-1", goals: [{ id: goal.id, title: "Котёл", contourId: "c-main" }] })]);
    expect(await tool("list_notes", { projectId: "p-home" })).toEqual(ideas);
    expect(await toolError("list_ideas", { projectId: "p-b" })).toBe("Project not found");
  });

  it("puts a task into a named contour's working set", async () => {
    const task = await tool("update_task", {
      taskId: "t-1",
      inWorkingSet: true,
      workingSetContourId: "c-home",
    });
    expect(task).toMatchObject({ inWorkingSet: true, workingSetContourId: "c-home" });
    expect(await toolError("update_task", { taskId: "t-1", workingSetContourId: "c-home" })).toMatch(
      /inWorkingSet: true/,
    );
  });

  it("keeps another user's goals out of reach", async () => {
    const theirs = await createGoal({ contourId: "c-b", title: "Чужая" }, tokenB);
    expect(await toolError("get_goal", { goalId: theirs.id })).toBe("Goal not found");
    expect(await toolError("update_goal", { goalId: theirs.id, action: "achieve" })).toMatch(/^404/);
    expect((await tool<{ goals: unknown[] }>("list_goals")).goals).toHaveLength(0);
  });
});
