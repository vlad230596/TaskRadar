import { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma";
import { countByDay, historyRangeStart, replayStatusTime } from "../domain/history";
import { historyQuerySchema } from "../schemas";

/*
 * `GET /history` -- the whole history mode in one response (F11).
 *
 * WHY ONE ROUTE FOR THREE BLOCKS
 *
 * The same argument `/board` makes: the screen (`design/reference/History.html`)
 * shows the week's bars, the tasks that have hung longest and what moved in each
 * project, all at once and always together. Three routes would be three
 * round-trips over a mobile network to draw one screen, and three chances for
 * the blocks to disagree about what "now" is -- the bars ending yesterday while
 * the ages are counted from today is the kind of wrongness nobody reports and
 * everybody half-notices.
 *
 * WHY THE SERVER AGGREGATES
 *
 * The alternative is `GET /tasks/events` and a fold on the client, and it gets
 * worse every week the tool is used: the phone would download every transition
 * ever recorded to draw seven bars. The journal is the server's to read; the
 * wire carries answers.
 *
 * WHY THIS IS NOT SQL
 *
 * Every count below is done in JavaScript over rows Prisma returned, rather
 * than in `date_trunc`/`GROUP BY`. Two reasons, in this order: the day
 * boundaries are the *client's* (see `localDayKey`), so grouping in the
 * database would mean pushing the caller's timezone into raw SQL for a
 * correctness property that is easier to read and test as a pure function; and
 * the row counts are those of one person's tracker -- hundreds of events, tens
 * of tasks -- where the query planner is not the interesting variable. If this
 * ever stops being true, the honest fix is a materialised daily count, not a
 * cleverer query.
 */
export async function historyRoutes(app: FastifyInstance): Promise<void> {
  app.get("/history", async (request, reply) => {
    const query = historyQuerySchema.parse(request.query);

    // One `now` for the whole response, read once. Every block below is
    // measured against it, so the bars and the ages cannot describe two
    // different moments.
    const now = new Date();
    const from = historyRangeStart(query.range, now, query.tzOffsetMinutes);

    /*
     * Openings and closings in one query rather than two, partitioned below.
     *
     * They are the same rows from the same index scan, filtered by the same
     * date -- and asking twice would make it possible for a task created
     * between the two queries to be counted as closed in a project that never
     * shows it opening.
     */
    const movements = await prisma.taskEvent.findMany({
      where: {
        OR: [{ kind: "created" }, { kind: "status", toStatus: "done" }],
        ...(from ? { at: { gte: from } } : {}),
      },
      select: {
        kind: true,
        at: true,
        task: { select: { projectId: true, project: { select: { name: true } } } },
      },
      orderBy: { at: "asc" },
    });

    const closings = movements.filter((event) => event.kind !== "created");

    /*
     * Movement per project: what appeared and what got finished.
     *
     * Only projects that moved are listed. A project with nothing in either
     * column is not a row saying "zero" -- it is a project nothing happened in,
     * which is what its absence says, and listing every project would turn the
     * block that answers "where did the work go" into the project list again.
     */
    const byProject = new Map<string, { projectId: string; name: string; opened: number; closed: number }>();
    for (const event of movements) {
      const row = byProject.get(event.task.projectId) ?? {
        projectId: event.task.projectId,
        name: event.task.project.name,
        opened: 0,
        closed: 0,
      };
      if (event.kind === "created") row.opened += 1;
      else row.closed += 1;
      byProject.set(row.projectId, row);
    }

    /*
     * "Висит дольше всего": open tasks, oldest first, with the time broken down
     * by status -- which is the number the whole journal exists to produce.
     *
     * Done tasks are excluded because they are not hanging, and tasks in
     * archived projects are excluded because a parked project is not a stalled
     * one: archiving is how a project is deliberately put down (README), and a
     * list of things to feel bad about that fills with work somebody already
     * decided to stop is a list that stops being read.
     *
     * Every open task's journal is read, not just the winners': which tasks
     * have hung longest is only knowable after the replay. That is the one
     * query here whose cost grows with the data, hence the cap on
     * `staleLimit` -- and at a dozen open tasks with a handful of events each
     * it is a single indexed fetch.
     */
    const openTasks = await prisma.task.findMany({
      where: { status: { not: "done" }, project: { archivedAt: null } },
      include: {
        project: { select: { id: true, name: true } },
        events: { orderBy: { at: "asc" } },
      },
    });

    const stale = openTasks
      .map((task) => {
        const { byStatus, currentSince } = replayStatusTime(task, task.events, now);
        return {
          id: task.id,
          title: task.title,
          status: task.status,
          projectId: task.project.id,
          projectName: task.project.name,
          createdAt: task.createdAt,
          focusedAt: task.focusedAt,
          /** Total age, and the ordering key: how long it has existed unfinished. */
          ageMs: Math.max(0, now.getTime() - task.createdAt.getTime()),
          /** When the current status began, and how long it has held. */
          currentSince,
          currentForMs: Math.max(0, now.getTime() - currentSince.getTime()),
          /** Where that age went. The bar under each row in the design. */
          byStatus,
        };
      })
      .sort((a, b) => b.ageMs - a.ageMs)
      .slice(0, query.staleLimit);

    reply.send({
      /*
       * The window is echoed back rather than left for the client to
       * reconstruct: it was computed here, in the client's own timezone, and a
       * client that recomputed it would be a second implementation of the
       * day-boundary rule -- the exact thing `localDayKey` exists to keep in
       * one place. `from` is null for "all", which is not a date.
       */
      range: query.range,
      from,
      to: now,
      /** One entry per day, zero-filled for 7d/30d. See `countByDay`. */
      closedByDay: countByDay(
        closings.map((event) => event.at),
        query.tzOffsetMinutes,
        from,
        now,
      ),
      closedTotal: closings.length,
      projects: [...byProject.values()].sort(
        (a, b) => b.opened + b.closed - (a.opened + a.closed) || a.name.localeCompare(b.name),
      ),
      stale,
    });
  });
}
