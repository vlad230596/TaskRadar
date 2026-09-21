import { describe, it, expect } from "vitest";
import {
  countByDay,
  historyRangeStart,
  localDayKey,
  replayStatusTime,
  StatusEventLike,
} from "../src/domain/history";

/*
 * The arithmetic behind the history screen (F11).
 *
 * Every aggregate the server sends is a fold over rows it has already read, and
 * every fold is here -- so these are table tests over dates rather than tests
 * against a database. The route that calls them is covered in tasks.test.ts.
 */

const HOUR = 3_600_000;
const DAY = 24 * HOUR;

/** Moscow: three hours east of UTC, in the sign this code uses (add to UTC). */
const MSK = 180;

describe("localDayKey", () => {
  it("puts a timestamp on the client's day, not on the server's", () => {
    // 01:00 in Moscow is still the previous day in UTC. The bars are read as
    // "my week", and this is the whole reason the offset travels with the
    // request.
    const at = new Date("2026-09-20T22:30:00.000Z");

    expect(localDayKey(at, 0)).toBe("2026-09-20");
    expect(localDayKey(at, MSK)).toBe("2026-09-21");
  });

  it("handles offsets west of UTC too", () => {
    const at = new Date("2026-09-21T02:00:00.000Z");
    expect(localDayKey(at, -300)).toBe("2026-09-20");
  });
});

describe("historyRangeStart", () => {
  const now = new Date("2026-09-21T16:00:00.000Z");

  it("starts a week at local midnight six days back, not at now minus 7×24h", () => {
    // Otherwise the leftmost bar is a stump whose height depends on what time
    // of day the screen happened to be opened.
    const from = historyRangeStart("7d", now, 0)!;

    expect(from.toISOString()).toBe("2026-09-15T00:00:00.000Z");
    expect(localDayKey(from, 0)).toBe("2026-09-15");
  });

  it("aligns that midnight to the client's timezone", () => {
    const from = historyRangeStart("7d", now, MSK)!;

    // Local midnight in Moscow is 21:00 UTC the day before.
    expect(from.toISOString()).toBe("2026-09-14T21:00:00.000Z");
    expect(localDayKey(from, MSK)).toBe("2026-09-15");
  });

  it("spans thirty days for the month", () => {
    expect(localDayKey(historyRangeStart("30d", now, 0)!, 0)).toBe("2026-08-23");
  });

  it("has no start for 'all'", () => {
    // Not a date at all: the earliest thing the journal holds is a fact about
    // the data, and turning it into a request parameter here would invent one.
    expect(historyRangeStart("all", now, 0)).toBeNull();
  });
});

describe("countByDay", () => {
  const to = new Date("2026-09-21T10:00:00.000Z");

  it("counts closings per day and fills in the days nothing happened", () => {
    const from = historyRangeStart("7d", to, 0)!;
    const closings = [
      new Date("2026-09-21T09:00:00.000Z"),
      new Date("2026-09-21T08:00:00.000Z"),
      new Date("2026-09-18T12:00:00.000Z"),
    ];

    const days = countByDay(closings, 0, from, to);

    // Seven bars including today -- a week with three closings still has to
    // draw the five empty columns, which is the difference between a chart and
    // a list.
    expect(days).toHaveLength(7);
    expect(days.map((d) => d.date)).toEqual([
      "2026-09-15",
      "2026-09-16",
      "2026-09-17",
      "2026-09-18",
      "2026-09-19",
      "2026-09-20",
      "2026-09-21",
    ]);
    expect(days.map((d) => d.count)).toEqual([0, 0, 0, 1, 0, 0, 2]);
  });

  it("buckets by the client's day boundary", () => {
    // Same instant, two answers: in Moscow this closing belongs to the 21st.
    const closings = [new Date("2026-09-20T21:30:00.000Z")];
    const from = new Date("2026-09-19T00:00:00.000Z");

    expect(countByDay(closings, 0, from, to).find((d) => d.count > 0)!.date).toBe("2026-09-20");
    expect(countByDay(closings, MSK, from, to).find((d) => d.count > 0)!.date).toBe("2026-09-21");
  });

  it("returns only the days that have something on them for 'all'", () => {
    // A zero-filled axis from the first closing to today is mostly emptiness
    // and grows forever; the screen that wants contiguous bars is the week.
    const days = countByDay(
      [new Date("2026-01-04T10:00:00.000Z"), new Date("2026-09-21T09:00:00.000Z")],
      0,
      null,
      to,
    );

    expect(days).toEqual([
      { date: "2026-01-04", count: 1 },
      { date: "2026-09-21", count: 1 },
    ]);
  });

  it("gives a range with no closings a row of zeros rather than nothing", () => {
    const days = countByDay([], 0, historyRangeStart("7d", to, 0), to);

    expect(days).toHaveLength(7);
    expect(days.every((d) => d.count === 0)).toBe(true);
  });
});

describe("replayStatusTime", () => {
  const createdAt = new Date("2026-09-01T00:00:00.000Z");
  const now = new Date("2026-09-21T00:00:00.000Z");

  function event(kind: StatusEventLike["kind"], at: Date, toStatus: StatusEventLike["toStatus"]) {
    return { kind, at, toStatus };
  }

  it("splits a task's life between the statuses it passed through", () => {
    /*
     * The question the whole table exists for: this task spent five days
     * waiting, nine days blocked and six more waiting -- and `updatedAt` can
     * only say "touched on the 15th", because the nine days stopped existing
     * the moment the task stopped being blocked.
     */
    const events = [
      event("created", createdAt, "pending"),
      event("status", new Date("2026-09-06T00:00:00.000Z"), "blocked"),
      event("status", new Date("2026-09-15T00:00:00.000Z"), "pending"),
    ];

    const { byStatus, currentSince } = replayStatusTime(
      { createdAt, status: "pending" },
      events,
      now,
    );

    expect(byStatus.pending).toBe(11 * DAY);
    expect(byStatus.blocked).toBe(9 * DAY);
    expect(byStatus.done).toBe(0);
    expect(currentSince.toISOString()).toBe("2026-09-15T00:00:00.000Z");
  });

  it("ignores focus events", () => {
    // Picking a task up is not a change of status -- treating it as one would
    // make it look like a transition on the chart.
    const withFocus = [
      event("created", createdAt, "pending"),
      event("focused", new Date("2026-09-10T00:00:00.000Z"), null),
      event("unfocused", new Date("2026-09-12T00:00:00.000Z"), null),
    ];

    const { byStatus, currentSince } = replayStatusTime(
      { createdAt, status: "pending" },
      withFocus,
      now,
    );

    expect(byStatus.pending).toBe(20 * DAY);
    expect(currentSince).toEqual(createdAt);
  });

  it("counts the open interval up to now", () => {
    const events = [
      event("created", createdAt, "pending"),
      event("status", new Date("2026-09-11T00:00:00.000Z"), "blocked"),
    ];

    const { byStatus } = replayStatusTime({ createdAt, status: "blocked" }, events, now);

    expect(byStatus.pending).toBe(10 * DAY);
    expect(byStatus.blocked).toBe(10 * DAY);
  });

  it("attributes the whole life to the current status when the journal is empty", () => {
    /*
     * Total by construction: no caller ever has to handle "this task has no
     * history". The worst case is a first interval longer than it really was --
     * which is exactly the approximation the F11 migration's backfill makes for
     * tasks that predate the table.
     */
    const { byStatus, currentSince } = replayStatusTime({ createdAt, status: "blocked" }, [], now);

    expect(byStatus.blocked).toBe(20 * DAY);
    expect(byStatus.pending).toBe(0);
    expect(currentSince).toEqual(createdAt);
  });

  it("never reports negative time", () => {
    // Clocks move backwards (NTP, a laptop waking up); a bar of negative width
    // is worse than a bar of zero.
    const { byStatus } = replayStatusTime(
      { createdAt: now, status: "pending" },
      [event("created", now, "pending")],
      new Date(now.getTime() - HOUR),
    );

    expect(byStatus.pending).toBe(0);
  });
});
