import { Prisma } from "@prisma/client";
import { describe, it, expect, vi } from "vitest";
import { aiClearData, aiMarkFields } from "../src/domain/aiMark";

/*
 * "Правил AI": the first source is kept, every later save only moves the
 * snapshot, and a row of someone else or of another kind marks nothing.
 */

function txWith(row: { inputText: string; kind: string } | null) {
  const findFirst = vi.fn(async (): Promise<unknown> => row);
  return { tx: { dictationParse: { findFirst } } as never, findFirst };
}

const snapshot = { title: "Позвонить в сервис", description: null };

describe("aiMarkFields", () => {
  it("marks a row AI never touched with the words it came from", async () => {
    const { tx, findFirst } = txWith({ inputText: "ну позвонить в сервис", kind: "task" });
    await expect(aiMarkFields(tx, "u1", "p1", ["task"], null, snapshot)).resolves.toEqual({
      aiSource: "ну позвонить в сервис",
      aiKind: "task",
      aiResult: snapshot,
    });
    expect(findFirst).toHaveBeenCalledWith({
      where: { id: "p1", userId: "u1", kind: { in: ["task"] } },
      select: { inputText: true, kind: true },
    });
  });

  it("keeps the first source on a second processing, and moves only the snapshot", async () => {
    const { tx } = txWith({ inputText: "второй исходник", kind: "task_tidy" });
    await expect(
      aiMarkFields(tx, "u1", "p2", ["task_tidy"], "первый исходник", snapshot),
    ).resolves.toEqual({ aiResult: snapshot });
  });

  it("marks nothing for an unknown, foreign or other-kind row", async () => {
    const { tx } = txWith(null);
    await expect(aiMarkFields(tx, "u1", "p1", ["note"], null, snapshot)).resolves.toEqual({});
  });

  it("does not look anything up for a plain save", async () => {
    const { tx, findFirst } = txWith(null);
    await expect(aiMarkFields(tx, "u1", undefined, ["note"], null, snapshot)).resolves.toEqual({});
    expect(findFirst).not.toHaveBeenCalled();
  });
});

describe("aiClearData", () => {
  it("clears all three columns", () => {
    expect(aiClearData()).toEqual({ aiSource: null, aiKind: null, aiResult: Prisma.DbNull });
  });
});
