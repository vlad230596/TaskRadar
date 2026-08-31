import { describe, it, expect } from "vitest";
import { canHardDeleteProject } from "../src/domain/projectDeleteGuard";

describe("canHardDeleteProject", () => {
  it("returns false when the project has not been archived", () => {
    expect(canHardDeleteProject({ archivedAt: null })).toBe(false);
  });

  it("returns true once the project has been archived", () => {
    expect(canHardDeleteProject({ archivedAt: new Date() })).toBe(true);
  });
});
