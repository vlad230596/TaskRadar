import { FastifyInstance } from "fastify";
import { Prisma, Review } from "@prisma/client";
import { prisma } from "../lib/prisma";
import { userIdOf } from "../lib/users";
import { settingsOf } from "../lib/userSettings";
import { goalInclude, goalStateWhere, goalView, GoalView } from "../domain/goals";
import {
  countByProject,
  previousMonth,
  reviewDue,
  reviewPeriod,
} from "../domain/review";
import { localDayKey } from "../domain/history";
import { createReviewSchema, listReviewsQuerySchema, tzQuerySchema } from "../schemas";
import { placedTaskInclude, placedTaskView } from "./today";
import { projectsWithRhythm } from "./projects";

/*
 * The weekly review (design/today-history-contract.md, history-review-decisions.md).
 *
 * The review screen acts through the routes that already exist -- PATCH a
 * task, take one into work, slot a goal, set a rhythm -- and this file only
 * answers the three questions those routes cannot: is a review due
 * (`/reviews/status`), what does it look at (`/reviews/draft`), and what was
 * its result (`POST /reviews`, kept as a row and listed by `GET /reviews`).
 *
 * Every closing counted here is a task's `doneAt` (see the model): a closing
 * taken back cleared it, so revoked closings are counted nowhere.
 */

/** A review as the API shows it. */
export function reviewView(row: Review) {
  return {
    id: row.id,
    periodStart: row.periodStart,
    periodEnd: row.periodEnd,
    monthly: row.monthly,
    closedCount: row.closedCount,
    byProject: row.byProject,
    achievedGoals: row.achievedGoals,
    summary: row.summary,
    createdAt: row.createdAt,
  };
}

export type ReviewView = ReturnType<typeof reviewView>;

/** A `POST /reviews` this soon after the last one is a retry of it, not a new review. */
export const REVIEW_RETRY_MS = 10 * 60_000;

function lastReviewOf(userId: string) {
  return prisma.review.findFirst({ where: { userId }, orderBy: { periodEnd: "desc" } });
}

/** [userId]'s closings (tasks done within the window), any project, archived too. */
function closedBetween(userId: string, from: Date, to: Date) {
  return prisma.task.findMany({
    where: { status: "done", doneAt: { gte: from, lte: to }, project: { scope: { userId } } },
    orderBy: { doneAt: "asc" },
    include: placedTaskInclude,
  });
}

function achievedBetween(userId: string, from: Date, to: Date) {
  return prisma.goal.findMany({
    where: { userId, achievedAt: { gte: from, lte: to } },
    orderBy: { achievedAt: "asc" },
    include: goalInclude,
  });
}

function byProjectOf(rows: { projectId: string; project: { name: string } }[]) {
  return countByProject(rows.map((r) => ({ projectId: r.projectId, projectName: r.project.name })));
}

/** A day (`YYYY-MM-DD`) as a stored task date: UTC midnight. */
function asStoredDate(day: string): Date {
  return new Date(`${day}T00:00:00.000Z`);
}

export async function reviewRoutes(app: FastifyInstance): Promise<void> {
  app.get("/reviews/status", async (request, reply) => {
    const userId = userIdOf(request);
    const { tzOffsetMinutes } = tzQuerySchema.parse(request.query);
    const [settings, last] = await Promise.all([settingsOf(prisma, userId), lastReviewOf(userId)]);
    reply.send(reviewDue(settings, last, new Date(), tzOffsetMinutes));
  });

  /*
   * What the six steps look at, in one read: the period since the last review
   * and its closings (step 1), what was intended and is still open (step 2),
   * the goals (step 3), the projects off their rhythm (step 4), and for the
   * first review of a month, the month before (the monthly section). Steps 5
   * and 6 need nothing new: the working set and dates are the app's own.
   *
   * «Задумано» (intended) is not a stored plan -- there is none, by decision.
   * It is what the owner was going to do, read from the state as it stands:
   * the working sets of all contours, the next steps of goals in slots, and
   * the tasks dated within the period. Only what is still open: the closed
   * part of the intention is step 1.
   */
  app.get("/reviews/draft", async (request, reply) => {
    const userId = userIdOf(request);
    const { tzOffsetMinutes } = tzQuerySchema.parse(request.query);
    const now = new Date();
    const [settings, last] = await Promise.all([settingsOf(prisma, userId), lastReviewOf(userId)]);
    const period = reviewPeriod(last, now, tzOffsetMinutes);
    const horizonDays = settings.laterHorizonDays;

    const goalRows = await prisma.goal.findMany({
      where: { userId, ...goalStateWhere(["slot", "bench"]) },
      orderBy: [{ contour: { position: "asc" } }, { position: "asc" }],
      include: goalInclude,
    });
    const goals: GoalView[] = goalRows.map((row) => goalView(row, now, horizonDays));
    const stepIds = new Set(
      goals.filter((g) => g.state === "slot" && g.nextStep !== null).map((g) => g.nextStep!.id),
    );

    const firstDay = asStoredDate(localDayKey(period.periodStart, tzOffsetMinutes));
    const lastDay = asStoredDate(localDayKey(period.periodEnd, tzOffsetMinutes));
    const [closed, open, projects] = await Promise.all([
      closedBetween(userId, period.periodStart, period.periodEnd),
      prisma.task.findMany({
        where: {
          status: { in: ["pending", "blocked"] },
          project: { scope: { userId } },
          OR: [
            { focusedAt: { not: null } },
            { id: { in: [...stepIds] } },
            { remindAt: { gte: firstDay, lte: lastDay }, project: { archivedAt: null } },
          ],
        },
        include: placedTaskInclude,
      }),
      projectsWithRhythm(userId, { archived: false }, now),
    ]);

    const intended = open
      .map((row) => {
        const reasons: ("workingSet" | "goalStep" | "dated")[] = [];
        if (row.focusedAt !== null) reasons.push("workingSet");
        if (stepIds.has(row.id)) reasons.push("goalStep");
        if (row.remindAt !== null && row.remindAt >= firstDay && row.remindAt <= lastDay && row.project.archivedAt === null) {
          reasons.push("dated");
        }
        return { row, reasons };
      })
      .filter((one) => one.reasons.length > 0)
      .sort(
        (a, b) =>
          (a.row.focusedAt?.getTime() ?? Infinity) - (b.row.focusedAt?.getTime() ?? Infinity) ||
          (a.row.remindAt?.getTime() ?? Infinity) - (b.row.remindAt?.getTime() ?? Infinity) ||
          a.row.position - b.row.position,
      )
      .map(({ row, reasons }) => ({ task: placedTaskView(row), reasons }));

    let month: null | {
      month: string;
      byProject: ReturnType<typeof countByProject>;
      achievedGoals: GoalView[];
    } = null;
    if (period.monthly) {
      const range = previousMonth(now, tzOffsetMinutes);
      const end = new Date(range.end.getTime() - 1);
      const [monthClosed, monthGoals] = await Promise.all([
        closedBetween(userId, range.start, end),
        achievedBetween(userId, range.start, end),
      ]);
      month = {
        month: range.month,
        byProject: byProjectOf(monthClosed),
        achievedGoals: monthGoals.map((row) => goalView(row, now, horizonDays)),
      };
    }

    reply.send({
      periodStart: period.periodStart,
      periodEnd: period.periodEnd,
      monthly: period.monthly,
      done: closed.map((row) => ({ task: placedTaskView(row), doneAt: row.doneAt })),
      intended,
      goals,
      rhythm: projects
        .filter((p) => p.rhythm !== null && p.rhythm.signal !== null)
        .map(({ rhythm, ...project }) => ({ project, rhythm })),
      month,
    });
  });

  /*
   * The review is finished: the server computes the period and its numbers
   * itself -- the client only adds the one-line summary -- and keeps them as
   * they are now, so a task deleted or moved later does not rewrite a past
   * review. The next review starts where this one ends.
   */
  app.post("/reviews", async (request, reply) => {
    const userId = userIdOf(request);
    const body = createReviewSchema.parse(request.body);
    const now = new Date();
    const last = await lastReviewOf(userId);
    /*
     * A retry after a lost answer (or a double tap) must not record a second,
     * minutes-long review: the newest review, finished within
     * `REVIEW_RETRY_MS`, IS this review. It is answered 200 as it stands --
     * with the summary replaced when the retry carries one -- and its period
     * and numbers stay those of the first request.
     */
    if (last !== null && now.getTime() - last.createdAt.getTime() < REVIEW_RETRY_MS) {
      const same =
        body.summary !== null && body.summary !== last.summary
          ? await prisma.review.update({ where: { id: last.id }, data: { summary: body.summary } })
          : last;
      reply.status(200).send(reviewView(same));
      return;
    }
    const period = reviewPeriod(last, now, body.tzOffsetMinutes);
    const [closed, achieved] = await Promise.all([
      prisma.task.findMany({
        where: {
          status: "done",
          doneAt: { gte: period.periodStart, lte: period.periodEnd },
          project: { scope: { userId } },
        },
        select: { projectId: true, project: { select: { name: true } } },
      }),
      prisma.goal.findMany({
        where: { userId, achievedAt: { gte: period.periodStart, lte: period.periodEnd } },
        orderBy: { achievedAt: "asc" },
        select: { id: true, title: true },
      }),
    ]);
    const row = await prisma.review.create({
      data: {
        userId,
        periodStart: period.periodStart,
        periodEnd: period.periodEnd,
        monthly: period.monthly,
        closedCount: closed.length,
        byProject: byProjectOf(closed) as unknown as Prisma.InputJsonValue,
        achievedGoals: achieved.map((g) => ({ goalId: g.id, title: g.title })),
        summary: body.summary,
      },
    });
    reply.status(201).send(reviewView(row));
  });

  app.get("/reviews", async (request, reply) => {
    const userId = userIdOf(request);
    const { limit } = listReviewsQuerySchema.parse(request.query);
    const rows = await prisma.review.findMany({
      where: { userId },
      orderBy: { periodEnd: "desc" },
      take: limit,
    });
    reply.send(rows.map(reviewView));
  });
}
