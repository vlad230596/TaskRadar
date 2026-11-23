import { FastifyInstance } from "fastify";
import { Prisma } from "@prisma/client";
import { prisma } from "../lib/prisma";
import { userIdOf } from "../lib/users";
import { ValidationError } from "../lib/errors";
import { focusQuerySchema, focusTaskSchema, idParamSchema } from "../schemas";
import { getTaskOrThrow } from "./tasks";
import { taskInclude, taskView } from "../domain/taskView";
import { defaultContour, ownedContour } from "../domain/contours";

/*
 * The working set (F11): the two to five tasks the "work" mode shows, one of
 * them large and the rest underneath.
 *
 * WHY THE SET LIVES ON THE SERVER
 *
 * It could have been a list of ids in the client's own storage, and that is
 * cheaper in every way except the one that matters: the set is assembled at a
 * desk, where fifteen projects fit on one screen and choosing is easy, and then
 * worked through from a phone in a queue somewhere. A set kept on the device
 * that assembled it is a set the device that needs it cannot see.
 *
 * WHY THERE IS NO LIMIT OF FIVE HERE
 *
 * Five is what fits on the screen and what a person can hold in mind -- the
 * header draws five slots (`design/reference/Pick.html`). The server has no way
 * to know that, and enforcing it would mean a 409 whose message can only be a
 * restatement of a layout decision. If the number ever changes, it changes in
 * one place; and a set of six built by curl is a screen that scrolls, not a
 * corrupt database.
 *
 * Both writes below go through a transaction with their journal row, for the
 * same reason every other task write does: `focusedAt` with no `focused` event
 * to explain it is a task that entered the set at a time nobody recorded.
 *
 * ONE SET PER CONTOUR (design/goals-ideas-contract.md)
 *
 * Since contours, "the set" is the set of one contour: `Task.focusContourId`
 * says whose. "Работа" and "Личное" each keep their own handful, and the work
 * screen shows the active contour's. A task is in at most one set -- it has
 * one `focusContourId` -- and taking it into another contour's set moves it
 * there rather than adding a second membership.
 */
export async function focusRoutes(app: FastifyInstance): Promise<void> {
  /*
   * The set itself, in the order it was built.
   *
   * The project is included -- id and name only -- because the work screen
   * labels every task with the project it belongs to, and that is the whole
   * point of a set drawn from fifteen of them. Fetching it here rather than
   * letting the client join against its cached board keeps the phone right when
   * the board it cached is stale, and costs one `IN (...)`.
   *
   * Archived projects are NOT filtered out. A task somebody deliberately put in
   * the set does not silently vanish from the one screen they will be looking
   * at because the project around it was tidied away; the archive hides
   * projects from the board, which is a different question.
   *
   * `?contourId=` narrows it to one contour's set. Without it, every set at
   * once, as before contours -- an older app keeps working, and each task says
   * which set it is in (`focusContourId`). Someone else's contour id is not
   * refused; it simply matches none of this user's tasks. The owner filter is
   * what keeps people apart, not the id.
   */
  app.get("/focus", async (request, reply) => {
    const userId = userIdOf(request);
    const { contourId } = focusQuerySchema.parse(request.query);
    /*
     * A task in the set with no contour (picked by a backend from before
     * contours, e.g. during a rollback) belongs to the default contour, which
     * is where it would have gone -- so it is not invisible on every screen.
     */
    let contourFilter: Prisma.TaskWhereInput = {};
    if (contourId !== undefined) {
      const isDefault = (await defaultContour(prisma, userId)).id === contourId;
      contourFilter = isDefault
        ? { OR: [{ focusContourId: contourId }, { focusContourId: null }] }
        : { focusContourId: contourId };
    }
    const tasks = await prisma.task.findMany({
      where: {
        focusedAt: { not: null },
        ...contourFilter,
        project: { scope: { userId } },
      },
      orderBy: { focusedAt: "asc" },
      include: { project: { select: { id: true, name: true } }, ...taskInclude },
    });
    reply.send(tasks.map(taskView));
  });

  /*
   * Put a task in the set.
   *
   * Idempotent, and that is a decision rather than a shortcut: a task already
   * in the set keeps the `focusedAt` it has and records nothing. Re-stamping it
   * would move it to the end of the set -- the order is `focusedAt` -- so a
   * double tap on a phone, or a retried request, would silently reorder the
   * work the person is in the middle of.
   *
   * `{ contourId }` names whose set; without it, the default contour's (the
   * first by position) -- which is also what an app from before contours gets,
   * since it sends no body at all. A task already in another contour's set is
   * moved to this one, and only `focusContourId` changes: `focusedAt` is when
   * it was picked, which this is not, and no journal row is written -- the
   * journal records entering and leaving work, and the task never left.
   *
   * A contour that is not the user's is a 400, not a 404: the task exists, the
   * request is what is wrong (as for a category, ./tasks.ts).
   */
  app.post("/tasks/:id/focus", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const userId = userIdOf(request);
    const body = focusTaskSchema.parse(request.body);
    const task = await getTaskOrThrow(userId, id);

    let contourId: string;
    if (body.contourId !== undefined) {
      const contour = await ownedContour(prisma, userId, body.contourId);
      if (contour === null) throw new ValidationError(`Contour ${body.contourId} was not found`);
      contourId = contour.id;
    } else {
      contourId = (await defaultContour(prisma, userId)).id;
    }

    const updated = await prisma.$transaction(async (tx) => {
      if (task.focusedAt !== null) {
        // Read rather than an empty update, which would still bump `updatedAt`.
        if (task.focusContourId === contourId) {
          return tx.task.findUniqueOrThrow({ where: { id }, include: taskInclude });
        }
        return tx.task.update({
          where: { id },
          data: { focusContourId: contourId },
          include: taskInclude,
        });
      }
      const focused = await tx.task.update({
        where: { id },
        data: { focusedAt: new Date(), focusContourId: contourId },
        include: taskInclude,
      });
      await tx.taskEvent.create({ data: { taskId: id, kind: "focused" } });
      return focused;
    });

    reply.send(taskView(updated));
  });

  /*
   * Take it back out. Idempotent in the same way and for a plainer reason:
   * removing something that is not there is not an error anybody can act on,
   * and the client's next read shows the set it expected either way.
   *
   * Leaving the set leaves the contour's set too: `focusContourId` is cleared
   * with `focusedAt`, so a task out of work belongs to no contour's set.
   *
   * Note that this is not the only way out of the set -- finishing a task
   * leaves it too, from `PATCH /tasks/:id`. See ../domain/taskEvents.ts.
   */
  app.delete("/tasks/:id/focus", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const task = await getTaskOrThrow(userIdOf(request), id);

    const updated = await prisma.$transaction(async (tx) => {
      if (task.focusedAt === null) {
        return tx.task.findUniqueOrThrow({ where: { id }, include: taskInclude });
      }
      const unfocused = await tx.task.update({
        where: { id },
        data: { focusedAt: null, focusContourId: null },
        include: taskInclude,
      });
      await tx.taskEvent.create({ data: { taskId: id, kind: "unfocused" } });
      return unfocused;
    });

    reply.send(taskView(updated));
  });
}
