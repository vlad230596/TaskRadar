import { z } from "zod";

/**
 * Where the dictation parser's language model lives.
 *
 * Any OpenAI-compatible `/chat/completions` endpoint: DeepSeek, OpenRouter,
 * Alibaba's Qwen, or a local Ollama / llama.cpp server on a desktop GPU. The
 * provider is a line in `.env` rather than a code path, so trying a different
 * model is a restart, not a release.
 *
 * OPTIONAL, UNLIKE AUTH
 *
 * The auth variables are required because an app nobody can log into is not an
 * app. This one is optional because the feature is an improvement, not the
 * path: with no model configured, dictation still works exactly as before -- the
 * recognised words become the task title as spoken -- and `POST
 * /dictation/parse` answers 503 so the client knows to fall back.
 *
 * Half a configuration is a different matter: `LLM_MODEL` with no
 * `LLM_BASE_URL` is a typo, not a choice, and it fails the boot instead of
 * quietly switching the feature off.
 */
export interface LlmConfig {
  /** Base URL up to and including the version segment, e.g. `https://api.deepseek.com/v1`. */
  baseUrl: string;
  /** Bearer token. May be empty for a local server that does not check one. */
  apiKey: string;
  model: string;
  /**
   * How long one parse may take before the client is told to fall back. Kept
   * under the app's 15 s receive timeout (`app/lib/api/api_client.dart`), so
   * the phone hears a 502 from us rather than giving up on its own.
   */
  timeoutMs: number;
}

const llmEnvSchema = z.object({
  LLM_BASE_URL: z
    .string()
    .url("LLM_BASE_URL must be a URL")
    .transform((value) => value.replace(/\/+$/, "")),
  LLM_API_KEY: z.string().default(""),
  LLM_MODEL: z.string().min(1, "LLM_MODEL must not be empty"),
  LLM_TIMEOUT_MS: z.coerce.number().int().positive().default(12_000),
});

/** Returns the model configuration, or `null` when none is set at all. */
export function loadLlmConfig(env: NodeJS.ProcessEnv = process.env): LlmConfig | null {
  const present = ["LLM_BASE_URL", "LLM_API_KEY", "LLM_MODEL"].some(
    (key) => (env[key] ?? "").trim() !== "",
  );
  if (!present) return null;

  const parsed = llmEnvSchema.safeParse(env);
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((issue) => `${issue.path.join(".")}: ${issue.message}`)
      .join("; ");
    throw new Error(`Invalid LLM configuration: ${issues}`);
  }

  return {
    baseUrl: parsed.data.LLM_BASE_URL,
    apiKey: parsed.data.LLM_API_KEY,
    model: parsed.data.LLM_MODEL,
    timeoutMs: parsed.data.LLM_TIMEOUT_MS,
  };
}
