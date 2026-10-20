import { describe, it, expect, beforeAll, afterAll, beforeEach, vi } from "vitest";
import type { FastifyInstance } from "fastify";
import { OWNER_SUBJECT, type AuthConfig } from "../src/lib/authConfig";
import { inMemoryUsers, tokenFor, USER_A } from "./support/users";
import { DICTATION_PROMPT_VERSION, type DictationParser } from "../src/domain/dictation";
import type { RosterEntry } from "../src/domain/modelRoster";
import type { CompleteJson } from "../src/lib/llmClient";

/*
 * The parse route with a roster of models (14.10.2026): which models are
 * asked, what the stream says when several answer, what it costs, and who may
 * change the list.
 */

const samples = vi.hoisted(() => [] as Record<string, unknown>[]);
const usage = vi.hoisted(() => ({ count: 0 }));
const stored = vi.hoisted(() => [] as Record<string, unknown>[]);
const prismaMock = vi.hoisted(() => ({
  aiUsage: {
    upsert: vi.fn(async (args: { update: { count: { increment: number } } }) => {
      usage.count += args.update.count.increment;
      return { count: usage.count };
    }),
  },
  dictationParse: {
    create: vi.fn(async (args: { data: Record<string, unknown> }) => {
      samples.push(args.data);
      return { id: `dp-${samples.length}` };
    }),
  },
  llmModel: {
    findMany: vi.fn(async () => stored),
    deleteMany: vi.fn(async () => {
      stored.length = 0;
    }),
    create: vi.fn(async (args: { data: Record<string, unknown> }) => {
      stored.push({ id: `m-${stored.length + 1}`, ...emptyHealth, ...args.data });
    }),
    updateMany: vi.fn(async () => ({ count: 1 })),
  },
  appSetting: { findUnique: vi.fn(async () => null) },
  $transaction: vi.fn(async (fn: (tx: unknown) => Promise<unknown>) => fn(prismaMock)),
}));
vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
process.env.DATABASE_URL ??= "postgresql://placeholder:placeholder@localhost:5432/placeholder";

const emptyHealth = {
  enabled: true,
  autoDisabledAt: null,
  autoDisabledReason: null,
  consecutiveFailures: 0,
  failStreakStartedAt: null,
  lastSuccessAt: null,
  lastFailureAt: null,
};

const authConfig: AuthConfig = {
  email: "owner@example.com",
  passwordHash: "$2b$04$zV5VFEALedx8Rfd/ucwUSOrHYSSr8xveuActiCTdzOmCsBSDTbYXO",
  jwtSecret: "test-jwt-secret-".repeat(4),
  cookieSecure: false,
};

function entry(name: string, overrides: Partial<RosterEntry> = {}): RosterEntry {
  return {
    id: name,
    name,
    label: null,
    baseUrl: null,
    apiKeyEnv: null,
    temperature: null,
    ...emptyHealth,
    ...overrides,
  };
}

/** The roster the route reads, and what it recorded. */
let roster: RosterEntry[] = [];
const recorded: [string, boolean][] = [];
/** Models that fail when asked. */
const broken = new Set<string>();
/** How long each model takes, in ms. */
const delays = new Map<string, number>();

const parser: DictationParser = vi.fn(async (_input, hooks) => {
  const model = hooks?.target?.model ?? "env-model";
  hooks?.onStage?.({ stage: "model_started", model });
  await new Promise((resolve) => setTimeout(resolve, delays.get(model) ?? 0));
  const ok = !broken.has(model);
  return {
    model,
    promptVersion: DICTATION_PROMPT_VERSION,
    rawReply: ok ? "{}" : null,
    result: ok
      ? { title: `от ${model}`, description: null, remindDate: null, remindTime: null }
      : null,
    error: ok ? null : "down",
    category: ok ? undefined : "provider_down",
    durationMs: 1,
  };
});

describe("the parse route with a roster", () => {
  let app: FastifyInstance;
  let token: string;
  let ownerToken: string;

  beforeAll(async () => {
    const { buildApp } = await import("../src/app");
    const base = inMemoryUsers();
    const users = {
      ...base,
      isActive: async (id: string) => id === OWNER_SUBJECT || base.isActive(id),
    };
    app = await buildApp({
      authConfig,
      logger: false,
      users,
      dictationHeartbeatMs: 1000,
      dictation: {
        parser,
        defaultModel: "env-model",
        defaultBaseUrl: "https://env.example/v1",
        roster: {
          read: async () => roster,
          record: async (e, ok) => {
            recorded.push([e.name, ok]);
          },
          clientFor: () => vi.fn<CompleteJson>(),
        },
      },
    });
    token = await tokenFor(app, USER_A.email);
    ownerToken = app.jwt.sign({ sub: OWNER_SUBJECT });
  });

  afterAll(async () => {
    await app?.close();
  });

  beforeEach(() => {
    samples.length = 0;
    recorded.length = 0;
    broken.clear();
    delays.clear();
    usage.count = 0;
    stored.length = 0;
  });

  const parse = (payload: Record<string, unknown>, stream = false) =>
    app.inject({
      method: "POST",
      url: "/dictation/parse",
      headers: {
        authorization: `Bearer ${token}`,
        ...(stream ? { accept: "text/event-stream" } : {}),
      },
      payload: { text: "купить хлеб", timeZone: "UTC", ...payload },
    });

  const eventsOf = (payload: string) =>
    payload
      .split("\n\n")
      .filter((block) => block.trim() !== "")
      .map((block) => {
        const lines = block.split("\n");
        return [
          lines.find((line) => line.startsWith("event: "))!.slice(7),
          JSON.parse(lines.find((line) => line.startsWith("data: "))!.slice(6)),
        ] as [string, Record<string, unknown>];
      })
      .filter(([event]) => event !== "heartbeat");

  it("falls back to the next model when the first fails, and says who answered", async () => {
    roster = [entry("a", { label: "Модель А" }), entry("b", { label: "Модель Б" })];
    broken.add("a");

    const res = await parse({});

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ title: "от b", model: "b", modelLabel: "Модель Б" });
    expect(recorded).toEqual([
      ["a", false],
      ["b", true],
    ]);
    // One dataset row per model asked.
    expect(samples.map((row) => row.model)).toEqual(["a", "b"]);
    expect(usage.count).toBe(1);
  });

  it("races a top model that failed lately against the one that answered last", async () => {
    roster = [
      entry("top", { consecutiveFailures: 1, lastFailureAt: new Date() }),
      entry("good", { lastSuccessAt: new Date() }),
    ];
    delays.set("top", 30);

    const res = await parse({});

    expect(res.json()).toMatchObject({ model: "good" });
    // The slower top one was asked too, and is left to finish.
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(recorded).toEqual([
      ["good", true],
      ["top", true],
    ]);
    expect(usage.count).toBe(1);
  });

  it("sends to several: a candidate per model as it answers, then the first as the result", async () => {
    roster = [entry("slow"), entry("fast"), entry("third")];
    delays.set("slow", 30);

    const res = await parse({ multi: true }, true);
    const events = eventsOf(res.payload);

    const candidates = events.filter(([event]) => event === "candidate");
    expect(candidates.map(([, data]) => data.model)).toEqual(["fast", "slow"]);
    expect(candidates[0]![1]).toMatchObject({
      modelLabel: "fast",
      result: { title: "от fast", parseId: "dp-1", model: "fast" },
    });
    expect(events.at(-1)).toEqual(["result", expect.objectContaining({ model: "fast" })]);
    // Two models asked, two requests of the day's allowance.
    expect(usage.count).toBe(2);
  });

  it("says which model failed in send-to-several, and still answers with the other", async () => {
    roster = [entry("a"), entry("b")];
    broken.add("a");

    const events = eventsOf((await parse({ multi: true }, true)).payload);

    expect(events).toContainEqual([
      "candidate_failed",
      { model: "a", modelLabel: "a", cause: "provider_down" },
    ]);
    expect(events.at(-1)).toEqual(["result", expect.objectContaining({ model: "b" })]);
  });

  it("ends with an error when every model failed", async () => {
    roster = [entry("a"), entry("b")];
    broken.add("a");
    broken.add("b");

    const res = await parse({});
    expect(res.statusCode).toBe(502);
  });

  describe("the list, from the app", () => {
    const get = (bearer: string) =>
      app.inject({
        method: "GET",
        url: "/dictation/models",
        headers: { authorization: `Bearer ${bearer}` },
      });
    const put = (bearer: string, models: unknown[]) =>
      app.inject({
        method: "PUT",
        url: "/dictation/models",
        headers: { authorization: `Bearer ${bearer}` },
        payload: { models },
      });

    it("lets only the owner change it", async () => {
      const res = await put(token, [{ name: "x", enabled: true }]);
      expect(res.statusCode).toBe(403);
    });

    it("stores the owner's list in order, and shows where each key comes from", async () => {
      process.env.LLM_SECOND_KEY = "secret";
      const res = await put(ownerToken, [
        { name: "deepseek-chat", label: "DeepSeek", enabled: true },
        {
          name: "qwen",
          baseUrl: "https://qwen.example/v1/",
          apiKeyEnv: "LLM_SECOND_KEY",
          enabled: true,
        },
      ]);
      expect(res.statusCode).toBe(200);
      const body = res.json() as { models: Record<string, unknown>[] };
      expect(body.models.map((m) => [m.name, m.baseUrl, m.keyPresent])).toEqual([
        ["deepseek-chat", null, true],
        ["qwen", "https://qwen.example/v1", true],
      ]);
      expect(JSON.stringify(body)).not.toContain("secret");
    });

    it("hides providers and keys from everyone but the owner", async () => {
      stored.push({
        id: "m-1",
        position: 0,
        name: "a",
        label: null,
        baseUrl: "https://x",
        apiKeyEnv: "LLM_X",
        ...emptyHealth,
      });
      const body = (await get(token)).json() as { models: Record<string, unknown>[] };
      expect(body.models[0]).toMatchObject({ name: "a", status: "ok" });
      expect(body.models[0]).not.toHaveProperty("baseUrl");
      expect(body.models[0]).not.toHaveProperty("apiKeyEnv");
    });

    it("keeps a model's temperature when an older app sends the list without it", async () => {
      stored.push({ id: "m-1", position: 0, name: "a", temperature: 0.5, ...emptyHealth });
      prismaMock.llmModel.updateMany.mockClear();

      await put(ownerToken, [{ id: "m-1", name: "a", enabled: true }]);
      const kept = prismaMock.llmModel.updateMany.mock.calls[0] as unknown as [
        { data: Record<string, unknown> },
      ];
      expect(kept[0].data).not.toHaveProperty("temperature");

      await put(ownerToken, [{ id: "m-1", name: "a", temperature: null, enabled: true }]);
      const reset = prismaMock.llmModel.updateMany.mock.calls[1] as unknown as [
        { data: Record<string, unknown> },
      ];
      expect(reset[0].data).toMatchObject({ temperature: null });
    });

    it("refuses a temperature no provider accepts", async () => {
      const res = await put(ownerToken, [{ name: "x", temperature: 5, enabled: true }]);
      expect(res.statusCode).toBe(400);
    });

    it("refuses a key variable outside LLM_, so no other secret can be sent anywhere", async () => {
      const res = await put(ownerToken, [{ name: "x", apiKeyEnv: "JWT_SECRET", enabled: true }]);
      expect(res.statusCode).toBe(400);
    });
  });
});
