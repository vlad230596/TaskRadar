import { describe, it, expect } from "vitest";
import { addDays, dayOf, isLater, localToday, todayView } from "../src/domain/today";
import { nextStepOf } from "../src/domain/goals";

/*
 * «Сегодня», «С прошлых дней» and «Позже» (design/today-history-contract.md):
 * the pure rules. The app runs the same ones offline on its cache, so these
 * cases are the reference both sides are held to.
 */

const d = (day: string) => new Date(`${day}T00:00:00.000Z`);
const TODAY = "2026-11-27";

interface T {
  id: string;
  status: "pending" | "done" | "blocked";
  remindAt: Date | null;
  remindTime: string | null;
  doneAt: Date | null;
  position: number;
}

function task(id: string, row: Partial<T> = {}): T {
  return { id, status: "pending", remindAt: d(TODAY), remindTime: null, doneAt: null, position: 1000, ...row };
}

describe("day helpers", () => {
  it("reads the stored day, adds days across months and years", () => {
    expect(dayOf(d("2026-11-27"))).toBe("2026-11-27");
    expect(dayOf(null)).toBeNull();
    expect(addDays("2026-11-27", 10)).toBe("2026-12-07");
    expect(addDays("2026-12-28", 5)).toBe("2027-01-02");
    expect(addDays("2026-03-01", -1)).toBe("2026-02-28");
  });

  it("takes today in the owner's zone", () => {
    const late = new Date("2026-11-26T22:30:00.000Z");
    expect(localToday(late)).toBe("2026-11-26");
    expect(localToday(late, 180)).toBe("2026-11-27");
  });
});

describe("isLater", () => {
  it("is open and dated beyond today + horizon", () => {
    expect(isLater({ status: "pending", remindAt: d("2026-12-08") }, TODAY, 10)).toBe(true);
    expect(isLater({ status: "blocked", remindAt: d("2026-12-08") }, TODAY, 10)).toBe(true);
  });

  it("is not at the horizon, not without a date, not when done", () => {
    expect(isLater({ status: "pending", remindAt: d("2026-12-07") }, TODAY, 10)).toBe(false);
    expect(isLater({ status: "pending", remindAt: null }, TODAY, 10)).toBe(false);
    expect(isLater({ status: "done", remindAt: d("2027-01-01") }, TODAY, 10)).toBe(false);
  });

  it("follows the horizon", () => {
    expect(isLater({ status: "pending", remindAt: d("2026-11-29") }, TODAY, 1)).toBe(true);
    expect(isLater({ status: "pending", remindAt: d("2026-11-29") }, TODAY, 2)).toBe(false);
  });
});

describe("todayView", () => {
  it("splits open tasks into today and the tail, and ignores undated and future ones", () => {
    const view = todayView(
      [
        task("today"),
        task("yesterday", { remindAt: d("2026-11-26") }),
        task("tomorrow", { remindAt: d("2026-11-28") }),
        task("undated", { remindAt: null }),
        task("blocked-today", { status: "blocked" }),
      ],
      TODAY,
    );
    expect(view.date).toBe(TODAY);
    expect(view.today.map((t) => t.id)).toEqual(["today", "blocked-today"]);
    expect(view.tail.map((t) => t.id)).toEqual(["yesterday"]);
    expect(view.doneToday).toEqual([]);
  });

  it("puts timed tasks first by time, then the rest in board order", () => {
    const view = todayView(
      [
        task("b", { position: 2000 }),
        task("t15", { remindTime: "15:00", position: 5000 }),
        task("a", { position: 1000 }),
        task("t09", { remindTime: "09:30", position: 9000 }),
      ],
      TODAY,
    );
    expect(view.today.map((t) => t.id)).toEqual(["t09", "t15", "a", "b"]);
  });

  it("uses the caller's board order for ties", () => {
    const rank: Record<string, number> = { home: 2, work: 1 };
    const view = todayView(
      [task("home", { position: 1 }), task("work", { position: 2 })],
      TODAY,
      0,
      (x, y) => rank[x.id]! - rank[y.id]!,
    );
    expect(view.today.map((t) => t.id)).toEqual(["work", "home"]);
  });

  it("orders the tail by date, then board order", () => {
    const view = todayView(
      [
        task("c", { remindAt: d("2026-11-25"), position: 1 }),
        task("a", { remindAt: d("2026-11-20"), position: 3 }),
        task("b", { remindAt: d("2026-11-25"), position: 0 }),
      ],
      TODAY,
    );
    expect(view.tail.map((t) => t.id)).toEqual(["a", "b", "c"]);
  });

  it("keeps what was closed today (local day) and dated today or earlier, by doneAt", () => {
    const view = todayView(
      [
        task("late", { status: "done", doneAt: new Date("2026-11-27T15:00:00.000Z") }),
        task("early", {
          status: "done",
          remindAt: d("2026-11-20"),
          doneAt: new Date("2026-11-27T06:00:00.000Z"),
        }),
        task("yesterday", { status: "done", doneAt: new Date("2026-11-26T15:00:00.000Z") }),
        task("future-closed", {
          status: "done",
          remindAt: d("2026-12-01"),
          doneAt: new Date("2026-11-27T10:00:00.000Z"),
        }),
        task("undated-closed", { status: "done", remindAt: null, doneAt: new Date("2026-11-27T10:00:00.000Z") }),
      ],
      TODAY,
    );
    expect(view.doneToday.map((t) => t.id)).toEqual(["early", "late"]);
  });

  it("counts a closing just after local midnight for the local day", () => {
    const closed = task("x", { status: "done", doneAt: new Date("2026-11-26T21:30:00.000Z") });
    expect(todayView([closed], TODAY, 0).doneToday).toEqual([]);
    expect(todayView([closed], TODAY, 180).doneToday.map((t) => t.id)).toEqual(["x"]);
  });
});

describe("nextStepOf with «Позже»", () => {
  const later = { today: TODAY, horizonDays: 10 };

  it("passes over a pending task beyond the horizon for one that is for now", () => {
    const tasks = [
      { id: "far", status: "pending" as const, remindAt: d("2027-02-25") },
      { id: "blocked", status: "blocked" as const, remindAt: null },
      { id: "near", status: "pending" as const, remindAt: d("2026-11-30") },
    ];
    expect(nextStepOf(tasks, later)?.id).toBe("near");
  });

  it("falls back to the first pending when every pending one is «Позже»", () => {
    const tasks = [
      { id: "done", status: "done" as const, remindAt: null },
      { id: "far1", status: "pending" as const, remindAt: d("2027-02-25") },
      { id: "far2", status: "pending" as const, remindAt: d("2027-01-10") },
    ];
    expect(nextStepOf(tasks, later)?.id).toBe("far1");
  });

  it("is null with nothing pending, and the plain first pending without the rule", () => {
    expect(nextStepOf([{ id: "b", status: "blocked" as const, remindAt: null }], later)).toBeNull();
    expect(nextStepOf([{ id: "far", status: "pending" as const, remindAt: d("2027-02-25") }])?.id).toBe("far");
  });
});
