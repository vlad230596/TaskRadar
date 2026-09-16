import { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma";
import { annotateIsCurrent } from "../domain/isCurrent";
import { boardQuerySchema } from "../schemas";

/**
 * `GET /board` -- the whole board (projects with their tasks) in one response.
 *
 * Why this exists next to `GET /projects` + `GET /projects/:id/tasks` rather than
 * replacing them: a client that renders the board needs everything at once, while
 * a client that just toggled one task's status needs one project's tasks. Keeping
 * both means neither caller overfetches -- and the Flutter client uses both: this
 * route for the board, the per-project ones for the project screen and for the
 * re-read after a mutation that can move `isCurrent`.
 *
 * The motivation is latency, not code tidiness. Rendering the board with the
 * per-project route costs 1 + N requests; over a mobile network with ~15 projects
 * that is 16 sequential round-trips on every cold start, which is seconds of
 * staring at a spinner. One request makes it one.
 *
 * That argument only holds if the server does not simply move the N round-trips
 * onto the database, hence the `include` below instead of a loop over projects.
 */
export async function boardRoutes(app: FastifyInstance): Promise<void> {
  app.get("/board", async (request, reply) => {
    const query = boardQuerySchema.parse(request.query);
    const showArchived = query.archived === "true";

    /*
     * One Prisma call, not one per project. Prisma resolves an `include` of a
     * to-many relation with a fixed number of queries (parent rows, then the
     * children of all of them in a single `IN (...)`) regardless of how many
     * projects come back -- i.e. constant, not N+1.
     *
     * The `where` / `orderBy` on the projects deliberately mirror `GET /projects`
     * character for character, and the task `orderBy` mirrors
     * `GET /projects/:projectId/tasks`. A client must be able to swap between the
     * bulk route and the per-entity routes without the board resorting itself.
     *
     * Sorting the tasks here is also a correctness requirement, not a cosmetic
     * one: `annotateIsCurrent` is documented as trusting its input to already be
     * in ascending `position` order and picks the first pending task it sees, so
     * unordered rows would silently mark the wrong task as current.
     */
    const projects = await prisma.project.findMany({
      where: {
        archivedAt: showArchived ? { not: null } : null,
        // F7: optional, and the Flutter client does not use it -- it fetches
        // every scope's projects and filters locally, because the local
        // reminder queue is armed from this response and a server-filtered
        // board would stop raising reminders for scopes nobody is looking at.
        // The long version is on `listProjectsQuerySchema` in ../schemas.ts.
        ...(query.scopeId ? { scopeId: query.scopeId } : {}),
      },
      orderBy: { createdAt: "asc" },
      include: {
        tasks: { orderBy: { position: "asc" } },
      },
    });

    /*
     * Each project is returned in exactly the shape `GET /projects` returns, with
     * a `tasks` array added; each task in exactly the shape
     * `GET /projects/:projectId/tasks` returns, `isCurrent` included. That lets the
     * client keep a single Project/Task model rather than a second "board-flavoured"
     * pair of types that would drift apart.
     *
     * The top level is a bare array for the same reason -- it is the `GET /projects`
     * payload with one extra field per row, so an envelope object here would make the
     * two responses need different parsers for no gain.
     */
    reply.send(
      projects.map((project) => ({
        ...project,
        tasks: annotateIsCurrent(project.tasks),
      })),
    );
  });
}
