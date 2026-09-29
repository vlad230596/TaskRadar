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
  inventedDateTerms,
  NOTE_PROMPT_VERSION,
  SANDBOX_PROMPT_VERSION,
  TASK_TIDY_PROMPT_VERSION,
  type TidyParsers,
} from "../src/domain/tidy";
import { DICTATION_PROMPT_VERSION, type DictationParser } from "../src/domain/dictation";
import type { ParseTrace } from "../src/domain/parsePipeline";
import { inMemoryUsers, tokenFor, USER_A, USER_B } from "./support/users";

/*
 * "Причесать" (F15): the kinds `task_tidy`, `note` and `sandbox` of
 * `POST /dictation/parse`. As in `dictation.test.ts`, nothing here talks to a
 * model: what is pinned is the prompt each kind sends, what is done with a
 * reply that is half right, and that the sandbox's projects come from the
 * database and nowhere else.
 */

/** Rows written to `dictation_parses`, in order. */
const samples = vi.hoisted(() => [] as Record<string, unknown>[]);
/**
 * What `projects` holds -- with the user who owns each one's scope: the only
 * list the sandbox prompt may see.
 */
const projects = vi.hoisted(
  () => [] as { id: string; name: string; userId: string; archivedAt: Date | null }[],
);
const prismaMock = vi.hoisted(() => ({
  // The daily limit's counter; nothing in this file runs into it.
  aiUsage: { upsert: vi.fn(async () => ({ count: 1 })) },
  dictationParse: {
    create: vi.fn(async (args: { data: Record<string, unknown> }) => {
      samples.push(args.data);
      return { id: `dp-${samples.length}` };
    }),
  },
  project: {
    // Evaluates both halves of the filter: not archived, and owned by the
    // caller. A route that dropped either would show up in the prompt.
    findMany: vi.fn(
      async (args: { where: { archivedAt: null; scope: { userId: string } } }) =>
        projects
          .filter(
            (project) =>
              project.userId === args.where.scope.userId &&
              (args.where.archivedAt !== null || project.archivedAt === null),
          )
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
        warnings: [],
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
      ["a weekday", { title: "Позвонить маме", description: "До вторника." }, "вторника"],
      ["a relative day", { title: "Позвонить маме завтра", description: null }, "завтра"],
      ["a date", { title: "Позвонить маме", description: "Срок — 25.09." }, "25.09"],
      ["an ISO date", { title: "Позвонить маме", description: "2026-09-25" }, "2026-09-25"],
      ["a time", { title: "Позвонить маме в 10:00", description: null }, "10:00"],
      ["a month", { title: "Позвонить маме", description: "В начале октября." }, "октября"],
    ])("keeps a reply that invents %s, with a warning naming it", (_label, value, token) => {
      const tidied = interpretTaskTidyReply(reply(value), "позвонить маме");
      expect(tidied.title).toMatch(/^Позвонить маме/);
      expect(tidied.warnings).toEqual([{ kind: "invented_date", token }]);
    });

    it("warns about a number the model wrote down from words, and keeps the answer", () => {
      // "три ноль" is the user's own time, spelled out; the detector cannot
      // tell "3.00" from an invented one, so the user decides.
      const tidied = interpretTaskTidyReply(
        reply({ title: "Созвон с Петей", description: "В 3.00, обсудить смету." }),
        "созвон с петей в три ноль обсудить смету",
      );
      expect(tidied).toEqual({
        title: "Созвон с Петей",
        description: "В 3.00, обсудить смету.",
        warnings: [{ kind: "invented_date", token: "3.00" }],
      });
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

    it("finds every invented term once, in order, spelled as the reply spells it", () => {
      expect(
        inventedDateTerms("позвонить", "Позвонить Завтра в 10:00, потом в 10:00 и в Пятницу"),
      ).toEqual(["Завтра", "10:00", "Пятницу"]);
      expect(inventedDateTerms("позвонить", "Позвонить")).toEqual([]);
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
      warnings: [],
    });
    // The user's own title is not replaced, whatever the model says.
    expect(interpretNoteReply(content, "Дача")).toEqual({
      title: null,
      content: "- гвозди\n- краска",
      warnings: [],
    });
  });

  it("warns about a date the note did not have, and keeps the note", () => {
    const tidied = interpretNoteReply(
      reply({ title: null, content: "Купить гвозди до субботы." }),
      "Дача",
      "купить гвозди",
    );
    expect(tidied.content).toBe("Купить гвозди до субботы.");
    expect(tidied.warnings).toEqual([{ kind: "invented_date", token: "субботы" }]);
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

  it("asks for the line as a task too, so taking the project needs no second call", () => {
    const [system] = buildSandboxMessages({ ...input("колодки"), projects: choices });
    expect(system.content).toContain('"title"');
    expect(system.content).toContain('"description"');
    expect(SANDBOX_PROMPT_VERSION).toBe("sandbox-2");
  });

  it("keeps a project that is on the list, with its name from the list", () => {
    expect(
      interpretSandboxReply(
        reply({
          text: " Поменять колодки, передние ",
          title: "поменять колодки.",
          description: "Передние.",
          projectId: "prj_car",
        }),
        choices,
      ),
    ).toEqual({
      text: "Поменять колодки, передние",
      title: "Поменять колодки",
      description: "Передние.",
      projectId: "prj_car",
      projectName: "Машина",
      warnings: [],
    });
  });

  it("splits the line itself when the reply has no title", () => {
    const long =
      "Поменять колодки на машине. Передние, до зимы, заодно спросить в сервисе про " +
      "диски и сколько стоит работа, если делать всё вместе";
    const tidied = interpretSandboxReply(reply({ text: long, title: "  " }), choices);
    expect(tidied.title).toBe("Поменять колодки на машине");
    expect(tidied.description).toMatch(/^Передние/);
  });

  it("warns about a date the line did not have", () => {
    expect(
      interpretSandboxReply(
        reply({ text: "Колодки до пятницы", title: "Колодки", description: "До пятницы" }),
        choices,
        "колодки",
      ).warnings,
    ).toEqual([{ kind: "invented_date", token: "пятницы" }]);
  });

  it.each([
    ["an unknown id", "prj_invented"],
    ["a name instead of an id", "Машина"],
    ["null", null],
    ["a number", 3],
  ])("turns %s into no suggestion", (_label, projectId) => {
    expect(interpretSandboxReply(reply({ text: "Колодки", projectId }), choices)).toEqual({
      text: "Колодки",
      title: "Колодки",
      description: null,
      projectId: null,
      projectName: null,
      warnings: [],
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

  it("traces an invented date as a success with a warning, never as a failure", async () => {
    const answer = reply({ title: "Позвонить маме завтра", content: "Завтра", text: "Завтра" });
    const parsers = createTidyParsers(async () => answer, async () => "m");
    const warned = { warnings: [{ kind: "invented_date", token: "завтра" }] };

    expect(await parsers.task_tidy(input("позвонить маме"))).toMatchObject({
      result: { title: "Позвонить маме завтра", ...warned },
      rawReply: answer,
      error: null,
    });
    expect(await parsers.note(input("позвонить маме"))).toMatchObject({
      result: { content: "Завтра", ...warned },
      error: null,
    });
    expect(await parsers.sandbox({ ...input("позвонить маме"), projects: [] })).toMatchObject({
      result: { warnings: [{ kind: "invented_date", token: "Завтра" }] },
      error: null,
    });
  });
});

describe("POST /dictation/parse, the tidying kinds", () => {
  const authConfig: AuthConfig = {
    email: "owner@example.com",
    passwordHash: "$2b$04$zV5VFEALedx8Rfd/ucwUSOrHYSSr8xveuActiCTdzOmCsBSDTbYXO",
    jwtSecret: "test-jwt-secret-".repeat(4),
    cookieSecure: false,
  };

  let app: FastifyInstance;
  let bareApp: FastifyInstance;
  /** USER_A's token: who every test acts as unless it says otherwise. */
  let token: string;
  let tokenB: string;
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
    const users = inMemoryUsers();
    app = await buildApp({
      authConfig,
      logger: false,
      users,
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
      users,
      dictation: { parser, defaultModel: "env-model" },
    });
    token = await tokenFor(app, USER_A.email);
    tokenB = await tokenFor(app, USER_B.email);
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

  const post = (target: FastifyInstance, payload: Record<string, unknown>, bearer = token) =>
    target.inject({
      method: "POST",
      url: "/dictation/parse",
      headers: { authorization: `Bearer ${bearer}` },
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
      { id: "prj_home", name: "Дом", userId: USER_A.id, archivedAt: null },
      { id: "prj_old", name: "Старое", userId: USER_A.id, archivedAt: new Date() },
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
      expect.objectContaining({ where: { archivedAt: null, scope: { userId: USER_A.id } } }),
    );
    expect(samples[0]).toMatchObject({ kind: "sandbox" });
  });

  it("sandbox: lists only the caller's own projects, never another user's", async () => {
    projects.push(
      { id: "prj_home", name: "Дом", userId: USER_A.id, archivedAt: null },
      { id: "prj_old", name: "Старое", userId: USER_A.id, archivedAt: new Date() },
      { id: "prj_b", name: "Чужой проект", userId: USER_B.id, archivedAt: null },
    );
    const answer = traceOf({ text: "Колодки", projectId: null, projectName: null }, SANDBOX_PROMPT_VERSION);
    tidiers.sandbox.mockResolvedValueOnce(answer).mockResolvedValueOnce(answer);

    await post(app, { text: "колодки", timeZone: "UTC", kind: "sandbox" });
    await post(app, { text: "колодки", timeZone: "UTC", kind: "sandbox" }, tokenB);

    // A's list holds neither B's project nor their own archived one; B's holds
    // only B's -- their names never reach the other person's prompt.
    expect(tidiers.sandbox.mock.calls[0]![0].projects).toEqual([{ id: "prj_home", name: "Дом" }]);
    expect(tidiers.sandbox.mock.calls[1]![0].projects).toEqual([
      { id: "prj_b", name: "Чужой проект" },
    ]);
  });

  it("keeps each sample under the user who asked", async () => {
    const answer = traceOf({ title: "Позвонить маме", description: null }, TASK_TIDY_PROMPT_VERSION);
    tidiers.task_tidy.mockResolvedValueOnce(answer).mockResolvedValueOnce(answer);

    await post(app, { text: "x", timeZone: "UTC", kind: "task_tidy" });
    await post(app, { text: "y", timeZone: "UTC", kind: "task_tidy" }, tokenB);

    expect(samples.map((sample) => sample.userId)).toEqual([USER_A.id, USER_B.id]);
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
