/**
 * When a scope may be deleted (F7).
 *
 * A scope is not archived first the way a project is: it holds no content of
 * its own, so there is nothing in it to lose and nothing to restore. What it
 * does hold is *other things*, and that is what the two rules below protect.
 *
 * Pure predicate, like `projectDeleteGuard`, so the rules are unit-testable
 * without a database -- and so the route reads as one decision rather than two
 * scattered `if`s.
 */

export type ScopeDeleteRefusal =
  /** Projects still point at it. Deleting would orphan them (or, with a
   *  cascade, destroy them -- see the `Restrict` note in schema.prisma). */
  | "has-projects"
  /** It is the only scope there is. Every project needs one, so a database
   *  with zero scopes is one where no project can be created -- and the board,
   *  which always shows exactly one scope, would have nothing to show. */
  | "last-scope";

export interface ScopeDeleteContext {
  /**
   * How many projects reference this scope, **archived ones included**.
   *
   * Counting only active projects would be the friendlier-looking rule and the
   * wrong one: an archived project is a live row that can come back
   * (`getProjectOrThrow` in routes/projects.ts spells out why), so deleting the
   * scope out from under it would leave a project that cannot be unarchived
   * onto any board.
   */
  projectCount: number;
  /** How many scopes exist in total, this one included. */
  totalScopes: number;
}

/**
 * Returns why the scope cannot be deleted, or `null` when it can.
 *
 * A reason rather than a boolean: the two refusals need different messages --
 * "move its projects somewhere first" and "this is your only scope" are
 * different instructions, and a single 409 saying "cannot delete" would leave
 * the reader guessing which one they hit.
 */
export function scopeDeleteRefusal(context: ScopeDeleteContext): ScopeDeleteRefusal | null {
  if (context.projectCount > 0) return "has-projects";
  if (context.totalScopes <= 1) return "last-scope";
  return null;
}

/** The 409 message for each refusal, in one place so the route has no prose. */
export function scopeDeleteRefusalMessage(refusal: ScopeDeleteRefusal): string {
  switch (refusal) {
    case "has-projects":
      return "Scope still has projects; move or delete them first";
    case "last-scope":
      return "The last scope cannot be deleted";
  }
}
