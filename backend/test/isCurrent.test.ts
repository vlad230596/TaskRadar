import { describe, it, expect } from "vitest";
import { annotateIsCurrent } from "../src/domain/isCurrent";

describe("annotateIsCurrent", () => {
  it("returns an empty array for an empty list", () => {
    expect(annotateIsCurrent([])).toEqual([]);
  });

  it("marks the first task current when all tasks are pending", () => {
    const tasks = [{ id: "a", status: "pending" as const }, { id: "b", status: "pending" as const }, { id: "c", status: "pending" as const }];
    const result = annotateIsCurrent(tasks);
    expect(result.map((t) => t.isCurrent)).toEqual([true, false, false]);
  });

  it("skips leading done/blocked tasks to find the first pending one", () => {
    const tasks = [
      { id: "a", status: "done" as const },
      { id: "b", status: "blocked" as const },
      { id: "c", status: "pending" as const },
      { id: "d", status: "pending" as const },
    ];
    const result = annotateIsCurrent(tasks);
    expect(result.map((t) => t.isCurrent)).toEqual([false, false, true, false]);
  });

  it("does not let a blocked/done task ahead of a pending one consume the current slot", () => {
    const tasks = [
      { id: "a", status: "pending" as const },
      { id: "b", status: "done" as const },
      { id: "c", status: "blocked" as const },
      { id: "d", status: "pending" as const },
    ];
    const result = annotateIsCurrent(tasks);
    expect(result.map((t) => t.isCurrent)).toEqual([true, false, false, false]);
  });

  it("marks nothing current when there is no pending task at all", () => {
    const tasks = [
      { id: "a", status: "done" as const },
      { id: "b", status: "blocked" as const },
      { id: "c", status: "done" as const },
    ];
    const result = annotateIsCurrent(tasks);
    expect(result.every((t) => t.isCurrent === false)).toBe(true);
  });

  it("marks exactly one task current in a mixed-order list", () => {
    const tasks = [
      { id: "a", status: "blocked" as const },
      { id: "b", status: "pending" as const },
      { id: "c", status: "pending" as const },
      { id: "d", status: "done" as const },
    ];
    const result = annotateIsCurrent(tasks);
    expect(result.filter((t) => t.isCurrent)).toHaveLength(1);
    expect(result.map((t) => t.isCurrent)).toEqual([false, true, false, false]);
  });

  it("preserves the original task fields alongside isCurrent", () => {
    const tasks = [{ id: "a", status: "pending" as const, title: "Do the thing" }];
    const result = annotateIsCurrent(tasks);
    expect(result[0]).toEqual({ id: "a", status: "pending", title: "Do the thing", isCurrent: true });
  });
});
