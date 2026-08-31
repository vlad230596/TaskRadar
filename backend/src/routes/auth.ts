import { FastifyInstance, FastifyPluginAsync } from "fastify";
import { verifyCredentials } from "../lib/credentials";
import { AuthConfig, OWNER_SUBJECT, SESSION_COOKIE_NAME, SESSION_TTL_SECONDS } from "../lib/authConfig";
import { sessionCookieOptions } from "../lib/authGuard";
import { loginSchema } from "../schemas";

/**
 * Login / logout for the single TaskRadar user.
 *
 * Both routes are public (listed in PUBLIC_ROUTES) -- you obviously cannot require
 * a session in order to create one, and logout stays usable even once a token has
 * expired so a stuck client can always clear its cookie.
 */
export function authRoutes(config: AuthConfig): FastifyPluginAsync {
  return async function register(app: FastifyInstance): Promise<void> {
    app.post("/auth/login", async (request, reply) => {
      const body = loginSchema.parse(request.body);

      const valid = await verifyCredentials(body.email, body.password, config);
      if (!valid) {
        // One generic message for both "unknown email" and "wrong password".
        // `verifyCredentials` returns a single boolean and always does the bcrypt
        // work, so neither the body nor the response time distinguishes the two.
        reply.status(401).send({
          error: "Unauthorized",
          message: "Invalid email or password",
        });
        return;
      }

      // Minimal claims: one user means the token only has to say "the owner".
      // `expiresIn` is in seconds for @fastify/jwt (fast-jwt).
      const token = app.jwt.sign({ sub: OWNER_SUBJECT }, { expiresIn: SESSION_TTL_SECONDS });

      reply
        .setCookie(SESSION_COOKIE_NAME, token, sessionCookieOptions(config))
        .status(200)
        .send({ ok: true });
    });

    app.post("/auth/logout", async (_request, reply) => {
      // Same attributes as when it was set (notably `path`), otherwise the browser
      // would keep the original cookie alongside the expired one.
      reply
        .clearCookie(SESSION_COOKIE_NAME, sessionCookieOptions(config))
        .status(200)
        .send({ ok: true });
    });
  };
}
