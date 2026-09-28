import { describe, it, expect, beforeAll, afterAll, beforeEach, vi } from "vitest";
import type { FastifyInstance } from "fastify";
import type { AuthConfig } from "../src/lib/authConfig";
import { UpstreamModelError } from "../src/lib/llmClient";
import {
  buildNoteMessages,
  buildSandboxMessages,
  buildTaskTidyMessages,
  createTidyParsers,
  interpretNoteReply,
  interpretSandboxReply,
  interpretTaskTidyReply,
  inventedDateTerm,
  NOTE_PROMPT_VERSION,
  SANDBOX_PROMPT_VERSION,
  TASK_TIDY_PROMPT_VERSION,
  type TidyParsers,
} from "../src/domain/tidy";
import { DICTATION_PROMPT_VERSION, type DictationParser } from "../src/domain/dictation";
import type { ParseTrace } from "../src/domain/parsePipeline";

/*
 * "Причесать" (F15): the kinds `task_tidy`, `note` and `sandbox` of
 * `POST /dictation/parse`. As in `dictation.test.ts`, nothing here talks to a
 * model: what is pinned is the prompt each kind sends, what is done with a
 * reply that is half right, and that the sandbox's projects come from the
 * database and nowhere else.
 */

/** Rows written to `dictation_parses`, in order. */
const samples = vi.hoisted(() => [] as Record<string, unknown>[]);
/** What `projects` holds: the only list the sandbox prompt may see. */
const projects = vi.hoisted(() => [] as { id: string; name: string; archivedAt: Date | null }[]);
const prismaMock = vi.hoisted(() => ({
  dictationParse: {
    create: vi.fn(async (args: { data: Record<string, unknown> }) => {
      samples.push(args.data);
      return { id: `dp-${samples.length}` };
    }),
  },
  project: {
    findMany: vi.fn(async (args: { where: { archivedAt: null } }) =>
      projects
        .filter((project) => args.where.archivedAt !== null || project.archivedAt === null)
        .map(({ id, name }) => ({ id, name })),
    ),
  },
  appSetting: {
    findUnique: vi.fn(async () => null),
  },
}));
vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
process.env.DATABASE_URL ??= "postgresql://placeholder:placeholder@localhost:5432/placeholder";

const NOW = new Date("2026-09-23T22:30:00.000Z");
const input = (text: string, extra: Record<string, unknown> = {}) => ({
  text,
  timeZone: "Europe/Moscow",
  now: NOW,
  ...extra,
});
const reply = (value: unknown) => JSON.stringify(value);

describe("task_tidy", () => {
  describe("buildTaskTidyMessages", () => {
    const [system, user] = buildTaskTidyMessages(input("ну позвонить маме"));

    it("passes the task's text through untouched as the user turn", () => {
      expect(user).toEqual({ role: "user", content: "ну позвонить маме" });
    });

    it("asks for the two fields and forbids new facts and dates", () => {
      expect(system.content).toContain('"title"');
      expect(system.content).toContain('"description"');
      expect(system.content).toContain("НЕ добавляй фактов");
      expect(system.content).toContain("НЕ добавляй дат");
    });

    it("has no calendar and no reminder keys: it only tidies", () => {
      expect(system.content).not.toContain("remindDate");
      expect(system.content).not.toContain("Календарь");
    });
  });

  describe("interpretTaskTidyReply", () => {
    const source = "ну короче позвонить в сервис спросить про колодки в пятницу";

    it("keeps a well-formed reply, tidying the title", () => {
      expect(
        interpretTaskTidyReply(
          reply({ title: "позвонить в сервис.", description: "Спросить про колодки в пятницу." }),
          source,
        ),
      ).toEqual({
        title: "Позвонить в сервис",
        description: "Спросить про колодки в пятницу.",
      });
    });

    it("turns an empty or mistyped description into null", () => {
      expect(
        interpretTaskTidyReply(reply({ title: "Позвонить", description: "  " }), source),
      ).toMatchObject({ description: null });
      expect(
        interpretTaskTidyReply(reply({ title: "Позвонить", description: 7 }), source),
      ).toMatchObject({ description: null });
    });

    it.each([
      ["a weekday", { title: "Позвонить маме", description: "До вторника." }],
      ["a relative day", { title: "Позвонить маме завтра", description: null }],
      ["a date", { title: "Позвонить маме", description: "Срок — 25.09." }],
      ["an ISO date", { title: "Позвонить маме", description: "2026-09-25" }],
      ["a time", { title: "Позвонить маме в 10:00", description: null }],
      ["a month", { title: "Позвонить маме", description: "В начале октября." }],
    ])("refuses a reply that invents %s", (_label, value) => {
      expect(() => interpretTaskTidyReply(reply(value), "позвонить маме")).toThrow(
        UpstreamModelError,
      );
    });

    it("keeps a date the source did say", () => {
      expect(
        interpretTaskTidyReply(
          reply({ title: "Позвонить в сервис", description: "В пятницу, в 10:00." }),
          "позвонить в сервис в пятницу в 10:00",
        ).description,
      ).toBe("В пятницу, в 10:00.");
    });

    it.each([
      ["not JSON", "Конечно! Вот задача"],
      ["no title", reply({ description: "что-то" })],
      ["an empty title", reply({ title: " . " })],
    ])("refuses a reply with %s", (_label, content) => {
      expect(() => interpretTaskTidyReply(content, source)).toThrow(UpstreamModelError);
    });
  });

  describe("inventedDateTerm", () => {
    it("reads words as words, not as parts of other words", () => {
      // "средство" is not Wednesday and "мама" is not May.
      expect(inventedDateTerm("купить", "Купить средство для мамы")).toBeNull();
      expect(inventedDateTerm("купить", "Купить в среду")).toBe("среду");
    });

    it("does not mind a different form of a day that was said", () => {
      expect(inventedDateTerm("к пятнице", "До пятницы")).toBeNull();
      expect(inventedDateTerm("в субботу", "В субботу")).toBeNull();
    });
  });
});

describe("note", () => {
  it("asks for paragraphs and lists, and a title only when there is none", () => {
    const [untitled, user] = buildNoteMessages(input("ну значит так пункт первый"));
    expect(user).toEqual({ role: "user", content: "ну значит так пункт первый" });
    expect(untitled.content).toContain("абзацы");
    expect(untitled.content).toContain("«- »");
    expect(untitled.content).toContain("у заметки нет заголовка");

    const [titled] = buildNoteMessages(input("текст", { noteTitle: "Дача" }));
    expect(titled.content).toContain("у заметки уже есть заголовок («Дача»)");
    expect(titled.content).toContain('"title": null');
  });

  it("asks for no reminders", () => {
    const [system] = buildNoteMessages(input("текст"));
    expect(system.content).toContain("Напоминаний и сроков не ставь");
    expect(system.content).not.toContain("remindDate");
  });

  it("keeps a suggested title only for a note that has none", () => {
    const content = reply({ title: "план на дачу.", content: "- гвозди\n- краска" });
    expect(interpretNoteReply(content)).toEqual({
      title: "План на дачу",
      content: "- гвозди\n- краска",
    });
    // The user's own title is not replaced, whatever the model says.
    expect(interpretNoteReply(content, "Дача")).toEqual({
      title: null,
      content: "- гвозди\n- краска",
    });
  });

  it.each([
    ["not JSON", "Вот заметка"],
    ["no content", reply({ title: "Дача" })],
    ["empty content", reply({ content: "   " })],
  ])("refuses a reply with %s", (_label, content) => {
    expect(() => interpretNoteReply(content)).toThrow(UpstreamModelError);
  });
});

describe("sandbox", () => {
  const choices = [
    { id: "prj_home", name: "Дом" },
    { id: "prj_car", name: "Машина" },
  ];

  it("shows the model the projects, by id and name", () => {
    const [system, user] = buildSandboxMessages({ ...input("колодки"), projects: choices });
    expect(user).toEqual({ role: "user", content: "колодки" });
    expect(system.content).toContain("- prj_home — Дом");
    expect(system.content).toContain("- prj_car — Машина");
    expect(system.content).toContain("НЕ добавляй фактов");
  });

  it("says so when there are no projects to choose from", () => {
    const [system] = buildSandboxMessages({ ...input("колодки"), projects: [] });
    expect(system.content).toContain("проектов нет");
  });

  it("keeps a project that is on the list, with its name from the list", () => {
    expect(
      interpretSandboxReply(reply({ text: " Поменять колодки ", projectId: "prj_car" }), choices),
    ).toEqual({ text: "Поменять колодки", projectId: "prj_car", projectName: "Машина" });
  });

  it.each([
    ["an unknown id", "prj_invented"],
    ["a name instead of an id", "Машина"],
    ["null", null],
    ["a number", 3],
  ])("turns %s into no suggestion", (_label, projectId) => {
    expect(interpretSandboxReply(reply({ text: "Колодки", projectId }), choices)).toEqual({
      text: "Колодки",
      projectId: null,
      projectName: null,
    });
  });

  it.each([
    ["not JSON", "Колодки"],
    ["no text", reply({ projectId: "prj_car" })],
    ["empty text", reply({ text: " " })],
  ])("refuses a reply with %s", (_label, content) => {
    expect(() => interpretSandboxReply(content, choices)).toThrow(UpstreamModelError);
  });
});

describe("createTidyParsers", () => {
  it("traces each kind with its own prompt version", async () => {
    const complete = vi.fn(async () =>
      reply({ title: "Сделать", description: null, content: "Текст", text: "Строка" }),
    );
    const parsers = createTidyParsers(complete, async () => "m");

    const traces = [
      await parsers.task_tidy(input("сделать")),
      await parsers.note(input("текст")),
      await parsers.sandbox({ ...input("строка"), projects: [] }),
    ];
    expect(traces.map((trace) => trace.promptVersion)).toEqual([
      TASK_TIDY_PROMPT_VERSION,
      NOTE_PROMPT_VERSION,
      SANDBOX_PROMPT_VERSION,
    ]);
    expect(new Set([...traces.map((t) => t.promptVersion), DICTATION_PROMPT_VERSION]).size).toBe(4);
  });

  it("traces an invented date as a failure, keeping the reply", async () => {
    const parsers = createTidyParsers(
      async () => reply({ title: "Позвонить маме завтра" }),
      async () => "m",
    );
    expect(await parsers.task_tidy(input("позвонить маме"))).toMatchObject({
      result: null,
      rawReply: reply({ title: "Позвонить маме завтра" }),
      error: expect.stringMatching(/invents a date/),
    });
  });
});

describe("POST /dictation/parse, the tidying kinds", () => {
  const TEST_PASSWORD = "test-password-not-the-real-one";
  const authConfig: AuthConfig = {
    email: "owner@example.com",
    passwordHash: "$2b$04$zV5VFEALedx8Rfd/ucwUSOrHYSSr8xveuActiCTdzOmCsBSDTbYXO",
    jwtSecret: "test-jwt-secret-".repeat(4),
    cookieSecure: false,
  };

  let app: FastifyInstance;
  let bareApp: FastifyInstance;
  let token: string;
  const parser = vi.fn<DictationParser>();
  const tidiers = {
    task_tidy: vi.fn(),
    note: vi.fn(),
    sandbox: vi.fn(),
  };

  const traceOf = <T>(result: T | null, promptVersion: string): ParseTrace<T> => ({
    model: "env-model",
    promptVersion,
    rawReply: result === null ? null : JSON.stringify(result),
    result,
    error: result === null ? "status 500" : null,
    durationMs: 10,
  });

  beforeAll(async () => {
    const { buildApp } = await import("../src/app");
    app = await buildApp({
      authConfig,
      logger: false,
      dictation: {
        parser,
        tidiers: tidiers as unknown as TidyParsers,
        defaultModel: "env-model",
      },
    });
    // A server built before the tidying kinds: a parser for `task` only.
    bareApp = await buildApp({
      authConfig,
      logger: false,
      dictation: { parser, defaultModel: "env-model" },
    });
    const login = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: authConfig.email, password: TEST_PASSWORD },
    });
    token = (login.json() as { token: string }).token;
  });

  afterAll(async () => {
    await app?.close();
    await bareApp?.close();
  });

  beforeEach(() => {
    samples.length = 0;
    projects.length = 0;
    vi.clearAllMocks();
  });

  const post = (target: FastifyInstance, payload: Record<string, unknown>) =>
    target.inject({
      method: "POST",
      url: "/dictation/parse",
      headers: { authorization: `Bearer ${token}` },
      payload,
    });

  it("task_tidy: answers with the two fields, and keeps the sample under its kind", async () => {
    tidiers.task_tidy.mockResolvedValueOnce(
      traceOf({ title: "Позвонить маме", description: null }, TASK_TIDY_PROMPT_VERSION),
    );

    const res = await post(app, { text: "ну позвонить маме", timeZone: "UTC", kind: "task_tidy" });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ title: "Позвонить маме", description: null, parseId: "dp-1" });
    expect(parser).not.toHaveBeenCalled();
    expect(samples[0]).toMatchObject({
      kind: "task_tidy",
      inputText: "ну позвонить маме",
      promptVersion: TASK_TIDY_PROMPT_VERSION,
      status: "ok",
    });
  });

  it("note: passes the note's title on to the prompt's input", async () => {
    tidiers.note.mockResolvedValueOnce(
      traceOf({ title: null, content: "- гвозди" }, NOTE_PROMPT_VERSION),
    );

    const res = await post(app, {
      text: "гвозди",
      timeZone: "UTC",
      kind: "note",
      noteTitle: " Дача ",
    });

    expect(res.json()).toEqual({ title: null, content: "- гвозди", parseId: "dp-1" });
    expect(tidiers.note.mock.lastCall![0]).toMatchObject({ text: "гвозди", noteTitle: "Дача" });
    expect(samples[0]).toMatchObject({ kind: "note" });
  });

  it("sandbox: the projects come from the database, never from the request", async () => {
    projects.push(
      { id: "prj_home", name: "Дом", archivedAt: null },
      { id: "prj_old", name: "Старое", archivedAt: new Date() },
    );
    tidiers.sandbox.mockResolvedValueOnce(
      traceOf({ text: "Колодки", projectId: null, projectName: null }, SANDBOX_PROMPT_VERSION),
    );

    const res = await post(app, {
      text: "колодки",
      timeZone: "UTC",
      kind: "sandbox",
      // Not part of the schema: a client cannot put words in the prompt.
      projects: [{ id: "prj_evil", name: "Взлом" }],
    });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ text: "Колодки", projectId: null });
    expect(tidiers.sandbox.mock.lastCall![0].projects).toEqual([{ id: "prj_home", name: "Дом" }]);
    expect(prismaMock.project.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { archivedAt: null } }),
    );
    expect(samples[0]).toMatchObject({ kind: "sandbox" });
  });

  it("keeps a failed tidy as a sample of its kind, and answers 502", async () => {
    tidiers.task_tidy.mockResolvedValueOnce(traceOf(null, TASK_TIDY_PROMPT_VERSION));

    const res = await post(app, { text: "x", timeZone: "UTC", kind: "task_tidy" });

    expect(res.statusCode).toBe(502);
    expect(samples[0]).toMatchObject({ kind: "task_tidy", status: "failed" });
  });

  it("records `task` for a request that names no kind", async () => {
    parser.mockResolvedValueOnce(
      traceOf(
        { title: "Сделать", description: null, remindDate: null, remindTime: null },
        DICTATION_PROMPT_VERSION,
      ),
    );
    await post(app, { text: "x", timeZone: "UTC" });
    expect(samples[0]).toMatchObject({ kind: "task" });
  });

  it("answers 503 for a tidying kind on a server with no parser for it", async () => {
    const res = await post(bareApp, { text: "x", timeZone: "UTC", kind: "note" });
    expect(res.statusCode).toBe(503);
  });

  it("refuses a note title too long to be one", async () => {
    const res = await post(app, {
      text: "x",
      timeZone: "UTC",
      kind: "note",
      noteTitle: "а".repeat(501),
    });
    expect(res.statusCode).toBe(400);
  });
});
