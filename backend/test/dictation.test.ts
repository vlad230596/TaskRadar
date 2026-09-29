import { describe, it, expect, beforeAll, afterAll, beforeEach, vi } from "vitest";
import type { FastifyInstance } from "fastify";
import { OWNER_SUBJECT, type AuthConfig } from "../src/lib/authConfig";
import { inMemoryUsers, tokenFor, USER_A, USER_B } from "./support/users";
import {
  buildDictationMessages,
  createDictationParser,
  interpretModelReply,
  localDate,
  DICTATION_PROMPT_VERSION,
  type DictationTrace,
  type DictationParser,
} from "../src/domain/dictation";
import { createOpenAiCompatibleClient, UpstreamModelError } from "../src/lib/llmClient";
import { loadLlmConfig, streamTimeoutFor } from "../src/lib/llmConfig";
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
/** Rows written to `dictation_parses`, in order. */
const samples = vi.hoisted(() => [] as Record<string, unknown>[]);
/** `ai_usage` rows as `"userId|day" -> count`: what the daily limit reads and writes. */
const aiUsage = vi.hoisted(() => new Map<string, number>());
const prismaMock = vi.hoisted(() => ({
  aiUsage: {
    // The atomic upsert-and-increment `consumeAiQuota` relies on: answers the
    // count *after* this request, so the limit check sees what the real row would.
    upsert: vi.fn(
      async (args: { where: { userId_day: { userId: string; day: string } } }) => {
        const { userId, day } = args.where.userId_day;
        const count = (aiUsage.get(`${userId}|${day}`) ?? 0) + 1;
        aiUsage.set(`${userId}|${day}`, count);
        return { count };
      },
    ),
  },
  dictationParse: {
    create: vi.fn(async (args: { data: Record<string, unknown> }) => {
      samples.push(args.data);
      return { id: `dp-${samples.length}` };
    }),
  },
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

/** bcrypt hash of the test password at cost 4 (see test/support/users.ts). */
const TEST_HASH = "$2b$04$zV5VFEALedx8Rfd/ucwUSOrHYSSr8xveuActiCTdzOmCsBSDTbYXO";

const authConfig: AuthConfig = {
  email: "owner@example.com",
  passwordHash: TEST_HASH,
  jwtSecret: "test-jwt-secret-".repeat(4),
  cookieSecure: false,
};

/**
 * The users store the route tests pass to `buildApp`: USER_A and USER_B, and
 * the server's owner (`OWNER_SUBJECT`), who is not either of them -- the model
 * setting checks the id, and a token for it is signed directly.
 */
function usersWithOwner() {
  const base = inMemoryUsers();
  return { ...base, isActive: async (id: string) => id === OWNER_SUBJECT || base.isActive(id) };
}

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
    expect((await parse({ text: "x", timeZone: "UTC", now: NOW })).result?.remindDate).toBe(
      "2026-09-23",
    );
    expect(
      (await parse({ text: "x", timeZone: "Europe/Moscow", now: NOW })).result?.remindDate,
    ).toBeNull();
  });

  it("traces a success: the raw reply, the model, the prompt and the time", async () => {
    const reply = '{"title":"сделать."}';
    let now = 1000;
    const parse = createDictationParser(
      async () => {
        now += 1234;
        return reply;
      },
      async () => "some-model",
      () => now,
    );

    expect(await parse({ text: "x", timeZone: "UTC", now: NOW })).toEqual({
      model: "some-model",
      promptVersion: DICTATION_PROMPT_VERSION,
      // As received -- the tidying happens in `result`, and a prompt is worked
      // on by reading what the model actually said.
      rawReply: reply,
      result: { title: "Сделать", description: null, remindDate: null, remindTime: null },
      error: null,
      durationMs: 1234,
    });
  });

  it("reports its stages, and passes the budget and the signal to the model call", async () => {
    const stages: unknown[] = [];
    const complete = vi.fn(async () => JSON.stringify({ title: "Сделать" }));
    const signal = new AbortController().signal;
    const parse = createDictationParser(complete, async () => "some-model");

    await parse(
      { text: "x", timeZone: "UTC", now: NOW },
      { onStage: (stage) => stages.push(stage), timeoutMs: 40_000, signal },
    );

    expect(stages).toEqual([
      { stage: "model_started", model: "some-model" },
      { stage: "model_done", durationMs: expect.any(Number) },
      { stage: "validated" },
    ]);
    expect((complete.mock.calls[0] as unknown[])[2]).toEqual({ timeoutMs: 40_000, signal });
  });

  it("does not report a reply it could not use as validated", async () => {
    const stages: string[] = [];
    const parse = createDictationParser(
      async () => "не JSON",
      async () => "m",
    );
    await parse(
      { text: "x", timeZone: "UTC", now: NOW },
      { onStage: ({ stage }) => stages.push(stage) },
    );
    expect(stages).toEqual(["model_started", "model_done"]);
  });

  it("traces a failure instead of throwing, keeping what did arrive", async () => {
    const unusable = createDictationParser(
      async () => "Конечно! Вот задача",
      async () => "m",
    );
    expect(await unusable({ text: "x", timeZone: "UTC", now: NOW })).toMatchObject({
      rawReply: "Конечно! Вот задача",
      result: null,
      error: "reply content is not JSON",
    });

    const silent = createDictationParser(
      async () => Promise.reject(new UpstreamModelError("status 429")),
      async () => "m",
    );
    expect(await silent({ text: "x", timeZone: "UTC", now: NOW })).toMatchObject({
      rawReply: null,
      result: null,
      error: "status 429",
    });
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

  it("lets one call take longer than the configured timeout", async () => {
    const fetchMock = vi.fn(
      async (_url: string, init: RequestInit) =>
        new Promise<Response>((resolve, reject) => {
          const timer = setTimeout(
            () => resolve(ok({ choices: [{ message: { content: "{}" } }] })),
            60,
          );
          init.signal?.addEventListener("abort", () => {
            clearTimeout(timer);
            reject(new Error("aborted"));
          });
        }),
    );
    const complete = createOpenAiCompatibleClient(
      { ...config, timeoutMs: 20 },
      fetchMock as unknown as typeof fetch,
    );

    await expect(complete([], "m")).rejects.toMatchObject({
      reason: expect.stringMatching(/request failed/),
    });
    await expect(complete([], "m", { timeoutMs: 500 })).resolves.toBe("{}");
  });

  it("gives up when the caller goes away, and says that is why", async () => {
    const fetchMock = vi.fn(
      async (_url: string, init: RequestInit) =>
        new Promise<Response>((_resolve, reject) => {
          init.signal?.addEventListener("abort", () => reject(new Error("aborted")));
        }),
    );
    const complete = createOpenAiCompatibleClient(config, fetchMock as unknown as typeof fetch);
    const gone = new AbortController();

    const call = complete([], "m", { signal: gone.signal });
    gone.abort();
    await expect(call).rejects.toMatchObject({ reason: "cancelled by the client" });
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
      streamTimeoutMs: 90_000,
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

describe("streamTimeoutFor", () => {
  const config = {
    baseUrl: "https://llm.example/v1",
    apiKey: "",
    model: "m",
    timeoutMs: 12_000,
    streamTimeoutMs: 90_000,
  };

  it("is the one-shot budget for a short dictation, and grows with a long one", () => {
    expect(streamTimeoutFor(config, 0)).toBe(12_000);
    expect(streamTimeoutFor(config, 3000)).toBe(42_000);
  });

  it("stops at the cap: ten minutes of speech must not wait forever either", () => {
    expect(streamTimeoutFor(config, 12_000)).toBe(90_000);
  });
});

describe("POST /dictation/parse", () => {
  let app: FastifyInstance;
  let offApp: FastifyInstance;
  /** A server whose users get two AI requests a day. */
  let limitedApp: FastifyInstance;
  /** USER_A's token: who every test acts as unless it says otherwise. */
  let token: string;
  let tokenB: string;
  let ownerToken: string;
  const parser = vi.fn<DictationParser>();
  const streamTimeoutMs = vi.fn((textLength: number) => 10_000 + textLength);

  beforeAll(async () => {
    const { buildApp } = await import("../src/app");
    const users = usersWithOwner();
    app = await buildApp({
      authConfig,
      logger: false,
      users,
      dictation: { parser, defaultModel: "env-model", streamTimeoutMs },
      dictationHeartbeatMs: 20,
    });
    offApp = await buildApp({ authConfig, logger: false, users, dictation: null });
    limitedApp = await buildApp({
      authConfig,
      logger: false,
      users,
      aiDailyLimit: 2,
      dictation: { parser, defaultModel: "env-model", streamTimeoutMs },
      dictationHeartbeatMs: 20,
    });
    token = await tokenFor(app, USER_A.email);
    tokenB = await tokenFor(app, USER_B.email);
    // All apps share one JWT secret (from authConfig), so this works on each.
    ownerToken = app.jwt.sign({ sub: OWNER_SUBJECT });
  });

  afterAll(async () => {
    await app?.close();
    await offApp?.close();
    await limitedApp?.close();
  });

  const post = (target: FastifyInstance, payload: unknown, withToken = true, bearer = token) =>
    target.inject({
      method: "POST",
      url: "/dictation/parse",
      headers: withToken ? { authorization: `Bearer ${bearer}` } : {},
      payload: payload as Record<string, unknown>,
    });

  const traceOf = (overrides: Partial<DictationTrace>): DictationTrace => ({
    model: "env-model",
    promptVersion: DICTATION_PROMPT_VERSION,
    rawReply: '{"title":"Позвонить маме"}',
    result: { title: "Позвонить маме", description: null, remindDate: null, remindTime: null },
    error: null,
    durationMs: 812,
    ...overrides,
  });

  beforeEach(() => {
    samples.length = 0;
    aiUsage.clear();
    prismaMock.aiUsage.upsert.mockClear();
  });

  it("answers with the proposal and the id of the sample it kept", async () => {
    parser.mockResolvedValueOnce(traceOf({}));

    const res = await post(app, { text: "  ну позвонить маме  ", timeZone: "Europe/Moscow" });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      title: "Позвонить маме",
      description: null,
      remindDate: null,
      remindTime: null,
      parseId: "dp-1",
    });
    expect(parser.mock.lastCall![0]).toEqual(
      expect.objectContaining({ text: "ну позвонить маме", timeZone: "Europe/Moscow" }),
    );
  });

  it("keeps everything a replay needs in the sample", async () => {
    parser.mockResolvedValueOnce(traceOf({}));
    await post(app, { text: "ну позвонить маме", timeZone: "Europe/Moscow" });

    expect(samples).toHaveLength(1);
    expect(samples[0]).toMatchObject({
      inputText: "ну позвонить маме",
      timeZone: "Europe/Moscow",
      model: "env-model",
      promptVersion: DICTATION_PROMPT_VERSION,
      status: "ok",
      rawReply: '{"title":"Позвонить маме"}',
      result: { title: "Позвонить маме", description: null, remindDate: null, remindTime: null },
      error: null,
      durationMs: 812,
    });
    // The prompt's calendar is built from this moment, so a replay needs it.
    expect(samples[0]!.requestedAt).toBeInstanceOf(Date);
  });

  it("keeps the sample under the caller, whoever that is", async () => {
    parser.mockResolvedValueOnce(traceOf({}));
    parser.mockResolvedValueOnce(traceOf({}));

    await post(app, { text: "x", timeZone: "UTC" });
    await post(app, { text: "y", timeZone: "UTC" }, true, tokenB);

    expect(samples.map((sample) => sample.userId)).toEqual([USER_A.id, USER_B.id]);
  });

  it("still answers when the sample cannot be kept", async () => {
    parser.mockResolvedValueOnce(traceOf({}));
    prismaMock.dictationParse.create.mockRejectedValueOnce(new Error("db down"));

    const res = await post(app, { text: "x", timeZone: "UTC" });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ title: "Позвонить маме", parseId: null });
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

  it("answers 502 when the model fails, and keeps the failure as a sample", async () => {
    parser.mockResolvedValueOnce(
      traceOf({ rawReply: null, result: null, error: "status 500", durationMs: 12000 }),
    );
    const res = await post(app, { text: "x", timeZone: "UTC" });

    expect(res.statusCode).toBe(502);
    expect(res.json()).toEqual({
      error: "UpstreamModelError",
      message: "Dictation model did not answer",
    });
    // A model that times out is exactly what a comparison between models has
    // to count.
    expect(samples[0]).toMatchObject({ status: "failed", error: "status 500", durationMs: 12000 });
  });

  it("answers 503 when no model is configured", async () => {
    const res = await post(offApp, { text: "x", timeZone: "UTC" });
    expect(res.statusCode).toBe(503);
  });

  describe("the daily AI limit", () => {
    const streamOf = (target: FastifyInstance, bearer = token) =>
      target.inject({
        method: "POST",
        url: "/dictation/parse",
        headers: { authorization: `Bearer ${bearer}`, accept: "text/event-stream" },
        payload: { text: "x", timeZone: "UTC" },
      });

    it("answers 429 with a readable message once the day's requests are spent", async () => {
      parser.mockReset();
      parser.mockResolvedValue(traceOf({}));
      try {
        const answers = [];
        for (let i = 0; i < 3; i++) answers.push(await post(limitedApp, { text: "x", timeZone: "UTC" }));

        expect(answers.map((res) => res.statusCode)).toEqual([200, 200, 429]);
        expect((answers[2]!.json() as { message: string }).message).toMatch(/limit.*\(2\)/i);
        // The refused request never reached the model, and left no sample.
        expect(parser).toHaveBeenCalledTimes(2);
        expect(samples).toHaveLength(2);
      } finally {
        parser.mockReset();
      }
    });

    it("counts per user: a different one is unaffected", async () => {
      parser.mockResolvedValue(traceOf({}));
      try {
        for (let i = 0; i < 3; i++) await post(limitedApp, { text: "x", timeZone: "UTC" });

        const other = await post(limitedApp, { text: "x", timeZone: "UTC" }, true, tokenB);
        expect(other.statusCode).toBe(200);
      } finally {
        parser.mockReset();
      }
    });

    it("is not spent by a request refused for its body", async () => {
      for (let i = 0; i < 5; i++) {
        expect((await post(limitedApp, { text: " ", timeZone: "UTC" })).statusCode).toBe(400);
      }
      expect(prismaMock.aiUsage.upsert).not.toHaveBeenCalled();
    });

    it("is not spent when the feature is switched off", async () => {
      for (let i = 0; i < 3; i++) {
        expect((await post(offApp, { text: "x", timeZone: "UTC" })).statusCode).toBe(503);
      }
      expect(prismaMock.aiUsage.upsert).not.toHaveBeenCalled();
    });

    it("answers a plain HTTP 429 to the streaming variant too, before any event", async () => {
      parser.mockResolvedValue(traceOf({}));
      try {
        await streamOf(limitedApp);
        await streamOf(limitedApp);
        const refused = await streamOf(limitedApp);

        expect(refused.statusCode).toBe(429);
        expect(refused.headers["content-type"]).toMatch(/json/);
        expect(refused.payload).not.toContain("event:");
        expect((refused.json() as { message: string }).message).toMatch(/limit/i);
      } finally {
        parser.mockReset();
      }
    });
  });

  describe("as an event stream", () => {
    const postStream = (target: FastifyInstance, payload: unknown, bearer = token) =>
      target.inject({
        method: "POST",
        url: "/dictation/parse",
        headers: { authorization: `Bearer ${bearer}`, accept: "text/event-stream" },
        payload: payload as Record<string, unknown>,
      });

    /** The stream as `[event, data]` pairs, in the order they were written. */
    const eventsOf = (payload: string) =>
      payload
        .split("\n\n")
        .filter((block) => block.trim() !== "")
        .map((block) => {
          const lines = block.split("\n");
          const event = lines.find((line) => line.startsWith("event: "))!.slice(7);
          const data = JSON.parse(lines.find((line) => line.startsWith("data: "))!.slice(6));
          return [event, data] as [string, Record<string, unknown>];
        });
    const withoutHeartbeats = (events: [string, Record<string, unknown>][]) =>
      events.filter(([event]) => event !== "heartbeat");

    /** A parser that goes through its stages as the real one does. */
    const staged =
      (result: DictationTrace, waitMs = 0): DictationParser =>
      async (_input, hooks) => {
        hooks?.onStage?.({ stage: "model_started", model: result.model });
        await new Promise((resolve) => setTimeout(resolve, waitMs));
        hooks?.onStage?.({ stage: "model_done", durationMs: 5 });
        if (result.result !== null) hooks?.onStage?.({ stage: "validated" });
        return result;
      };

    it("says every stage, in order, and ends with the same payload as the JSON reply", async () => {
      parser.mockImplementationOnce(staged(traceOf({})));

      const res = await postStream(app, { text: "ну позвонить маме", timeZone: "Europe/Moscow" });

      expect(res.statusCode).toBe(200);
      expect(res.headers["content-type"]).toMatch(/^text\/event-stream/);
      // What keeps Caddy (and any nginx) from compressing or holding it back.
      expect(res.headers["cache-control"]).toContain("no-transform");
      expect(res.headers["x-accel-buffering"]).toBe("no");
      expect(withoutHeartbeats(eventsOf(res.payload))).toEqual([
        ["accepted", { kind: "task" }],
        ["model_started", { model: "env-model" }],
        ["model_done", { durationMs: 5 }],
        ["validated", {}],
        [
          "result",
          {
            title: "Позвонить маме",
            description: null,
            remindDate: null,
            remindTime: null,
            parseId: "dp-1",
          },
        ],
      ]);
      expect(samples).toHaveLength(1);
    });

    it("keeps saying it is alive while the model thinks", async () => {
      parser.mockImplementationOnce(staged(traceOf({}), 120));

      const events = eventsOf((await postStream(app, { text: "x", timeZone: "UTC" })).payload);
      const names = events.map(([event]) => event);

      const between = names.slice(names.indexOf("model_started"), names.indexOf("model_done"));
      expect(between.filter((name) => name === "heartbeat").length).toBeGreaterThanOrEqual(2);
      expect(names.at(-1)).toBe("result");
    });

    it("gives a long dictation a longer budget than the one-shot reply", async () => {
      parser.mockImplementationOnce(staged(traceOf({})));
      const text = "а".repeat(6000);

      const res = await postStream(app, { text, timeZone: "UTC" });

      expect(res.statusCode).toBe(200);
      expect(streamTimeoutMs).toHaveBeenLastCalledWith(6000);
      expect(parser.mock.lastCall![1]).toMatchObject({ timeoutMs: 16_000 });
      // The one-shot reply still refuses it: an old client could not wait.
      expect((await post(app, { text, timeZone: "UTC" })).statusCode).toBe(400);
    });

    it("ends with an error event when the model fails, and keeps the sample", async () => {
      parser.mockImplementationOnce(
        staged(traceOf({ rawReply: null, result: null, error: "status 500" })),
      );

      const res = await postStream(app, { text: "x", timeZone: "UTC" });

      expect(res.statusCode).toBe(200);
      const events = withoutHeartbeats(eventsOf(res.payload));
      expect(events.map(([event]) => event)).toEqual([
        "accepted",
        "model_started",
        "model_done",
        "error",
      ]);
      // The provider's reason stays in the dataset, as in the JSON reply.
      expect(events.at(-1)![1]).toEqual({
        code: "model_failed",
        message: "Dictation model did not answer",
      });
      expect(samples[0]).toMatchObject({ status: "failed", error: "status 500" });
    });

    it("turns anything unexpected into an error event rather than a cut connection", async () => {
      parser.mockRejectedValueOnce(new Error("bug"));

      const events = eventsOf((await postStream(app, { text: "x", timeZone: "UTC" })).payload);

      expect(withoutHeartbeats(events).at(-1)).toEqual([
        "error",
        { code: "internal", message: "Internal Server Error" },
      ]);
    });

    it("still answers what fails before the stream with an HTTP status", async () => {
      const bad = await postStream(app, { text: " ", timeZone: "UTC" });
      expect(bad.statusCode).toBe(400);
      expect(bad.headers["content-type"]).toMatch(/json/);

      expect(
        (await postStream(app, { text: "x", timeZone: "UTC", kind: "novel" })).statusCode,
      ).toBe(400);
      expect((await postStream(offApp, { text: "x", timeZone: "UTC" })).statusCode).toBe(503);
    });

    it("leaves the JSON reply as it was for a client that did not ask for a stream", async () => {
      parser.mockImplementationOnce(staged(traceOf({})));

      const res = await post(app, { text: "x", timeZone: "UTC", kind: "task" });

      expect(res.headers["content-type"]).toMatch(/^application\/json/);
      expect(res.json()).toMatchObject({ title: "Позвонить маме", parseId: "dp-1" });
      // The one-shot reply keeps the parser's own budget.
      expect(parser.mock.lastCall![1]).toBeUndefined();
    });
  });

  describe("the model, from the app", () => {
    // The setting is the owner's to change, so the writes below act as the owner
    // unless a test says otherwise; reading is open to every user.
    const model = (
      target: FastifyInstance,
      method: "GET" | "PUT",
      payload?: unknown,
      bearer = ownerToken,
    ) =>
      target.inject({
        method,
        url: "/dictation/model",
        headers: { authorization: `Bearer ${bearer}` },
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

    it("is readable by any user", async () => {
      const res = await model(app, "GET", undefined, token);
      expect(res.statusCode).toBe(200);
      expect(res.json()).toMatchObject({ model: "env-model" });
    });

    it("refuses a change from anyone but the owner, and stores nothing", async () => {
      for (const bearer of [token, tokenB]) {
        const res = await model(app, "PUT", { model: "vendor/other" }, bearer);
        expect(res.statusCode).toBe(403);
      }
      expect(settings.has("dictation.model")).toBe(false);
    });

    it("lets the owner change it, and every user then sees the new one", async () => {
      const put = await model(app, "PUT", { model: "vendor/other" });
      expect(put.statusCode).toBe(200);
      expect((await model(app, "GET", undefined, tokenB)).json()).toMatchObject({
        model: "vendor/other",
        override: "vendor/other",
      });
    });

    it("answers 503 on both when no model is configured", async () => {
      expect((await model(offApp, "GET")).statusCode).toBe(503);
      expect((await model(offApp, "PUT", { model: "x" })).statusCode).toBe(503);
    });
  });
});
