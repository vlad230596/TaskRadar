import { FastifyInstance } from "fastify";
import { Prisma } from "@prisma/client";
import { prisma } from "../lib/prisma";
import { userIdOf } from "../lib/users";
import { ConflictError, HttpError, NotFoundError, ValidationError } from "../lib/errors";
import {
  computeAppendPosition,
  computePositionBetween,
  computeRebalancedPositions,
  PositionExhaustedError,
} from "../domain/position";
import { ownedContour } from "../domain/contours";
import {
  effectiveWindowDays,
  extendedWindowEnd,
  goalInclude,
  goalState,
  goalStateWhere,
  goalView,
  windowEnd,
} from "../domain/goals";
import {
  createGoalSchema,
  goalIdeaParamSchema,
  goalTaskParamSchema,
  idParamSchema,
  listGoalsQuerySchema,
  moveGoalTaskSchema,
  slotGoalSchema,
  updateGoalSchema,
} from "../schemas";

/*
 * Goals (design/goals-ideas-contract.md): a few results the owner pushes for a
 * window at a time, each in one of its contour's slots, each with a "why" and
 * a next step.
 *
 * Every answer that describes a goal is the whole `GoalView`
 * (../domain/goals.ts) -- its tasks, next step, ideas and progress -- read
 * back after the write. A goal is small (a handful of tasks), and one shape
 * everywhere means the app replaces its cached goal with whatever came back,
 * whichever button was pressed.
 *
 * Ownership: a goal carries `userId` (it is a root, see `User` in
 * schema.prisma), so every lookup filters on it; a task or an idea joined to
 * a goal is checked through its project's scope, like everywhere else.
 * Somebody else's goal is a 404 exactly like a missing one.
 *
 * Writes of goals are online-only in this iteration (the contract): there is
 * no idempotency key here, because there is no outbox to replay them.
 */

/**
 * 409 `{ error: "slots_full" }`: the contour's slots are taken. Its own error
 * name, not a plain Conflict, because the app answers it with a specific
 * screen ("освободить слот?"), and switching on a message string is fragile.
 */
class SlotsFullError extends HttpError {
  constructor(slots: number) {
    super(409, `All ${slots} slot(s) of this contour are taken`, { slots });
    this.name = "slots_full";
  }
}

type Db = Prisma.TransactionClient;

async function getGoalOrThrow(db: Db, userId: string, id: string) {
  const goal = await db.goal.findFirst({ where: { id, userId } });
  if (!goal) throw new NotFoundError("Goal");
  return goal;
}

async function contourOr400(db: Db, userId: string, contourId: string) {
  const contour = await ownedContour(db, userId, contourId);
  if (contour === null) throw new ValidationError(`Contour ${contourId} was not found`);
  return contour;
}

/**
 * Refuses a goal into [contour]'s slots when they are all taken by others.
 *
 * Counted inside the caller's transaction, but not under a lock: two slot
 * requests racing for the last slot can both pass. That is accepted on
 * purpose -- one person's devices do not race for slots, and the outcome is
 * the same "more goals than slots" that lowering `slots` produces anyway,
 * which the app already shows as an overflow.
 */
async function assertSlotFree(
  db: Db,
  contour: { id: string; slots: number },
  exceptGoalId: string | null,
): Promise<void> {
  const taken = await db.goal.count({
    where: {
      contourId: contour.id,
      ...goalStateWhere(["slot"]),
      ...(exceptGoalId !== null ? { id: { not: exceptGoalId } } : {}),
    },
  });
  if (taken >= contour.slots) throw new SlotsFullError(contour.slots);
}

/** Position for a goal appended to the end of [contourId]'s order. */
async function appendGoalPosition(db: Db, contourId: string): Promise<number> {
  const last = await db.goal.aggregate({ where: { contourId }, _max: { position: true } });
  return computeAppendPosition(last._max.position);
}

/** The goal as the API shows it, read fresh. */
async function viewOf(db: Db, id: string) {
  return goalView(await db.goal.findUniqueOrThrow({ where: { id }, include: goalInclude }));
}

/** A task of [userId]'s, or a 404 naming it. */
async function assertOwnTask(db: Db, userId: string, taskId: string): Promise<void> {
  const task = await db.task.findFirst({
    where: { id: taskId, project: { scope: { userId } } },
    select: { id: true },
  });
  if (!task) throw new NotFoundError("Task");
}

export async function goalRoutes(app: FastifyInstance): Promise<void> {
  /*
   * `?state=slot,bench` by default -- what the planning screen and the work
   * screen's block show; `achieved` is asked for separately by the history
   * screen, so a long list of finished goals is not carried on every read.
   * Ordered by contour, then by position within it, which is the order both
   * screens draw.
   */
  app.get("/goals", async (request, reply) => {
    const userId = userIdOf(request);
    const query = listGoalsQuerySchema.parse(request.query);
    const rows = await prisma.goal.findMany({
      where: {
        userId,
        ...(query.contourId !== undefined ? { contourId: query.contourId } : {}),
        ...goalStateWhere(query.state),
      },
      orderBy: [{ contour: { position: "asc" } }, { position: "asc" }],
      include: goalInclude,
    });
    const now = new Date();
    reply.send(rows.map((row) => goalView(row, now)));
  });

  app.get("/goals/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    await getGoalOrThrow(prisma, userIdOf(request), id);
    reply.send(await viewOf(prisma, id));
  });

  /*
   * A new goal goes last in its contour, on the bench -- or straight into a
   * slot with `slot: true`, refused whole (nothing created) when the slots
   * are taken, so the app can offer "на скамейку" instead without a goal
   * already half-made.
   */
  app.post("/goals", async (request, reply) => {
    const userId = userIdOf(request);
    const body = createGoalSchema.parse(request.body);
    const view = await prisma.$transaction(async (tx) => {
      const contour = await contourOr400(tx, userId, body.contourId);
      const now = new Date();
      if (body.slot === true) await assertSlotFree(tx, contour, null);
      const goal = await tx.goal.create({
        data: {
          userId,
          contourId: contour.id,
          title: body.title,
          why: body.why ?? null,
          position: await appendGoalPosition(tx, contour.id),
          ...(body.slot === true
            ? { slottedAt: now, windowEndsAt: windowEnd(now, contour.windowDays) }
            : {}),
        },
      });
      return viewOf(tx, goal.id);
    });
    reply.status(201).send(view);
  });

  /*
   * Fields only; moving between slot, bench and achieved has routes of its
   * own below, because each is a decision with its own rule.
   *
   * Moving to another contour keeps the goal's state. A goal in a slot needs
   * a free slot over there (409 `slots_full` otherwise) -- carrying it across
   * would quietly overfill a contour the owner did not touch. It goes to the
   * end of the new contour's order unless a position is given.
   *
   * Changing `windowDays` does not move a running window's end: it applies
   * from the next slot or extension, so a goal does not silently become
   * overdue because a setting changed.
   */
  app.patch("/goals/:id", async (request, reply) => {
    const userId = userIdOf(request);
    const { id } = idParamSchema.parse(request.params);
    const body = updateGoalSchema.parse(request.body);
    const view = await prisma.$transaction(async (tx) => {
      const goal = await getGoalOrThrow(tx, userId, id);
      const data: Prisma.GoalUncheckedUpdateInput = {};
      if (body.title !== undefined) data.title = body.title;
      if (body.why !== undefined) data.why = body.why;
      if (body.windowDays !== undefined) data.windowDays = body.windowDays;
      if (body.position !== undefined) data.position = body.position;
      if (body.contourId !== undefined && body.contourId !== goal.contourId) {
        const target = await contourOr400(tx, userId, body.contourId);
        if (goalState(goal) === "slot") await assertSlotFree(tx, target, goal.id);
        data.contourId = target.id;
        if (body.position === undefined) data.position = await appendGoalPosition(tx, target.id);
      }
      await tx.goal.update({ where: { id }, data });
      return viewOf(tx, id);
    });
    reply.send(view);
  });

  /*
   * Into a slot: `slottedAt = now`, a fresh window from now. `{ windowDays }`
   * sets the goal's own window first (and keeps it for later windows).
   *
   * Already in a slot: nothing changes -- a double tap must not restart the
   * window. Achieved: 409, the goal is reopened first (`/reopen`), so
   * "достигнута" cannot be undone by a stray slot button.
   */
  app.post("/goals/:id/slot", async (request, reply) => {
    const userId = userIdOf(request);
    const { id } = idParamSchema.parse(request.params);
    const body = slotGoalSchema.parse(request.body);
    const view = await prisma.$transaction(async (tx) => {
      const goal = await getGoalOrThrow(tx, userId, id);
      const state = goalState(goal);
      if (state === "achieved") throw new ConflictError("The goal is achieved; reopen it first");
      if (state === "slot") return viewOf(tx, id);
      const contour = await tx.contour.findUniqueOrThrow({ where: { id: goal.contourId } });
      await assertSlotFree(tx, contour, goal.id);
      const ownWindow = body.windowDays ?? goal.windowDays;
      const now = new Date();
      await tx.goal.update({
        where: { id },
        data: {
          slottedAt: now,
          windowDays: ownWindow,
          windowEndsAt: windowEnd(now, effectiveWindowDays({ windowDays: ownWindow }, contour)),
        },
      });
      return viewOf(tx, id);
    });
    reply.send(view);
  });

  /*
   * "Оставить": one more window, from the later of now and the current end
   * (`extendedWindowEnd`). Only for a goal in a slot -- a benched goal has no
   * window to extend, and quietly slotting it here would bypass the slot
   * limit.
   */
  app.post("/goals/:id/extend", async (request, reply) => {
    const userId = userIdOf(request);
    const { id } = idParamSchema.parse(request.params);
    const view = await prisma.$transaction(async (tx) => {
      const goal = await getGoalOrThrow(tx, userId, id);
      if (goalState(goal) !== "slot") throw new ConflictError("Only a goal in a slot can be extended");
      const contour = await tx.contour.findUniqueOrThrow({ where: { id: goal.contourId } });
      await tx.goal.update({
        where: { id },
        data: {
          windowEndsAt: extendedWindowEnd(
            new Date(),
            goal.windowEndsAt,
            effectiveWindowDays(goal, contour),
          ),
        },
      });
      return viewOf(tx, id);
    });
    reply.send(view);
  });

  /** To the bench. Idempotent; an achieved goal stays achieved (that is `/reopen`). */
  app.post("/goals/:id/bench", async (request, reply) => {
    const userId = userIdOf(request);
    const { id } = idParamSchema.parse(request.params);
    const view = await prisma.$transaction(async (tx) => {
      const goal = await getGoalOrThrow(tx, userId, id);
      if (goalState(goal) === "slot") {
        await tx.goal.update({ where: { id }, data: { slottedAt: null, windowEndsAt: null } });
      }
      return viewOf(tx, id);
    });
    reply.send(view);
  });

  /*
   * "Достигнута": only ever by hand. Leaves the slot. Idempotent -- a repeat
   * keeps the first `achievedAt`, which is the date the history screen shows.
   */
  app.post("/goals/:id/achieve", async (request, reply) => {
    const userId = userIdOf(request);
    const { id } = idParamSchema.parse(request.params);
    const view = await prisma.$transaction(async (tx) => {
      const goal = await getGoalOrThrow(tx, userId, id);
      if (goal.achievedAt === null) {
        await tx.goal.update({
          where: { id },
          data: { achievedAt: new Date(), slottedAt: null, windowEndsAt: null },
        });
      }
      return viewOf(tx, id);
    });
    reply.send(view);
  });

  /** Back from achieved, onto the bench -- never straight into a slot. */
  app.post("/goals/:id/reopen", async (request, reply) => {
    const userId = userIdOf(request);
    const { id } = idParamSchema.parse(request.params);
    const view = await prisma.$transaction(async (tx) => {
      const goal = await getGoalOrThrow(tx, userId, id);
      if (goal.achievedAt !== null) {
        await tx.goal.update({
          where: { id },
          data: { achievedAt: null, slottedAt: null, windowEndsAt: null },
        });
      }
      return viewOf(tx, id);
    });
    reply.send(view);
  });

  /** The goal and its links; the tasks and ideas themselves stay. */
  app.delete("/goals/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    await getGoalOrThrow(prisma, userIdOf(request), id);
    await prisma.goal.delete({ where: { id } });
    reply.status(204).send();
  });

  /*
   * Link a task (any of the owner's projects), at the end of the goal's list.
   * Idempotent: an existing link keeps its place -- a retried request must not
   * move the goal's next step.
   */
  app.put("/goals/:id/tasks/:taskId", async (request, reply) => {
    const userId = userIdOf(request);
    const { id, taskId } = goalTaskParamSchema.parse(request.params);
    const view = await prisma.$transaction(async (tx) => {
      await getGoalOrThrow(tx, userId, id);
      await assertOwnTask(tx, userId, taskId);
      const existing = await tx.goalTask.findUnique({
        where: { goalId_taskId: { goalId: id, taskId } },
      });
      if (existing === null) {
        const last = await tx.goalTask.aggregate({
          where: { goalId: id },
          _max: { position: true },
        });
        await tx.goalTask.create({
          data: { goalId: id, taskId, position: computeAppendPosition(last._max.position) },
        });
      }
      return viewOf(tx, id);
    });
    reply.send(view);
  });

  /** Unlink. Idempotent: a link that is not there is the state asked for. */
  app.delete("/goals/:id/tasks/:taskId", async (request, reply) => {
    const userId = userIdOf(request);
    const { id, taskId } = goalTaskParamSchema.parse(request.params);
    const view = await prisma.$transaction(async (tx) => {
      await getGoalOrThrow(tx, userId, id);
      await tx.goalTask.deleteMany({ where: { goalId: id, taskId } });
      return viewOf(tx, id);
    });
    reply.send(view);
  });

  /*
   * Reorder a task within the goal -- which is how the owner chooses the next
   * step. `PATCH /tasks/:id/position` among the goal's links instead of a
   * project's tasks, with the same neighbours-by-id body and the same
   * rebalance fallback (../domain/position.ts). `beforeTaskId` is the task
   * that will come just before this one, `afterTaskId` the one just after.
   */
  app.post("/goals/:id/tasks/:taskId/move", async (request, reply) => {
    const userId = userIdOf(request);
    const { id, taskId } = goalTaskParamSchema.parse(request.params);
    const body = moveGoalTaskSchema.parse(request.body);
    const beforeId = body.beforeTaskId ?? null;
    const afterId = body.afterTaskId ?? null;
    if (beforeId === taskId || afterId === taskId) {
      throw new ValidationError("A task cannot be positioned relative to itself");
    }

    const view = await prisma.$transaction(async (tx) => {
      await getGoalOrThrow(tx, userId, id);
      const link = await tx.goalTask.findUnique({
        where: { goalId_taskId: { goalId: id, taskId } },
      });
      if (!link) throw new NotFoundError("Task in this goal");

      const neighbour = async (neighbourId: string | null): Promise<number | null> => {
        if (neighbourId === null) return null;
        const other = await tx.goalTask.findUnique({
          where: { goalId_taskId: { goalId: id, taskId: neighbourId } },
        });
        if (!other) {
          throw new ValidationError(`Neighbor task ${neighbourId} was not found in this goal`);
        }
        return other.position;
      };

      let position: number;
      try {
        position = computePositionBetween(await neighbour(beforeId), await neighbour(afterId));
      } catch (err) {
        if (!(err instanceof PositionExhaustedError)) throw err;
        const all = await tx.goalTask.findMany({
          where: { goalId: id },
          orderBy: [{ position: "asc" }, { createdAt: "asc" }],
        });
        const rebalanced = computeRebalancedPositions(all.map((row) => row.taskId));
        for (const row of rebalanced) {
          await tx.goalTask.update({
            where: { goalId_taskId: { goalId: id, taskId: row.id } },
            data: { position: row.position },
          });
        }
        const at = (neighbourId: string | null) =>
          neighbourId === null
            ? null
            : (rebalanced.find((row) => row.id === neighbourId)?.position ?? null);
        position = computePositionBetween(at(beforeId), at(afterId));
      }

      await tx.goalTask.update({
        where: { goalId_taskId: { goalId: id, taskId } },
        data: { position },
      });
      return viewOf(tx, id);
    });
    reply.send(view);
  });

  /** Keep an idea (a note of any of the owner's projects) next to the goal. Idempotent. */
  app.put("/goals/:id/ideas/:noteId", async (request, reply) => {
    const userId = userIdOf(request);
    const { id, noteId } = goalIdeaParamSchema.parse(request.params);
    const view = await prisma.$transaction(async (tx) => {
      await getGoalOrThrow(tx, userId, id);
      const note = await tx.note.findFirst({
        where: { id: noteId, project: { scope: { userId } } },
        select: { id: true },
      });
      if (!note) throw new NotFoundError("Idea");
      const existing = await tx.goalIdea.findUnique({
        where: { goalId_noteId: { goalId: id, noteId } },
      });
      if (existing === null) await tx.goalIdea.create({ data: { goalId: id, noteId } });
      return viewOf(tx, id);
    });
    reply.send(view);
  });

  app.delete("/goals/:id/ideas/:noteId", async (request, reply) => {
    const userId = userIdOf(request);
    const { id, noteId } = goalIdeaParamSchema.parse(request.params);
    const view = await prisma.$transaction(async (tx) => {
      await getGoalOrThrow(tx, userId, id);
      await tx.goalIdea.deleteMany({ where: { goalId: id, noteId } });
      return viewOf(tx, id);
    });
    reply.send(view);
  });
}
