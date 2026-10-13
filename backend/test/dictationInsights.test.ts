import { describe, it, expect, beforeAll, afterAll, beforeEach, vi } from "vitest";
import type { FastifyInstance } from "fastify";
import { OWNER_SUBJECT, type AuthConfig } from "../src/lib/authConfig";
import { inMemoryUsers, tokenFor, USER_A } from "./support/users";
import { computeStats, type StatsRow } from "../src/domain/aiStats";
import { levelRules, levelRulesVersion, LEVEL_RULES } from "../src/domain/aiLevels";
import type { DictationParser } from "../src/domain/dictation";

/*
 * The owner's statistics and prompts (14.10.2026): what counts as an answer
 * that landed, and editing what a level means.
 */

const settings = vi.hoisted(() => new Map<string, string>());
const rows = vi.hoisted(() => [] as Record<string, unknown>[]);
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
  dictationParse: { findMany: vi.fn(async () => rows) },
}));
vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
process.env.DATABASE_URL ??= "postgresql://placeholder:placeholder@localhost:5432/placeholder";

function row(overrides: Partial<StatsRow>): StatsRow {
  return {
    kind: "task_tidy",
    model: "a",
    promptVersion: "tidy-3",
    level: 2,
    status: "ok",
    durationMs: 1000,
    result: { title: "Позвонить", description: null },
    linkedAt: null,
    finalTitle: null,
    finalDescription: null,
    finalContent: null,
    ...overrides,
  };
}

describe("computeStats", () => {
  it("counts each model's answers, failures and mean time", () => {
    const stats = computeStats([
      row({ durationMs: 1000 }),
      row({ durationMs: 3000 }),
      row({ status: "failed", durationMs: 9000 }),
      row({ model: "b" }),
    ]);
    expect(stats.models).toEqual([
      { model: "a", total: 3, ok: 2, failed: 1, avgDurationMs: 2000 },
      { model: "b", total: 1, ok: 1, failed: 0, avgDurationMs: 1000 },
    ]);
  });

  it("splits a level's answers into saved as is, saved edited and not saved", () => {
    const linkedAt = new Date();
    const stats = computeStats([
      row({ linkedAt, finalTitle: " Позвонить ", finalDescription: null }),
      row({ linkedAt, finalTitle: "Позвонить маме", finalDescription: null }),
      row({}),
      row({ level: 3, linkedAt, finalTitle: "Позвонить" }),
      row({
        kind: "note",
        promptVersion: "note-3",
        result: { content: "Текст" },
        linkedAt,
        finalContent: "Текст",
      }),
    ]);
    expect(stats.levels).toEqual([
      {
        kind: "note",
        level: 2,
        promptVersion: "note-3",
        answered: 1,
        savedAsIs: 1,
        savedEdited: 0,
        notSaved: 0,
      },
      {
        kind: "task_tidy",
        level: 2,
        promptVersion: "tidy-3",
        answered: 3,
        savedAsIs: 1,
        savedEdited: 1,
        notSaved: 1,
      },
      {
        kind: "task_tidy",
        level: 3,
        promptVersion: "tidy-3",
        answered: 1,
        savedAsIs: 1,
        savedEdited: 0,
        notSaved: 0,
      },
    ]);
  });
});

const authConfig: AuthConfig = {
  email: "owner@example.com",
  passwordHash: "$2b$04$zV5VFEALedx8Rfd/ucwUSOrHYSSr8xveuActiCTdzOmCsBSDTbYXO",
  jwtSecret: "test-jwt-secret-".repeat(4),
  cookieSecure: false,
};

describe("the insights routes", () => {
  let app: FastifyInstance;
  let token: string;
  let ownerToken: string;

  beforeAll(async () => {
    const { buildApp } = await import("../src/app");
    const base = inMemoryUsers();
    app = await buildApp({
      authConfig,
      logger: false,
      users: { ...base, isActive: async (id: string) => id === OWNER_SUBJECT || base.isActive(id) },
      dictation: { parser: vi.fn<DictationParser>(), defaultModel: "env-model" },
    });
    token = await tokenFor(app, USER_A.email);
    ownerToken = app.jwt.sign({ sub: OWNER_SUBJECT });
  });

  afterAll(async () => {
    await app?.close();
  });

  beforeEach(() => {
    rows.length = 0;
  });

  const call = (method: "GET" | "PUT", url: string, bearer: string, payload?: unknown) =>
    app.inject({
      method,
      url,
      headers: { authorization: `Bearer ${bearer}` },
      ...(payload === undefined ? {} : { payload: payload as Record<string, unknown> }),
    });

  it("shows statistics and prompts to the owner only", async () => {
    expect((await call("GET", "/dictation/stats", token)).statusCode).toBe(403);
    expect((await call("GET", "/dictation/prompts", token)).statusCode).toBe(403);
    expect(
      (await call("PUT", "/dictation/prompts/levels/2", token, { rules: ["x"] })).statusCode,
    ).toBe(403);
  });

  it("answers the statistics for the period asked", async () => {
    rows.push(row({}) as unknown as Record<string, unknown>);
    const res = await call("GET", "/dictation/stats?days=7", ownerToken);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ days: 7, rows: 1, models: [{ model: "a", total: 1 }] });
  });

  it("shows every kind at every level, as the model reads it", async () => {
    const body = (await call("GET", "/dictation/prompts", ownerToken)).json() as {
      levels: { level: number; overridden: boolean }[];
      kinds: { kind: string; prompts: { level: number; system: string; user: string }[] }[];
    };
    expect(body.levels.map((l) => [l.level, l.overridden])).toEqual([
      [1, false],
      [2, false],
      [3, false],
    ]);
    expect(body.kinds.map((k) => k.kind)).toEqual(["task", "task_tidy", "note", "sandbox"]);
    const tidy = body.kinds.find((k) => k.kind === "task_tidy")!;
    expect(tidy.prompts[0]!.system).toContain("ЛЁГКАЯ");
    expect(tidy.prompts[0]!.user).toContain("<user_text>");
  });

  it("an edited level goes into the prompts and the version, and resets", async () => {
    const res = await call("PUT", "/dictation/prompts/levels/2", ownerToken, {
      rules: ["Сила обработки: МОЯ.", "- только запятые;"],
    });
    expect(res.statusCode).toBe(200);
    expect(levelRules(2)).toEqual(["Сила обработки: МОЯ.", "- только запятые;"]);
    expect(levelRulesVersion()).toMatch(/^\+lv[0-9a-z]+$/);
    const body = res.json() as { kinds: { version: string; prompts: { system: string }[] }[] };
    expect(body.kinds[1]!.version).toMatch(/^tidy-3\+lv/);
    expect(body.kinds[1]!.prompts[1]!.system).toContain("МОЯ");

    await call("PUT", "/dictation/prompts/levels/2", ownerToken, { rules: null });
    expect(levelRules(2)).toEqual(LEVEL_RULES[2]);
    expect(levelRulesVersion()).toBe("");
    expect(settings.size).toBe(0);
  });
});
