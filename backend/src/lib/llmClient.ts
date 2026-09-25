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
 */
export type CompleteJson = (messages: ChatMessage[]) => Promise<string>;

/**
 * The model did not produce an answer we can use: unreachable, timed out, an
 * error status, or a reply that is not the JSON we asked for.
 *
 * 502 rather than 500 because it is not this server that broke, and the
 * distinction is what lets the client fall back quietly instead of reporting an
 * outage. The message never carries the upstream body -- a provider's error
 * text can echo the request, and the request carries the API key's owner.
 */
export class UpstreamModelError extends HttpError {
  constructor(public readonly reason: string) {
    super(502, "Dictation model did not answer");
  }
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
  return async (messages) => {
    let response: Response;
    try {
      response = await fetchImpl(`${config.baseUrl}/chat/completions`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          ...(config.apiKey === "" ? {} : { authorization: `Bearer ${config.apiKey}` }),
        },
        body: JSON.stringify({
          model: config.model,
          messages,
          temperature: 0.1,
          response_format: { type: "json_object" },
        }),
        signal: AbortSignal.timeout(config.timeoutMs),
      });
    } catch (error) {
      throw new UpstreamModelError(`request failed: ${(error as Error).message}`);
    }

    if (!response.ok) {
      throw new UpstreamModelError(`status ${response.status}`);
    }

    let body: unknown;
    try {
      body = await response.json();
    } catch {
      throw new UpstreamModelError("reply is not JSON");
    }

    const content = (body as { choices?: { message?: { content?: unknown } }[] }).choices?.[0]
      ?.message?.content;
    if (typeof content !== "string" || content.trim() === "") {
      throw new UpstreamModelError("reply has no message content");
    }
    return content;
  };
}
