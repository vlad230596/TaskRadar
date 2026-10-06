import { HttpError } from "./errors";
import { LlmConfig } from "./llmConfig";

export interface ChatMessage {
  role: "system" | "user" | "assistant";
  content: string;
}

/**
 * One chat turn that must come back as a JSON object. Returns the raw text of
 * the reply; turning it into something typed is the caller's job, because only
 * the caller knows what shape it asked for.
 *
 * [model] is per call rather than fixed at construction: the app can switch
 * models (F14), and a client built once at boot must follow without a restart.
 */
export type CompleteJson = (
  messages: ChatMessage[],
  model: string,
  options?: CompleteOptions,
) => Promise<string>;

export interface CompleteOptions {
  /** Overrides the configured `LLM_TIMEOUT_MS` for this one call. */
  timeoutMs?: number | undefined;
  /** Aborts the call early -- the person waiting for it has gone. */
  signal?: AbortSignal | undefined;
}

/**
 * Why the model gave no answer, in words a client may be shown. The provider's
 * own text stays in [UpstreamModelError.reason]; this is the class it falls
 * into, which is what decides what the user can do about it -- pick another
 * model, top up the account, wait a minute, or just try again.
 */
export type UpstreamCause =
  /** The provider does not know the model: retired, renamed, a typo. */
  | "model_not_found"
  /** The key was refused. */
  | "unauthorized"
  /** The account behind the key has run out of money. */
  | "no_credits"
  /** Too many requests to the provider, or to the model. */
  | "rate_limited"
  /** The provider itself is failing (5xx). */
  | "provider_down"
  /** The provider refused the request for some other reason (another 4xx). */
  | "rejected"
  /** No answer within the budget. */
  | "timeout"
  /** The provider could not be reached at all. */
  | "unreachable"
  /** An answer came, but not one we can use. */
  | "bad_reply"
  /** The person waiting for the answer went away. */
  | "cancelled";

/**
 * The model did not produce an answer we can use: unreachable, timed out, an
 * error status, or a reply that is not the JSON we asked for.
 *
 * 502 rather than 500 because it is not this server that broke, and the
 * distinction is what lets the client fall back quietly instead of reporting an
 * outage.
 *
 * Two descriptions of one failure, for two readers. [reason] is for the log
 * and the dataset, and may quote the provider's error -- its code and the
 * start of its message, which is what tells a retired model from an empty
 * account. [category] is for the client, and is only ever one of
 * [UpstreamCause]: the provider's text never leaves this server, since it can
 * echo the request, and the request carries the API key's owner.
 */
export class UpstreamModelError extends HttpError {
  constructor(
    public readonly reason: string,
    public readonly category: UpstreamCause = "bad_reply",
    /** The model that was asked, when known -- for "pick another model". */
    public readonly model?: string,
  ) {
    super(502, "Dictation model did not answer", {
      cause: category,
      ...(model === undefined ? {} : { model }),
    });
  }
}

/** The class of an error [status] from the provider, given its [detail]. */
export function causeOfStatus(status: number, detail: string): UpstreamCause {
  if (status === 404) return "model_not_found";
  // DeepSeek answers an unknown model with a 400 "Model Not Exist".
  if (status === 400 && /model/i.test(detail) && /not.?exist|not.?found|invalid|unknown/i.test(detail)) {
    return "model_not_found";
  }
  if (status === 401 || status === 403) return "unauthorized";
  if (status === 402) return "no_credits";
  if (status === 429) return "rate_limited";
  if (status === 408 || status === 504) return "timeout";
  if (status >= 500) return "provider_down";
  return "rejected";
}

/** How much of the provider's error message the log keeps. */
const DETAIL_LIMIT = 200;

/**
 * The provider's error body, as one short line for the log: the OpenAI shape
 * `{error: {code, type, message}}` that DeepSeek and OpenRouter both answer
 * with, or the start of the body as text when it is anything else. Empty when
 * there is no body.
 */
export function describeErrorBody(text: string): string {
  let parts: string[];
  try {
    const error = (JSON.parse(text) as { error?: unknown }).error;
    if (typeof error === "object" && error !== null) {
      const { code, type, message } = error as Record<string, unknown>;
      parts = [
        code !== undefined && code !== null ? `code ${String(code)}` : "",
        typeof type === "string" ? `type ${type}` : "",
        typeof message === "string" ? message : "",
      ];
    } else {
      parts = [typeof error === "string" ? error : text];
    }
  } catch {
    parts = [text];
  }
  const line = parts
    .filter((part) => part !== "")
    .join(": ")
    .replace(/\s+/g, " ")
    .trim();
  return line.length > DETAIL_LIMIT ? `${line.slice(0, DETAIL_LIMIT)}…` : line;
}

/**
 * `POST {baseUrl}/chat/completions` with `response_format: json_object`.
 *
 * The one request shape every provider on the list speaks (DeepSeek, OpenRouter,
 * Qwen, Ollama, llama.cpp), which is the whole reason for choosing it over any
 * provider's own SDK: switching between them is `.env`, not code.
 *
 * Temperature is low on purpose. The task is rewriting, not writing -- the same
 * dictation should come back as the same title every time, and a model allowed
 * to be creative starts adding words the user never said.
 */
export function createOpenAiCompatibleClient(
  config: LlmConfig,
  fetchImpl: typeof fetch = fetch,
): CompleteJson {
  return async (messages, model, options = {}) => {
    const timeout = AbortSignal.timeout(options.timeoutMs ?? config.timeoutMs);
    const signal = options.signal ? AbortSignal.any([timeout, options.signal]) : timeout;
    let response: Response;
    try {
      response = await fetchImpl(`${config.baseUrl}/chat/completions`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          ...(config.apiKey === "" ? {} : { authorization: `Bearer ${config.apiKey}` }),
        },
        body: JSON.stringify({
          model,
          messages,
          temperature: 0.1,
          response_format: { type: "json_object" },
        }),
        signal,
      });
    } catch (error) {
      if (options.signal?.aborted) {
        throw new UpstreamModelError("cancelled by the client", "cancelled");
      }
      const timedOut = timeout.aborted;
      throw new UpstreamModelError(
        `request failed: ${(error as Error).message}`,
        timedOut ? "timeout" : "unreachable",
      );
    }

    if (!response.ok) {
      const detail = describeErrorBody(await response.text().catch(() => ""));
      throw new UpstreamModelError(
        detail === "" ? `status ${response.status}` : `status ${response.status} (${detail})`,
        causeOfStatus(response.status, detail),
      );
    }

    let body: unknown;
    try {
      body = await response.json();
    } catch (error) {
      // The budget covers the body too: a slow model sends its headers at once
      // and the answer only when it is done, so running out lands here.
      if (options.signal?.aborted) {
        throw new UpstreamModelError("cancelled by the client", "cancelled");
      }
      if (timeout.aborted) {
        throw new UpstreamModelError(`reply cut off: ${(error as Error).message}`, "timeout");
      }
      throw new UpstreamModelError("reply is not JSON", "bad_reply");
    }

    const content = (body as { choices?: { message?: { content?: unknown } }[] }).choices?.[0]
      ?.message?.content;
    if (typeof content !== "string" || content.trim() === "") {
      throw new UpstreamModelError("reply has no message content", "bad_reply");
    }
    return content;
  };
}
