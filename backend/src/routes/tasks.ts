import { FastifyInstance } from "fastify";
import type { z } from "zod";
import { prisma } from "../lib/prisma";
import { userIdOf } from "../lib/users";
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
  moveTaskSchema,
  idParamSchema,
  projectIdParamSchema,
} from "../schemas";
import { linkDictationParse } from "../domain/dictationLink";
import { aiClearData, aiMarkFields } from "../domain/aiMark";
import { getProjectOrThrow } from "./projects";
import { isUniqueConstraintViolation } from "../lib/prismaErrors";
import {
  checklistColumn,
  checklistOf,
  locationColumns,
  sameChecklist,
  sameLocation,
  taskInclude,
  taskView,
} from "../domain/taskView";

export async function getTaskOrThrow(userId: string, id: string) {
  // A task belongs to whoever owns its project's scope.
  const task = await prisma.task.findFirst({
    where: { id, project: { scope: { userId } } },
  });
  if (!task) {
    throw new NotFoundError("Task");
  }
  return task;
}

/**
 * Refuses a category that is not one of this project's. Null and undefined
 * pass: "без категории" and "unchanged" need no lookup.
 *
 * A 400 rather than a 404: the task exists, the request is what is wrong. And
 * the same answer for a category of another project as for one of another
 * user, so the reply says nothing about what exists elsewhere.
 */
async function assertCategoryInProject(
  categoryId: string | null | undefined,
  projectId: string,
): Promise<void> {
  if (categoryId === null || categoryId === undefined) return;
  const category = await prisma.taskCategory.findFirst({ where: { id: categoryId, projectId } });
  if (!category) {
    throw new ValidationError(`Category ${categoryId} was not found in this project`);
  }
}

type Task = Awaited<ReturnType<typeof getTaskOrThrow>>;
type TaskPatch = z.infer<typeof updateTaskSchema>;

/** The fields `expected` may describe, in the order a 409 lists them. */
const CHECKED_FIELDS = [
  "title",
  "description",
  "categoryId",
  "status",
  "remindAt",
  "remindTime",
  // Task editor (design/task-editor-spec.md §10): compared whole, see sameValue.
  "checklist",
  "location",
] as const;
type CheckedField = (typeof CHECKED_FIELDS)[number];

/**
 * Whether two values of one task field mean the same thing.
 *
 * `remindAt` is a calendar date stored as UTC midnight, and everything that
 * reads it takes the `YYYY-MM-DD` prefix (see `remindTime` on the model), so
 * that prefix is what is compared. A description of `""` and of `null` are both
 * "no description" -- a client that normalised one into the other is not
 * looking at a different task. Everything else compares as stored, with
 * `undefined` read as `null`.
 */
function sameValue(field: CheckedField, a: unknown, b: unknown): boolean {
  if (field === "remindAt") {
    const day = (v: unknown) => (v instanceof Date ? v.toISOString().slice(0, 10) : null);
    return day(a) === day(b);
  }
  if (field === "description") return (a || null) === (b || null);
  // The whole list, item by item, in order; `[]` and null are both "no list".
  if (field === "checklist") return sameChecklist(a, b);
  if (field === "location") return sameLocation(a, b);
  return (a ?? null) === (b ?? null);
}

/**
 * The fields of [body] whose base the task no longer has: for each field the
 * client both changes and states an `expected` value for, a conflict is the
 * task's current value differing from the expected one -- *unless* the task
 * already holds the value being asked for. That exception is what makes a
 * retry safe: an edit that landed and whose answer was lost comes back with a
 * base that no longer matches, and turning it into a conflict would ask the
 * user to resolve a disagreement with themselves.
 *
 * Fields described in `expected` but not being changed are ignored: the client
 * is not overwriting them, so whatever happened to them is not this edit's
 * business.
 */
function conflictingFields(before: Task, body: TaskPatch): CheckedField[] {
  const expected = body.expected;
  if (expected === undefined) return [];
  // The task as the API shows it: `location` is one value there, four columns in the row.
  const shown = taskView(before);
  return CHECKED_FIELDS.filter((field) => {
    if (body[field] === undefined || expected[field] === undefined) return false;
    const current = shown[field];
    if (sameValue(field, current, body[field])) return false;
    return !sameValue(field, current, expected[field]);
  });
}

export async function taskRoutes(app: FastifyInstance): Promise<void> {
  /*
   * Creating a task -- and, since the offline outbox, optionally with the
   * client's idempotency key `createKey`.
   *
   * The design is `POST /inbox`'s `captureKey`, and its note says why a queue
   * needs one. In short: a queued create retried after a lost answer must not
   * become a twin. A known key answers 200 with the task as it stands now --
   * not rewritten from the replayed body, which would let a late duplicate
   * undo an edit made since -- and writes nothing, so no second `created`
   * event either. A new key answers 201, as a create without one always has.
   *
   * The key is looked up within the project, which is what the unique index
   * covers (see `@@unique([projectId, createKey])` in schema.prisma for why
   * per project is per user). A task deleted (or unfiled) since is not
   * remembered: a replay arriving after that creates it again, exactly as a
   * replayed inbox capture does after its line was discarded.
   */
  app.post("/projects/:projectId/tasks", async (request, reply) => {
    const { projectId } = projectIdParamSchema.parse(request.params);
    const userId = userIdOf(request);
    const body = createTaskSchema.parse(request.body);
    const { createKey } = body;
    await getProjectOrThrow(userId, projectId);

    if (createKey !== undefined) {
      const known = await prisma.task.findUnique({
        where: { projectId_createKey: { projectId, createKey } },
        include: taskInclude,
      });
      if (known) {
        reply.status(200).send(taskView(known));
        return;
      }
    }

    await assertCategoryInProject(body.categoryId, projectId);

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
    const create = () =>
      prisma.$transaction(async (tx) => {
        // A dictated or tidied task remembers the words it came from: ../domain/aiMark.ts.
        const ai = await aiMarkFields(
          tx,
          userId,
          body.dictationParseId,
          ["task", "sandbox", "task_tidy"],
          null,
          { title: body.title, description: body.description ?? null },
        );
        const created = await tx.task.create({
          data: {
            ...ai,
            projectId,
            title: body.title,
            description: body.description ?? null,
            categoryId: body.categoryId ?? null,
            ...(body.status !== undefined ? { status: body.status } : {}),
            remindAt: body.remindAt ?? null,
            // A time with no day is not a reminder; see `remindTime` on the model.
            remindTime: body.remindAt ? (body.remindTime ?? null) : null,
            position,
            ...(createKey !== undefined ? { createKey } : {}),
            ...checklistColumn(body.checklist),
            ...locationColumns(body.location),
          },
          include: taskInclude,
        });

        await tx.taskEvent.create({
          data: { taskId: created.id, kind: "created", toStatus: created.status },
        });

        /*
         * A dictated task (F14): link the dataset row and snapshot what was kept
         * -- the proposal after the user's corrections, the label a replay of
         * this input is scored against. A no-op for an unknown or already
         * labelled row; see ../domain/dictationLink.ts. Three kinds end as a new
         * task: a dictation parsed as one, a sandbox answer whose project was
         * taken, and a draft task tidied before its first save.
         */
        if (body.dictationParseId !== undefined) {
          await linkDictationParse(
            tx,
            userId,
            body.dictationParseId,
            ["task", "sandbox", "task_tidy"],
            {
              taskId: created.id,
              finalTitle: created.title,
              finalDescription: created.description,
              finalRemindAt: created.remindAt,
            },
          );
        }

        return created;
      });

    try {
      reply.status(201).send(taskView(await create()));
    } catch (error) {
      // Two copies of the same retry in flight at once: both found no task
      // above, and the unique index caught the loser inside its transaction,
      // which rolled back whole -- its `created` event included. Answer it as
      // the replay it is. Anything else is a real error.
      if (createKey === undefined || !isUniqueConstraintViolation(error)) throw error;
      const raced = await prisma.task.findUnique({
        where: { projectId_createKey: { projectId, createKey } },
        include: taskInclude,
      });
      if (!raced) throw error;
      reply.status(200).send(taskView(raced));
    }
  });

  app.get("/projects/:projectId/tasks", async (request, reply) => {
    const { projectId } = projectIdParamSchema.parse(request.params);
    await getProjectOrThrow(userIdOf(request), projectId);

    const tasks = await prisma.task.findMany({
      where: { projectId },
      orderBy: { position: "asc" },
      include: taskInclude,
    });
    reply.send(annotateIsCurrent(tasks.map(taskView)));
  });

  app.patch("/tasks/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const userId = userIdOf(request);
    const body = updateTaskSchema.parse(request.body);
    const before = await getTaskOrThrow(userId, id);

    /*
     * The offline outbox's conflict check (`expected` in ../schemas.ts): an
     * edit made against a task that has since changed under it, in a field
     * this edit would overwrite, is refused whole -- 409, nothing written, no
     * journal row -- and the reply carries the task as it now stands, in the
     * shape this route answers with, so the client can show both versions
     * without another round trip. Rules in `conflictingFields`.
     *
     * Checked against the row read just above, before any write. That leaves
     * a window: an edit committed between this read and the transaction below
     * is overwritten unchecked. Closing it would take `SELECT ... FOR UPDATE`
     * or a conditional `updateMany` on every checked field inside the
     * transaction; for one person's devices replaying an outbox the window is
     * milliseconds against the hours the check exists for, so it stays open
     * on purpose.
     */
    const conflicts = conflictingFields(before, body);
    if (conflicts.length > 0) {
      const attachments = await prisma.taskAttachment.findMany({
        where: { taskId: id },
        ...taskInclude.attachments,
      });
      reply
        .status(409)
        .send({ error: "conflict", fields: conflicts, task: taskView({ ...before, attachments }) });
      return;
    }

    await assertCategoryInProject(body.categoryId, before.projectId);

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
      categoryId?: string | null;
      status?: "pending" | "done" | "blocked";
      remindAt?: Date | null;
      remindTime?: string | null;
      focusedAt?: Date | null;
    } = {};
    if (body.title !== undefined) data.title = body.title;
    if (body.description !== undefined) data.description = body.description;
    if (body.categoryId !== undefined) data.categoryId = body.categoryId;
    if (body.status !== undefined) data.status = body.status;
    if (body.remindAt !== undefined) data.remindAt = body.remindAt;
    /*
     * The time of day goes with the date (`remindTime` on the model): clearing
     * the date clears the time, and a time is refused on a task that would be
     * left without a date -- it would sit there invisibly and come back the day
     * somebody sets a date, at an hour they never picked for it.
     */
    if (body.remindAt === null) {
      data.remindTime = null;
    } else if (body.remindTime !== undefined) {
      const date = body.remindAt !== undefined ? body.remindAt : before.remindAt;
      if (date === null && body.remindTime !== null) {
        throw new ValidationError("remindTime needs a reminder date (remindAt)");
      }
      data.remindTime = body.remindTime;
    }
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
      /*
       * AI on this task (../domain/aiMark.ts): an answer saved marks it, with
       * the fields as this save leaves them; "вернуть исходник" unmarks it.
       */
      const ai = body.aiClear
        ? aiClearData()
        : await aiMarkFields(
            tx,
            userId,
            body.dictationParseId,
            ["task_tidy", "note"],
            before.aiSource,
            {
              title: data.title ?? before.title,
              description: data.description !== undefined ? data.description : before.description,
            },
          );
      const updated = await tx.task.update({
        where: { id },
        data: {
          ...data,
          ...ai,
          ...checklistColumn(body.checklist),
          ...locationColumns(body.location),
        },
        include: taskInclude,
      });

      for (const event of movement.events) {
        await tx.taskEvent.create({ data: { taskId: id, ...event } });
      }

      /*
       * "Причесать" on this task (F15), saved: the `task_tidy` row learns the
       * task and the text as it now stands -- the answer after the user's
       * corrections. Same rules as for a new task; see
       * ../domain/dictationLink.ts.
       */
      if (body.dictationParseId !== undefined) {
        await linkDictationParse(tx, userId, body.dictationParseId, ["task_tidy"], {
          taskId: updated.id,
          finalTitle: updated.title,
          finalDescription: updated.description,
        });
        // The description alone, tidied as a body of text: labelled as one.
        await linkDictationParse(tx, userId, body.dictationParseId, ["note"], {
          taskId: updated.id,
          finalContent: updated.description,
        });
      }

      return updated;
    });

    reply.send(taskView(task));
  });

  app.patch("/tasks/:id/position", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const body = updateTaskPositionSchema.parse(request.body);
    const task = await getTaskOrThrow(userIdOf(request), id);

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
        rebalanced.map((r) =>
          prisma.task.update({ where: { id: r.id }, data: { position: r.position } }),
        ),
      );

      beforePosition = beforeId
        ? (rebalanced.find((r) => r.id === beforeId)?.position ?? null)
        : null;
      afterPosition = afterId ? (rebalanced.find((r) => r.id === afterId)?.position ?? null) : null;

      newPosition = computePositionBetween(beforePosition, afterPosition);
    }

    const updated = await prisma.task.update({
      where: { id },
      data: { position: newPosition },
      include: taskInclude,
    });
    reply.send(taskView(updated));
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
    await getTaskOrThrow(userIdOf(request), id);

    const events = await prisma.taskEvent.findMany({
      where: { taskId: id },
      orderBy: { at: "asc" },
    });
    reply.send(events);
  });

  /*
   * To another project: `{ projectId }`, one of the same user's projects.
   *
   * A route of its own rather than `projectId` in `PATCH /tasks/:id`, for the
   * reason `/position` and `/unfile` are their own: changing a task's home is
   * not a field edit. It decides the task's place in a list the client did not
   * send, drops a category that does not exist over there, and changes two
   * lists at once -- and the PATCH's `expected` check, built for fields, has
   * nothing to say about any of it.
   *
   * What the move does:
   *
   * - **last in the target project**, as a new task would be
   *   (`computeAppendPosition`). The old place means nothing in a list of other
   *   tasks, and the end is where a newcomer is looked for;
   * - **no category**: categories are per project (`TaskCategory`), and the
   *   task's group stays behind. The client cannot pick one here either -- a
   *   category of the target is chosen on the task screen afterwards, as for
   *   any task;
   * - **`createKey` cleared**: it is unique per project, and a key arriving in
   *   another project could in principle meet its twin there. Nothing is lost:
   *   a replay of the create names the *old* project and would not have found
   *   the task in the new one anyway;
   * - status, reminder, the working set (which spans projects) and the journal
   *   stay as they are. The journal records status and focus, not location --
   *   history reads a task's project from the task -- so a move writes no event.
   *
   * The same project is not an error: the answer is the task, unchanged.
   * That is what makes the offline outbox's replay of a move that already
   * landed harmless.
   *
   * A target the user does not own, or that does not exist, is a 400 rather
   * than a 404 -- the task exists, the request is what is wrong -- and the same
   * answer for both, as for a category (`assertCategoryInProject`). An
   * archived project is accepted, as `POST /projects/:id/tasks` accepts one:
   * the app offers only the board's projects, and the server does not second-
   * guess which projects are worth writing to.
   *
   * There is no push channel: other devices see the move on their next read
   * of either list, as they see every other write.
   */
  app.post("/tasks/:id/move", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const userId = userIdOf(request);
    const { projectId } = moveTaskSchema.parse(request.body);
    const task = await getTaskOrThrow(userId, id);

    const target = await prisma.project.findFirst({
      where: { id: projectId, scope: { userId } },
    });
    if (!target) {
      throw new ValidationError(`Project ${projectId} was not found`);
    }

    if (task.projectId === projectId) {
      reply.send(task);
      return;
    }

    const last = await prisma.task.aggregate({
      where: { projectId },
      _max: { position: true },
    });

    const moved = await prisma.task.update({
      where: { id },
      data: {
        projectId,
        position: computeAppendPosition(last._max.position),
        categoryId: null,
        createKey: null,
      },
    });
    reply.send(moved);
  });

  /*
   * Back to the sandbox: the task becomes an inbox line again, and stops being
   * a task -- `POST /inbox/:id/file` run backwards.
   *
   * For the task filed into the wrong project, typically because the right
   * one does not exist yet: moving it would need that project first, and the
   * sandbox is exactly the place for a thought whose home is not decided.
   *
   * The line is the title, and the description under it on its own line. A
   * line break always ends the title when the line is filed again
   * (../domain/inboxSplit.ts), so filing it back gives the same title and
   * description -- nothing the user wrote is lost on the way round.
   *
   * What does not survive is what only a task has: status, reminder, place in
   * the working set, and the journal (`onDelete: Cascade`). That is the point
   * rather than a loss -- an inbox item has none of those on purpose (see the
   * note at the top of ./inbox.ts), and a re-filed line starts a new life.
   *
   * One transaction, for the same two half-done states filing avoids: the
   * line created and the task left behind, or the task gone and no line.
   */
  app.post("/tasks/:id/unfile", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const userId = userIdOf(request);
    const task = await getTaskOrThrow(userId, id);

    const lines = task.description?.trim()
      ? `${task.title}\n${task.description.trim()}`
      : task.title;
    /*
     * Task editor (design/task-editor-spec.md §10): a checklist survives as
     * `- ` lines under the text -- the sandbox has no list, but the words are
     * the user's. The place does not survive (an inbox line has no place), and
     * the pictures go with the task's rows; their files are swept later
     * (src/scripts/sweepAttachments.ts). The client asks first when there are
     * any.
     */
    const items = checklistOf(task) ?? [];
    const text =
      items.length > 0
        ? `${lines}\n${items.map((item) => `- ${item.text.replace(/\s*\n\s*/g, " ")}`).join("\n")}`
        : lines;

    const item = await prisma.$transaction(async (tx) => {
      const created = await tx.inboxItem.create({ data: { userId, text } });
      await tx.task.delete({ where: { id } });
      return created;
    });

    reply.status(201).send(item);
  });

  /*
   * Deleting a task takes its journal with it (`onDelete: Cascade`), so there
   * is nothing to clean up here. That is the schema's decision and the note on
   * the model explains it: this is the task's own history, not an audit trail.
   */
  app.delete("/tasks/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    await getTaskOrThrow(userIdOf(request), id);
    await prisma.task.delete({ where: { id } });
    reply.status(204).send();
  });
}
