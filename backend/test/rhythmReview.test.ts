import { describe, it, expect } from "vitest";
import { computeRhythm, rhythmStats } from "../src/domain/rhythm";
import {
  countByProject,
  nextReviewMoment,
  previousMonth,
  recentWeeks,
  REVIEWS_INTRODUCED_AT,
  reviewDue,
  reviewPeriod,
  weekStartOf,
} from "../src/domain/review";

/*
 * The rhythm of a project and the weekly review (design/today-history-contract.md):
 * pure rules, tested as tables of dates.
 */

const DAY = 86_400_000;
const NOW = new Date("2026-11-27T12:00:00.000Z"); // a Friday
const ago = (days: number) => new Date(NOW.getTime() - days * DAY);
const MSK = 180;

describe("rhythmStats", () => {
  it("counts open tasks, closings of the last 14 days and the latest closing", () => {
    const stats = rhythmStats(
      [
        { status: "pending", doneAt: null },
        { status: "blocked", doneAt: null },
        { status: "done", doneAt: ago(1) },
        { status: "done", doneAt: ago(13.9) },
        { status: "done", doneAt: ago(15) },
        { status: "done", doneAt: null },
      ],
      NOW,
    );
    expect(stats).toEqual({ closedInWindow: 2, open: 2, lastClosedAt: ago(1) });
  });
});

describe("computeRhythm", () => {
  const project = (closed: number | null, max: number | null) => ({
    rhythmClosedPerWeek: closed,
    rhythmMaxOpen: max,
    createdAt: ago(60),
  });

  it("is null when neither number is set", () => {
    expect(computeRhythm(project(null, null), { closedInWindow: 0, open: 99, lastClosedAt: null }, NOW)).toBeNull();
  });

  it("signals silence when the two-week average is under the norm", () => {
    const rhythm = computeRhythm(project(3, null), { closedInWindow: 4, open: 5, lastClosedAt: ago(22) }, NOW);
    expect(rhythm).toEqual({
      closedPerWeek: 3,
      maxOpen: null,
      closedAvg: 2,
      open: 5,
      lastClosedAt: ago(22),
      silentWeeks: 3,
      signal: "silence",
    });
  });

  it("is quiet at or above the norm and under the ceiling", () => {
    const rhythm = computeRhythm(project(2, 20), { closedInWindow: 4, open: 20, lastClosedAt: ago(1) }, NOW);
    expect(rhythm?.signal).toBeNull();
    expect(rhythm?.silentWeeks).toBe(0);
  });

  it("signals overflow above the ceiling, and overflow wins over silence", () => {
    expect(
      computeRhythm(project(null, 20), { closedInWindow: 0, open: 24, lastClosedAt: null }, NOW)?.signal,
    ).toBe("overflow");
    expect(
      computeRhythm(project(5, 20), { closedInWindow: 0, open: 24, lastClosedAt: null }, NOW)?.signal,
    ).toBe("overflow");
  });

  it("counts silent weeks from the project's creation when nothing was ever closed", () => {
    expect(
      computeRhythm(project(1, null), { closedInWindow: 0, open: 1, lastClosedAt: null }, NOW)?.silentWeeks,
    ).toBe(8);
  });
});

describe("nextReviewMoment", () => {
  const monday9 = { reviewWeekday: 1, reviewTime: "09:00" };

  it("finds the next local Monday 09:00 after a moment", () => {
    // Friday 27.11 15:00 MSK -> Monday 30.11 09:00 MSK = 06:00 UTC.
    expect(nextReviewMoment(NOW, monday9, MSK).toISOString()).toBe("2026-11-30T06:00:00.000Z");
    expect(nextReviewMoment(NOW, monday9, 0).toISOString()).toBe("2026-11-30T09:00:00.000Z");
  });

  it("is strictly after: the review moment itself moves to the next week", () => {
    const moment = new Date("2026-11-30T06:00:00.000Z");
    expect(nextReviewMoment(moment, monday9, MSK).toISOString()).toBe("2026-12-07T06:00:00.000Z");
  });

  it("takes later the same day, and any weekday", () => {
    const mondayMorning = new Date("2026-11-30T04:00:00.000Z"); // 07:00 MSK
    expect(nextReviewMoment(mondayMorning, monday9, MSK).toISOString()).toBe("2026-11-30T06:00:00.000Z");
    const sunday20 = { reviewWeekday: 7, reviewTime: "20:00" };
    expect(nextReviewMoment(NOW, sunday20, MSK).toISOString()).toBe("2026-11-29T17:00:00.000Z");
  });
});

describe("reviewDue", () => {
  const user = { reviewWeekday: 1, reviewTime: "09:00", createdAt: new Date("2026-01-01T00:00:00.000Z") };

  it("with no review yet, waits for the first moment after reviews were introduced", () => {
    expect(REVIEWS_INTRODUCED_AT.toISOString()).toBe("2026-11-27T00:00:00.000Z");
    const before = reviewDue(user, null, NOW, MSK);
    expect(before).toEqual({ due: false, nextAt: new Date("2026-11-30T06:00:00.000Z"), lastAt: null });
    const after = reviewDue(user, null, new Date("2026-11-30T06:00:00.000Z"), MSK);
    expect(after.due).toBe(true);
  });

  it("for a user created later, counts from their creation", () => {
    const fresh = { ...user, createdAt: new Date("2026-12-08T10:00:00.000Z") };
    expect(reviewDue(fresh, null, new Date("2026-12-09T00:00:00.000Z"), MSK).nextAt.toISOString()).toBe(
      "2026-12-14T06:00:00.000Z",
    );
  });

  it("is due once the moment after the last review has come, and stays due (no stacking)", () => {
    const last = { periodEnd: new Date("2026-11-30T07:00:00.000Z") };
    const soon = reviewDue(user, last, new Date("2026-12-06T00:00:00.000Z"), MSK);
    expect(soon).toEqual({
      due: false,
      nextAt: new Date("2026-12-07T06:00:00.000Z"),
      lastAt: last.periodEnd,
    });
    const weeksLater = reviewDue(user, last, new Date("2026-12-25T00:00:00.000Z"), MSK);
    expect(weeksLater.due).toBe(true);
    expect(weeksLater.nextAt.toISOString()).toBe("2026-12-07T06:00:00.000Z");
  });
});

describe("reviewPeriod", () => {
  it("covers the week before for the first review, which is not monthly", () => {
    expect(reviewPeriod(null, NOW, MSK)).toEqual({ periodStart: ago(7), periodEnd: NOW, monthly: false });
  });

  it("starts where the last review ended, however long ago", () => {
    const last = { periodEnd: ago(20) };
    expect(reviewPeriod(last, NOW, MSK)).toMatchObject({ periodStart: ago(20), periodEnd: NOW });
  });

  it("is monthly when the last review was in another local month", () => {
    const now = new Date("2026-12-07T06:30:00.000Z");
    expect(reviewPeriod({ periodEnd: new Date("2026-11-30T06:30:00.000Z") }, now, MSK).monthly).toBe(true);
    expect(reviewPeriod({ periodEnd: new Date("2026-12-01T06:30:00.000Z") }, now, MSK).monthly).toBe(false);
    // 30.11 21:30 UTC is already 1.12 in Moscow: same month as the 7th there.
    const lateNov = { periodEnd: new Date("2026-11-30T21:30:00.000Z") };
    expect(reviewPeriod(lateNov, now, MSK).monthly).toBe(false);
    expect(reviewPeriod(lateNov, now, 0).monthly).toBe(true);
  });
});

describe("previousMonth", () => {
  it("is the local calendar month before, as instants", () => {
    expect(previousMonth(new Date("2026-12-07T06:00:00.000Z"), MSK)).toEqual({
      month: "2026-11",
      start: new Date("2026-10-31T21:00:00.000Z"),
      end: new Date("2026-11-30T21:00:00.000Z"),
    });
    expect(previousMonth(new Date("2027-01-04T06:00:00.000Z"), 0).month).toBe("2026-12");
  });
});

describe("weeks", () => {
  it("starts the owner's week on Monday", () => {
    expect(weekStartOf(NOW, MSK)).toBe("2026-11-23");
    // Sunday 29.11 22:00 UTC is Monday 30.11 01:00 in Moscow.
    expect(weekStartOf(new Date("2026-11-29T22:00:00.000Z"), MSK)).toBe("2026-11-30");
    expect(weekStartOf(new Date("2026-11-29T22:00:00.000Z"), 0)).toBe("2026-11-23");
  });

  it("lists the recent weeks newest first, each from local Monday midnight", () => {
    const weeks = recentWeeks(NOW, MSK, 3);
    expect(weeks.map((w) => w.start)).toEqual(["2026-11-23", "2026-11-16", "2026-11-09"]);
    expect(weeks[0]).toEqual({
      start: "2026-11-23",
      from: new Date("2026-11-22T21:00:00.000Z"),
      to: new Date("2026-11-29T21:00:00.000Z"),
    });
  });
});

describe("countByProject", () => {
  it("counts per project, most first, then by name", () => {
    expect(
      countByProject([
        { projectId: "b", projectName: "Ремонт" },
        { projectId: "a", projectName: "Дача" },
        { projectId: "b", projectName: "Ремонт" },
        { projectId: "c", projectName: "Авто" },
      ]),
    ).toEqual([
      { projectId: "b", name: "Ремонт", closed: 2 },
      { projectId: "c", name: "Авто", closed: 1 },
      { projectId: "a", name: "Дача", closed: 1 },
    ]);
  });
});
