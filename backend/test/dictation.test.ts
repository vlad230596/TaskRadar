import { describe, it, expect, beforeAll, afterAll, beforeEach, vi } from "vitest";
import type { FastifyInstance } from "fastify";
import type { AuthConfig } from "../src/lib/authConfig";
import {
  buildDictationMessages,
  createDictationParser,
  interpretModelReply,
  localDate,
  type DictationParser,
} from "../src/domain/dictation";
import { createOpenAiCompatibleClient, UpstreamModelError } from "../src/lib/llmClient";
import { loadLlmConfig } from "../src/lib/llmConfig";
import { resolveDictationModel } from "../src/domain/dictationModel";

/*
 * Dictation -> task (F14).
 *
 * No test here talks to a model. What is worth pinning is everything around
 * it: the calendar the model reads dates from, what is done with a reply that
 * is half right, the HTTP shape every OpenAI-compatible provider expects, and
 * the route's two ways of saying "use the raw words instead".
 */

/**
 * The one table these routes touch: `app_settings`, as a map. A fake that
 * really stores lets "save, then read back" be asserted as a sequence.
 */
const settings = vi.hoisted(() => new Map<string, string>());
const prismaMock = vi.hoisted(() => ({
  appSetting: {
    findUnique: vi.fn(async (args: { where: { key: string } }) => {
      const value = settings.get(args.where.key);
      return value === undefined ? null : { key: args.where.key, value };
    }),
    upsert: vi.fn(async (args: { where: { key: string }; update: { value: string } }) => {
      settings.set(args.where.key, args.update.value);
    }),
    deleteMany: vi.fn(async (args: { where: { key: string } }) => {
      settings.delete(args.where.key);
    }),
  },
}));
vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
process.env.DATABASE_URL ??= "postgresql://placeholder:placeholder@localhost:5432/placeholder";

const TEST_PASSWORD = "test-password-not-the-real-one";
/** bcrypt hash of TEST_PASSWORD at cost 4. */
const TEST_HASH = "$2b$04$zV5VFEALedx8Rfd/ucwUSOrHYSSr8xveuActiCTdzOmCsBSDTbYXO";

const authConfig: AuthConfig = {
  email: "owner@example.com",
  passwordHash: TEST_HASH,
  jwtSecret: "test-jwt-secret-".repeat(4),
  cookieSecure: false,
};

/** Wednesday 23 September 2026, 22:30 UTC -- already Thursday in Moscow. */
const NOW = new Date("2026-09-23T22:30:00.000Z");

describe("localDate", () => {
  it("reads the calendar date in the caller's zone, not UTC's", () => {
    expect(localDate(NOW, "UTC")).toBe("2026-09-23");
    expect(localDate(NOW, "Europe/Moscow")).toBe("2026-09-24");
  });
});

describe("buildDictationMessages", () => {
  const [system, user] = buildDictationMessages({
    text: "позвонить маме",
    timeZone: "Europe/Moscow",
    now: NOW,
  });

  it("passes the dictation through untouched as the user turn", () => {
    expect(user).toEqual({ role: "user", content: "позвонить маме" });
  });

  it("starts the calendar at the caller's today, with its weekday", () => {
    expect(system.content).toContain("2026-09-24 — четверг (сегодня)");
    expect(system.content).toContain("2026-09-25 — пятница (завтра)");
    expect(system.content).toContain("2026-10-07 — среда");
    expect(system.content).not.toContain("2026-10-08");
  });

  it("builds the examples from the same calendar the model is told to use", () => {
    // Said on a Thursday, "в пятницу" is tomorrow; an example with a fixed date
    // would contradict the table and teach the model to copy it.
    expect(system.content).toContain('"remindDate":"2026-09-25"');
  });
});

describe("interpretModelReply", () => {
  const today = "2026-09-24";
  const reply = (value: unknown) => JSON.stringify(value);

  it("keeps a well-formed reply", () => {
    expect(
      interpretModelReply(
        reply({
          title: "Позвонить в сервис",
          description: "Спросить про колодки",
          remindDate: "2026-09-25",
          remindTime: "10:00",
        }),
        today,
      ),
    ).toEqual({
      title: "Позвонить в сервис",
      description: "Спросить про колодки",
      remindDate: "2026-09-25",
      remindTime: "10:00",
    });
  });

  it("tidies the title and turns an empty description into null", () => {
    expect(
      interpretModelReply(reply({ title: "  позвонить маме. ", description: "  " }), today),
    ).toEqual({ title: "Позвонить маме", description: null, remindDate: null, remindTime: null });
  });

  it.each([
    ["in the past", "2026-09-23"],
    ["more than a year ahead", "2027-10-01"],
    ["not a real day", "2026-02-30"],
    ["not a date at all", "в пятницу"],
  ])("drops a reminder date %s", (_label, remindDate) => {
    const parsed = interpretModelReply(
      reply({ title: "Сделать", remindDate, remindTime: "10:00" }),
      today,
    );
    expect(parsed.remindDate).toBeNull();
    // A time with no day is not a reminder.
    expect(parsed.remindTime).toBeNull();
  });

  it("drops a malformed time but keeps the date", () => {
    const parsed = interpretModelReply(
      reply({ title: "Сделать", remindDate: "2026-09-24", remindTime: "25:00" }),
      today,
    );
    expect(parsed).toMatchObject({ remindDate: "2026-09-24", remindTime: null });
  });

  it("survives optional keys of the wrong type", () => {
    expect(
      interpretModelReply(reply({ title: "Сделать", description: 42, remindDate: false }), today),
    ).toEqual({ title: "Сделать", description: null, remindDate: null, remindTime: null });
  });

  it.each([
    ["not JSON", "Конечно! Вот задача: позвонить"],
    ["no title", reply({ description: "что-то" })],
    ["an empty title", reply({ title: " . " })],
  ])("refuses a reply with %s", (_label, content) => {
    expect(() => interpretModelReply(content, today)).toThrow(UpstreamModelError);
  });
});

describe("createDictationParser", () => {
  it("checks the reply against the caller's today", async () => {
    const parse = createDictationParser(
      async () => JSON.stringify({ title: "Сделать", remindDate: "2026-09-23" }),
      async () => "some-model",
    );
    // 2026-09-23 is still today in UTC but already yesterday in Moscow.
    expect((await parse({ text: "x", timeZone: "UTC", now: NOW })).remindDate).toBe("2026-09-23");
    expect((await parse({ text: "x", timeZone: "Europe/Moscow", now: NOW })).remindDate).toBeNull();
  });
});

describe("createDictationParser's model", () => {
  it("asks which model to use on every parse, so a change applies at once", async () => {
    const complete = vi.fn(async () => JSON.stringify({ title: "Сделать" }));
    let chosen = "first-model";
    const parse = createDictationParser(complete, async () => chosen);

    await parse({ text: "x", timeZone: "UTC", now: NOW });
    chosen = "second-model";
    await parse({ text: "x", timeZone: "UTC", now: NOW });

    expect(complete.mock.calls.map((call) => (call as unknown[])[1])).toEqual([
      "first-model",
      "second-model",
    ]);
  });
});

describe("resolveDictationModel", () => {
  it("is the .env model until one is chosen in the app", async () => {
    settings.clear();
    expect(await resolveDictationModel("env-model")).toBe("env-model");
    settings.set("dictation.model", "chosen-model");
    expect(await resolveDictationModel("env-model")).toBe("chosen-model");
    settings.clear();
  });
});

describe("createOpenAiCompatibleClient", () => {
  const config = {
    baseUrl: "https://llm.example/v1",
    apiKey: "sk-test",
    model: "some-model",
    timeoutMs: 1000,
  };
  const ok = (body: unknown) => new Response(JSON.stringify(body), { status: 200 });

  it("sends the chat-completions request every provider on the list understands", async () => {
    const fetchMock = vi.fn(async () =>
      ok({ choices: [{ message: { content: '{"title":"X"}' } }] }),
    );
    const complete = createOpenAiCompatibleClient(config, fetchMock as unknown as typeof fetch);

    await expect(complete([{ role: "user", content: "hi" }], "some-model")).resolves.toBe(
      '{"title":"X"}',
    );

    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe("https://llm.example/v1/chat/completions");
    expect((init.headers as Record<string, string>).authorization).toBe("Bearer sk-test");
    expect(JSON.parse(init.body as string)).toMatchObject({
      model: "some-model",
      messages: [{ role: "user", content: "hi" }],
      response_format: { type: "json_object" },
    });
  });

  it("sends no authorization header to a server that needs no key", async () => {
    const fetchMock = vi.fn(async () => ok({ choices: [{ message: { content: "{}" } }] }));
    await createOpenAiCompatibleClient(
      { ...config, apiKey: "" },
      fetchMock as unknown as typeof fetch,
    )([], "m");
    const [, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(init.headers).not.toHaveProperty("authorization");
  });

  it.each([
    ["a network failure", async () => Promise.reject(new Error("ECONNREFUSED"))],
    ["an error status", async () => new Response("quota", { status: 429 })],
    ["a body that is not JSON", async () => new Response("<html>", { status: 200 })],
    ["a reply with no content", async () => ok({ choices: [] })],
  ])("turns %s into a 502", async (_label, impl) => {
    const complete = createOpenAiCompatibleClient(config, vi.fn(impl) as unknown as typeof fetch);
    await expect(complete([], "m")).rejects.toBeInstanceOf(UpstreamModelError);
  });
});

describe("loadLlmConfig", () => {
  it("is off when nothing is set", () => {
    expect(loadLlmConfig({})).toBeNull();
  });

  it("reads a full configuration and trims the trailing slash", () => {
    expect(
      loadLlmConfig({
        LLM_BASE_URL: "https://api.deepseek.com/v1/",
        LLM_API_KEY: "sk-1",
        LLM_MODEL: "deepseek-chat",
      }),
    ).toEqual({
      baseUrl: "https://api.deepseek.com/v1",
      apiKey: "sk-1",
      model: "deepseek-chat",
      timeoutMs: 12_000,
    });
  });

  it("accepts a local server with no key", () => {
    expect(
      loadLlmConfig({ LLM_BASE_URL: "http://localhost:11434/v1", LLM_MODEL: "qwen3:14b" })?.apiKey,
    ).toBe("");
  });

  it("refuses half a configuration instead of quietly switching the feature off", () => {
    expect(() => loadLlmConfig({ LLM_MODEL: "deepseek-chat" })).toThrow(/LLM_BASE_URL/);
  });
});

describe("POST /dictation/parse", () => {
  let app: FastifyInstance;
  let offApp: FastifyInstance;
  let token: string;
  const parser = vi.fn<DictationParser>();

  beforeAll(async () => {
    const { buildApp } = await import("../src/app");
    app = await buildApp({
      authConfig,
      logger: false,
      dictation: { parser, defaultModel: "env-model" },
    });
    offApp = await buildApp({ authConfig, logger: false, dictation: null });
    const login = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: authConfig.email, password: TEST_PASSWORD },
    });
    token = (login.json() as { token: string }).token;
  });

  afterAll(async () => {
    await app?.close();
    await offApp?.close();
  });

  const post = (target: FastifyInstance, payload: unknown, withToken = true) =>
    target.inject({
      method: "POST",
      url: "/dictation/parse",
      headers: withToken ? { authorization: `Bearer ${token}` } : {},
      payload: payload as Record<string, unknown>,
    });

  it("answers with the parsed task and writes nothing", async () => {
    const parsed = {
      title: "Позвонить маме",
      description: null,
      remindDate: null,
      remindTime: null,
    };
    parser.mockResolvedValueOnce(parsed);

    const res = await post(app, { text: "  ну позвонить маме  ", timeZone: "Europe/Moscow" });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual(parsed);
    expect(parser).toHaveBeenLastCalledWith(
      expect.objectContaining({ text: "ну позвонить маме", timeZone: "Europe/Moscow" }),
    );
  });

  it("requires a session", async () => {
    const res = await post(app, { text: "x", timeZone: "UTC" }, false);
    expect(res.statusCode).toBe(401);
  });

  it.each([
    ["an empty text", { text: "  ", timeZone: "UTC" }],
    ["a text too long to be a dictation", { text: "а".repeat(4001), timeZone: "UTC" }],
    ["no time zone", { text: "x" }],
    ["a time zone that does not exist", { text: "x", timeZone: "Mars/Olympus" }],
  ])("refuses %s with a 400", async (_label, payload) => {
    expect((await post(app, payload)).statusCode).toBe(400);
  });

  it("answers 502 when the model fails", async () => {
    parser.mockRejectedValueOnce(new UpstreamModelError("status 500"));
    const res = await post(app, { text: "x", timeZone: "UTC" });
    expect(res.statusCode).toBe(502);
    expect(res.json()).toEqual({
      error: "UpstreamModelError",
      message: "Dictation model did not answer",
    });
  });

  it("answers 503 when no model is configured", async () => {
    const res = await post(offApp, { text: "x", timeZone: "UTC" });
    expect(res.statusCode).toBe(503);
  });

  describe("the model, from the app", () => {
    const model = (target: FastifyInstance, method: "GET" | "PUT", payload?: unknown) =>
      target.inject({
        method,
        url: "/dictation/model",
        headers: { authorization: `Bearer ${token}` },
        ...(payload === undefined ? {} : { payload: payload as Record<string, unknown> }),
      });

    beforeEach(() => settings.clear());

    it("is the .env model until one is chosen", async () => {
      const res = await model(app, "GET");
      expect(res.statusCode).toBe(200);
      expect(res.json()).toEqual({
        model: "env-model",
        defaultModel: "env-model",
        override: null,
      });
    });

    it("saves a choice, and reads it back", async () => {
      const put = await model(app, "PUT", { model: "  vendor/model-name:free " });
      expect(put.json()).toEqual({
        model: "vendor/model-name:free",
        defaultModel: "env-model",
        override: "vendor/model-name:free",
      });
      expect((await model(app, "GET")).json()).toMatchObject({ model: "vendor/model-name:free" });
    });

    it.each([
      ["null", null],
      ["an empty string", "  "],
      ["the .env model by name", "env-model"],
    ])("goes back to the .env model for %s", async (_label, value) => {
      await model(app, "PUT", { model: "vendor/other" });
      const res = await model(app, "PUT", { model: value });
      expect(res.json()).toEqual({ model: "env-model", defaultModel: "env-model", override: null });
      expect(settings.has("dictation.model")).toBe(false);
    });

    it.each([
      ["a sentence", "поставь самую умную"],
      ["no key at all", undefined],
    ])("refuses %s with a 400", async (_label, value) => {
      const res = await model(app, "PUT", value === undefined ? {} : { model: value });
      expect(res.statusCode).toBe(400);
    });

    it("answers 503 on both when no model is configured", async () => {
      expect((await model(offApp, "GET")).statusCode).toBe(503);
      expect((await model(offApp, "PUT", { model: "x" })).statusCode).toBe(503);
    });
  });
});
