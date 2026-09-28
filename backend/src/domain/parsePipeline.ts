import { UpstreamModelError } from "../lib/llmClient";
import type { DictationInput, DictationParser, DictationTrace } from "./dictation";

/*
 * One parse through the model, as a sequence of stages (F14).
 *
 * WHY STAGES
 *
 * A parse is a round trip to someone else's model, and on a long dictation it
 * takes tens of seconds. A spinner that says nothing for that long is
 * indistinguishable from a dead request, so the route can stream what is
 * happening -- `model_started`, `model_done`, `validated` -- and the phone shows
 * it as a stepper (`POST /dictation/parse` with `Accept: text/event-stream`, see
 * `../routes/dictation.ts`).
 *
 * WHY KINDS
 *
 * The task is the first thing dictation is tidied into, not the last: a note, an
 * existing task's description, a sandbox line will want prompts of their own.
 * Each is a [ParsePipeline] under its own [ParseKind], behind the same endpoint
 * and the same event sequence, so the client's stepper does not care which one
 * it is watching. Only `task` exists today.
 */

/** What a dictation can be parsed into. The request's `kind`, default `task`. */
export const PARSE_KINDS = ["task"] as const;
export type ParseKind = (typeof PARSE_KINDS)[number];

/** A step of the parse worth telling the person waiting for it about. */
export type ParseStage =
  | { stage: "model_started"; model: string }
  | { stage: "model_done"; durationMs: number }
  | { stage: "validated" };

/** How a caller watches, and bounds, one parse. All optional. */
export interface ParseHooks {
  onStage?: (stage: ParseStage) => void;
  /** Budget for the model call; the configured `LLM_TIMEOUT_MS` when absent. */
  timeoutMs?: number | undefined;
  /** Aborted when nobody is waiting for the answer any more. */
  signal?: AbortSignal | undefined;
}

/**
 * One kind of parse, start to finish: the model, the check of its reply, and
 * whatever is kept of it. Resolves with the `result` payload, or throws
 * [UpstreamModelError] when there is no usable answer.
 */
export type ParsePipeline = (
  input: DictationInput,
  hooks?: ParseHooks,
) => Promise<Record<string, unknown>>;

/** Keeps a finished parse in the dataset; the row's id, or null. */
export type KeepSample = (input: DictationInput, trace: DictationTrace) => Promise<string | null>;

/**
 * `task`: the words as a proposed task. The sample is kept whatever the
 * outcome -- a failure is exactly what a comparison between models has to
 * count -- and its id goes back as `parseId`.
 *
 * [onFailure] hears the reason, which is the log's to know and not the
 * client's: it can name the provider's status or a fragment of its reply.
 */
export function taskPipeline(
  parser: DictationParser,
  keep: KeepSample,
  onFailure: (reason: string | null, parseId: string | null) => void,
): ParsePipeline {
  return async (input, hooks) => {
    const trace = await parser(input, hooks);
    const parseId = await keep(input, trace);
    if (trace.result === null) {
      onFailure(trace.error, parseId);
      throw new UpstreamModelError(trace.error ?? "unknown");
    }
    return { ...trace.result, parseId };
  };
}
