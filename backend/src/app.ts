import Fastify, { FastifyInstance } from "fastify";
import fastifyCookie from "@fastify/cookie";
import fastifyJwt from "@fastify/jwt";
import { healthRoutes } from "./routes/health";
import { authRoutes } from "./routes/auth";
import { scopeRoutes } from "./routes/scopes";
import { projectRoutes } from "./routes/projects";
import { taskRoutes } from "./routes/tasks";
import { noteRoutes } from "./routes/notes";
import { inboxRoutes } from "./routes/inbox";
import { focusRoutes } from "./routes/focus";
import { historyRoutes } from "./routes/history";
import { boardRoutes } from "./routes/board";
import { dictationRoutes } from "./routes/dictation";
import { registerErrorHandler } from "./lib/errorHandler";
import { AuthConfig, SESSION_COOKIE_NAME, loadAuthConfig } from "./lib/authConfig";
import { createAuthGuard } from "./lib/authGuard";
import { loadLlmConfig } from "./lib/llmConfig";
import { createOpenAiCompatibleClient } from "./lib/llmClient";
import { createDictationParser } from "./domain/dictation";
import { resolveDictationModel } from "./domain/dictationModel";
import { DictationFeature } from "./routes/dictation";

export interface BuildAppOptions {
  /**
   * Auth configuration. Injectable so tests can supply a known secret and password
   * hash without touching the real `.env`; defaults to reading the environment.
   */
  authConfig?: AuthConfig;
  /** Enable request logging. Defaults to true; tests turn it off for quiet output. */
  logger?: boolean;
  /**
   * Dictation parsing (F14). Injectable so tests never call a real model;
   * defaults to what `LLM_*` in the environment describes, or `null` --
   * feature off -- when nothing does.
   */
  dictation?: DictationFeature | null;
}

function defaultDictation(): DictationFeature | null {
  const config = loadLlmConfig();
  if (config === null) return null;
  return {
    defaultModel: config.model,
    parser: createDictationParser(createOpenAiCompatibleClient(config), () =>
      resolveDictationModel(config.model),
    ),
  };
}

/** Builds the Fastify app, wired with auth. */
export async function buildApp(options: BuildAppOptions = {}): Promise<FastifyInstance> {
  const authConfig = options.authConfig ?? loadAuthConfig();
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
  app.addHook("onRequest", createAuthGuard());

  await app.register(healthRoutes);
  await app.register(authRoutes(authConfig));
  await app.register(scopeRoutes);
  await app.register(projectRoutes);
  await app.register(taskRoutes);
  await app.register(noteRoutes);
  await app.register(inboxRoutes);
  await app.register(focusRoutes);
  await app.register(historyRoutes);
  await app.register(boardRoutes);
  await app.register(dictationRoutes(dictation));

  return app;
}
