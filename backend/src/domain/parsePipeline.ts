import { ChatMessage, CompleteJson, UpstreamModelError } from "../lib/llmClient";
import type { DictationInput } from "./dictation";

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
 * The task was the first thing dictation was tidied into, not the last. Each
 * kind is its own prompt, its own reply shape and its own check of the reply,
 * behind the same endpoint and the same event sequence, so the client's
 * stepper does not care which one it is watching:
 *
 *     task       new dictation -> a proposed task, with a reminder (./dictation.ts)
 *     task_tidy  an existing task's text -> the same text, tidied (./tidy.ts)
 *     note       a note's body -> paragraphs and lists (./tidy.ts)
 *     sandbox    a sandbox line -> the line tidied, and a project for it (./tidy.ts)
 *
 * Every kind runs from the words it is sent, never from an earlier answer:
 * "Разобрать заново" sends the source again. The client keeps the source on
 * screen for that; nothing here remembers it between requests.
 */

/** What a dictation can be parsed into. The request's `kind`, default `task`. */
export const PARSE_KINDS = ["task", "task_tidy", "note", "sandbox"] as const;
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
 * Everything one parse did, successful or not -- what the dataset row keeps
 * (`DictationParse` in prisma/schema.prisma). [T] is the kind's reply shape.
 */
export interface ParseTrace<T> {
  model: string;
  promptVersion: string;
  /** The reply as received; null when none arrived. */
  rawReply: string | null;
  /** Null when the parse failed. */
  result: T | null;
  /** Why it failed; null when it did not. */
  error: string | null;
  durationMs: number;
}

/**
 * One kind's prompt and its check of the reply. [interpret] throws
 * [UpstreamModelError] when there is nothing usable in the reply.
 */
export interface ParseSpec<I, T> {
  /**
   * Which prompt a dataset row was produced with. Bumped whenever [build]
   * changes what it asks, so rows from different prompts are never compared
   * as if they were the same experiment.
   */
  promptVersion: string;
  build: (input: I) => ChatMessage[];
  interpret: (content: string, input: I) => T;
}

/**
 * A parse that never throws for a model failure: the failure is part of the
 * trace. [hooks] hear the stages as they pass and bound the model call.
 */
export type KindParser<I, T> = (input: I, hooks?: ParseHooks) => Promise<ParseTrace<T>>;

/**
 * [resolveModel] is asked on every parse, so a model chosen in the app takes
 * effect on the next one. See `./dictationModel.ts`.
 */
export function createKindParser<I, T>(
  spec: ParseSpec<I, T>,
  complete: CompleteJson,
  resolveModel: () => Promise<string>,
  clock: () => number = Date.now,
): KindParser<I, T> {
  return async (input, hooks = {}) => {
    const model = await resolveModel();
    hooks.onStage?.({ stage: "model_started", model });
    const started = clock();
    let rawReply: string | null = null;
    const trace = (result: T | null, error: string | null): ParseTrace<T> => ({
      model,
      promptVersion: spec.promptVersion,
      rawReply,
      result,
      error,
      durationMs: clock() - started,
    });
    try {
      rawReply = await complete(spec.build(input), model, {
        timeoutMs: hooks.timeoutMs,
        signal: hooks.signal,
      });
      hooks.onStage?.({ stage: "model_done", durationMs: clock() - started });
      const result = spec.interpret(rawReply, input);
      hooks.onStage?.({ stage: "validated" });
      return trace(result, null);
    } catch (error) {
      if (!(error instanceof UpstreamModelError)) throw error;
      return trace(null, error.reason);
    }
  };
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
export type KeepSample<I> = (input: I, trace: ParseTrace<object>) => Promise<string | null>;

/**
 * Any kind: the parse, then the sample. The sample is kept whatever the
 * outcome -- a failure is exactly what a comparison between models has to
 * count -- and its id goes back as `parseId`.
 *
 * [prepare] turns the request into the kind's input (the sandbox reads its
 * project list there). [onFailure] hears the reason, which is the log's to
 * know and not the client's: it can name the provider's status or a fragment
 * of its reply.
 */
export function keptPipeline<I extends DictationInput, T extends object>(
  parser: KindParser<I, T>,
  keep: KeepSample<I>,
  onFailure: (reason: string | null, parseId: string | null) => void,
  prepare: (input: DictationInput) => Promise<I> | I = (input) => input as I,
): ParsePipeline {
  return async (request, hooks) => {
    const input = await prepare(request);
    const trace = await parser(input, hooks);
    const parseId = await keep(input, trace);
    if (trace.result === null) {
      onFailure(trace.error, parseId);
      throw new UpstreamModelError(trace.error ?? "unknown");
    }
    return { ...trace.result, parseId };
  };
}
