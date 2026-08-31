import { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma";
import { NotFoundError, ConflictError } from "../lib/errors";
import { canHardDeleteProject } from "../domain/projectDeleteGuard";
import { createProjectSchema, listProjectsQuerySchema, idParamSchema } from "../schemas";

export async function getActiveProjectOrThrow(projectId: string) {
  const project = await prisma.project.findUnique({ where: { id: projectId } });
  if (!project) {
    throw new NotFoundError("Project");
  }
  return project;
}

export async function projectRoutes(app: FastifyInstance): Promise<void> {
  app.post("/projects", async (request, reply) => {
    const body = createProjectSchema.parse(request.body);
    const project = await prisma.project.create({ data: { name: body.name } });
    reply.status(201).send(project);
  });

  app.get("/projects", async (request, reply) => {
    const query = listProjectsQuerySchema.parse(request.query);
    const showArchived = query.archived === "true";

    const projects = await prisma.project.findMany({
      where: {
        archivedAt: showArchived ? { not: null } : null,
      },
      orderBy: { createdAt: "asc" },
    });
    reply.send(projects);
  });

  app.get("/projects/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const project = await getActiveProjectOrThrow(id);
    reply.send(project);
  });

  app.post("/projects/:id/archive", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    await getActiveProjectOrThrow(id);
    const project = await prisma.project.update({
      where: { id },
      data: { archivedAt: new Date() },
    });
    reply.send(project);
  });

  app.post("/projects/:id/unarchive", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    await getActiveProjectOrThrow(id);
    const project = await prisma.project.update({
      where: { id },
      data: { archivedAt: null },
    });
    reply.send(project);
  });

  app.delete("/projects/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const project = await getActiveProjectOrThrow(id);

    if (!canHardDeleteProject(project)) {
      throw new ConflictError("Project must be archived before it can be deleted");
    }

    await prisma.project.delete({ where: { id } });
    reply.status(204).send();
  });
}
