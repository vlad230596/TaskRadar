/*
 * The roster of models to parse with (14.10.2026): the owner's list of
 * preferred models, in order, and what each has been doing lately.
 *
 * THE RULES, AS AGREED WITH THE USER
 *
 * - Start with the model that answered last. A model that failed once is not
 *   dropped for good: the next request goes to the top of the list AND to the
 *   one that answered last, at the same time ([planSingle]) -- if the top one
 *   is back, it is used again; if not, no time was lost waiting for it.
 * - No background probing: a model's health is learnt only from real
 *   requests, so nothing is paid for that nobody asked.
 * - Three failures in a row: the model is skipped for [COOLDOWN_MS], then
 *   tried again (in a race, as above).
 * - [DISABLE_FAILURES] failures in a row within [DISABLE_WINDOW_MS]: the model
 *   is switched off -- marked, not deleted -- until the owner switches it back
 *   on. A provider's bad day must not cost the owner the list they set up.
 * - "Send to several" ([planMulti]): the first [MULTI_COUNT] usable models,
 *   all at once.
 *
 * Everything here is pure: the database side is `./modelRosterStore.ts`, the
 * running of attempts `./modelRouter.ts`.
 */

export const COOLDOWN_FAILURES = 3;
export const COOLDOWN_MS = 60 * 60 * 1000;
export const DISABLE_FAILURES = 6;
export const DISABLE_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;
export const MULTI_COUNT = 2;

export interface RosterEntry {
  /** Null for the one model of `.env` / the old setting, when no roster exists. */
  id: string | null;
  /** The model's name at its provider, as the API wants it. */
  name: string;
  /** What the app shows; the name when absent. */
  label: string | null;
  /** The provider's OpenAI-compatible base URL; `LLM_BASE_URL` when null. */
  baseUrl: string | null;
  /** The name of the env variable holding the key; `LLM_API_KEY` when null. */
  apiKeyEnv: string | null;
  /** Sampling temperature; the client's default when null (`../lib/llmClient.ts`). */
  temperature: number | null;
  enabled: boolean;
  autoDisabledAt: Date | null;
  consecutiveFailures: number;
  failStreakStartedAt: Date | null;
  lastSuccessAt: Date | null;
  lastFailureAt: Date | null;
}

/** Switched on by the owner and not switched off by its failures. */
export function isUsable(entry: RosterEntry): boolean {
  return entry.enabled && entry.autoDisabledAt === null;
}

/** Failed [COOLDOWN_FAILURES] times running, the last of them recently. */
export function isCoolingDown(entry: RosterEntry, now: Date): boolean {
  return (
    entry.consecutiveFailures >= COOLDOWN_FAILURES &&
    entry.lastFailureAt !== null &&
    now.getTime() - entry.lastFailureAt.getTime() < COOLDOWN_MS
  );
}

/**
 * The models worth asking now, in the owner's order. When every usable model
 * is cooling down, all of them -- asking one that has been failing beats
 * answering "no model" outright.
 */
export function eligible(entries: readonly RosterEntry[], now: Date): RosterEntry[] {
  const usable = entries.filter(isUsable);
  const warm = usable.filter((entry) => !isCoolingDown(entry, now));
  return warm.length > 0 ? warm : usable;
}

/** The model that answered most recently, or null when none ever has. */
export function lastGood(entries: readonly RosterEntry[]): RosterEntry | null {
  let best: RosterEntry | null = null;
  for (const entry of entries) {
    if (entry.lastSuccessAt === null) continue;
    if (best === null || entry.lastSuccessAt > best.lastSuccessAt!) best = entry;
  }
  return best;
}

/** One request's plan: [first] all at once, then [fallback] one by one. */
export interface SinglePlan {
  first: RosterEntry[];
  fallback: RosterEntry[];
}

/**
 * Who answers one request.
 *
 * The top of the list alone when it is also the one that answered last (or
 * nothing has answered yet). Otherwise the top has failed lately, or has
 * never been tried -- a new model, a reordered list -- and it races the one
 * that answered last. Everything else waits as the fallback, in order.
 */
export function planSingle(entries: readonly RosterEntry[], now: Date): SinglePlan {
  const list = eligible(entries, now);
  if (list.length === 0) return { first: [], fallback: [] };
  const top = list[0]!;
  const good = lastGood(list);
  const first = good === null || good === top ? [top] : [top, good];
  return { first, fallback: list.filter((entry) => !first.includes(entry)) };
}

/** "Отправить в несколько": the first [count] models worth asking. */
export function planMulti(
  entries: readonly RosterEntry[],
  now: Date,
  count = MULTI_COUNT,
): RosterEntry[] {
  return eligible(entries, now).slice(0, count);
}

/** What one attempt changes about its model. */
export interface HealthUpdate {
  consecutiveFailures: number;
  failStreakStartedAt: Date | null;
  lastSuccessAt?: Date;
  lastFailureAt?: Date;
  autoDisabledAt?: Date;
  autoDisabledReason?: string;
}

/**
 * The model after an attempt that [ok]. A streak that started more than
 * [DISABLE_WINDOW_MS] ago starts over: "six in a row within a week" is about
 * a model that is down, not one asked twice a month.
 */
export function afterAttempt(entry: RosterEntry, ok: boolean, now: Date): HealthUpdate {
  if (ok) return { consecutiveFailures: 0, failStreakStartedAt: null, lastSuccessAt: now };

  const stale =
    entry.failStreakStartedAt === null ||
    now.getTime() - entry.failStreakStartedAt.getTime() > DISABLE_WINDOW_MS;
  const failures = stale ? 1 : entry.consecutiveFailures + 1;
  const startedAt = stale ? now : entry.failStreakStartedAt!;
  const update: HealthUpdate = {
    consecutiveFailures: failures,
    failStreakStartedAt: startedAt,
    lastFailureAt: now,
  };
  if (failures >= DISABLE_FAILURES) {
    update.autoDisabledAt = now;
    update.autoDisabledReason = `${failures} неудач подряд с ${startedAt.toISOString().slice(0, 10)}`;
  }
  return update;
}
