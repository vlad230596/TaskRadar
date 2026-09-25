import { FastifyInstance, FastifyBaseLogger } from "fastify";
import { Prisma } from "@prisma/client";
import { prisma } from "../lib/prisma";
import { HttpError } from "../lib/errors";
import { UpstreamModelError } from "../lib/llmClient";
import { DictationInput, DictationParser, DictationTrace } from "../domain/dictation";
import { readDictationModelOverride, writeDictationModelOverride } from "../domain/dictationModel";
import { parseDictationSchema, setDictationModelSchema } from "../schemas";

/** What the dictation routes need when a model is configured. */
export interface DictationFeature {
  parser: DictationParser;
  /** `LLM_MODEL` from `.env`: what is used when the app has not chosen one. */
  defaultModel: string;
}

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
export function dictationRoutes(feature: DictationFeature | null) {
  return async function (app: FastifyInstance): Promise<void> {
    app.post("/dictation/parse", async (request, reply) => {
      const body = parseDictationSchema.parse(request.body);
      if (feature === null) throw new DictationUnavailableError();

      const input: DictationInput = {
        text: body.text,
        timeZone: body.timeZone,
        now: new Date(),
      };
      const trace = await feature.parser(input);
      const parseId = await keepSample(input, trace, request.log);

      if (trace.result === null) {
        // The reason goes to the log and the dataset, not to the client: it can
        // name the provider's status or a fragment of its reply, which is ours
        // to debug and nobody else's to read.
        request.log.warn({ reason: trace.error, parseId }, "dictation model failed");
        throw new UpstreamModelError(trace.error ?? "unknown");
      }
      reply.send({ ...trace.result, parseId });
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
