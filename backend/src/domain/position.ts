/**
 * Ordering scheme for Task.position within a project.
 *
 * `position` is a Float (double precision) rather than a sequential integer.
 * The reason: with a gapped scheme, moving one task to a new spot among its
 * siblings only ever requires writing the ONE row being moved — the new
 * position is simply picked strictly between its two new neighbours'
 * existing positions (or GAP beyond the end/start if it has no neighbour on
 * one side). Nothing else in the project needs to change.
 *
 * If we instead stored dense integers (1, 2, 3, ...) and wanted to "insert
 * between 1 and 2", every task from that point on would need to be
 * renumbered — an O(n) write on every single move. A big integer with fixed
 * gaps (e.g. 1000, 2000, 3000, ...) gets most of the same benefit, but a
 * Float lets you keep bisecting the gap between two neighbours indefinitely
 * (1500, then 1250, then 1125, ...) with no pre-chosen gap size to run out
 * of — until IEEE-754 double precision (~15-17 significant decimal digits)
 * is exhausted, which given at most a few dozen tasks per project and a
 * human doing the reordering, will not happen in practice. The exhaustion
 * case is still handled explicitly (see `PositionExhaustedError` and
 * `computeRebalancedPositions` below) rather than assumed away.
 */

export const POSITION_GAP = 1000;

/** Thrown when two neighbouring positions are too close together (or equal)
 * to compute a distinct float strictly between them — floating point
 * precision has been exhausted for that particular pair. Callers should
 * catch this and fall back to `computeRebalancedPositions` to renumber the
 * whole project with fresh, evenly-spaced gaps, then retry.
 */
export class PositionExhaustedError extends Error {
  constructor() {
    super(
      "Cannot compute a distinct position between these two neighbours; positions need rebalancing.",
    );
    this.name = "PositionExhaustedError";
  }
}

/** Position for a brand-new task appended to the end of a project's list. */
export function computeAppendPosition(lastPosition: number | null): number {
  return lastPosition === null ? POSITION_GAP : lastPosition + POSITION_GAP;
}

/**
 * Position for a task moved (or created) so that it sits between `before`
 * and `after` (either may be `null` to mean "no neighbour on that side",
 * i.e. move to the very start / very end of the list).
 *
 * Throws `PositionExhaustedError` if `before` and `after` are both given but
 * are too close together to bisect into a distinct value.
 */
export function computePositionBetween(
  before: number | null,
  after: number | null,
): number {
  if (before === null && after === null) {
    return POSITION_GAP;
  }
  if (before === null) {
    // after !== null here
    return (after as number) - POSITION_GAP;
  }
  if (after === null) {
    return before + POSITION_GAP;
  }

  if (before >= after) {
    throw new PositionExhaustedError();
  }

  const mid = before + (after - before) / 2;
  if (mid <= before || mid >= after) {
    // Floating point precision between `before` and `after` is exhausted.
    throw new PositionExhaustedError();
  }
  return mid;
}

/**
 * Renumbers a whole ordered list of task ids with fresh, evenly-spaced
 * positions (POSITION_GAP, 2*POSITION_GAP, ...). Used only as a rare
 * fallback when `computePositionBetween` reports precision exhaustion
 * between some pair of neighbours. This is the one place an O(n) write is
 * intentional and unavoidable — it happens only when the cheap path is no
 * longer possible, not on every move.
 */
export function computeRebalancedPositions(
  taskIdsInOrder: readonly string[],
): { id: string; position: number }[] {
  return taskIdsInOrder.map((id, index) => ({
    id,
    position: (index + 1) * POSITION_GAP,
  }));
}
