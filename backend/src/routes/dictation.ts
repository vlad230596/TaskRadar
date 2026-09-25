import { FastifyInstance } from "fastify";
import { HttpError } from "../lib/errors";
import { UpstreamModelError } from "../lib/llmClient";
import { DictationParser } from "../domain/dictation";
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

/*
 * Dictation -> task (F14). See `../domain/dictation.ts` for what the model does.
 *
 * A PURE TRANSFORMATION, NOT A WRITE
 *
 * The route answers with a proposed task and stores nothing. The client decides
 * what to do with it -- create the task, show it for correction, or throw it
 * away and use the raw words -- through the task routes that already exist and
 * already write the journal. A second way to create a task, here, would be a
 * second place that had to remember the `created` event.
 *
 * It is also what makes the fallback trivial: when this answers 502 or 503 the
 * client has lost nothing, because nothing was written.
 */
export function dictationRoutes(feature: DictationFeature | null) {
  return async function (app: FastifyInstance): Promise<void> {
    app.post("/dictation/parse", async (request, reply) => {
      const body = parseDictationSchema.parse(request.body);
      if (feature === null) throw new DictationUnavailableError();

      try {
        const parsed = await feature.parser({
          text: body.text,
          timeZone: body.timeZone,
          now: new Date(),
        });
        reply.send(parsed);
      } catch (error) {
        // The reason goes to the log and not to the client: it can name the
        // provider's status or a fragment of its reply, which is ours to debug
        // and nobody else's to read.
        if (error instanceof UpstreamModelError) {
          request.log.warn({ reason: error.reason }, "dictation model failed");
        }
        throw error;
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
