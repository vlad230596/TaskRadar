import { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma";
import { NotFoundError } from "../lib/errors";
import { computeAppendPosition } from "../domain/position";
import {
  createInboxItemSchema,
  updateInboxItemSchema,
  fileInboxItemSchema,
  idParamSchema,
} from "../schemas";
import { getProjectOrThrow } from "./projects";

/*
 * The sandbox (F8): write it down now, decide where it goes later.
 *
 * WHAT THIS IS FOR
 *
 * `../../../README.md` builds the product around the cost of *restoring
 * context*, and the cheapest moment to lose something is the one where writing
 * it down costs a decision. "Надо не забыть" arrives while walking, and picking
 * one project out of fifteen right then is the price at which a thought simply
 * does not get written down at all. So an inbox item is one line of text and
 * nothing else -- no status, no order, no reminder date, no project.
 *
 * It becomes a Task the moment it is filed (`POST /inbox/:id/file`), and from
 * then on it is an ordinary task in an ordinary project. Nothing here is a
 * parallel task system: there is no way to complete, block or schedule an inbox
 * item, on purpose. An item you can work on directly is an item you never file,
 * and an unfiled pile is the thing this product exists to prevent.
 *
 * WHY THERE IS NO SCOPE ON IT
 *
 * Scopes (F7) partition the board by part of life. The sandbox deliberately
 * sits across all of them: the whole scenario is "I am not deciding anything
 * right now", and asking which scope a thought belongs to is exactly the
 * decision being deferred. The scope gets decided when the item is filed,
 * because a project already has one.
 */

async function getInboxItemOrThrow(id: string) {
  const item = await prisma.inboxItem.findUnique({ where: { id } });
  if (!item) {
    throw new NotFoundError("Inbox item");
  }
  return item;
}

export async function inboxRoutes(app: FastifyInstance): Promise<void> {
  /*
   * Oldest first, and that is a product decision rather than a default.
   *
   * The pile is processed from the top, and the item at risk of rotting is the
   * one that has been waiting longest -- putting the newest at the top would
   * make an old item sink out of sight exactly as it becomes the one that
   * matters. It also matches what the eye expects from a queue.
   */
  app.get("/inbox", async (_request, reply) => {
    const items = await prisma.inboxItem.findMany({
      orderBy: { createdAt: "asc" },
    });
    reply.send(items);
  });

  app.post("/inbox", async (request, reply) => {
    const body = createInboxItemSchema.parse(request.body);
    const item = await prisma.inboxItem.create({ data: { text: body.text } });
    reply.status(201).send(item);
  });

  /*
   * Editing the text before filing it.
   *
   * Worth having for one reason: an item captured in a hurry (or, from F9,
   * dictated) is often *almost* right, and the alternative to fixing it here is
   * filing a task with a typo into a project and fixing it there -- which is
   * the same edit, one screen further away.
   */
  app.patch("/inbox/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const body = updateInboxItemSchema.parse(request.body);
    await getInboxItemOrThrow(id);

    const item = await prisma.inboxItem.update({
      where: { id },
      data: { text: body.text },
    });
    reply.send(item);
  });

  /*
   * Throwing one away. No archive, no confirmation on the server: an inbox item
   * is a line of text somebody typed a moment ago, and the reversible-archive
   * machinery a Project gets (`projectDeleteGuard`) exists because a project
   * holds months of work. This holds a sentence.
   */
  app.delete("/inbox/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    await getInboxItemOrThrow(id);
    await prisma.inboxItem.delete({ where: { id } });
    reply.status(204).send();
  });

  /*
   * Filing: the item becomes a task at the end of a project, and stops being an
   * inbox item.
   *
   * ONE ROUTE RATHER THAN "CREATE A TASK, THEN DELETE THE ITEM" FROM THE CLIENT
   *
   * Two requests from a phone on a train produce two ways to be half-done, and
   * both are bad in a way the user cannot see: the task created and the item
   * left behind means the same thing gets filed twice, and the item deleted
   * without the task created means the thought is simply gone. A transaction
   * makes the pair atomic, and it costs one route.
   *
   * The reply is the created task, in exactly the shape `POST /projects/:id/tasks`
   * answers with -- the raw row, **without `isCurrent`**. Same reason as there:
   * `isCurrent` is a property of the project's whole ordered list, and this
   * response carries one row. A client that needs it re-reads the project, which
   * is what `ProjectTasks` already does after every structural change.
   */
  app.post("/inbox/:id/file", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const body = fileInboxItemSchema.parse(request.body);

    const item = await getInboxItemOrThrow(id);
    await getProjectOrThrow(body.projectId);

    // Appended, like any new task: the item has no order of its own, and
    // dropping it into the middle of a project's list would be inventing one.
    const last = await prisma.task.aggregate({
      where: { projectId: body.projectId },
      _max: { position: true },
    });
    const position = computeAppendPosition(last._max.position);

    const [task] = await prisma.$transaction([
      prisma.task.create({
        data: {
          projectId: body.projectId,
          title: item.text,
          position,
        },
      }),
      prisma.inboxItem.delete({ where: { id } }),
    ]);

    reply.status(201).send(task);
  });
}
