import { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma";
import { userIdOf } from "../lib/users";
import { settingsOf, settingsView } from "../lib/userSettings";
import { updateSettingsSchema } from "../schemas";

/*
 * `GET` / `PATCH /settings` (design/today-history-contract.md): the owner's
 * settings that every device shares -- the «Позже» horizon and the review's
 * day and time. Device-only preferences (theme, dictation on the phone) stay
 * on the device; these live here because they decide what the server itself
 * computes (the current task, a goal's next step, when a review is due).
 */
export async function settingsRoutes(app: FastifyInstance): Promise<void> {
  app.get("/settings", async (request, reply) => {
    reply.send(settingsView(await settingsOf(prisma, userIdOf(request))));
  });

  app.patch("/settings", async (request, reply) => {
    const userId = userIdOf(request);
    const body = updateSettingsSchema.parse(request.body ?? {});
    if (Object.keys(body).length > 0) {
      const data: { laterHorizonDays?: number; reviewWeekday?: number; reviewTime?: string } = {};
      if (body.laterHorizonDays !== undefined) data.laterHorizonDays = body.laterHorizonDays;
      if (body.reviewWeekday !== undefined) data.reviewWeekday = body.reviewWeekday;
      if (body.reviewTime !== undefined) data.reviewTime = body.reviewTime;
      await prisma.user.update({ where: { id: userId }, data });
    }
    reply.send(settingsView(await settingsOf(prisma, userId)));
  });
}
