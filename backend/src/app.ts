import Fastify, { FastifyInstance } from "fastify";
import fastifyCookie from "@fastify/cookie";
import fastifyJwt from "@fastify/jwt";
import { healthRoutes } from "./routes/health";
import { authRoutes } from "./routes/auth";
import { scopeRoutes } from "./routes/scopes";
import { projectRoutes } from "./routes/projects";
import { taskRoutes } from "./routes/tasks";
import { noteRoutes } from "./routes/notes";
import { categoryRoutes } from "./routes/categories";
import { inboxRoutes } from "./routes/inbox";
import { focusRoutes } from "./routes/focus";
import { historyRoutes } from "./routes/history";
import { boardRoutes } from "./routes/board";
import { dictationRoutes } from "./routes/dictation";
import { registerErrorHandler } from "./lib/errorHandler";
import { AuthConfig, SESSION_COOKIE_NAME, loadAuthConfig } from "./lib/authConfig";
import { createAuthGuard } from "./lib/authGuard";
import { UserStore, prismaUserStore } from "./lib/users";
import { loadLlmConfig, streamTimeoutFor } from "./lib/llmConfig";
import { CompleteJson, createOpenAiCompatibleClient } from "./lib/llmClient";
import { recordAttempt, rosterForParsing } from "./domain/modelRosterStore";
import type { RosterEntry } from "./domain/modelRoster";
import { dictationModelRoutes } from "./routes/dictationModels";
import { createDictationParser } from "./domain/dictation";
import { createTidyParsers } from "./domain/tidy";
import { resolveDictationModel } from "./domain/dictationModel";
import { DictationFeature } from "./routes/dictation";

export interface BuildAppOptions {
  /**
   * Auth configuration. Injectable so tests can supply a known secret and password
   * hash without touching the real `.env`; defaults to reading the environment.
   */
  authConfig?: AuthConfig;
  /**
   * Where users are looked up. Injectable so route tests need no database;
   * defaults to the `users` table.
   */
  users?: UserStore;
  /** Enable request logging. Defaults to true; tests turn it off for quiet output. */
  logger?: boolean;
  /**
   * Dictation parsing (F14). Injectable so tests never call a real model;
   * defaults to what `LLM_*` in the environment describes, or `null` --
   * feature off -- when nothing does.
   */
  dictation?: DictationFeature | null;
  /** AI requests one user may make per UTC day. Defaults to `AI_DAILY_LIMIT`, else 50. */
  aiDailyLimit?: number;
  /** Heartbeat of a streamed dictation parse. Tests shorten it; 5 s otherwise. */
  dictationHeartbeatMs?: number;
}

function defaultDictation(): DictationFeature | null {
  const config = loadLlmConfig();
  if (config === null) return null;
  const complete = createOpenAiCompatibleClient(config);
  const resolveModel = () => resolveDictationModel(config.model);
  /*
   * One client per provider and key (`../domain/modelRoster.ts`): an entry
   * with no URL or key of its own uses `.env`'s. Keys are read from the
   * environment by the name the entry gives, never stored anywhere else.
   */
  const clients = new Map<string, CompleteJson>();
  const clientFor = (entry: RosterEntry): CompleteJson => {
    const baseUrl = entry.baseUrl ?? config.baseUrl;
    const key = `${baseUrl}\n${entry.apiKeyEnv ?? ""}`;
    let client = clients.get(key);
    if (client === undefined) {
      const apiKey =
        entry.apiKeyEnv === null ? config.apiKey : (process.env[entry.apiKeyEnv] ?? "");
      client = createOpenAiCompatibleClient({ ...config, baseUrl, apiKey });
      clients.set(key, client);
    }
    return client;
  };
  return {
    defaultModel: config.model,
    defaultBaseUrl: config.baseUrl,
    parser: createDictationParser(complete, resolveModel),
    tidiers: createTidyParsers(complete, resolveModel),
    streamTimeoutMs: (textLength) => streamTimeoutFor(config, textLength),
    roster: {
      read: () => rosterForParsing(config.model),
      record: (entry, ok) => recordAttempt(entry, ok),
      clientFor,
    },
  };
}

/** Builds the Fastify app, wired with auth. */
export async function buildApp(options: BuildAppOptions = {}): Promise<FastifyInstance> {
  const authConfig = options.authConfig ?? loadAuthConfig();
  const users = options.users ?? prismaUserStore;
  const dictation = options.dictation !== undefined ? options.dictation : defaultDictation();

  const app = Fastify({
    logger: options.logger ?? true,
  });

  registerErrorHandler(app);

  /*
   * Registration order here is load-bearing.
   *
   * @fastify/cookie installs the onRequest hook that populates `request.cookies`,
   * and @fastify/jwt reads the session token from there. `addHook` takes effect
   * immediately while `register` is deferred until boot, so calling addHook right
   * after a non-awaited register would put the auth guard EARLIER in the onRequest
   * chain than the cookie parser -- the guard would then see no cookies and reject
   * every request. Awaiting each register boots it now, guaranteeing both plugins
   * are in place before the guard is appended to the chain.
   */
  await app.register(fastifyCookie);
  await app.register(fastifyJwt, {
    secret: authConfig.jwtSecret,
    cookie: {
      cookieName: SESSION_COOKIE_NAME,
      // The cookie carries a JWT, which is already signed and verified by
      // @fastify/jwt; there is no separate @fastify/cookie signature to check.
      signed: false,
    },
  });

  // Global guard. Registered before the routes so it applies to all of them
  // (including the not-found handler), with PUBLIC_ROUTES as the only exceptions.
  app.addHook("onRequest", createAuthGuard(users));

  await app.register(healthRoutes);
  await app.register(authRoutes(authConfig, users));
  await app.register(scopeRoutes);
  await app.register(projectRoutes);
  await app.register(taskRoutes);
  await app.register(noteRoutes);
  await app.register(categoryRoutes);
  await app.register(inboxRoutes);
  await app.register(focusRoutes);
  await app.register(historyRoutes);
  await app.register(boardRoutes);
  await app.register(dictationRoutes(dictation, {
      heartbeatMs: options.dictationHeartbeatMs,
      dailyLimit: options.aiDailyLimit,
    }));
  await app.register(
    dictationModelRoutes(
      dictation === null
        ? null
        : { defaultModel: dictation.defaultModel, defaultBaseUrl: dictation.defaultBaseUrl ?? "" },
    ),
  );

  return app;
}
