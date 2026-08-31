/**
 * Shared fetch helper for every page that talks to the TaskRadar API.
 *
 * - Always sends `credentials: "include"` so the httpOnly session cookie
 *   round-trips (required even same-origin-via-proxy, since Vite's dev proxy
 *   still counts as a separate "request" the browser must be told to attach
 *   cookies to).
 * - Talks in relative paths only (e.g. "/projects"), which the Vite dev
 *   server proxies to the backend -- see vite.config.ts. Never build an
 *   absolute http://localhost:3001/... URL here.
 * - Centralizes JSON encode/decode and error handling.
 * - Centralizes the app-wide reaction to an expired/missing session: register
 *   a handler once (see main.tsx) and every future caller gets "redirect to
 *   /login on 401" for free, without each page having to know about routing.
 */

export class ApiError extends Error {
  readonly status: number;
  readonly body: unknown;

  constructor(status: number, message: string, body?: unknown) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.body = body;
  }
}

export class UnauthorizedError extends ApiError {
  constructor(body?: unknown) {
    super(401, "Unauthorized", body);
    this.name = "UnauthorizedError";
  }
}

type UnauthorizedHandler = () => void;

let unauthorizedHandler: UnauthorizedHandler | null = null;

/** Called once at app startup (see main.tsx) to wire up "401 -> go to /login". */
export function setUnauthorizedHandler(handler: UnauthorizedHandler): void {
  unauthorizedHandler = handler;
}

interface ApiRequestOptions {
  method?: "GET" | "POST" | "PATCH" | "DELETE";
  body?: unknown;
  /**
   * Skip the global 401 handler for this call. Use this for the login
   * request itself: a 401 there means "wrong password", an expected and
   * normal outcome the caller displays inline -- not a session that needs
   * clearing / a redirect away from the page the user is already on.
   */
  skipUnauthorizedHandler?: boolean;
}

async function parseJsonSafe(res: Response): Promise<unknown> {
  const text = await res.text();
  if (!text) return undefined;
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

function extractMessage(body: unknown, fallback: string): string {
  if (body && typeof body === "object" && "message" in body && typeof body.message === "string") {
    return body.message;
  }
  return fallback;
}

export async function apiRequest<T>(path: string, options: ApiRequestOptions = {}): Promise<T> {
  const { method = "GET", body, skipUnauthorizedHandler = false } = options;

  const res = await fetch(path, {
    method,
    credentials: "include",
    headers: body !== undefined ? { "Content-Type": "application/json" } : undefined,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });

  if (res.status === 401) {
    const responseBody = await parseJsonSafe(res);
    if (!skipUnauthorizedHandler) {
      unauthorizedHandler?.();
    }
    throw new UnauthorizedError(responseBody);
  }

  if (!res.ok) {
    const responseBody = await parseJsonSafe(res);
    throw new ApiError(res.status, extractMessage(responseBody, res.statusText), responseBody);
  }

  if (res.status === 204) {
    return undefined as T;
  }

  return (await parseJsonSafe(res)) as T;
}

export const api = {
  get: <T,>(path: string): Promise<T> => apiRequest<T>(path),
  post: <T,>(path: string, body?: unknown, options?: Omit<ApiRequestOptions, "method" | "body">): Promise<T> =>
    apiRequest<T>(path, { ...options, method: "POST", body }),
  patch: <T,>(path: string, body?: unknown, options?: Omit<ApiRequestOptions, "method" | "body">): Promise<T> =>
    apiRequest<T>(path, { ...options, method: "PATCH", body }),
  delete: <T,>(path: string, options?: Omit<ApiRequestOptions, "method" | "body">): Promise<T> =>
    apiRequest<T>(path, { ...options, method: "DELETE" }),
};
