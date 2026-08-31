import type { onRequestHookHandler } from "fastify";
import type { CookieSerializeOptions } from "@fastify/cookie";
import { AuthConfig, SESSION_TTL_SECONDS } from "./authConfig";

/**
 * Routes reachable without a session cookie, as `"<METHOD> <route pattern>"`.
 *
 * Everything not listed here requires a valid JWT. The allowlist is deliberately
 * exhaustive-by-default: adding a new route protects it automatically, and
 * forgetting to list a genuinely public one fails closed (401) rather than open.
 */
export const PUBLIC_ROUTES: ReadonlySet<string> = new Set([
  "GET /health",
  "POST /auth/login",
  "POST /auth/logout",
]);

/**
 * Decides whether a request targets a public route.
 *
 * Matches on the route *pattern* that Fastify actually resolved
 * (`request.routeOptions.url`), not on the raw request URL. That side-steps every
 * path-normalisation trick -- percent-encoding, traversal segments, query strings --
 * because the comparison happens after routing, against the registered pattern.
 *
 * An unresolved route (`undefined`, i.e. a 404) is treated as NOT public, so an
 * unauthenticated caller gets a flat 401 for unknown paths and cannot enumerate
 * which routes exist.
 */
export function isPublicRoute(method: string, routeUrl: string | undefined): boolean {
  if (routeUrl === undefined) {
    return false;
  }
  return PUBLIC_ROUTES.has(`${method} ${routeUrl}`);
}

/** Options for the session cookie. Shared by login (set) and logout (clear). */
export function sessionCookieOptions(config: AuthConfig): CookieSerializeOptions {
  return {
    // The token must be unreadable to page JavaScript, so an XSS bug cannot
    // exfiltrate a 30-day session.
    httpOnly: true,

    // "lax" still sends the cookie on normal top-level navigation to the app but
    // withholds it from cross-site POSTs, which blocks the basic CSRF shape while
    // keeping a single-user tool pleasant to use.
    sameSite: "lax",

    // Driven entirely by the COOKIE_SECURE env var -- never hardcoded. On plain
    // HTTP (local dev, LAN phone testing) a `Secure` cookie would be accepted and
    // then silently never sent back, breaking auth with no visible error.
    secure: config.cookieSecure,

    // Scoped to the whole app so every route sees it, and so logout's clear
    // targets the same cookie the login set.
    path: "/",

    // Seconds. Matched to the JWT's own expiry so the browser discards the cookie
    // at the same moment the token stops verifying -- no confusing window where a
    // cookie is present but permanently rejected.
    maxAge: SESSION_TTL_SECONDS,
  };
}

/**
 * Global `onRequest` guard: requires a valid session JWT on everything except the
 * routes in {@link PUBLIC_ROUTES}.
 *
 * Failures always produce the same opaque 401 body. The underlying reason
 * (no cookie / malformed / bad signature / expired) is never returned to the
 * caller and no stack trace escapes: the verification error is swallowed here
 * rather than thrown, so it can't reach the central error handler.
 */
export function createAuthGuard(): onRequestHookHandler {
  return async function authGuard(request, reply) {
    if (isPublicRoute(request.method, request.routeOptions.url)) {
      return;
    }

    try {
      // Reads the token from the session cookie (configured on @fastify/jwt) and
      // verifies signature + expiry.
      await request.jwtVerify();
    } catch {
      reply.status(401).send({ error: "Unauthorized", message: "Unauthorized" });
      // Returning the reply halts the lifecycle so the route handler never runs.
      return reply;
    }
  };
}
