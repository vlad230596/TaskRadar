import { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma";
import { userIdOf } from "../lib/users";
import { NotFoundError } from "../lib/errors";
import { linkDictationParse } from "../domain/dictationLink";
import { aiClearData, aiMarkFields } from "../domain/aiMark";
import {
  createNoteSchema,
  updateNoteSchema,
  idParamSchema,
  projectIdParamSchema,
} from "../schemas";
import { getProjectOrThrow } from "./projects";
import { computeAppendPosition } from "../domain/position";
import { taskInclude, taskView } from "../domain/taskView";

async function getNoteOrThrow(userId: string, id: string) {
  const note = await prisma.note.findFirst({ where: { id, project: { scope: { userId } } } });
  if (!note) {
    throw new NotFoundError("Note");
  }
  return note;
}

/*
 * A note saved from a "Причесать" answer (F15) labels the `note` dataset row
 * with the note and what it now says -- the answer after the user's
 * corrections -- in the same transaction as the write, like a task does. See
 * ../domain/dictationLink.ts for why an unknown or labelled row is a no-op.
 */
export async function noteRoutes(app: FastifyInstance): Promise<void> {
  app.post("/projects/:projectId/notes", async (request, reply) => {
    const { projectId } = projectIdParamSchema.parse(request.params);
    const userId = userIdOf(request);
    const body = createNoteSchema.parse(request.body);
    await getProjectOrThrow(userId, projectId);

    const parseId = body.dictationParseId;
    const note = await prisma.$transaction(async (tx) => {
      const ai = await aiMarkFields(tx, userId, parseId, ["note"], null, {
        title: body.title,
        content: body.content,
      });
      const created = await tx.note.create({
        data: { ...ai, projectId, title: body.title, content: body.content },
      });
      if (parseId !== undefined) {
        await linkDictationParse(tx, userId, parseId, ["note"], {
          noteId: created.id,
          finalTitle: created.title,
          finalContent: created.content,
        });
      }
      return created;
    });
    reply.status(201).send(note);
  });

  app.get("/projects/:projectId/notes", async (request, reply) => {
    const { projectId } = projectIdParamSchema.parse(request.params);
    await getProjectOrThrow(userIdOf(request), projectId);

    const notes = await prisma.note.findMany({
      where: { projectId },
      orderBy: { createdAt: "asc" },
    });
    reply.send(notes);
  });

  app.patch("/notes/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const userId = userIdOf(request);
    const body = updateNoteSchema.parse(request.body);
    const before = await getNoteOrThrow(userId, id);

    const data: { title?: string; content?: string } = {};
    if (body.title !== undefined) data.title = body.title;
    if (body.content !== undefined) data.content = body.content;

    const parseId = body.dictationParseId;
    const note = await prisma.$transaction(async (tx) => {
      // AI on this note: ../domain/aiMark.ts.
      const ai = body.aiClear
        ? aiClearData()
        : await aiMarkFields(tx, userId, parseId, ["note"], before.aiSource, {
            title: data.title ?? before.title,
            content: data.content ?? before.content,
          });
      const updated = await tx.note.update({ where: { id }, data: { ...data, ...ai } });
      if (parseId !== undefined) {
        await linkDictationParse(tx, userId, parseId, ["note"], {
          noteId: updated.id,
          finalTitle: updated.title,
          finalContent: updated.content,
        });
      }
      return updated;
    });
    reply.send(note);
  });

  /*
   * "Сделать задачей" (design/goals-ideas-contract.md): the idea becomes a task
   * at the end of the same project, and stops being an idea.
   *
   * Title from the idea's title, description from its text (or none). The
   * goals the idea was kept next to follow it: each `GoalIdea` becomes a
   * `GoalTask` at the end of that goal, so the thought that was parked beside
   * a goal is now one of its steps without a second gesture.
   *
   * One transaction, with the task's `created` journal row (every task has
   * one, see `TaskEvent`), for the two half-done states it rules out: a task
   * made and the idea left behind (a twin), or the idea gone and no task.
   *
   * What the idea does not pass on: its AI marks (they describe the note's
   * text as a note; the task has not been processed as a task) and its
   * dataset rows, which keep their snapshot and lose the link
   * (`DictationParse.noteId` is `SetNull`).
   */
  app.post("/notes/:id/to-task", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const note = await getNoteOrThrow(userIdOf(request), id);

    const task = await prisma.$transaction(async (tx) => {
      const last = await tx.task.aggregate({
        where: { projectId: note.projectId },
        _max: { position: true },
      });
      const created = await tx.task.create({
        data: {
          projectId: note.projectId,
          title: note.title,
          description: note.content.trim() === "" ? null : note.content,
          position: computeAppendPosition(last._max.position),
        },
      });
      await tx.taskEvent.create({
        data: { taskId: created.id, kind: "created", toStatus: created.status },
      });

      const links = await tx.goalIdea.findMany({
        where: { noteId: id },
        orderBy: { createdAt: "asc" },
      });
      for (const link of links) {
        const lastInGoal = await tx.goalTask.aggregate({
          where: { goalId: link.goalId },
          _max: { position: true },
        });
        await tx.goalTask.create({
          data: {
            goalId: link.goalId,
            taskId: created.id,
            position: computeAppendPosition(lastInGoal._max.position),
          },
        });
      }

      // Takes its `GoalIdea` rows with it (Cascade).
      await tx.note.delete({ where: { id } });
      return tx.task.findUniqueOrThrow({ where: { id: created.id }, include: taskInclude });
    });

    reply.status(201).send(taskView(task));
  });

  app.delete("/notes/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    await getNoteOrThrow(userIdOf(request), id);
    await prisma.note.delete({ where: { id } });
    reply.status(204).send();
  });
}
