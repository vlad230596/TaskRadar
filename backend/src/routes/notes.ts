import { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma";
import { userIdOf } from "../lib/users";
import { NotFoundError } from "../lib/errors";
import { linkDictationParse } from "../domain/dictationLink";
import { createNoteSchema, updateNoteSchema, idParamSchema, projectIdParamSchema } from "../schemas";
import { getProjectOrThrow } from "./projects";

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
      const created = await tx.note.create({
        data: { projectId, title: body.title, content: body.content },
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
    await getNoteOrThrow(userId, id);

    const data: { title?: string; content?: string } = {};
    if (body.title !== undefined) data.title = body.title;
    if (body.content !== undefined) data.content = body.content;

    const parseId = body.dictationParseId;
    const note = await prisma.$transaction(async (tx) => {
      const updated = await tx.note.update({ where: { id }, data });
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

  app.delete("/notes/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    await getNoteOrThrow(userIdOf(request), id);
    await prisma.note.delete({ where: { id } });
    reply.status(204).send();
  });
}
