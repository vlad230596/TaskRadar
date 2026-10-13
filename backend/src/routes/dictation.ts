import { FastifyInstance, FastifyBaseLogger } from "fastify";
import { Prisma } from "@prisma/client";
import { prisma } from "../lib/prisma";
import { userIdOf } from "../lib/users";
import { OWNER_SUBJECT } from "../lib/authConfig";
import { consumeAiQuota, loadAiDailyLimit } from "../lib/aiLimit";
import { HttpError } from "../lib/errors";
import { CompleteJson, UpstreamModelError } from "../lib/llmClient";
import { openEventStream, wantsEventStream } from "../lib/eventStream";
import { DictationInput, DictationParser } from "../domain/dictation";
import { readDictationModelOverride, writeDictationModelOverride } from "../domain/dictationModel";
import {
  keptPipeline,
  ParseHooks,
  ParseKind,
  ParsePipeline,
  ParseTrace,
} from "../domain/parsePipeline";
import { planMulti, planSingle, RosterEntry } from "../domain/modelRoster";
import { MultiOutcome, runMulti, runSingle } from "../domain/modelRouter";
import { SandboxInput, TidyParsers } from "../domain/tidy";
import {
  parseDictationSchema,
  parseDictationStreamSchema,
  setDictationModelSchema,
} from "../schemas";

/** What the dictation routes need when a model is configured. */
export interface DictationFeature {
  parser: DictationParser;
  /**
   * The tidying kinds -- `task_tidy`, `note`, `sandbox` (`../domain/tidy.ts`).
   * Absent: those kinds answer 503, as with no model at all.
   */
  tidiers?: TidyParsers;
  /** `LLM_MODEL` from `.env`: what is used when the app has not chosen one. */
  defaultModel: string;
  /** `LLM_BASE_URL`: where a roster entry with no URL of its own goes. */
  defaultBaseUrl?: string;
  /**
   * The model call's budget in a streamed parse of [textLength] characters
   * (`streamTimeoutFor` in `../lib/llmConfig.ts`). Absent: the parser's own
   * default, as in the one-shot reply.
   */
  streamTimeoutMs?: (textLength: number) => number;
  /**
   * The owner's list of models (`../domain/modelRoster.ts`): who is asked,
   * what each attempt taught us, and how to reach each one's provider.
   * Absent: the parsers' own single model, as before the roster existed.
   */
  roster?: {
    read: () => Promise<RosterEntry[]>;
    record: (entry: RosterEntry, ok: boolean) => Promise<void>;
    clientFor: (entry: RosterEntry) => CompleteJson;
  };
}

export interface DictationRouteOptions {
  /** How often a streamed parse says it is still alive. */
  heartbeatMs?: number | undefined;
  /** AI requests one user may make per UTC day. Defaults to `AI_DAILY_LIMIT`. */
  dailyLimit?: number | undefined;
}

const HEARTBEAT_MS = 5_000;

/**
 * No model is configured on this server. 503, not 404: the route exists, the
 * feature is switched off, and the client's answer to both is the same -- keep
 * the words as they were spoken.
 */
class DictationUnavailableError extends HttpError {
  constructor() {
    super(503, "Dictation parsing is not configured");
  }
}

/**
 * The projects a sandbox line can be filed into, for the `sandbox` prompt:
 * every one of the caller's own not archived, read here and never taken from the request -- see
 * `../domain/tidy.ts`.
 */
async function sandboxInputFor(userId: string, input: DictationInput): Promise<SandboxInput> {
  const projects = await prisma.project.findMany({
    where: { archivedAt: null, scope: { userId } },
    select: { id: true, name: true },
    orderBy: { createdAt: "asc" },
  });
  return { ...input, projects };
}

/**
 * Keeps one parse in the dataset (`DictationParse` in prisma/schema.prisma)
 * and returns its id, or null when it could not be kept.
 *
 * A failed write is logged and swallowed: the dataset is for improving the
 * prompt later, and losing one sample is no reason to take the proposal away
 * from the person waiting for it now.
 */
async function keepSample(
  userId: string,
  kind: ParseKind,
  input: DictationInput,
  trace: ParseTrace<object>,
  log: FastifyBaseLogger,
): Promise<string | null> {
  try {
    const row = await prisma.dictationParse.create({
      data: {
        userId,
        kind,
        inputText: input.text,
        timeZone: input.timeZone,
        requestedAt: input.now,
        model: trace.model,
        promptVersion: trace.promptVersion,
        level: input.level ?? null,
        status: trace.result === null ? "failed" : "ok",
        rawReply: trace.rawReply,
        result: trace.result === null ? Prisma.JsonNull : { ...trace.result },
        error: trace.error,
        durationMs: trace.durationMs,
      },
      select: { id: true },
    });
    return row.id;
  } catch (error) {
    log.error({ err: error }, "could not keep the dictation sample");
    return null;
  }
}

/**
 * The pipeline for [kind], or null when this server has no parser for it.
 *
 * The reason for a failure goes to the log and the dataset, not to the client:
 * it can name the provider's status or a fragment of its reply, which is ours
 * to debug and nobody else's to read. The client hears only its class
 * (`UpstreamCause` in ../lib/llmClient.ts) and the model that was asked.
 */
function pipelineFor(
  userId: string,
  feature: DictationFeature,
  kind: ParseKind,
  log: FastifyBaseLogger,
): ParsePipeline | null {
  const keep = <I extends DictationInput>(sample: I, trace: ParseTrace<object>) =>
    keepSample(userId, kind, sample, trace, log);
  const onFailure = (reason: string | null, parseId: string | null) =>
    log.warn({ reason, parseId, kind }, "dictation model failed");

  if (kind === "task") return keptPipeline(feature.parser, keep, onFailure);
  const tidiers = feature.tidiers;
  if (tidiers === undefined) return null;
  switch (kind) {
    case "task_tidy":
      return keptPipeline(tidiers.task_tidy, keep, onFailure);
    case "note":
      return keptPipeline(tidiers.note, keep, onFailure);
    case "sandbox":
      return keptPipeline(tidiers.sandbox, keep, onFailure, (input) => sandboxInputFor(userId, input));
  }
}

/*
 * Dictation -> task (F14), and the tidying kinds beside it (F15). See
 * `../domain/dictation.ts` and `../domain/tidy.ts` for what the model does.
 *
 * NO TASK IS WRITTEN HERE
 *
 * The route answers with a proposed task. The client decides what to do with
 * it -- create the task, correct it first, or throw it away and use the raw
 * words -- through the task route that already exists and already writes the
 * journal. A second way to create a task, here, would be a second place that
 * had to remember the `created` event.
 *
 * What *is* written is the dataset row: input, reply, duration. Its id goes
 * back as `parseId`, and the route that saves the answer links the row to what
 * was saved when the client sends it along as `dictationParseId`: the task
 * routes (a new task, a tidied one), the note routes and the sandbox's -- see
 * `../domain/dictationLink.ts`.
 */
export function dictationRoutes(
  feature: DictationFeature | null,
  options: DictationRouteOptions = {},
) {
  const heartbeatMs = options.heartbeatMs ?? HEARTBEAT_MS;
  const dailyLimit = options.dailyLimit ?? loadAiDailyLimit();

  return async function (app: FastifyInstance): Promise<void> {
    /*
     * ONE ROUTE, TWO REPLIES
     *
     * Without `Accept: text/event-stream` -- every client released before the
     * stream existed -- the reply is the one JSON body it always was, with the
     * same statuses and the same `LLM_TIMEOUT_MS`.
     *
     * With it, the reply is a stream of events, so a parse of a long dictation
     * can take the minute it needs without the phone taking the silence for a
     * dead request:
     *
     *     accepted       {kind}                  the body was valid; work starts
     *     model_started  {model}                 the request to the model is out
     *     model_done     {durationMs}            the model answered
     *     validated      {}                      its answer is usable
     *     result         {..., parseId}          the same payload as the JSON reply
     *     error          {code, message,         instead of result; ends the stream;
     *                     cause?, model?}         cause is an UpstreamCause (../lib/llmClient.ts)
     *     heartbeat      {}                      every 5 s, whatever else is said
     *
     * What `result` holds depends on the request's `kind` (`task` when absent):
     *
     *     task       {title, description, remindDate, remindTime}
     *     task_tidy  {title, description, warnings}
     *     note       {title, content, warnings}       title only when the note had none
     *     sandbox    {text, title, description,       the line, and the same text as a
     *                 projectId, projectName,         task for filing it; the project
     *                 warnings}                       both null without a match
     *
     * `warnings` is a list, usually empty, of what the user should check
     * before taking the answer -- today `{kind: "invented_date", token}`, a
     * date the words did not say (`../domain/tidy.ts`). A warning never
     * withholds the answer.
     *
     * Every event's data may carry `partial` -- reserved for a model that
     * streams its answer, sent by nothing yet. Anything that fails before
     * `accepted` (a bad body, no session, no model configured) is still an
     * ordinary HTTP status, so a client handles those exactly as before.
     */
    app.post("/dictation/parse", async (request, reply) => {
      const stream = wantsEventStream(request.headers.accept);
      const body = (stream ? parseDictationStreamSchema : parseDictationSchema).parse(request.body);
      if (feature === null) throw new DictationUnavailableError();

      const input: DictationInput = {
        text: body.text,
        timeZone: body.timeZone,
        now: new Date(),
        noteTitle: body.noteTitle,
        level: body.level,
      };
      const userId = userIdOf(request);
      const pipeline = pipelineFor(userId, feature, body.kind, request.log);
      if (pipeline === null) throw new DictationUnavailableError();

      /*
       * Who is asked (`../domain/modelRoster.ts`): with a roster, a plan of
       * models; "send to several" asks the first few at once and is only for
       * a streamed reply. Without a roster, the parser's one model.
       */
      const roster = feature.roster;
      const multi = stream && "multi" in body && body.multi === true;
      const entries = roster === undefined ? null : await roster.read();
      const multiPlan = multi && entries !== null ? planMulti(entries, input.now) : null;

      // The owner's key pays for every user, so each gets a day's allowance.
      // Spent here, before the stream opens, so a refusal is an ordinary 429
      // the client can show, and a request that was never going to run (bad
      // body, feature off) costs nothing. "Send to several" costs one per
      // model asked; a race the server starts on its own costs one.
      await consumeAiQuota(userId, dailyLimit, input.now, Math.max(1, multiPlan?.length ?? 1));

      /** The parse, through the roster when there is one. */
      const run = (
        hooks?: ParseHooks,
        onOutcome?: (outcome: MultiOutcome<Record<string, unknown>>) => void,
      ): Promise<Record<string, unknown>> => {
        if (roster === undefined || entries === null) return pipeline(input, hooks);
        const deps = {
          attempt: async (entry: RosterEntry) => ({
            ...(await pipeline(input, {
              ...hooks,
              target: { model: entry.name, complete: roster.clientFor(entry) },
            })),
            // What the app calls the model; its name at the provider otherwise.
            modelLabel: entry.label ?? entry.name,
          }),
          record: async (entry: RosterEntry, ok: boolean) => {
            try {
              await roster.record(entry, ok);
            } catch (error) {
              request.log.error({ err: error }, "could not record the model's outcome");
            }
          },
        };
        return multiPlan !== null
          ? runMulti(multiPlan, deps, onOutcome ?? (() => {}))
          : runSingle(planSingle(entries, input.now), deps);
      };

      if (!stream) {
        reply.send(await run());
        return;
      }

      const events = openEventStream(reply, { heartbeatMs });
      events.send("accepted", { kind: body.kind });
      try {
        const result = await run(
          {
            onStage: ({ stage, ...data }) => events.send(stage, data),
            timeoutMs: feature.streamTimeoutMs?.(input.text.length),
            signal: events.signal,
          },
          // Each model's answer as it comes: the fast one is read while the
          // slow one is still thinking.
          (outcome) => {
            const model = outcome.entry.name;
            const modelLabel = outcome.entry.label ?? model;
            if (outcome.ok) {
              events.send("candidate", { model, modelLabel, result: outcome.result });
            } else {
              const error = outcome.error;
              events.send("candidate_failed", {
                model,
                modelLabel,
                cause: error instanceof UpstreamModelError ? error.category : "internal",
              });
            }
          },
        );
        events.send("result", result);
      } catch (error) {
        if (error instanceof UpstreamModelError) {
          // `model` is dropped by JSON when the failure is not tied to one.
          events.send("error", {
            code: "model_failed",
            message: error.message,
            cause: error.category,
            model: error.model,
          });
        } else {
          request.log.error({ err: error }, "dictation parse failed");
          events.send("error", { code: "internal", message: "Internal Server Error" });
        }
      } finally {
        events.close();
      }
    });

    /*
     * The model, as the settings screen shows it: what is in use, what `.env`
     * says, and whether the app has overridden it. See
     * `../domain/dictationModel.ts` for why the model is changeable from the
     * app and the key is not.
     */
    async function describeModel(defaultModel: string) {
      const override = await readDictationModelOverride();
      return { model: override ?? defaultModel, defaultModel, override };
    }

    app.get("/dictation/model", async (_request, reply) => {
      if (feature === null) throw new DictationUnavailableError();
      reply.send(await describeModel(feature.defaultModel));
    });

    app.put("/dictation/model", async (request, reply) => {
      const body = setDictationModelSchema.parse(request.body);
      // The model is one setting for the whole server and it decides what the
      // owner's key is spent on, so only the owner may change it. Everyone can
      // read it.
      if (userIdOf(request) !== OWNER_SUBJECT) throw new HttpError(403, "Only the owner can change the model");
      if (feature === null) throw new DictationUnavailableError();

      // Choosing the `.env` model by name is the same as choosing nothing, and
      // stored as nothing -- otherwise a later change of LLM_MODEL would be
      // silently shadowed by a row that only ever meant "the default".
      const model = body.model === feature.defaultModel ? null : body.model;
      await writeDictationModelOverride(model);
      reply.send(await describeModel(feature.defaultModel));
    });
  };
}
