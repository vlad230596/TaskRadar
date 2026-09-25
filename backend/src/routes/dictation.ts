import { FastifyInstance } from "fastify";
import { HttpError } from "../lib/errors";
import { UpstreamModelError } from "../lib/llmClient";
import { DictationParser } from "../domain/dictation";
import { parseDictationSchema } from "../schemas";

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
export function dictationRoutes(parser: DictationParser | null) {
  return async function (app: FastifyInstance): Promise<void> {
    app.post("/dictation/parse", async (request, reply) => {
      const body = parseDictationSchema.parse(request.body);
      if (parser === null) throw new DictationUnavailableError();

      try {
        const parsed = await parser({
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
  };
}
