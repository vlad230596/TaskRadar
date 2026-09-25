import { describe, it, expect } from "vitest";
import {
  labelRemindDate,
  normalise,
  quantile,
  scoreSample,
  similarity,
  summarise,
} from "../src/domain/dictationReplay";

/*
 * Scoring a replay of the dictation dataset (F14). The numbers a model is kept
 * or dropped on, so each rule is pinned: what counts as the same title, where
 * the label's date comes from, and what a failed parse scores.
 */

const label = { title: "Позвонить в сервис", description: null, remindDate: "2026-10-02" };

describe("normalise", () => {
  it("ignores case, ё, whitespace runs and trailing punctuation", () => {
    expect(normalise("  Позвонить   в сервис… ")).toBe("позвонить в сервис");
    expect(normalise("Ещё раз.")).toBe(normalise("еще раз"));
    expect(normalise(null)).toBe("");
  });
});

describe("similarity", () => {
  it("is 1 for the same text and falls with the edits needed", () => {
    expect(similarity("Позвонить в сервис.", "позвонить в сервис")).toBe(1);
    expect(similarity("кот", "кит")).toBeCloseTo(2 / 3);
    expect(similarity("", null)).toBe(1);
  });
});

describe("labelRemindDate", () => {
  it("reads the stored UTC midnight as the calendar day, never through a local time", () => {
    expect(labelRemindDate(new Date("2026-10-02T00:00:00.000Z"))).toBe("2026-10-02");
    expect(labelRemindDate(null)).toBeNull();
  });
});

describe("scoreSample", () => {
  it("scores a matching answer", () => {
    expect(
      scoreSample(
        {
          title: "позвонить в сервис.",
          description: null,
          remindDate: "2026-10-02",
          remindTime: null,
        },
        label,
      ),
    ).toEqual({
      ok: true,
      titleExact: true,
      titleSimilarity: 1,
      descriptionExact: true,
      remindExact: true,
    });
  });

  it("tells a wrong reminder and a near-miss title apart from a match", () => {
    const score = scoreSample(
      { title: "Позвонить в автосервис", description: null, remindDate: null, remindTime: null },
      label,
    );
    expect(score).toMatchObject({ ok: true, titleExact: false, remindExact: false });
    expect(score.titleSimilarity).toBeGreaterThan(0.8);
  });

  it("scores a failed parse as zero on everything", () => {
    expect(scoreSample(null, label)).toEqual({
      ok: false,
      titleExact: false,
      titleSimilarity: 0,
      descriptionExact: false,
      remindExact: false,
    });
  });
});

describe("summarise and quantile", () => {
  it("averages the scores into rates", () => {
    const hit = scoreSample(
      {
        title: "Позвонить в сервис",
        description: null,
        remindDate: "2026-10-02",
        remindTime: null,
      },
      label,
    );
    expect(summarise([hit, scoreSample(null, label)])).toMatchObject({
      samples: 2,
      okRate: 0.5,
      titleExactRate: 0.5,
      remindExactRate: 0.5,
    });
    expect(summarise([]).samples).toBe(0);
  });

  it("takes the nearest-rank quantile", () => {
    expect(quantile([300, 100, 200, 400], 0.5)).toBe(200);
    expect(quantile([300, 100, 200, 400], 0.95)).toBe(400);
    expect(quantile([], 0.5)).toBe(0);
  });
});
