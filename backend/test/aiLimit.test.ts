import { describe, it, expect, vi, beforeEach } from "vitest";

const prismaMock = vi.hoisted(() => ({
  aiUsage: { upsert: vi.fn() },
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));

// Belt and braces, as in the other tests that mock the client.
process.env.DATABASE_URL ??= "postgresql://placeholder:placeholder@localhost:5432/placeholder";

import {
  AiLimitError,
  DEFAULT_AI_DAILY_LIMIT,
  consumeAiQuota,
  loadAiDailyLimit,
  utcDay,
} from "../src/lib/aiLimit";

describe("loadAiDailyLimit", () => {
  it("defaults to 50 when unset or blank", () => {
    expect(DEFAULT_AI_DAILY_LIMIT).toBe(50);
    expect(loadAiDailyLimit({})).toBe(50);
    expect(loadAiDailyLimit({ AI_DAILY_LIMIT: "" })).toBe(50);
    expect(loadAiDailyLimit({ AI_DAILY_LIMIT: "   " })).toBe(50);
  });

  it("reads a positive integer", () => {
    expect(loadAiDailyLimit({ AI_DAILY_LIMIT: "5" })).toBe(5);
    expect(loadAiDailyLimit({ AI_DAILY_LIMIT: " 120 " })).toBe(120);
  });

  it("falls back to the default for anything else", () => {
    for (const bad of ["0", "-3", "2.5", "abc", "10x", "NaN", "Infinity"]) {
      expect(loadAiDailyLimit({ AI_DAILY_LIMIT: bad }), bad).toBe(50);
    }
  });
});

describe("utcDay", () => {
  it("is the UTC calendar date", () => {
    expect(utcDay(new Date("2026-09-29T00:00:00Z"))).toBe("2026-09-29");
    expect(utcDay(new Date("2026-09-29T23:59:59.999Z"))).toBe("2026-09-29");
  });

  it("does not follow the local time zone", () => {
    // 23:30 at UTC-5 is already the next day in UTC.
    expect(utcDay(new Date("2026-09-29T23:30:00-05:00"))).toBe("2026-09-30");
  });
});

describe("consumeAiQuota", () => {
  const now = new Date("2026-09-29T12:00:00Z");

  /** A counter that behaves like the real upsert-and-increment. */
  function useCounter(): void {
    let count = 0;
    prismaMock.aiUsage.upsert.mockImplementation(async () => ({ count: (count += 1) }));
  }

  beforeEach(() => {
    prismaMock.aiUsage.upsert.mockReset();
  });

  it("allows requests up to the limit", async () => {
    useCounter();
    for (let i = 0; i < 3; i += 1) {
      await expect(consumeAiQuota("user-a", 3, now)).resolves.toBeUndefined();
    }
  });

  it("throws AiLimitError with status 429 beyond the limit", async () => {
    useCounter();
    for (let i = 0; i < 3; i += 1) await consumeAiQuota("user-a", 3, now);

    const error = await consumeAiQuota("user-a", 3, now).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(AiLimitError);
    expect((error as AiLimitError).statusCode).toBe(429);
    expect((error as AiLimitError).message).toContain("3");
  });

  it("counts by user and UTC day", async () => {
    useCounter();
    await consumeAiQuota("user-a", 3, now);
    expect(prismaMock.aiUsage.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { userId_day: { userId: "user-a", day: "2026-09-29" } },
        create: { userId: "user-a", day: "2026-09-29", count: 1 },
        update: { count: { increment: 1 } },
      }),
    );
  });
});
