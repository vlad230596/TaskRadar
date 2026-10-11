import { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma";
import { userIdOf } from "../lib/users";
import { ConflictError, NotFoundError } from "../lib/errors";
import { computeAppendPosition } from "../domain/position";
import { createCategorySchema, idParamSchema, projectIdParamSchema, updateCategorySchema } from "../schemas";
import { getProjectOrThrow } from "./projects";

/*
 * Task categories: the groups a project's tasks are drawn in (see
 * `TaskCategory` in prisma/schema.prisma).
 *
 * A category belongs to whoever owns its project's scope, the same chain as a
 * task or a note. Which task is in which category is the task's own field
 * (`PATCH /tasks/:id { categoryId }`), not a route here.
 */

async function getCategoryOrThrow(userId: string, id: string) {
  const category = await prisma.taskCategory.findFirst({
    where: { id, project: { scope: { userId } } },
  });
  if (!category) {
    throw new NotFoundError("Category");
  }
  return category;
}

/**
 * Two groups called "Кухня" in one project would be two headings nobody can
 * tell apart, and a picker with the word twice. Compared without case --
 * "кухня" is the same group; the schema has already trimmed the name.
 */
async function assertNameFree(projectId: string, name: string, exceptId?: string): Promise<void> {
  const clash = await prisma.taskCategory.findFirst({
    where: {
      projectId,
      name: { equals: name, mode: "insensitive" },
      ...(exceptId ? { id: { not: exceptId } } : {}),
    },
  });
  if (clash) {
    throw new ConflictError(`A category named "${name}" already exists in this project`);
  }
}

export async function categoryRoutes(app: FastifyInstance): Promise<void> {
  app.get("/projects/:projectId/categories", async (request, reply) => {
    const { projectId } = projectIdParamSchema.parse(request.params);
    await getProjectOrThrow(userIdOf(request), projectId);

    const categories = await prisma.taskCategory.findMany({
      where: { projectId },
      orderBy: { position: "asc" },
    });
    reply.send(categories);
  });

  app.post("/projects/:projectId/categories", async (request, reply) => {
    const { projectId } = projectIdParamSchema.parse(request.params);
    const body = createCategorySchema.parse(request.body);
    await getProjectOrThrow(userIdOf(request), projectId);
    await assertNameFree(projectId, body.name);

    const last = await prisma.taskCategory.aggregate({
      where: { projectId },
      _max: { position: true },
    });
    const category = await prisma.taskCategory.create({
      data: { projectId, name: body.name, position: computeAppendPosition(last._max.position) },
    });
    reply.status(201).send(category);
  });

  app.patch("/categories/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const body = updateCategorySchema.parse(request.body);
    const category = await getCategoryOrThrow(userIdOf(request), id);
    await assertNameFree(category.projectId, body.name, id);

    const updated = await prisma.taskCategory.update({ where: { id }, data: { name: body.name } });
    reply.send(updated);
  });

  /*
   * The tasks stay: the foreign key is `ON DELETE SET NULL`, so they fall back
   * to "без категории" in the same statement. Removing a heading must never
   * remove the work under it.
   */
  app.delete("/categories/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    await getCategoryOrThrow(userIdOf(request), id);
    await prisma.taskCategory.delete({ where: { id } });
    reply.status(204).send();
  });
}
