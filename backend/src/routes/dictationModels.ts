import { FastifyInstance } from "fastify";
import { z } from "zod";
import { OWNER_SUBJECT } from "../lib/authConfig";
import { HttpError } from "../lib/errors";
import { userIdOf } from "../lib/users";
import { isCoolingDown, RosterEntry } from "../domain/modelRoster";
import { readRoster, reenableModel, writeRoster } from "../domain/modelRosterStore";
import { resolveDictationModel } from "../domain/dictationModel";
import { idParamSchema } from "../schemas";

/*
 * The roster of models, for the settings screen (14.10.2026). See
 * ../domain/modelRoster.ts for what the list means.
 *
 * Under `/dictation/` on purpose: Caddy forwards known prefixes only, and a
 * new one is a deploy change.
 *
 * WHO SEES WHAT
 *
 * Everyone may read the list -- which model is answering is useful to anyone
 * dictating -- but only the owner sees where each provider lives and which
 * key it uses, and only the owner may change anything: the keys are the
 * owner's, and so is the bill.
 *
 * WHY A KEY IS NAMED, NEVER SENT
 *
 * An entry names the env variable that holds its key (`apiKeyEnv`), and the
 * name must start with `LLM_`. The key itself never leaves `.env`; and the
 * prefix keeps an entry from pointing a request at, say, `JWT_SECRET` and
 * sending it to a URL of its choosing.
 */

const API_KEY_ENV = /^LLM_[A-Z0-9_]{1,60}$/;

const rosterInputSchema = z.object({
  models: z
    .array(
      z.object({
        id: z.string().min(1).max(100).optional(),
        name: z.string().trim().min(1, "name is required").max(200),
        label: z
          .string()
          .trim()
          .max(100)
          .nullish()
          .transform((value) => value || null),
        baseUrl: z
          .string()
          .trim()
          .url("baseUrl must be a URL")
          .refine((value) => /^https?:\/\//.test(value), "baseUrl must be http(s)")
          .transform((value) => value.replace(/\/+$/, ""))
          .nullish()
          .or(z.literal("").transform(() => null)),
        apiKeyEnv: z
          .string()
          .trim()
          .regex(API_KEY_ENV, "apiKeyEnv must be an env variable name starting with LLM_")
          .nullish()
          .or(z.literal("").transform(() => null)),
        enabled: z.boolean().default(true),
      }),
    )
    .max(10, "at most 10 models"),
});

export interface DictationModelsOptions {
  /** `LLM_MODEL`, and the base URL used when an entry names none. */
  defaultModel: string;
  defaultBaseUrl: string;
  env?: NodeJS.ProcessEnv;
}

export function dictationModelRoutes(options: DictationModelsOptions | null) {
  const env = options?.env ?? process.env;

  function describe(entry: RosterEntry & { id: string | null }, owner: boolean, now: Date) {
    const status = entry.autoDisabledAt
      ? "auto_disabled"
      : !entry.enabled
        ? "disabled"
        : isCoolingDown(entry, now)
          ? "cooling_down"
          : "ok";
    return {
      id: entry.id,
      name: entry.name,
      label: entry.label,
      enabled: entry.enabled,
      status,
      autoDisabledAt: entry.autoDisabledAt,
      autoDisabledReason:
        (entry as { autoDisabledReason?: string | null }).autoDisabledReason ?? null,
      consecutiveFailures: entry.consecutiveFailures,
      lastSuccessAt: entry.lastSuccessAt,
      lastFailureAt: entry.lastFailureAt,
      ...(owner
        ? {
            baseUrl: entry.baseUrl,
            apiKeyEnv: entry.apiKeyEnv,
            // Whether the named variable is set, so a typo shows before the
            // first failed request does. Never its value.
            keyPresent:
              entry.apiKeyEnv === null ? true : (env[entry.apiKeyEnv] ?? "").trim() !== "",
          }
        : {}),
    };
  }

  async function list(owner: boolean) {
    const now = new Date();
    const models = (await readRoster()).map((entry) => describe(entry, owner, now));
    return {
      models,
      // What answers while the list is empty: the old app setting, else `.env`.
      defaultModel: options === null ? null : await resolveDictationModel(options.defaultModel),
      ...(owner ? { defaultBaseUrl: options?.defaultBaseUrl ?? null } : {}),
    };
  }

  function requireOwner(userId: string) {
    if (userId !== OWNER_SUBJECT) throw new HttpError(403, "Only the owner can change the models");
  }

  return async function (app: FastifyInstance): Promise<void> {
    app.get("/dictation/models", async (request, reply) => {
      if (options === null) throw new HttpError(503, "Dictation parsing is not configured");
      reply.send(await list(userIdOf(request) === OWNER_SUBJECT));
    });

    app.put("/dictation/models", async (request, reply) => {
      requireOwner(userIdOf(request));
      if (options === null) throw new HttpError(503, "Dictation parsing is not configured");
      const body = rosterInputSchema.parse(request.body);
      await writeRoster(body.models);
      reply.send(await list(true));
    });

    app.post("/dictation/models/:id/reenable", async (request, reply) => {
      requireOwner(userIdOf(request));
      if (options === null) throw new HttpError(503, "Dictation parsing is not configured");
      const { id } = idParamSchema.parse(request.params);
      await reenableModel(id);
      reply.send(await list(true));
    });
  };
}
