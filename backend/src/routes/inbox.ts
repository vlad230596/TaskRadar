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
 * Since F8.1 a line can also be captured with no network at all: the client
 * queues it on the device and replays it later, which is why `POST /inbox`
 * takes an idempotency key. Filing deliberately did *not* follow -- see the
 * note on that route.
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

/**
 * Whether [error] is Prisma's "a unique index already holds this value" (P2002).
 *
 * Matched on the code rather than with `instanceof PrismaClientKnownRequestError`
 * on purpose: the route tests run against an in-memory fake of the client (there
 * is no database in that environment), and a check that insisted on the real
 * error class would make the one branch that exists for a race untestable.
 */
function isUniqueConstraintViolation(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    (error as { code?: unknown }).code === "P2002"
  );
}

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

  /*
   * Capture. One line of text, and -- since F8.1 -- optionally the client's own
   * idempotency key.
   *
   * WHY THE KEY EXISTS
   *
   * The phone captures into a local queue and sends when it can (F8.1: the
   * sandbox has to work with no network at all, because "надо не забыть"
   * arrives in a lift). A queue implies retries, and a retry cannot tell the
   * difference between "the request never arrived" and "it arrived and the
   * answer was lost on the way back" -- from the device both are a timeout. The
   * second case, retried blindly, puts two identical lines in the pile, which
   * is a small betrayal of the one promise this feature makes: you wrote it
   * down once.
   *
   * So the client generates the key, and this route is an upsert on it.
   *
   * WHAT A REPLAY DOES *NOT* DO: it does not rewrite the text. A second request
   * with a known key answers with the row as it stands, because the only way
   * the stored text can differ from the replayed text is that somebody edited
   * it (`PATCH /inbox/:id`) in between -- and a late duplicate of the original
   * capture undoing that edit would be a write travelling backwards in time.
   *
   * The status says which happened: 201 for a line that is new here, 200 for
   * one the server already had. Nothing in the client depends on the
   * difference, which is why it is safe to be honest about it.
   */
  app.post("/inbox", async (request, reply) => {
    const body = createInboxItemSchema.parse(request.body);
    const { captureKey } = body;

    if (captureKey === undefined) {
      const item = await prisma.inboxItem.create({ data: { text: body.text } });
      reply.status(201).send(item);
      return;
    }

    const known = await prisma.inboxItem.findUnique({ where: { captureKey } });
    if (known) {
      reply.status(200).send(known);
      return;
    }

    try {
      const item = await prisma.inboxItem.create({
        data: { text: body.text, captureKey },
      });
      reply.status(201).send(item);
    } catch (error) {
      // Two copies of the same retry in flight at once: the check above passed
      // in both, and the unique index caught the loser. That is the index doing
      // its job, not a failure -- re-read and answer as a replay. Anything else
      // is a real error and belongs to the error handler.
      if (!isUniqueConstraintViolation(error)) throw error;

      const raced = await prisma.inboxItem.findUnique({ where: { captureKey } });
      if (!raced) throw error;
      reply.status(200).send(raced);
    }
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
   * WHY FILING DID NOT GET AN OFFLINE PATH TOO (F8.1)
   *
   * Capture is safe to queue because a captured line has no order to be
   * inserted into the wrong place in, no state anyone else can change, and a
   * lifetime of hours -- so two devices merging their queues is set union, with
   * nothing to choose between. Filing has all three: it lands at a position in
   * a project's list, next to tasks somebody may have reordered, completed or
   * archived on another device since. That is the conflict resolution the whole
   * product still defers, and it does not become simpler for being reached from
   * here.
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

    /*
     * Three writes now, not two (F11): the task, its `created` journal row, and
     * the item's removal. The journal row is what makes the new task's clock
     * start -- see the note on `POST /projects/:projectId/tasks` -- and it
     * belongs in this transaction rather than after it for the reason the other
     * two do: a task that exists with no record of when it began is a task the
     * history mode cannot place in time.
     *
     * An interactive transaction rather than the array form it used to be,
     * because the event needs the id of the task created a line above it, and
     * the array form has no way to say that.
     */
    const task = await prisma.$transaction(async (tx) => {
      const created = await tx.task.create({
        data: {
          projectId: body.projectId,
          title: item.text,
          position,
        },
      });

      await tx.taskEvent.create({
        data: { taskId: created.id, kind: "created", toStatus: created.status },
      });
      await tx.inboxItem.delete({ where: { id } });

      return created;
    });

    reply.status(201).send(task);
  });
}
