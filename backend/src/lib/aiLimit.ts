import { prisma } from "./prisma";
import { HttpError } from "./errors";

/** Requests per user per UTC day when `AI_DAILY_LIMIT` does not say otherwise. */
export const DEFAULT_AI_DAILY_LIMIT = 50;

/** `AI_DAILY_LIMIT` from the environment: a positive integer, else the default. */
export function loadAiDailyLimit(env: NodeJS.ProcessEnv = process.env): number {
  const raw = env.AI_DAILY_LIMIT;
  if (raw === undefined || raw.trim() === "") return DEFAULT_AI_DAILY_LIMIT;
  const value = Number(raw);
  return Number.isInteger(value) && value > 0 ? value : DEFAULT_AI_DAILY_LIMIT;
}

/** Answered when a user has spent the day's AI requests. */
export class AiLimitError extends HttpError {
  constructor(limit: number) {
    super(429, `Daily AI request limit reached (${limit}). It resets at 00:00 UTC.`);
  }
}

/** The UTC calendar day a moment falls on, as `YYYY-MM-DD`. */
export function utcDay(now: Date): string {
  return now.toISOString().slice(0, 10);
}

/**
 * Spends one of the user's AI requests for today, or throws {@link AiLimitError}.
 *
 * One atomic upsert-and-increment rather than read-then-write, so two requests
 * arriving together cannot both see "49" and both go through. The request that
 * crosses the line is counted too; it costs nothing and keeps this a single
 * statement.
 *
 * Every user is held to the same limit -- the owner's key pays for all of them.
 * Counted per request, not per token: a request is what the client can see and
 * what the operator can reason about, and one dictation is one model call.
 */
export async function consumeAiQuota(userId: string, limit: number, now: Date): Promise<void> {
  const row = await prisma.aiUsage.upsert({
    where: { userId_day: { userId, day: utcDay(now) } },
    create: { userId, day: utcDay(now), count: 1 },
    update: { count: { increment: 1 } },
    select: { count: true },
  });
  if (row.count > limit) throw new AiLimitError(limit);
}
