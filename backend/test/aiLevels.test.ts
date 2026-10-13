import { describe, it, expect } from "vitest";
import {
  AI_LEVEL_DEFAULT,
  AI_LEVEL_MAX,
  AI_LEVEL_MIN,
  LEVEL_RULES,
  cleanupRules,
  normaliseLevel,
} from "../src/domain/aiLevels";
import { buildDictationMessages } from "../src/domain/dictation";
import { buildNoteMessages, buildTaskTidyMessages } from "../src/domain/tidy";
import { parseDictationSchema } from "../src/schemas";

/*
 * The level changes how freely the wording may move; the rules against
 * inventing hold at every level.
 */

const input = (level?: number) => ({
  text: "текст",
  timeZone: "Europe/Moscow",
  now: new Date("2026-09-24T09:00:00Z"),
  level,
});

describe("levels", () => {
  it("has rules for every stop", () => {
    for (let level = AI_LEVEL_MIN; level <= AI_LEVEL_MAX; level++) {
      expect(LEVEL_RULES[level]?.length).toBeGreaterThan(0);
    }
  });

  it("normalises odd values to a level that exists", () => {
    expect(normaliseLevel(undefined)).toBe(AI_LEVEL_DEFAULT);
    expect(normaliseLevel(1.5)).toBe(AI_LEVEL_DEFAULT);
    expect(normaliseLevel(0)).toBe(AI_LEVEL_MIN);
    expect(normaliseLevel(99)).toBe(AI_LEVEL_MAX);
  });

  it("keeps the no-inventing rules at every level, and dates only where asked", () => {
    for (let level = AI_LEVEL_MIN; level <= AI_LEVEL_MAX; level++) {
      const rules = cleanupRules(level, { dates: true }).join("\n");
      expect(rules).toContain("НЕ добавляй фактов");
      expect(rules).toContain("НЕ добавляй дат");
    }
    expect(cleanupRules(2, { dates: false }).join("\n")).not.toContain("НЕ добавляй дат");
  });

  it("puts the chosen level into every prompt", () => {
    expect(buildTaskTidyMessages(input(1))[0]!.content).toContain("ЛЁГКАЯ");
    expect(buildNoteMessages(input(3))[0]!.content).toContain("СИЛЬНАЯ");
    expect(buildDictationMessages(input())[0]!.content).toContain("ОБЫЧНАЯ");
  });

  it("lets a strong note compress the wording, and keeps every fact", () => {
    const strong = buildNoteMessages(input(3))[0]!.content;
    expect(strong).toContain("формулировки можно сжимать");
    expect(buildNoteMessages(input(1))[0]!.content).toContain("не сокращай до пересказа");
  });
});

describe("the request", () => {
  const body = { text: "т", timeZone: "Europe/Moscow" };

  it("defaults the level for old clients", () => {
    expect(parseDictationSchema.parse(body).level).toBe(AI_LEVEL_DEFAULT);
  });

  it("refuses a level that does not exist", () => {
    expect(() => parseDictationSchema.parse({ ...body, level: AI_LEVEL_MAX + 1 })).toThrow();
    expect(() => parseDictationSchema.parse({ ...body, level: 1.5 })).toThrow();
  });
});
