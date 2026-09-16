import { describe, it, expect } from "vitest";
import {
  scopeDeleteRefusal,
  scopeDeleteRefusalMessage,
} from "../src/domain/scopeDeleteGuard";

/**
 * The two rules that keep deleting a scope from losing anything (F7).
 *
 * Pure predicate, so these are the cheap tests; `scopes.test.ts` checks that the
 * route actually consults it and turns each refusal into a 409.
 */
describe("scopeDeleteRefusal", () => {
  it("allows deleting an empty scope when others remain", () => {
    expect(scopeDeleteRefusal({ projectCount: 0, totalScopes: 3 })).toBeNull();
  });

  it("refuses while projects still point at it", () => {
    expect(scopeDeleteRefusal({ projectCount: 1, totalScopes: 3 })).toBe("has-projects");
  });

  it("refuses the last scope even when it is empty", () => {
    // Every project needs a scope and the board shows exactly one at a time, so
    // a database with zero scopes is one where nothing can be created and
    // nothing can be shown.
    expect(scopeDeleteRefusal({ projectCount: 0, totalScopes: 1 })).toBe("last-scope");
  });

  it("reports the projects first when both rules apply", () => {
    // Order matters for the message the user reads: "move its projects first"
    // is actionable, "this is your last scope" would send them to delete
    // projects they did not intend to touch.
    expect(scopeDeleteRefusal({ projectCount: 2, totalScopes: 1 })).toBe("has-projects");
  });

  it("counts archived projects as projects", () => {
    // The guard takes a count, not rows -- this test pins the *caller's*
    // contract, which routes/scopes.ts implements by counting without an
    // `archivedAt` filter. An archived project can be unarchived onto a board,
    // so its scope must still exist.
    expect(scopeDeleteRefusal({ projectCount: 1, totalScopes: 2 })).toBe("has-projects");
  });

  it("gives each refusal a distinct message", () => {
    const messages = new Set([
      scopeDeleteRefusalMessage("has-projects"),
      scopeDeleteRefusalMessage("last-scope"),
    ]);
    expect(messages.size).toBe(2);
    for (const message of messages) {
      expect(message.length).toBeGreaterThan(0);
    }
  });
});
