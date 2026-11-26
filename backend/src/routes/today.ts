import { FastifyInstance } from "fastify";
import { Prisma } from "@prisma/client";
import { prisma } from "../lib/prisma";
import { userIdOf } from "../lib/users";
import { taskInclude, taskView } from "../domain/taskView";
import { localInstant } from "../domain/review";
import { localToday, todayView } from "../domain/today";
import { tzQuerySchema } from "../schemas";

/*
 * `GET /today` (design/today-history-contract.md): the day block of «Работа»
 * -- «Сегодня», what was closed today, and «С прошлых дней» -- computed on
 * the server for MCP and for the app to check its own offline answer against.
 * The rules are `todayView` (../domain/today.ts).
 */

/** A task read with its project and scope, for lists that span projects. */
export const placedTaskInclude = {
  ...taskInclude,
  project: {
    select: {
      id: true,
      name: true,
      createdAt: true,
      archivedAt: true,
      scope: { select: { id: true, name: true, position: true } },
    },
  },
} as const satisfies Prisma.TaskInclude;

export type PlacedTaskRow = Prisma.TaskGetPayload<{ include: typeof placedTaskInclude }>;

/** `taskView` + where the task lives: `projectName`, `scopeId`, `scopeName`. */
export function placedTaskView(row: PlacedTaskRow) {
  const { project, ...task } = row;
  return {
    ...taskView(task),
    projectName: project.name,
    scopeId: project.scope.id,
    scopeName: project.scope.name,
  };
}

/** Board order across projects: scope, then project (by creation), then position. */
export function boardOrder(a: PlacedTaskRow, b: PlacedTaskRow): number {
  return (
    a.project.scope.position - b.project.scope.position ||
    a.project.scope.id.localeCompare(b.project.scope.id) ||
    a.project.createdAt.getTime() - b.project.createdAt.getTime() ||
    a.project.id.localeCompare(b.project.id) ||
    a.position - b.position
  );
}

/**
 * The owner's day block at [now]. Tasks of archived projects are left out, as
 * the board leaves them out: an archived project is put down, and its dates
 * stop asking for attention (they also stop raising reminders).
 */
export async function loadTodayRows(userId: string, now: Date, tzOffsetMinutes: number) {
  const today = localToday(now, tzOffsetMinutes);
  const rows = await prisma.task.findMany({
    where: {
      project: { archivedAt: null, scope: { userId } },
      // A date is a UTC midnight: everything up to and including today's.
      remindAt: { not: null, lte: new Date(`${today}T00:00:00.000Z`) },
      OR: [
        { status: { in: ["pending", "blocked"] } },
        { status: "done", doneAt: { gte: localInstant(today, "00:00", tzOffsetMinutes) } },
      ],
    },
    include: placedTaskInclude,
  });
  return todayView(rows, today, tzOffsetMinutes, boardOrder);
}

/** `GET /today`'s answer: [loadTodayRows] with every task as `placedTaskView`. */
export async function loadToday(userId: string, now: Date, tzOffsetMinutes: number) {
  const view = await loadTodayRows(userId, now, tzOffsetMinutes);
  return {
    date: view.date,
    today: view.today.map(placedTaskView),
    doneToday: view.doneToday.map(placedTaskView),
    tail: view.tail.map(placedTaskView),
  };
}

export async function todayRoutes(app: FastifyInstance): Promise<void> {
  app.get("/today", async (request, reply) => {
    const { tzOffsetMinutes } = tzQuerySchema.parse(request.query);
    reply.send(await loadToday(userIdOf(request), new Date(), tzOffsetMinutes));
  });
}
