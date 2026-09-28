import { FastifyInstance, FastifyBaseLogger } from "fastify";
import { Prisma } from "@prisma/client";
import { prisma } from "../lib/prisma";
import { HttpError } from "../lib/errors";
import { UpstreamModelError } from "../lib/llmClient";
import { openEventStream, wantsEventStream } from "../lib/eventStream";
import { DictationInput, DictationParser, DictationTrace } from "../domain/dictation";
import { readDictationModelOverride, writeDictationModelOverride } from "../domain/dictationModel";
import { ParseKind, ParsePipeline, taskPipeline } from "../domain/parsePipeline";
import {
  parseDictationSchema,
  parseDictationStreamSchema,
  setDictationModelSchema,
} from "../schemas";

/** What the dictation routes need when a model is configured. */
export interface DictationFeature {
  parser: DictationParser;
  /** `LLM_MODEL` from `.env`: what is used when the app has not chosen one. */
  defaultModel: string;
  /**
   * The model call's budget in a streamed parse of [textLength] characters
   * (`streamTimeoutFor` in `../lib/llmConfig.ts`). Absent: the parser's own
   * default, as in the one-shot reply.
   */
  streamTimeoutMs?: (textLength: number) => number;
}

export interface DictationRouteOptions {
  /** How often a streamed parse says it is still alive. */
  heartbeatMs?: number | undefined;
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
 * Keeps one parse in the dataset (`DictationParse` in prisma/schema.prisma)
 * and returns its id, or null when it could not be kept.
 *
 * A failed write is logged and swallowed: the dataset is for improving the
 * prompt later, and losing one sample is no reason to take the proposal away
 * from the person waiting for it now.
 */
async function keepSample(
  input: DictationInput,
  trace: DictationTrace,
  log: FastifyBaseLogger,
): Promise<string | null> {
  try {
    const row = await prisma.dictationParse.create({
      data: {
        inputText: input.text,
        timeZone: input.timeZone,
        requestedAt: input.now,
        model: trace.model,
        promptVersion: trace.promptVersion,
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

/*
 * Dictation -> task (F14). See `../domain/dictation.ts` for what the model does.
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
 * back as `parseId`, and the task route links the row to the task when the
 * client sends it along -- see `dictationParseId` there.
 */
export function dictationRoutes(
  feature: DictationFeature | null,
  options: DictationRouteOptions = {},
) {
  const heartbeatMs = options.heartbeatMs ?? HEARTBEAT_MS;

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
     *     result         {title, ..., parseId}   the same payload as the JSON reply
     *     error          {code, message}         instead of result; ends the stream
     *     heartbeat      {}                      every 5 s, whatever else is said
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
      };
      const pipelines: Record<ParseKind, ParsePipeline> = {
        task: taskPipeline(
          feature.parser,
          (sample, trace) => keepSample(sample, trace, request.log),
          // The reason goes to the log and the dataset, not to the client: it
          // can name the provider's status or a fragment of its reply, which is
          // ours to debug and nobody else's to read.
          (reason, parseId) => request.log.warn({ reason, parseId }, "dictation model failed"),
        ),
      };
      const pipeline = pipelines[body.kind];

      if (!stream) {
        reply.send(await pipeline(input));
        return;
      }

      const events = openEventStream(reply, { heartbeatMs });
      events.send("accepted", { kind: body.kind });
      try {
        const result = await pipeline(input, {
          onStage: ({ stage, ...data }) => events.send(stage, data),
          timeoutMs: feature.streamTimeoutMs?.(input.text.length),
          signal: events.signal,
        });
        events.send("result", result);
      } catch (error) {
        if (error instanceof UpstreamModelError) {
          events.send("error", { code: "model_failed", message: error.message });
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
