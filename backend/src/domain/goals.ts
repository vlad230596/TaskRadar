import { Prisma, TaskStatus } from "@prisma/client";
import { DEFAULT_LATER_HORIZON_DAYS, isLater, LaterRule, localToday } from "./today";

/*
 * Goals (design/goals-ideas-contract.md): the rules that do not need a
 * database, and the one shape a goal is shown in.
 *
 * A goal's state is derived from its timestamps and never stored -- a stored
 * state is a column that can disagree with `slottedAt` / `achievedAt`, and
 * the first bug that wrote one without the other would leave a goal that is
 * "in a slot" with no slot time. So everything that asks "where is this goal"
 * asks `goalState`, and every query that filters by state uses
 * `goalStateWhere`, which is the same rule written for Postgres.
 */

export const GOAL_STATES = ["slot", "bench", "achieved"] as const;
export type GoalState = (typeof GOAL_STATES)[number];

const DAY_MS = 24 * 60 * 60 * 1000;

interface GoalTimes {
  slottedAt: Date | null;
  achievedAt: Date | null;
}

/** achieved beats slot: an achieved goal has left its slot, whatever the row says. */
export function goalState(goal: GoalTimes): GoalState {
  if (goal.achievedAt !== null) return "achieved";
  if (goal.slottedAt !== null) return "slot";
  return "bench";
}

/** `goalState` as a Prisma filter: the goals in any of [states]. */
export function goalStateWhere(states: readonly GoalState[]): Prisma.GoalWhereInput {
  const one = (state: GoalState): Prisma.GoalWhereInput => {
    if (state === "achieved") return { achievedAt: { not: null } };
    if (state === "slot") return { achievedAt: null, slottedAt: { not: null } };
    return { achievedAt: null, slottedAt: null };
  };
  return { OR: states.map(one) };
}

/** The window that applies: the goal's own, else its contour's. */
export function effectiveWindowDays(
  goal: { windowDays: number | null },
  contour: { windowDays: number },
): number {
  return goal.windowDays ?? contour.windowDays;
}

/** End of a window of [days] starting at [from]. Whole days of 24 hours. */
export function windowEnd(from: Date, days: number): Date {
  return new Date(from.getTime() + days * DAY_MS);
}

/**
 * "Продлить": one more window, counted from the later of now and the current
 * end. From the end when the window is still running -- extending on Tuesday
 * a window that ends on Friday must not lose the three days left. From now
 * when it has already run out -- otherwise a goal left expired for a fortnight
 * would be "extended" into the past and ask again at once.
 */
export function extendedWindowEnd(now: Date, current: Date | null, days: number): Date {
  const base = current !== null && current.getTime() > now.getTime() ? current : now;
  return windowEnd(base, days);
}

/** What a goal's task list carries about each task. */
export interface GoalTaskView {
  id: string;
  title: string;
  status: TaskStatus;
  projectId: string;
  projectName: string;
  focusedAt: Date | null;
  focusContourId: string | null;
  /** The task's date (`YYYY-MM-DD` on the wire), for «Позже». */
  remindAt: Date | null;
}

/**
 * The goal's next step: the first task, in the goal's own order, that is still
 * pending. Blocked tasks are skipped, not stopped at -- the point of the step
 * is something the owner can do now, and a blocked task is by definition not
 * that. Done tasks are history. Null when nothing pending is left; the app
 * then offers "Обсудить" (and says "всё заблокировано" if blocked ones remain).
 *
 * «Позже» (design/today-history-contract.md), when [later] is given: a task
 * dated beyond the owner's horizon is passed over for one that is for now --
 * but if every pending task is «Позже», the first pending one is still the
 * step: a goal in a slot should name what comes next, even if it is a date.
 */
export function nextStepOf<T extends { status: TaskStatus; remindAt?: Date | null }>(
  tasksInOrder: readonly T[],
  later?: LaterRule,
): T | null {
  const pending = tasksInOrder.filter((task) => task.status === "pending");
  if (later !== undefined) {
    const now = pending.find(
      (task) =>
        !isLater({ status: task.status, remindAt: task.remindAt ?? null }, later.today, later.horizonDays),
    );
    if (now !== undefined) return now;
  }
  return pending[0] ?? null;
}

/**
 * The `include` every goal read uses: the linked tasks in the goal's order
 * with their project names, the ideas with theirs, and the contour's window.
 * One `findMany` with this is a fixed number of queries however many goals
 * come back -- Prisma loads each relation for all parents in one `IN (...)`.
 */
export const goalInclude = {
  contour: { select: { windowDays: true } },
  tasks: {
    orderBy: [{ position: "asc" }, { createdAt: "asc" }],
    select: {
      position: true,
      task: {
        select: {
          id: true,
          title: true,
          status: true,
          projectId: true,
          focusedAt: true,
          focusContourId: true,
          remindAt: true,
          project: { select: { name: true } },
        },
      },
    },
  },
  ideas: {
    orderBy: { createdAt: "asc" },
    select: {
      note: {
        select: { id: true, title: true, projectId: true, project: { select: { name: true } } },
      },
    },
  },
} as const satisfies Prisma.GoalInclude;

export type GoalRow = Prisma.GoalGetPayload<{ include: typeof goalInclude }>;

/**
 * A goal as the API (and the MCP server) shows it -- `GoalView` in the contract.
 * [horizonDays] is the owner's «Позже» horizon, for the next step; the
 * server's today for it is UTC.
 */
export function goalView(
  row: GoalRow,
  now: Date = new Date(),
  horizonDays: number = DEFAULT_LATER_HORIZON_DAYS,
) {
  const state = goalState(row);
  const tasks: GoalTaskView[] = row.tasks.map(({ task }) => ({
    id: task.id,
    title: task.title,
    status: task.status,
    projectId: task.projectId,
    projectName: task.project.name,
    focusedAt: task.focusedAt,
    focusContourId: task.focusContourId,
    remindAt: task.remindAt,
  }));
  return {
    id: row.id,
    contourId: row.contourId,
    title: row.title,
    why: row.why,
    state,
    slottedAt: row.slottedAt,
    // What applies, not what is stored: the app draws "окно 7 дней" either way.
    windowDays: effectiveWindowDays(row, row.contour),
    ownWindowDays: row.windowDays,
    windowEndsAt: row.windowEndsAt,
    windowExpired:
      state === "slot" && row.windowEndsAt !== null && row.windowEndsAt.getTime() <= now.getTime(),
    achievedAt: row.achievedAt,
    position: row.position,
    createdAt: row.createdAt,
    tasks,
    nextStep: nextStepOf(tasks, { today: localToday(now), horizonDays }),
    ideas: row.ideas.map(({ note }) => ({
      id: note.id,
      title: note.title,
      projectId: note.projectId,
      projectName: note.project.name,
    })),
    progress: {
      done: tasks.filter((task) => task.status === "done").length,
      total: tasks.length,
    },
  };
}

export type GoalView = ReturnType<typeof goalView>;
