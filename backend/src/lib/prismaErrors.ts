/**
 * Whether [error] is Prisma's "a unique index already holds this value" (P2002).
 *
 * Used by the idempotent creates (`POST /inbox` with `captureKey`,
 * `POST /projects/:projectId/tasks` with `createKey`) to tell "the other copy
 * of this retry won the race" from a real failure.
 *
 * Matched on the code rather than with `instanceof PrismaClientKnownRequestError`
 * on purpose: the route tests run against an in-memory fake of the client (there
 * is no database in that environment), and a check that insisted on the real
 * error class would make the one branch that exists for a race untestable.
 */
export function isUniqueConstraintViolation(error: unknown): boolean {
  return (
    typeof error === "object" && error !== null && (error as { code?: unknown }).code === "P2002"
  );
}
