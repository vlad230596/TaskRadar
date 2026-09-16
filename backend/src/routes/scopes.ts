import { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma";
import { NotFoundError, ConflictError, ValidationError } from "../lib/errors";
import {
  computeAppendPosition,
  computePositionBetween,
  computeRebalancedPositions,
  PositionExhaustedError,
} from "../domain/position";
import { scopeDeleteRefusal, scopeDeleteRefusalMessage } from "../domain/scopeDeleteGuard";
import {
  createScopeSchema,
  updateScopeSchema,
  updateScopePositionSchema,
  idParamSchema,
} from "../schemas";

/*
 * Scopes (F7): the spaces projects are grouped into -- "work at company A",
 * "home", "the dacha" -- with the board showing exactly one at a time.
 *
 * WHY A SCOPE IS NOT JUST A PROJECT TAG
 *
 * `README.md` builds the product around a board you can take in at a glance,
 * and states its own limit out loud: 10-15 projects fit on one screen. The
 * scope is what keeps that true once the projects belong to genuinely
 * unrelated parts of a life -- it partitions the *board*, so each one stays the
 * size the product assumes. A tag would filter a list; a scope decides which
 * board you are looking at, which is why a project has exactly one and why it
 * is a required column rather than a join table.
 *
 * WHAT A SCOPE DELIBERATELY IS NOT
 *
 * It is not the "потоки/направления" idea that `README.md` and
 * `project-tracker-brief.md` keep deferring: that one groups tasks *inside* a
 * project, and it is still deferred. A scope groups projects, and changes
 * nothing about what a project is.
 */

/** Loads a scope by id, or answers 404. */
export async function getScopeOrThrow(scopeId: string) {
  const scope = await prisma.scope.findUnique({ where: { id: scopeId } });
  if (!scope) {
    throw new NotFoundError("Scope");
  }
  return scope;
}

/**
 * The scope a project goes into when the client did not name one.
 *
 * "First by position" rather than "oldest" or "a magic default id": the order
 * is the one the user arranged themselves, and the first tab is the one their
 * board opens on, so an unattributed project lands where they are already
 * looking. The migration guarantees at least one scope exists, but a database
 * that somehow has none gets a clear 409 instead of a foreign key error.
 */
export async function getDefaultScopeOrThrow() {
  const scope = await prisma.scope.findFirst({ orderBy: { position: "asc" } });
  if (!scope) {
    throw new ConflictError("No scope exists to put this project in; create one first");
  }
  return scope;
}

export async function scopeRoutes(app: FastifyInstance): Promise<void> {
  /*
   * The whole list, always. There is no `archived` flavour and no pagination:
   * scopes are a handful of rows that the client renders as a switcher, and it
   * needs all of them to draw it.
   */
  app.get("/scopes", async (_request, reply) => {
    const scopes = await prisma.scope.findMany({ orderBy: { position: "asc" } });
    reply.send(scopes);
  });

  app.post("/scopes", async (request, reply) => {
    const body = createScopeSchema.parse(request.body);

    // Appended to the end, like a new task in a project: a scope created now is
    // not claimed to belong anywhere in particular, and the user can drag it.
    const last = await prisma.scope.findFirst({ orderBy: { position: "desc" } });
    const position = computeAppendPosition(last?.position ?? null);

    const scope = await prisma.scope.create({ data: { name: body.name, position } });
    reply.status(201).send(scope);
  });

  app.patch("/scopes/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const body = updateScopeSchema.parse(request.body);
    // Existence first, so a missing scope is a 404 rather than Prisma's P2025
    // surfacing as an opaque 500 -- same order as `PATCH /projects/:id`.
    await getScopeOrThrow(id);

    const scope = await prisma.scope.update({ where: { id }, data: { name: body.name } });
    reply.send(scope);
  });

  /*
   * Reordering, by naming the neighbours rather than an index.
   *
   * This is `PATCH /tasks/:id/position` with `task` swapped for `scope`, and
   * the duplication is on purpose rather than a shared helper: the two differ
   * in the one place that matters (a task is positioned among its *project's*
   * tasks, a scope among all scopes), and a generic "reposition any entity"
   * helper would have to take the sibling query as a parameter -- which is the
   * whole body of the function.
   */
  app.patch("/scopes/:id/position", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const body = updateScopePositionSchema.parse(request.body);
    await getScopeOrThrow(id);

    const beforeId = body.beforeScopeId ?? null;
    const afterId = body.afterScopeId ?? null;

    if (beforeId === id || afterId === id) {
      throw new ValidationError("A scope cannot be positioned relative to itself");
    }

    async function resolveNeighborPosition(neighborId: string | null): Promise<number | null> {
      if (neighborId === null) return null;
      const neighbor = await prisma.scope.findUnique({ where: { id: neighborId } });
      if (!neighbor) {
        throw new ValidationError(`Neighbor scope ${neighborId} was not found`);
      }
      return neighbor.position;
    }

    let beforePosition = await resolveNeighborPosition(beforeId);
    let afterPosition = await resolveNeighborPosition(afterId);

    let newPosition: number;
    try {
      newPosition = computePositionBetween(beforePosition, afterPosition);
    } catch (err) {
      if (!(err instanceof PositionExhaustedError)) throw err;

      // Bisection ran out of float precision between these two neighbours:
      // renumber every scope with fresh gaps, then compute the move again
      // against the new numbers. Same fallback as tasks, and about as likely to
      // fire here as being struck by lightning while reordering five rows --
      // but "about as likely" is not "impossible", and the tasks route already
      // proved the cheap way to handle it.
      const allScopes = await prisma.scope.findMany({ orderBy: { position: "asc" } });
      const rebalanced = computeRebalancedPositions(allScopes.map((s) => s.id));

      await prisma.$transaction(
        rebalanced.map((r) =>
          prisma.scope.update({ where: { id: r.id }, data: { position: r.position } }),
        ),
      );

      beforePosition = beforeId
        ? (rebalanced.find((r) => r.id === beforeId)?.position ?? null)
        : null;
      afterPosition = afterId ? (rebalanced.find((r) => r.id === afterId)?.position ?? null) : null;

      newPosition = computePositionBetween(beforePosition, afterPosition);
    }

    const updated = await prisma.scope.update({ where: { id }, data: { position: newPosition } });
    reply.send(updated);
  });

  /*
   * Delete, with no archive step in front of it.
   *
   * A project gets archive-then-delete because it holds work that took months
   * to accumulate. A scope holds nothing of its own -- it is a name and an
   * order -- so the reversible half would be ceremony. What it does hold is
   * *projects*, and the guard refuses while any of them (archived ones
   * included) still point at it; see domain/scopeDeleteGuard.ts.
   */
  app.delete("/scopes/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    await getScopeOrThrow(id);

    const [projectCount, totalScopes] = await Promise.all([
      prisma.project.count({ where: { scopeId: id } }),
      prisma.scope.count(),
    ]);

    const refusal = scopeDeleteRefusal({ projectCount, totalScopes });
    if (refusal !== null) {
      throw new ConflictError(scopeDeleteRefusalMessage(refusal));
    }

    await prisma.scope.delete({ where: { id } });
    reply.status(204).send();
  });
}
