import { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma";
import { NotFoundError, ValidationError } from "../lib/errors";
import { annotateIsCurrent } from "../domain/isCurrent";
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
  idParamSchema,
  projectIdParamSchema,
} from "../schemas";
import { getActiveProjectOrThrow } from "./projects";

async function getTaskOrThrow(id: string) {
  const task = await prisma.task.findUnique({ where: { id } });
  if (!task) {
    throw new NotFoundError("Task");
  }
  return task;
}

export async function taskRoutes(app: FastifyInstance): Promise<void> {
  app.post("/projects/:projectId/tasks", async (request, reply) => {
    const { projectId } = projectIdParamSchema.parse(request.params);
    const body = createTaskSchema.parse(request.body);
    await getActiveProjectOrThrow(projectId);

    const last = await prisma.task.aggregate({
      where: { projectId },
      _max: { position: true },
    });
    const position = computeAppendPosition(last._max.position);

    const task = await prisma.task.create({
      data: {
        projectId,
        title: body.title,
        description: body.description ?? null,
        ...(body.status !== undefined ? { status: body.status } : {}),
        remindAt: body.remindAt ?? null,
        position,
      },
    });
    reply.status(201).send(task);
  });

  app.get("/projects/:projectId/tasks", async (request, reply) => {
    const { projectId } = projectIdParamSchema.parse(request.params);
    await getActiveProjectOrThrow(projectId);

    const tasks = await prisma.task.findMany({
      where: { projectId },
      orderBy: { position: "asc" },
    });
    reply.send(annotateIsCurrent(tasks));
  });

  app.patch("/tasks/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const body = updateTaskSchema.parse(request.body);
    await getTaskOrThrow(id);

    const data: {
      title?: string;
      description?: string | null;
      status?: "pending" | "done" | "blocked";
      remindAt?: Date | null;
    } = {};
    if (body.title !== undefined) data.title = body.title;
    if (body.description !== undefined) data.description = body.description;
    if (body.status !== undefined) data.status = body.status;
    if (body.remindAt !== undefined) data.remindAt = body.remindAt;

    const task = await prisma.task.update({ where: { id }, data });
    reply.send(task);
  });

  app.patch("/tasks/:id/position", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const body = updateTaskPositionSchema.parse(request.body);
    const task = await getTaskOrThrow(id);

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
        rebalanced.map((r) => prisma.task.update({ where: { id: r.id }, data: { position: r.position } })),
      );

      beforePosition = beforeId
        ? (rebalanced.find((r) => r.id === beforeId)?.position ?? null)
        : null;
      afterPosition = afterId ? (rebalanced.find((r) => r.id === afterId)?.position ?? null) : null;

      newPosition = computePositionBetween(beforePosition, afterPosition);
    }

    const updated = await prisma.task.update({ where: { id }, data: { position: newPosition } });
    reply.send(updated);
  });

  app.delete("/tasks/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    await getTaskOrThrow(id);
    await prisma.task.delete({ where: { id } });
    reply.status(204).send();
  });
}
