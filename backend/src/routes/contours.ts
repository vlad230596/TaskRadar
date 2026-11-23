import { FastifyInstance } from "fastify";
import { Prisma } from "@prisma/client";
import { prisma } from "../lib/prisma";
import { userIdOf } from "../lib/users";
import { ConflictError, NotFoundError, ValidationError } from "../lib/errors";
import { computeAppendPosition } from "../domain/position";
import { defaultContour, ownedContour } from "../domain/contours";
import {
  createContourSchema,
  idParamSchema,
  setActiveContourSchema,
  updateContourSchema,
} from "../schemas";

/*
 * Contours (design/goals-ideas-contract.md): sets of goal slots in force at
 * different times -- "Работа" on weekdays, "Личное" the rest.
 *
 * WHICH ONE IS ACTIVE IS NOT DECIDED HERE
 *
 * "Active now" depends on the device's clock and time zone at the moment the
 * screen is drawn, and a request carries neither reliably -- the phone may
 * have been offline since, or crossed a time zone. So the server stores the
 * contours (with their schedules) and the owner's manual override, and the app
 * resolves the rest itself (`resolveActiveContour` in the contract). That is
 * also why `GET /contours` answers `active` exactly as stored rather than
 * "resolved": the app needs the raw `until` to know when its own answer flips.
 */

async function getContourOrThrow(userId: string, id: string) {
  const contour = await ownedContour(prisma, userId, id);
  if (!contour) throw new NotFoundError("Contour");
  return contour;
}

/** The stored schedule as a Prisma value: SQL NULL for "no schedule". */
function scheduleColumn(
  schedule: Prisma.InputJsonValue | null | undefined,
): { schedule: Prisma.InputJsonValue | typeof Prisma.DbNull } | Record<string, never> {
  if (schedule === undefined) return {};
  return { schedule: schedule === null ? Prisma.DbNull : schedule };
}

export async function contourRoutes(app: FastifyInstance): Promise<void> {
  /*
   * Every contour, in order, and the manual override. `defaultContour` first,
   * so a user who somehow has none gets «Основной» here rather than an empty
   * list the app cannot draw (see ../domain/contours.ts).
   */
  app.get("/contours", async (request, reply) => {
    const userId = userIdOf(request);
    await defaultContour(prisma, userId);
    const [contours, user] = await Promise.all([
      prisma.contour.findMany({ where: { userId }, orderBy: { position: "asc" } }),
      prisma.user.findUnique({
        where: { id: userId },
        select: { activeContourId: true, activeContourUntil: true },
      }),
    ]);
    reply.send({
      contours,
      active: {
        contourId: user?.activeContourId ?? null,
        until: user?.activeContourUntil ?? null,
      },
    });
  });

  app.post("/contours", async (request, reply) => {
    const userId = userIdOf(request);
    const body = createContourSchema.parse(request.body);
    // Last, like a new scope: a new contour is not claimed to be the default.
    const last = await prisma.contour.findFirst({
      where: { userId },
      orderBy: { position: "desc" },
    });
    const contour = await prisma.contour.create({
      data: {
        userId,
        name: body.name,
        ...(body.slots !== undefined ? { slots: body.slots } : {}),
        ...(body.windowDays !== undefined ? { windowDays: body.windowDays } : {}),
        ...scheduleColumn(body.schedule),
        position: computeAppendPosition(last?.position ?? null),
      },
    });
    reply.status(201).send(contour);
  });

  /*
   * Lowering `slots` below the number of goals already in them is allowed:
   * the surplus stays in its slots and the app shows the overflow. Refusing
   * would make the owner bench goals before they may change a setting, which
   * is the wrong order -- deciding which goal to drop is the thing the
   * overflow is there to prompt.
   */
  app.patch("/contours/:id", async (request, reply) => {
    const userId = userIdOf(request);
    const { id } = idParamSchema.parse(request.params);
    const body = updateContourSchema.parse(request.body);
    await getContourOrThrow(userId, id);

    const contour = await prisma.contour.update({
      where: { id },
      data: {
        ...(body.name !== undefined ? { name: body.name } : {}),
        ...(body.slots !== undefined ? { slots: body.slots } : {}),
        ...(body.windowDays !== undefined ? { windowDays: body.windowDays } : {}),
        ...(body.position !== undefined ? { position: body.position } : {}),
        ...scheduleColumn(body.schedule),
      },
    });
    reply.send(contour);
  });

  /*
   * Refused (409) for the last contour -- a user always has one -- and for a
   * contour with goals, achieved ones included: those are the history screen's
   * "Достигнутые цели", and deleting a contour must never take them along.
   * The owner moves them first (`PATCH /goals/:id { contourId }`), as projects
   * are moved out of a scope before it goes.
   *
   * The contour's working set is not lost either: its tasks move to the
   * default contour of what is left, in the same transaction as the delete.
   * (`focusContourId` is `SetNull` as a backstop, but a task in the set of no
   * contour would sit on no work screen.) A manual override pointing here is
   * cleared by its foreign key.
   */
  app.delete("/contours/:id", async (request, reply) => {
    const userId = userIdOf(request);
    const { id } = idParamSchema.parse(request.params);
    await getContourOrThrow(userId, id);

    const [total, goals] = await Promise.all([
      prisma.contour.count({ where: { userId } }),
      prisma.goal.count({ where: { contourId: id } }),
    ]);
    if (total <= 1) throw new ConflictError("The last contour cannot be deleted");
    if (goals > 0) {
      throw new ConflictError("The contour has goals; move them to another contour first");
    }

    await prisma.$transaction(async (tx) => {
      const heir = await tx.contour.findFirst({
        where: { userId, id: { not: id } },
        orderBy: { position: "asc" },
      });
      if (heir !== null) {
        await tx.task.updateMany({
          where: { focusContourId: id },
          data: { focusContourId: heir.id },
        });
      }
      await tx.contour.delete({ where: { id } });
    });
    reply.status(204).send();
  });

  /*
   * The manual switch. `until` is computed by the app (the next moment the
   * schedules would give a different answer, or null when no contour has a
   * schedule) -- the server stores it and hands it to the other devices.
   * `{ contourId: null }` drops the override; `until` is then meaningless and
   * cleared with it.
   */
  app.put("/contours/active", async (request, reply) => {
    const userId = userIdOf(request);
    const body = setActiveContourSchema.parse(request.body);
    if (body.contourId !== null && (await ownedContour(prisma, userId, body.contourId)) === null) {
      throw new ValidationError(`Contour ${body.contourId} was not found`);
    }
    const user = await prisma.user.update({
      where: { id: userId },
      data: {
        activeContourId: body.contourId,
        activeContourUntil: body.contourId === null ? null : body.until,
      },
      select: { activeContourId: true, activeContourUntil: true },
    });
    reply.send({ contourId: user.activeContourId, until: user.activeContourUntil });
  });
}
