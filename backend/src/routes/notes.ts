import { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma";
import { NotFoundError } from "../lib/errors";
import { createNoteSchema, updateNoteSchema, idParamSchema, projectIdParamSchema } from "../schemas";
import { getProjectOrThrow } from "./projects";

async function getNoteOrThrow(id: string) {
  const note = await prisma.note.findUnique({ where: { id } });
  if (!note) {
    throw new NotFoundError("Note");
  }
  return note;
}

export async function noteRoutes(app: FastifyInstance): Promise<void> {
  app.post("/projects/:projectId/notes", async (request, reply) => {
    const { projectId } = projectIdParamSchema.parse(request.params);
    const body = createNoteSchema.parse(request.body);
    await getProjectOrThrow(projectId);

    const note = await prisma.note.create({
      data: { projectId, title: body.title, content: body.content },
    });
    reply.status(201).send(note);
  });

  app.get("/projects/:projectId/notes", async (request, reply) => {
    const { projectId } = projectIdParamSchema.parse(request.params);
    await getProjectOrThrow(projectId);

    const notes = await prisma.note.findMany({
      where: { projectId },
      orderBy: { createdAt: "asc" },
    });
    reply.send(notes);
  });

  app.patch("/notes/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const body = updateNoteSchema.parse(request.body);
    await getNoteOrThrow(id);

    const data: { title?: string; content?: string } = {};
    if (body.title !== undefined) data.title = body.title;
    if (body.content !== undefined) data.content = body.content;

    const note = await prisma.note.update({ where: { id }, data });
    reply.send(note);
  });

  app.delete("/notes/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    await getNoteOrThrow(id);
    await prisma.note.delete({ where: { id } });
    reply.status(204).send();
  });
}
