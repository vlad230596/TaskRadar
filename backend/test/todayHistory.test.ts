import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach, vi } from "vitest";
import type { FastifyInstance } from "fastify";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import type { AuthConfig } from "../src/lib/authConfig";
import { inMemoryUsers, tokenFor, USER_A, USER_B } from "./support/users";
import { installFakeDb, type Row } from "./support/fakeDb";

/*
 * «Сегодня», История, пересмотр и ритм (design/today-history-contract.md),
 * through the routes and the MCP tools, against the in-memory database of
 * ./support/fakeDb.ts -- which evaluates every owner filter, so the second
 * user's rows in the seed are a standing check that nothing leaks.
 *
 * The clock is Friday 27.11.2026, 09:00 UTC (12:00 in Moscow, tz +180).
 */

const prismaMock = vi.hoisted(() => ({}) as Record<string, unknown>);
vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
process.env.DATABASE_URL ??= "postgresql://placeholder:placeholder@localhost:5432/placeholder";

const fake = installFakeDb(prismaMock);

const config: AuthConfig = {
  email: USER_A.email,
  passwordHash: "$2b$04$zV5VFEALedx8Rfd/ucwUSOrHYSSr8xveuActiCTdzOmCsBSDTbYXO",
  jwtSecret: "test-jwt-secret-".repeat(4),
  cookieSecure: false,
};

const NOW = new Date("2026-11-27T09:00:00.000Z");
const T0 = new Date("2026-01-01T00:00:00.000Z");
const MSK = 180;
const day = (d: string) => new Date(`${d}T00:00:00.000Z`);
const at = (iso: string) => new Date(iso);

function task(row: Row): Row {
  return { createdAt: T0, updatedAt: T0, ...row };
}

function seed(): void {
  fake.load({
    user: [
      { id: USER_A.id, createdAt: T0 },
      { id: USER_B.id, createdAt: T0 },
    ],
    scope: [
      { id: "s-work", userId: USER_A.id, name: "Работа", position: 1000 },
      { id: "s-home", userId: USER_A.id, name: "Дом", position: 2000 },
      { id: "s-b", userId: USER_B.id, name: "Чужое", position: 1000 },
    ],
    project: [
      { id: "p-work", name: "TaskRadar", scopeId: "s-work", createdAt: T0, updatedAt: T0 },
      { id: "p-home", name: "Квартира", scopeId: "s-home", createdAt: at("2026-02-01T00:00:00Z"), updatedAt: T0 },
      {
        id: "p-arch",
        name: "Старое",
        scopeId: "s-home",
        archivedAt: at("2026-10-01T00:00:00Z"),
        createdAt: T0,
        updatedAt: T0,
      },
      { id: "p-b", name: "B secret", scopeId: "s-b", createdAt: T0, updatedAt: T0 },
    ],
    contour: [
      { id: "c-main", userId: USER_A.id, name: "Работа", position: 1000, createdAt: T0, updatedAt: T0 },
      { id: "c-home", userId: USER_A.id, name: "Личное", position: 2000, createdAt: T0, updatedAt: T0 },
      { id: "c-b", userId: USER_B.id, name: "Чужой", position: 1000, createdAt: T0, updatedAt: T0 },
    ],
    task: [
      task({ id: "t-later", projectId: "p-work", title: "Продлить домен", position: 500, remindAt: day("2027-02-25") }),
      task({ id: "t-work-today", projectId: "p-work", title: "Ждать ревью", status: "blocked", position: 1000, remindAt: day("2026-11-27") }),
      task({ id: "t-tail", projectId: "p-work", title: "Ответить Пете", position: 2000, remindAt: day("2026-11-24") }),
      task({
        id: "t-done-yday",
        projectId: "p-work",
        title: "Релиз",
        status: "done",
        position: 3000,
        remindAt: day("2026-11-26"),
        doneAt: at("2026-11-26T10:00:00Z"),
      }),
      task({ id: "t-future", projectId: "p-work", title: "Собрать отзывы", position: 4000, remindAt: day("2026-11-30") }),
      task({ id: "t-home-today", projectId: "p-home", title: "Вынести мусор", position: 1000, remindAt: day("2026-11-27") }),
      task({
        id: "t-courier",
        projectId: "p-home",
        title: "Встретить курьера",
        position: 2000,
        remindAt: day("2026-11-27"),
        remindTime: "15:00",
      }),
      task({
        id: "t-done-today",
        projectId: "p-home",
        title: "Позвонить маме",
        status: "done",
        position: 3000,
        remindAt: day("2026-11-27"),
        doneAt: at("2026-11-27T07:00:00Z"),
      }),
      task({
        id: "t-last-week",
        projectId: "p-home",
        title: "Починить кран",
        status: "done",
        position: 4000,
        doneAt: at("2026-11-20T10:00:00Z"),
      }),
      task({ id: "t-arch", projectId: "p-arch", title: "Архивное", position: 1000, remindAt: day("2026-11-27") }),
      task({ id: "t-b", projectId: "p-b", title: "B private", position: 1000, remindAt: day("2026-11-27") }),
      task({
        id: "t-b-done",
        projectId: "p-b",
        title: "B done",
        status: "done",
        position: 2000,
        doneAt: at("2026-11-27T06:00:00Z"),
      }),
    ],
  });
}

let app: FastifyInstance;
let token: string;
let tokenB: string;

function call(method: string, url: string, payload?: unknown, bearer?: string) {
  return app.inject({
    method: method as "GET",
    url,
    headers: { authorization: `Bearer ${bearer ?? token}` },
    ...(payload === undefined ? {} : { payload: payload as Record<string, unknown> }),
  });
}

async function json<T = Row>(method: string, url: string, payload?: unknown, bearer?: string): Promise<T> {
  const res = await call(method, url, payload, bearer);
  if (res.statusCode >= 300) throw new Error(`${method} ${url} -> ${res.statusCode} ${res.body}`);
  return res.json() as T;
}

const ids = (list: { id: string }[]) => list.map((t) => t.id);
const events = (taskId: string) =>
  fake.tables.taskEvent!.filter((e) => e.taskId === taskId).map(({ kind, fromStatus, toStatus, contourId, revokedAt }) => ({
    kind,
    fromStatus,
    toStatus,
    contourId,
    revoked: revokedAt !== null,
  }));

beforeAll(async () => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(NOW);
  const { buildApp } = await import("../src/app");
  app = await buildApp({ authConfig: config, users: inMemoryUsers(), logger: false, dictation: null });
  await app.ready();
  token = await tokenFor(app, USER_A.email);
  tokenB = await tokenFor(app, USER_B.email);
});

afterAll(async () => {
  await app?.close();
  vi.useRealTimers();
});

beforeEach(() => {
  vi.setSystemTime(NOW);
  seed();
});

afterEach(() => {
  vi.setSystemTime(NOW);
});

// ---- settings ----

describe("/settings", () => {
  it("answers the defaults, and a PATCH of any subset", async () => {
    expect(await json("GET", "/settings")).toEqual({ laterHorizonDays: 10, reviewWeekday: 1, reviewTime: "09:00" });
    expect(await json("PATCH", "/settings", { laterHorizonDays: 3 })).toEqual({
      laterHorizonDays: 3,
      reviewWeekday: 1,
      reviewTime: "09:00",
    });
    expect(await json("PATCH", "/settings", { reviewWeekday: 7, reviewTime: "20:30" })).toMatchObject({
      laterHorizonDays: 3,
      reviewWeekday: 7,
      reviewTime: "20:30",
    });
    expect(fake.byId("user", USER_B.id)).toMatchObject({ laterHorizonDays: 10, reviewWeekday: 1 });
  });

  it("refuses values out of bounds and unknown keys", async () => {
    for (const body of [
      { laterHorizonDays: 0 },
      { laterHorizonDays: 91 },
      { reviewWeekday: 8 },
      { reviewTime: "9:00" },
      { reviewTime: "24:00" },
      { horizon: 5 },
    ]) {
      expect((await call("PATCH", "/settings", body)).statusCode).toBe(400);
    }
    expect(fake.byId("user", USER_A.id)).toMatchObject({ laterHorizonDays: 10, reviewTime: "09:00" });
  });

  it("needs a login", async () => {
    expect((await app.inject({ method: "GET", url: "/settings" })).statusCode).toBe(401);
  });
});

// ---- today ----

describe("GET /today", () => {
  it("lists today, closed today and the tail, own and non-archived only", async () => {
    const view = await json<{
      date: string;
      today: Row[];
      doneToday: Row[];
      tail: Row[];
    }>("GET", `/today?tzOffsetMinutes=${MSK}`);
    expect(view.date).toBe("2026-11-27");
    // Timed first; then the rest by scope (Работа before Дом), project, position.
    expect(ids(view.today)).toEqual(["t-courier", "t-work-today", "t-home-today"]);
    expect(ids(view.doneToday)).toEqual(["t-done-today"]);
    expect(ids(view.tail)).toEqual(["t-tail"]);
  });

  it("carries the full task with where it lives, and doneAt", async () => {
    const view = await json<{ today: Row[]; doneToday: Row[] }>("GET", "/today");
    expect(view.today[0]).toMatchObject({
      id: "t-courier",
      remindAt: "2026-11-27T00:00:00.000Z",
      remindTime: "15:00",
      projectName: "Квартира",
      scopeId: "s-home",
      scopeName: "Дом",
      goals: [],
      location: null,
      doneAt: null,
    });
    expect(view.today[0]).not.toHaveProperty("project");
    expect(view.doneToday[0]).toMatchObject({ id: "t-done-today", doneAt: "2026-11-27T07:00:00.000Z" });
  });

  it("is the owner's local day", async () => {
    // 09:00 UTC is 23:00 of the 26th at UTC-10.
    const view = await json<{ date: string; today: Row[]; doneToday: Row[]; tail: Row[] }>(
      "GET",
      "/today?tzOffsetMinutes=-600",
    );
    expect(view.date).toBe("2026-11-26");
    expect(view.today).toEqual([]);
    expect(ids(view.doneToday)).toEqual(["t-done-yday"]);
    expect(ids(view.tail)).toEqual(["t-tail"]);
  });

  it("shows B only B's day", async () => {
    const view = await json<{ today: Row[]; doneToday: Row[] }>("GET", "/today", undefined, tokenB);
    expect(ids(view.today)).toEqual(["t-b"]);
    expect(view.doneToday).toEqual([]); // t-b-done has no date
  });

  it("refuses a nonsense offset", async () => {
    expect((await call("GET", "/today?tzOffsetMinutes=9999")).statusCode).toBe(400);
  });
});

// ---- closing, revoking, reopening ----

describe("doneAt and revoked closings", () => {
  it("stamps doneAt on closing and records whose working set the task left", async () => {
    fake.byId("task", "t-tail")!.focusedAt = at("2026-11-25T10:00:00Z");
    fake.byId("task", "t-tail")!.focusContourId = "c-home";
    const closed = await json("PATCH", "/tasks/t-tail", { status: "done" });
    expect(closed).toMatchObject({ status: "done", doneAt: NOW.toISOString(), focusedAt: null, focusContourId: null });
    expect(events("t-tail")).toEqual([
      { kind: "status", fromStatus: "pending", toStatus: "done", contourId: null, revoked: false },
      { kind: "unfocused", fromStatus: null, toStatus: null, contourId: "c-home", revoked: false },
    ]);
    const stamps = fake.tables.taskEvent!.filter((e) => e.taskId === "t-tail").map((e) => e.at.getTime());
    expect(new Set(stamps).size).toBe(1);
  });

  it("takes a plain status change out of done as a revoked closing", async () => {
    await json("PATCH", "/tasks/t-tail", { status: "done" });
    vi.setSystemTime(new Date(NOW.getTime() + 60_000));
    const back = await json("PATCH", "/tasks/t-tail", { status: "blocked" });
    expect(back).toMatchObject({ status: "blocked", doneAt: null });
    expect(events("t-tail")).toEqual([
      { kind: "status", fromStatus: "pending", toStatus: "done", contourId: null, revoked: true },
      { kind: "status", fromStatus: "done", toStatus: "blocked", contourId: null, revoked: false },
    ]);
  });

  it("stamps a task created as done", async () => {
    const created = await json("POST", "/projects/p-home/tasks", { title: "Уже сделано", status: "done" });
    expect(created.doneAt).toBe(NOW.toISOString());
  });
});

describe("focus events carry the contour", () => {
  it("writes the contour on entering and on leaving the set", async () => {
    await json("POST", "/tasks/t-tail/focus", { contourId: "c-home" });
    await json("DELETE", "/tasks/t-tail/focus");
    expect(events("t-tail").map((e) => [e.kind, e.contourId])).toEqual([
      ["focused", "c-home"],
      ["unfocused", "c-home"],
    ]);
  });
});

describe("POST /tasks/:id/reopen", () => {
  it("returns a closed task to its status and its working set, and revokes the closing", async () => {
    await json("POST", "/tasks/t-work-today/focus", { contourId: "c-home" });
    await json("PATCH", "/tasks/t-work-today", { status: "done" });
    vi.setSystemTime(new Date(NOW.getTime() + 60_000));

    const reopened = await json("POST", "/tasks/t-work-today/reopen");
    expect(reopened).toMatchObject({
      id: "t-work-today",
      status: "blocked",
      doneAt: null,
      focusContourId: "c-home",
      position: 1000,
    });
    expect(reopened.focusedAt).not.toBeNull();
    expect(events("t-work-today")).toEqual([
      { kind: "focused", fromStatus: null, toStatus: null, contourId: "c-home", revoked: false },
      { kind: "status", fromStatus: "blocked", toStatus: "done", contourId: null, revoked: true },
      { kind: "unfocused", fromStatus: null, toStatus: null, contourId: "c-home", revoked: false },
      { kind: "reopened", fromStatus: "done", toStatus: "blocked", contourId: null, revoked: false },
      { kind: "focused", fromStatus: null, toStatus: null, contourId: "c-home", revoked: false },
    ]);
    // Dated today: back in «Сегодня» by itself.
    const view = await json<{ today: Row[] }>("GET", "/today");
    expect(ids(view.today)).toContain("t-work-today");
  });

  it("leaves a task that was not in a set out of every set", async () => {
    await json("PATCH", "/tasks/t-tail", { status: "done" });
    const reopened = await json("POST", "/tasks/t-tail/reopen");
    expect(reopened).toMatchObject({ status: "pending", focusedAt: null, focusContourId: null });
  });

  it("sends an exit that recorded no contour to the default contour", async () => {
    // A closing journaled before contours were recorded: the exit has none.
    fake.tables.taskEvent!.push(
      { id: "e-old-close", taskId: "t-done-yday", kind: "status", fromStatus: "pending", toStatus: "done", contourId: null, revokedAt: null, at: at("2026-11-26T10:00:00.000Z") },
      { id: "e-old-exit", taskId: "t-done-yday", kind: "unfocused", fromStatus: null, toStatus: null, contourId: null, revokedAt: null, at: at("2026-11-26T10:00:00.004Z") },
    );
    const reopened = await json("POST", "/tasks/t-done-yday/reopen");
    expect(reopened).toMatchObject({ status: "pending", focusContourId: "c-main" });
    expect(fake.byId("taskEvent", "e-old-close")!.revokedAt).toEqual(NOW);
  });

  it("reopens a task with no closing in the journal as pending", async () => {
    const reopened = await json("POST", "/tasks/t-last-week/reopen");
    expect(reopened).toMatchObject({ status: "pending", doneAt: null, focusedAt: null });
    expect(events("t-last-week")).toEqual([
      { kind: "reopened", fromStatus: "done", toStatus: "pending", contourId: null, revoked: false },
    ]);
  });

  it("is 409 not_done for a task that is not closed, 404 for someone else's", async () => {
    const res = await call("POST", "/tasks/t-tail/reopen");
    expect(res.statusCode).toBe(409);
    expect(res.json()).toMatchObject({ error: "not_done" });
    expect((await call("POST", "/tasks/t-b-done/reopen")).statusCode).toBe(404);
    expect(fake.byId("task", "t-b-done")!.status).toBe("done");
  });
});

// ---- history ----

describe("GET /history/done", () => {
  it("lists closings, freshest first, own only, archived projects included", async () => {
    fake.byId("task", "t-arch")!.status = "done";
    fake.byId("task", "t-arch")!.doneAt = at("2026-11-25T10:00:00Z");
    const page = await json<{ items: { task: Row; doneAt: string }[]; nextBefore: string | null }>(
      "GET",
      "/history/done",
    );
    expect(page.items.map((i) => i.task.id)).toEqual(["t-done-today", "t-done-yday", "t-arch", "t-last-week"]);
    expect(page.items[0]).toMatchObject({
      doneAt: "2026-11-27T07:00:00.000Z",
      task: { id: "t-done-today", projectName: "Квартира", status: "done" },
    });
    expect(page.nextBefore).toBeNull();
  });

  it("pages with before / nextBefore", async () => {
    const first = await json<{ items: { task: Row }[]; nextBefore: string | null }>("GET", "/history/done?limit=2");
    expect(first.items.map((i) => i.task.id)).toEqual(["t-done-today", "t-done-yday"]);
    expect(first.nextBefore).toBe("2026-11-26T10:00:00.000Z");
    const second = await json<{ items: { task: Row }[]; nextBefore: string | null }>(
      "GET",
      `/history/done?limit=2&before=${encodeURIComponent(first.nextBefore!)}`,
    );
    expect(second.items.map((i) => i.task.id)).toEqual(["t-last-week"]);
    expect(second.nextBefore).toBeNull();
  });

  it("drops a reopened task, and lists a re-closed one once", async () => {
    await json("POST", "/tasks/t-done-today/reopen");
    vi.setSystemTime(new Date(NOW.getTime() + 60_000));
    await json("PATCH", "/tasks/t-done-yday", { status: "pending" });
    await json("PATCH", "/tasks/t-done-yday", { status: "done" });
    const page = await json<{ items: { task: Row; doneAt: string }[] }>("GET", "/history/done");
    expect(page.items.map((i) => [i.task.id, i.doneAt])).toEqual([
      ["t-done-yday", "2026-11-27T09:01:00.000Z"],
      ["t-last-week", "2026-11-20T10:00:00.000Z"],
    ]);
  });

  it("refuses a limit out of bounds", async () => {
    expect((await call("GET", "/history/done?limit=0")).statusCode).toBe(400);
    expect((await call("GET", "/history/done?limit=101")).statusCode).toBe(400);
  });
});

describe("GET /history/weeks", () => {
  it("counts closings per local week, newest first, with the review of the week", async () => {
    fake.tables.review!.push({
      id: "r-1",
      userId: USER_A.id,
      periodStart: at("2026-11-16T06:00:00Z"),
      periodEnd: at("2026-11-23T06:30:00Z"),
      monthly: false,
      closedCount: 1,
      byProject: [{ projectId: "p-home", name: "Квартира", closed: 1 }],
      achievedGoals: [],
      summary: "Неделя ремонта",
      createdAt: at("2026-11-23T06:30:00Z"),
    });
    const { weeks } = await json<{ weeks: Row[] }>("GET", `/history/weeks?weeks=3&tzOffsetMinutes=${MSK}`);
    expect(weeks.map((w) => [w.start, w.closed])).toEqual([
      ["2026-11-23", 2],
      ["2026-11-16", 1],
      ["2026-11-09", 0],
    ]);
    expect(weeks[0]!.byProject).toEqual([
      { projectId: "p-work", name: "TaskRadar", closed: 1 },
      { projectId: "p-home", name: "Квартира", closed: 1 },
    ]);
    expect(weeks[0]!.review).toMatchObject({ id: "r-1", summary: "Неделя ремонта", closedCount: 1 });
    expect(weeks[1]!.review).toBeNull();
  });

  it("does not count B's closings, nor a reopened one", async () => {
    await json("POST", "/tasks/t-done-today/reopen");
    const { weeks } = await json<{ weeks: Row[] }>("GET", "/history/weeks?weeks=1");
    expect(weeks).toEqual([
      { start: "2026-11-23", closed: 1, byProject: [{ projectId: "p-work", name: "TaskRadar", closed: 1 }], review: null },
    ]);
  });
});

describe("GET /history (old app)", () => {
  it("still answers, and counts no revoked closing", async () => {
    fake.tables.taskEvent!.push(
      { id: "e1", taskId: "t-done-today", kind: "status", fromStatus: "pending", toStatus: "done", contourId: null, revokedAt: null, at: at("2026-11-27T07:00:00Z") },
      { id: "e2", taskId: "t-tail", kind: "status", fromStatus: "pending", toStatus: "done", contourId: null, revokedAt: at("2026-11-26T08:00:00Z"), at: at("2026-11-26T07:00:00Z") },
    );
    const history = await json<{ closedTotal: number; closedByDay: { date: string; count: number }[] }>(
      "GET",
      "/history?range=7d",
    );
    expect(history.closedTotal).toBe(1);
    expect(history.closedByDay.find((d) => d.date === "2026-11-26")!.count).toBe(0);
  });
});

// ---- reviews ----

describe("reviews", () => {
  it("is not due before the first review moment, and due after it", async () => {
    expect(await json("GET", `/reviews/status?tzOffsetMinutes=${MSK}`)).toEqual({
      due: false,
      nextAt: "2026-11-30T06:00:00.000Z",
      lastAt: null,
    });
    vi.setSystemTime(at("2026-11-30T06:00:00Z"));
    expect(await json("GET", `/reviews/status?tzOffsetMinutes=${MSK}`)).toMatchObject({ due: true });
  });

  it("follows the owner's review day and time", async () => {
    await json("PATCH", "/settings", { reviewWeekday: 5, reviewTime: "11:00" });
    // Friday 11:00 MSK = 08:00 UTC: an hour ago, and after reviews were introduced (27.11 00:00).
    expect(await json("GET", `/reviews/status?tzOffsetMinutes=${MSK}`)).toMatchObject({
      due: true,
      nextAt: "2026-11-27T08:00:00.000Z",
    });
  });

  it("records a review with the period's numbers, and starts the next one where it ended", async () => {
    vi.setSystemTime(at("2026-11-30T06:30:00Z"));
    const res = await call("POST", "/reviews", { summary: "  Неделя ремонта  ", tzOffsetMinutes: MSK });
    expect(res.statusCode).toBe(201);
    const review = res.json() as Row;
    expect(review).toMatchObject({
      periodStart: "2026-11-23T06:30:00.000Z",
      periodEnd: "2026-11-30T06:30:00.000Z",
      monthly: false,
      closedCount: 2,
      byProject: [
        { projectId: "p-work", name: "TaskRadar", closed: 1 },
        { projectId: "p-home", name: "Квартира", closed: 1 },
      ],
      achievedGoals: [],
      summary: "Неделя ремонта",
    });
    expect(await json("GET", `/reviews/status?tzOffsetMinutes=${MSK}`)).toEqual({
      due: false,
      nextAt: "2026-12-07T06:00:00.000Z",
      lastAt: "2026-11-30T06:30:00.000Z",
    });

    vi.setSystemTime(at("2026-12-07T07:00:00Z"));
    const next = await json("POST", "/reviews", { tzOffsetMinutes: MSK });
    expect(next).toMatchObject({ periodStart: "2026-11-30T06:30:00.000Z", monthly: true, closedCount: 0, summary: null });

    const list = await json<Row[]>("GET", "/reviews");
    expect(list.map((r) => r.periodEnd)).toEqual(["2026-12-07T07:00:00.000Z", "2026-11-30T06:30:00.000Z"]);
    expect(await json<Row[]>("GET", "/reviews?limit=1")).toHaveLength(1);
    expect(await json("GET", "/reviews", undefined, tokenB)).toEqual([]);
    expect(await json("GET", "/reviews/status", undefined, tokenB)).toMatchObject({ lastAt: null });
  });

  it("counts goals achieved within the period", async () => {
    fake.tables.goal!.push({
      id: "g-1",
      userId: USER_A.id,
      contourId: "c-main",
      title: "Запустить TaskRadar",
      why: null,
      windowDays: null,
      windowEndsAt: null,
      position: 1000,
      achievedAt: at("2026-11-26T12:00:00Z"),
      slottedAt: at("2026-11-01T00:00:00Z"),
      createdAt: T0,
      updatedAt: T0,
    });
    const review = await json("POST", "/reviews", {});
    expect(review.achievedGoals).toEqual([{ goalId: "g-1", title: "Запустить TaskRadar" }]);
  });

  it("answers a retry with the review it already recorded, taking a new summary", async () => {
    vi.setSystemTime(at("2026-11-30T06:30:00Z"));
    const first = await call("POST", "/reviews", { tzOffsetMinutes: MSK });
    expect(first.statusCode).toBe(201);
    vi.setSystemTime(at("2026-11-30T06:31:00Z"));
    const retry = await call("POST", "/reviews", { summary: "Итог", tzOffsetMinutes: MSK });
    expect(retry.statusCode).toBe(200);
    expect(retry.json()).toMatchObject({
      id: (first.json() as Row).id,
      periodStart: "2026-11-23T06:30:00.000Z",
      periodEnd: "2026-11-30T06:30:00.000Z",
      summary: "Итог",
    });
    // A retry without a summary keeps the one given.
    const again = await call("POST", "/reviews", { tzOffsetMinutes: MSK });
    expect(again.json()).toMatchObject({ id: (first.json() as Row).id, summary: "Итог" });
    expect(fake.tables.review).toHaveLength(1);
    // Ten minutes on, it is a new review again.
    vi.setSystemTime(at("2026-11-30T06:41:00Z"));
    expect((await call("POST", "/reviews", {})).statusCode).toBe(201);
    expect(fake.tables.review).toHaveLength(2);
    // B's retry window is B's own.
    expect((await call("POST", "/reviews", {}, tokenB)).statusCode).toBe(201);
  });

  it("refuses a summary longer than 300 characters", async () => {
    expect((await call("POST", "/reviews", { summary: "x".repeat(301) })).statusCode).toBe(400);
    expect(fake.tables.review).toEqual([]);
  });

  it("drafts the steps: done, intended with reasons, goals, rhythm, no month on the first review", async () => {
    // In the working set, the next step of a slotted goal, and dated in the period.
    fake.byId("task", "t-home-today")!.focusedAt = at("2026-11-25T08:00:00Z");
    fake.byId("task", "t-home-today")!.focusContourId = "c-home";
    fake.tables.goal!.push({
      id: "g-slot",
      userId: USER_A.id,
      contourId: "c-main",
      title: "Выпустить релиз",
      why: null,
      windowDays: null,
      achievedAt: null,
      position: 1000,
      slottedAt: at("2026-11-20T00:00:00Z"),
      windowEndsAt: at("2026-11-27T00:00:00Z"),
      createdAt: T0,
      updatedAt: T0,
    });
    fake.tables.goalTask!.push(
      { goalId: "g-slot", taskId: "t-later", position: 1000, createdAt: T0 },
      { goalId: "g-slot", taskId: "t-future", position: 2000, createdAt: T0 },
    );
    fake.byId("project", "p-work")!.rhythmMaxOpen = 2;

    const draft = await json<Row>("GET", `/reviews/draft?tzOffsetMinutes=${MSK}`);
    expect(draft).toMatchObject({
      periodStart: "2026-11-20T09:00:00.000Z",
      periodEnd: NOW.toISOString(),
      monthly: false,
      month: null,
    });
    expect(draft.done.map((d: Row) => d.task.id)).toEqual(["t-last-week", "t-done-yday", "t-done-today"]);
    const intended = Object.fromEntries(draft.intended.map((i: Row) => [i.task.id, i.reasons]));
    expect(intended).toEqual({
      "t-home-today": ["workingSet", "dated"],
      "t-future": ["goalStep"],
      "t-work-today": ["dated"],
      "t-courier": ["dated"],
      "t-tail": ["dated"],
    });
    // The goal's next step skipped «Позже».
    expect(draft.goals).toHaveLength(1);
    expect(draft.goals[0]).toMatchObject({ id: "g-slot", windowExpired: true, nextStep: { id: "t-future" } });
    expect(draft.rhythm).toEqual([
      {
        project: expect.objectContaining({ id: "p-work", name: "TaskRadar", rhythmMaxOpen: 2 }),
        rhythm: expect.objectContaining({ open: 4, maxOpen: 2, signal: "overflow" }),
      },
    ]);
  });

  it("adds the past month to the first review of a new month", async () => {
    fake.tables.review!.push({
      id: "r-nov",
      userId: USER_A.id,
      periodStart: at("2026-11-23T06:00:00Z"),
      periodEnd: at("2026-11-30T06:00:00Z"),
      monthly: false,
      closedCount: 0,
      byProject: [],
      achievedGoals: [],
      summary: null,
      createdAt: at("2026-11-30T06:00:00Z"),
    });
    vi.setSystemTime(at("2026-12-07T06:30:00Z"));
    const draft = await json<Row>("GET", `/reviews/draft?tzOffsetMinutes=${MSK}`);
    expect(draft.monthly).toBe(true);
    expect(draft.month).toEqual({
      month: "2026-11",
      byProject: [
        { projectId: "p-home", name: "Квартира", closed: 2 },
        { projectId: "p-work", name: "TaskRadar", closed: 1 },
      ],
      achievedGoals: [],
    });
  });
});

// ---- rhythm, «Позже» on the board ----

describe("project rhythm", () => {
  it("is set and cleared through PATCH /projects/:id, and shown everywhere a project is", async () => {
    const set = await json("PATCH", "/projects/p-work", { rhythmClosedPerWeek: 3, rhythmMaxOpen: 20 });
    expect(set).toMatchObject({
      rhythmClosedPerWeek: 3,
      rhythmMaxOpen: 20,
      rhythm: {
        closedPerWeek: 3,
        maxOpen: 20,
        closedAvg: 0.5,
        open: 4,
        lastClosedAt: "2026-11-26T10:00:00.000Z",
        silentWeeks: 0,
        signal: "silence",
      },
    });
    const listed = await json<Row[]>("GET", "/projects");
    expect(listed.find((p) => p.id === "p-work")!.rhythm.signal).toBe("silence");
    expect(listed.find((p) => p.id === "p-home")!.rhythm).toBeNull();
    const board = await json<Row[]>("GET", "/board");
    expect(board.find((p) => p.id === "p-work")!.rhythm).toMatchObject({ closedAvg: 0.5, open: 4 });
    expect((await json("GET", "/projects/p-work")).rhythm).not.toBeNull();

    const off = await json("PATCH", "/projects/p-work", { rhythmClosedPerWeek: null, rhythmMaxOpen: null });
    expect(off).toMatchObject({ rhythmClosedPerWeek: null, rhythmMaxOpen: null, rhythm: null });
  });

  it("refuses numbers out of bounds, and someone else's project", async () => {
    expect((await call("PATCH", "/projects/p-work", { rhythmClosedPerWeek: 0 })).statusCode).toBe(400);
    expect((await call("PATCH", "/projects/p-work", { rhythmMaxOpen: 501 })).statusCode).toBe(400);
    expect((await call("PATCH", "/projects/p-b", { rhythmMaxOpen: 5 })).statusCode).toBe(404);
    expect(fake.byId("project", "p-b")!.rhythmMaxOpen).toBeNull();
  });
});

describe("«Позже» is never current", () => {
  it("skips a task beyond the horizon on the board and the project list, by the owner's horizon", async () => {
    const current = async () => {
      const board = await json<Row[]>("GET", "/board");
      const fromBoard = board.find((p) => p.id === "p-work")!.tasks.filter((t: Row) => t.isCurrent);
      const fromList = (await json<Row[]>("GET", "/projects/p-work/tasks")).filter((t) => t.isCurrent);
      expect(ids(fromList)).toEqual(ids(fromBoard));
      return ids(fromBoard);
    };
    expect(await current()).toEqual(["t-tail"]);
    await json("PATCH", "/settings", { laterHorizonDays: 90 });
    expect(await current()).toEqual(["t-later"]);
  });

  it("passes over «Позже» for a goal's next step", async () => {
    const goal = await json("POST", "/goals", { title: "Домен", contourId: "c-main" });
    await json("PUT", `/goals/${goal.id}/tasks/t-later`);
    const linked = await json("PUT", `/goals/${goal.id}/tasks/t-future`);
    expect(linked.nextStep).toMatchObject({ id: "t-future" });
    const listed = await json<Row[]>("GET", "/goals");
    expect(listed[0]!.nextStep).toMatchObject({ id: "t-future" });
    expect(listed[0]!.tasks[0]).toMatchObject({ id: "t-later", remindAt: "2027-02-25T00:00:00.000Z" });
  });
});

// ---- MCP ----

describe("MCP: today, done, reviews", () => {
  let client: Client;

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

  async function tool<T = Row>(name: string, args: Row = {}): Promise<T> {
    const result = (await client.callTool({ name, arguments: args })) as {
      isError?: boolean;
      content: { text: string }[];
    };
    if (result.isError) throw new Error(`tool error: ${result.content[0]?.text}`);
    return JSON.parse(result.content[0]!.text) as T;
  }

  beforeEach(async () => {
    client = await connect(token, USER_A.id);
  });

  it("list_today: the day, with project and scope, in the owner's zone", async () => {
    const view = await tool("list_today", { tzOffsetMinutes: MSK });
    expect(view.date).toBe("2026-11-27");
    expect(ids(view.today)).toEqual(["t-courier", "t-work-today", "t-home-today"]);
    expect(view.today[0]).toMatchObject({
      title: "Встретить курьера",
      remindAt: "2026-11-27",
      remindTime: "15:00",
      project: "Квартира",
      scope: "Дом",
    });
    expect(view.doneToday[0]).toMatchObject({ id: "t-done-today", doneAt: "2026-11-27T07:00:00.000Z" });
    expect(ids(view.tail)).toEqual(["t-tail"]);
  });

  it("list_done: closings with doneAt, pages, never another user's", async () => {
    const all = await tool("list_done");
    expect(ids(all.tasks)).toEqual(["t-done-today", "t-done-yday", "t-last-week"]);
    expect(all.more).toBeUndefined();
    const first = await tool("list_done", { limit: 1 });
    expect(first).toMatchObject({ tasks: [{ id: "t-done-today" }], more: true });
    const next = await tool("list_done", { limit: 5, before: first.tasks[0].doneAt });
    expect(ids(next.tasks)).toEqual(["t-done-yday", "t-last-week"]);
  });

  it("list_reviews: the records, newest first", async () => {
    vi.setSystemTime(at("2026-11-30T06:30:00Z"));
    await json("POST", "/reviews", { summary: "Итог", tzOffsetMinutes: MSK });
    const { reviews } = await tool("list_reviews");
    expect(reviews).toEqual([
      {
        id: expect.any(String),
        periodStart: "2026-11-23T06:30:00.000Z",
        periodEnd: "2026-11-30T06:30:00.000Z",
        closed: 2,
        byProject: expect.any(Array),
        achievedGoals: [],
        summary: "Итог",
      },
    ]);
    const other = await connect(tokenB, USER_B.id);
    const result = (await other.callTool({ name: "list_reviews", arguments: {} })) as { content: { text: string }[] };
    expect(JSON.parse(result.content[0]!.text)).toEqual({ reviews: [] });
  });

  it("list_projects shows the rhythm; list_tasks never marks «Позже» current; get_task has doneAt", async () => {
    fake.byId("project", "p-work")!.rhythmClosedPerWeek = 3;
    const projects = await tool<Row[]>("list_projects");
    expect(projects.find((p) => p.id === "p-work")!.rhythm).toMatchObject({
      closedPerWeek: 3,
      closedAvg: 0.5,
      signal: "silence",
      lastClosedAt: "2026-11-26T10:00:00.000Z",
    });
    expect(projects.find((p) => p.id === "p-home")!.rhythm).toBeUndefined();
    const { tasks } = await tool("list_tasks", { projectId: "p-work" });
    expect(tasks.filter((t: Row) => t.current).map((t: Row) => t.id)).toEqual(["t-tail"]);
    const done = await tool("get_task", { taskId: "t-done-yday", pictures: false });
    expect(done.doneAt).toBe("2026-11-26T10:00:00.000Z");
    const open = await tool("get_task", { taskId: "t-tail", pictures: false });
    expect(open).not.toHaveProperty("doneAt");
  });

  it("describes the date as when the owner gets to it, and the time as only for a moment", async () => {
    const { tools } = await client.listTools();
    const update = tools.find((t) => t.name === "update_task")!;
    const props = (update.inputSchema as { properties: Row }).properties;
    expect(props.remindAt.description).toMatch(/day the owner will get to it/);
    expect(props.remindTime.description).toMatch(/only if the moment matters/);
    for (const name of ["list_today", "list_done", "list_reviews"]) {
      expect(tools.find((t) => t.name === name)!.annotations?.readOnlyHint).toBe(true);
    }
  });
});
