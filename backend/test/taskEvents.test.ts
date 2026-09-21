import { describe, it, expect } from "vitest";
import { planStatusChange } from "../src/domain/taskEvents";

/*
 * The rules the journal is written by (F11), tested where they live: a pure
 * function, no database, no HTTP. The routes that use it are covered in
 * tasks.test.ts -- what is checked here is the decision, not the plumbing.
 */

const T = new Date("2026-09-20T10:00:00.000Z");

describe("planStatusChange", () => {
  it("records the transition when the status actually moves", () => {
    const { events } = planStatusChange({ status: "pending", focusedAt: null }, "blocked");

    expect(events).toEqual([{ kind: "status", fromStatus: "pending", toStatus: "blocked" }]);
  });

  it("records nothing when no status was sent at all", () => {
    // A rename, which is the common case: nothing moved, so the life of the
    // task did not gain a row.
    expect(planStatusChange({ status: "pending", focusedAt: null }, undefined)).toEqual({
      events: [],
      leavesFocus: false,
    });
  });

  it("records nothing when the status is sent unchanged", () => {
    /*
     * The client sends the whole editable shape when a title is corrected, so
     * `status: "pending"` arrives on an already-pending task constantly. Those
     * must not become journal rows: they would fill the "life of this task"
     * section with nothing happening, and make `replayStatusTime` report
     * movement where the task sat still.
     */
    expect(planStatusChange({ status: "blocked", focusedAt: T }, "blocked")).toEqual({
      events: [],
      leavesFocus: false,
    });
  });

  it("takes a finished task out of the working set, and says so", () => {
    const { events, leavesFocus } = planStatusChange({ status: "pending", focusedAt: T }, "done");

    expect(leavesFocus).toBe(true);
    // Both rows, in order: the set is left *because* the task was finished, and
    // an empty `focusedAt` with nothing in the journal to explain it is a task
    // that left the set at a time nobody recorded.
    expect(events).toEqual([
      { kind: "status", fromStatus: "pending", toStatus: "done" },
      { kind: "unfocused", fromStatus: null, toStatus: null },
    ]);
  });

  it("does not record leaving a set the task was never in", () => {
    const { events, leavesFocus } = planStatusChange({ status: "pending", focusedAt: null }, "done");

    expect(leavesFocus).toBe(false);
    expect(events).toEqual([{ kind: "status", fromStatus: "pending", toStatus: "done" }]);
  });

  it("keeps a blocked task in the working set", () => {
    // Blocking is usually temporary ("жду кабель, спросить завтра"), and a task
    // you are waiting on is still a task you are working on.
    const { events, leavesFocus } = planStatusChange({ status: "pending", focusedAt: T }, "blocked");

    expect(leavesFocus).toBe(false);
    expect(events).toEqual([{ kind: "status", fromStatus: "pending", toStatus: "blocked" }]);
  });

  it("records reopening a done task", () => {
    const { events } = planStatusChange({ status: "done", focusedAt: null }, "pending");

    expect(events).toEqual([{ kind: "status", fromStatus: "done", toStatus: "pending" }]);
  });
});
