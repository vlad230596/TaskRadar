import { describe, it, expect } from "vitest";
import {
  computeAppendPosition,
  computePositionBetween,
  computeRebalancedPositions,
  PositionExhaustedError,
  POSITION_GAP,
} from "../src/domain/position";

describe("computeAppendPosition", () => {
  it("uses the gap as the first position when the list is empty", () => {
    expect(computeAppendPosition(null)).toBe(POSITION_GAP);
  });

  it("adds a gap after the last existing position", () => {
    expect(computeAppendPosition(1000)).toBe(2000);
    expect(computeAppendPosition(2500)).toBe(3500);
  });
});

describe("computePositionBetween", () => {
  it("returns the gap value when there are no neighbours on either side", () => {
    expect(computePositionBetween(null, null)).toBe(POSITION_GAP);
  });

  it("inserts at the very start (before is null) by subtracting a gap from `after`", () => {
    expect(computePositionBetween(null, 1000)).toBe(0);
    expect(computePositionBetween(null, 500)).toBe(-500);
  });

  it("inserts at the very end (after is null) by adding a gap to `before`", () => {
    expect(computePositionBetween(1000, null)).toBe(2000);
  });

  it("bisects the midpoint between two close neighbours", () => {
    expect(computePositionBetween(1000, 2000)).toBe(1500);
    expect(computePositionBetween(1000, 1002)).toBe(1001);
  });

  it("can keep bisecting a shrinking gap many times before exhaustion", () => {
    const before = 1000;
    let after = 2000;
    for (let i = 0; i < 30; i++) {
      const mid = computePositionBetween(before, after);
      expect(mid).toBeGreaterThan(before);
      expect(mid).toBeLessThan(after);
      after = mid; // keep narrowing from the top, same as repeatedly inserting just above `before`
    }
  });

  it("throws PositionExhaustedError when before >= after", () => {
    expect(() => computePositionBetween(2000, 1000)).toThrow(PositionExhaustedError);
    expect(() => computePositionBetween(1000, 1000)).toThrow(PositionExhaustedError);
  });

  it("throws PositionExhaustedError when the gap is too small to bisect distinctly", () => {
    const before = 1;
    // The smallest possible increment representable above `before` at this magnitude.
    const after = before + Number.EPSILON;
    expect(() => computePositionBetween(before, after)).toThrow(PositionExhaustedError);
  });
});

describe("computeRebalancedPositions", () => {
  it("returns an empty array for an empty list", () => {
    expect(computeRebalancedPositions([])).toEqual([]);
  });

  it("assigns fresh, evenly spaced positions in the given order", () => {
    const result = computeRebalancedPositions(["a", "b", "c"]);
    expect(result).toEqual([
      { id: "a", position: POSITION_GAP },
      { id: "b", position: 2 * POSITION_GAP },
      { id: "c", position: 3 * POSITION_GAP },
    ]);
  });

  it("produces positions that resolve a previously-exhausted gap", () => {
    // Simulate: two tasks whose positions have become too close to bisect.
    const before = 1;
    const after = before + Number.EPSILON;
    expect(() => computePositionBetween(before, after)).toThrow(PositionExhaustedError);

    const rebalanced = computeRebalancedPositions(["x", "y"]);
    const [x, y] = rebalanced;
    expect(x).toBeDefined();
    expect(y).toBeDefined();
    // After rebalancing, the same two neighbours are far enough apart to bisect again.
    expect(() => computePositionBetween(x!.position, y!.position)).not.toThrow();
  });
});
