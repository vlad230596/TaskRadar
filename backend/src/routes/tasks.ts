import { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma";
import { NotFoundError, ValidationError } from "../lib/errors";
import { annotateIsCurrent } from "../domain/isCurrent";
import { planStatusChange } from "../domain/taskEvents";
import {
  computeAppendPosition,
  computePositionBetween,
  computeRebalancedPositions,
  PositionExhaustedError,
} from "../domain/position";
import {
  createTaskSchema,
  updateTaskSchema,
  updateTaskPositionSchema,
  idParamSchema,
  projectIdParamSchema,
} from "../schemas";
import { getProjectOrThrow } from "./projects";

export async function getTaskOrThrow(id: string) {
  const task = await prisma.task.findUnique({ where: { id } });
  if (!task) {
    throw new NotFoundError("Task");
  }
  return task;
}

export async function taskRoutes(app: FastifyInstance): Promise<void> {
  app.post("/projects/:projectId/tasks", async (request, reply) => {
    const { projectId } = projectIdParamSchema.parse(request.params);
    const body = createTaskSchema.parse(request.body);
    await getProjectOrThrow(projectId);

    const last = await prisma.task.aggregate({
      where: { projectId },
      _max: { position: true },
    });
    const position = computeAppendPosition(last._max.position);

    /*
     * The task and its first journal row, in one transaction (F11).
     *
     * The `created` event is what starts the clock the history mode reads --
     * "how long has this been hanging" is measured from it, not from
     * `createdAt`, so that one replay of the journal answers every question
     * about the task's life. A task with no `created` event is therefore not a
     * cosmetic gap: it is a task the history mode cannot place in time, which
     * is why this is a transaction and not two writes.
     *
     * `toStatus` carries the status the task was born in. Almost always
     * `pending`, but `POST` accepts a status, and a journal that has to consult
     * the task row to know where its first interval began is a journal that
     * cannot be replayed on its own.
     */
    const task = await prisma.$transaction(async (tx) => {
      const created = await tx.task.create({
        data: {
          projectId,
          title: body.title,
          description: body.description ?? null,
          ...(body.status !== undefined ? { status: body.status } : {}),
          remindAt: body.remindAt ?? null,
          position,
        },
      });

      await tx.taskEvent.create({
        data: { taskId: created.id, kind: "created", toStatus: created.status },
      });

      return created;
    });

    reply.status(201).send(task);
  });

  app.get("/projects/:projectId/tasks", async (request, reply) => {
    const { projectId } = projectIdParamSchema.parse(request.params);
    await getProjectOrThrow(projectId);

    const tasks = await prisma.task.findMany({
      where: { projectId },
      orderBy: { position: "asc" },
    });
    reply.send(annotateIsCurrent(tasks));
  });

  app.patch("/tasks/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const body = updateTaskSchema.parse(request.body);
    const before = await getTaskOrThrow(id);

    /*
     * What this change means for the journal and for the working set, decided
     * before anything is written. The rules -- an unchanged status records
     * nothing, finishing a task takes it out of the set -- live in
     * ../domain/taskEvents.ts, next to the reasons for them.
     */
    const movement = planStatusChange(before, body.status);

    const data: {
      title?: string;
      description?: string | null;
      status?: "pending" | "done" | "blocked";
      remindAt?: Date | null;
      focusedAt?: Date | null;
    } = {};
    if (body.title !== undefined) data.title = body.title;
    if (body.description !== undefined) data.description = body.description;
    if (body.status !== undefined) data.status = body.status;
    if (body.remindAt !== undefined) data.remindAt = body.remindAt;
    if (movement.leavesFocus) data.focusedAt = null;

    /*
     * One transaction, unconditionally -- even for a pure rename, which writes
     * no events at all.
     *
     * The alternative is a branch that takes the plain-update path when there
     * is nothing to journal, and it buys a `BEGIN` that Postgres was going to
     * issue around the single statement anyway. What it costs is the one thing
     * this table must not have: two ways for a task to be written, only one of
     * which keeps the journal honest. Anybody adding a field here gets the
     * guarantee without having to notice it.
     */
    const task = await prisma.$transaction(async (tx) => {
      const updated = await tx.task.update({ where: { id }, data });

      for (const event of movement.events) {
        await tx.taskEvent.create({ data: { taskId: id, ...event } });
      }

      return updated;
    });

    reply.send(task);
  });

  app.patch("/tasks/:id/position", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const body = updateTaskPositionSchema.parse(request.body);
    const task = await getTaskOrThrow(id);

    const beforeId = body.beforeTaskId ?? null;
    const afterId = body.afterTaskId ?? null;

    if (beforeId === id || afterId === id) {
      throw new ValidationError("A task cannot be positioned relative to itself");
    }

    async function resolveNeighborPosition(neighborId: string | null): Promise<number | null> {
      if (neighborId === null) return null;
      const neighbor = await prisma.task.findUnique({ where: { id: neighborId } });
      if (!neighbor || neighbor.projectId !== task.projectId) {
        throw new ValidationError(`Neighbor task ${neighborId} was not found in this project`);
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

      // Neighbours are too close together to bisect further: renumber every
      // task in the project with fresh, evenly-spaced positions, then retry
      // the move once using the freshly rebalanced neighbour positions.
      const allTasks = await prisma.task.findMany({
        where: { projectId: task.projectId },
        orderBy: { position: "asc" },
      });
      const rebalanced = computeRebalancedPositions(allTasks.map((t) => t.id));

      await prisma.$transaction(
        rebalanced.map((r) => prisma.task.update({ where: { id: r.id }, data: { position: r.position } })),
      );

      beforePosition = beforeId
        ? (rebalanced.find((r) => r.id === beforeId)?.position ?? null)
        : null;
      afterPosition = afterId ? (rebalanced.find((r) => r.id === afterId)?.position ?? null) : null;

      newPosition = computePositionBetween(beforePosition, afterPosition);
    }

    const updated = await prisma.task.update({ where: { id }, data: { position: newPosition } });
    reply.send(updated);
  });

  /*
   * The life of one task, for the section of the task screen with that name
   * (F11, `design/reference/Edit.html`).
   *
   * Separate from `GET /projects/:projectId/tasks` rather than an `include` on
   * it, because the journal is read for exactly one task at a time -- the one
   * that is open -- while the list is read for every task in a project on every
   * visit. Attaching it to the list would multiply the heaviest table in the
   * schema by the screen that is opened most often, to draw something no list
   * row shows.
   *
   * Ascending `at`, which is both how the section reads and the order
   * `replayStatusTime` requires; the `[taskId, at]` index serves it directly.
   * The rows go out as they are stored: this is the one place where the raw
   * journal is the answer, and a client that wants "3 дня в blocked" gets that
   * from `GET /history` instead of recomputing it here.
   */
  app.get("/tasks/:id/events", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    await getTaskOrThrow(id);

    const events = await prisma.taskEvent.findMany({
      where: { taskId: id },
      orderBy: { at: "asc" },
    });
    reply.send(events);
  });

  /*
   * Deleting a task takes its journal with it (`onDelete: Cascade`), so there
   * is nothing to clean up here. That is the schema's decision and the note on
   * the model explains it: this is the task's own history, not an audit trail.
   */
  app.delete("/tasks/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    await getTaskOrThrow(id);
    await prisma.task.delete({ where: { id } });
    reply.status(204).send();
  });
}
