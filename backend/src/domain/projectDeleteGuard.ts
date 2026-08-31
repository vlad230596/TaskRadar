/**
 * Archive is reversible, delete is not — so hard-deleting a Project is only
 * allowed once it has been archived first. Pure predicate so the guard's
 * logic can be unit tested without touching the DB.
 */
export function canHardDeleteProject(project: { archivedAt: Date | null }): boolean {
  return project.archivedAt !== null;
}
