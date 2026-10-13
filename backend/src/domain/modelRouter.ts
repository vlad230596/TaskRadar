import { UpstreamModelError } from "../lib/llmClient";
import type { RosterEntry, SinglePlan } from "./modelRoster";

/*
 * Running a parse against the roster (14.10.2026): who is asked when, and
 * what each answer or failure teaches the roster. Which models make the plan
 * is `./modelRoster.ts`; this only runs it.
 *
 * WHY THE LOSER OF A RACE IS NOT STOPPED
 *
 * When the top model races the one that answered last, the first answer goes
 * to the user at once -- but the other request is left to finish. Stopping it
 * would save one call and lose the only thing the race was for: learning
 * whether the top model is back. (It is stopped when the user cancels: then
 * nobody is waiting for either.)
 */

export interface RouterDeps<R> {
  /** One model asked; rejects with [UpstreamModelError] when it fails. */
  attempt: (entry: RosterEntry) => Promise<R>;
  /** What the attempt taught us about [entry]. */
  record: (entry: RosterEntry, ok: boolean) => Promise<void>;
}

/** A cancelled attempt says nothing about the model. */
function counts(error: unknown): boolean {
  return !(error instanceof UpstreamModelError && error.category === "cancelled");
}

function isCancelled(error: unknown): boolean {
  return error instanceof UpstreamModelError && error.category === "cancelled";
}

/** [entry] asked, with the outcome recorded either way. */
async function recorded<R>(entry: RosterEntry, deps: RouterDeps<R>): Promise<R> {
  let result: R;
  try {
    result = await deps.attempt(entry);
  } catch (error) {
    if (counts(error)) await deps.record(entry, false);
    throw error;
  }
  await deps.record(entry, true);
  return result;
}

/**
 * The first of [attempts] to succeed; when all fail, the first one's error --
 * the top of the list is the model the user cares about. No rejection is
 * left unhandled, including those that come after the winner.
 */
function firstSuccess<R>(attempts: Promise<R>[]): Promise<R> {
  return new Promise<R>((resolve, reject) => {
    const errors: unknown[] = new Array(attempts.length);
    let failed = 0;
    attempts.forEach((attempt, index) => {
      attempt.then(resolve, (error: unknown) => {
        errors[index] = error;
        failed += 1;
        if (failed === attempts.length) reject(errors[0]);
      });
    });
  });
}

/** Nothing to ask: no model is switched on. */
export function noModelError(): UpstreamModelError {
  return new UpstreamModelError("no usable model in the roster", "model_not_found");
}

/**
 * One answer for one request: [plan.first] all at once, the first success
 * wins; if all of them fail, [plan.fallback] one at a time. A cancellation
 * ends it all at once.
 */
export async function runSingle<R>(plan: SinglePlan, deps: RouterDeps<R>): Promise<R> {
  if (plan.first.length === 0) throw noModelError();
  let lastError: unknown;
  try {
    return await firstSuccess(plan.first.map((entry) => recorded(entry, deps)));
  } catch (error) {
    if (isCancelled(error)) throw error;
    lastError = error;
  }
  for (const entry of plan.fallback) {
    try {
      return await recorded(entry, deps);
    } catch (error) {
      if (isCancelled(error)) throw error;
      lastError = error;
    }
  }
  throw lastError;
}

/** One model's outcome in "send to several". */
export type MultiOutcome<R> =
  { entry: RosterEntry; ok: true; result: R } | { entry: RosterEntry; ok: false; error: unknown };

/**
 * "Отправить в несколько": every one of [entries] at once, [onOutcome] as
 * each settles -- the fast one is heard while the slow one is still
 * thinking. Resolves, once all have settled, with the first success in time;
 * rejects with the first entry's error when none succeeded.
 */
export async function runMulti<R>(
  entries: readonly RosterEntry[],
  deps: RouterDeps<R>,
  onOutcome: (outcome: MultiOutcome<R>) => void,
): Promise<R> {
  if (entries.length === 0) throw noModelError();
  let first: { result: R } | null = null;
  const settled = await Promise.allSettled(
    entries.map((entry) =>
      recorded(entry, deps).then(
        (result) => {
          first ??= { result };
          onOutcome({ entry, ok: true, result });
          return result;
        },
        (error: unknown) => {
          onOutcome({ entry, ok: false, error });
          throw error;
        },
      ),
    ),
  );
  if (first !== null) return (first as { result: R }).result;
  throw (settled[0] as PromiseRejectedResult).reason;
}
