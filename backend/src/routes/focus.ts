import { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma";
import { idParamSchema } from "../schemas";
import { getTaskOrThrow } from "./tasks";

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
   */
  app.get("/focus", async (_request, reply) => {
    const tasks = await prisma.task.findMany({
      where: { focusedAt: { not: null } },
      orderBy: { focusedAt: "asc" },
      include: { project: { select: { id: true, name: true } } },
    });
    reply.send(tasks);
  });

  /*
   * Put a task in the set.
   *
   * Idempotent, and that is a decision rather than a shortcut: a task already
   * in the set keeps the `focusedAt` it has and records nothing. Re-stamping it
   * would move it to the end of the set -- the order is `focusedAt` -- so a
   * double tap on a phone, or a retried request, would silently reorder the
   * work the person is in the middle of.
   */
  app.post("/tasks/:id/focus", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const task = await getTaskOrThrow(id);

    if (task.focusedAt !== null) {
      reply.send(task);
      return;
    }

    const updated = await prisma.$transaction(async (tx) => {
      const focused = await tx.task.update({
        where: { id },
        data: { focusedAt: new Date() },
      });
      await tx.taskEvent.create({ data: { taskId: id, kind: "focused" } });
      return focused;
    });

    reply.send(updated);
  });

  /*
   * Take it back out. Idempotent in the same way and for a plainer reason:
   * removing something that is not there is not an error anybody can act on,
   * and the client's next read shows the set it expected either way.
   *
   * Note that this is not the only way out of the set -- finishing a task
   * leaves it too, from `PATCH /tasks/:id`. See ../domain/taskEvents.ts.
   */
  app.delete("/tasks/:id/focus", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const task = await getTaskOrThrow(id);

    if (task.focusedAt === null) {
      reply.send(task);
      return;
    }

    const updated = await prisma.$transaction(async (tx) => {
      const unfocused = await tx.task.update({
        where: { id },
        data: { focusedAt: null },
      });
      await tx.taskEvent.create({ data: { taskId: id, kind: "unfocused" } });
      return unfocused;
    });

    reply.send(updated);
  });
}
