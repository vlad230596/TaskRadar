import { FastifyInstance, FastifyPluginAsync } from "fastify";
import { verifyCredentials } from "../lib/credentials";
import { AuthConfig, SESSION_COOKIE_NAME, SESSION_TTL_SECONDS } from "../lib/authConfig";
import { UserStore } from "../lib/users";
import { sessionCookieOptions } from "../lib/authGuard";
import { loginSchema } from "../schemas";

/**
 * Login / logout / session probe.
 *
 * Login and logout are public (listed in PUBLIC_ROUTES) -- you obviously cannot
 * require a session in order to create one, and logout stays usable even once a
 * token has expired so a stuck client can always clear its cookie. `GET /auth/me`
 * is deliberately NOT public: answering "is this session alive?" is exactly the
 * job of the guard, so the route only has to exist to be useful.
 */
export function authRoutes(config: AuthConfig, users: UserStore): FastifyPluginAsync {
  return async function register(app: FastifyInstance): Promise<void> {
    app.post("/auth/login", async (request, reply) => {
      const body = loginSchema.parse(request.body);

      const userId = await verifyCredentials(await users.findByEmail(body.email), body.password);
      if (userId === null) {
        // One generic message for "unknown email", "disabled" and "wrong
        // password". `verifyCredentials` always does the bcrypt work, so neither
        // the body nor the response time distinguishes them.
        reply.status(401).send({
          error: "Unauthorized",
          message: "Invalid email or password",
        });
        return;
      }

      // Minimal claims: just whose session this is. `expiresIn` is in seconds
      // for @fastify/jwt (fast-jwt).
      const token = app.jwt.sign({ sub: userId }, { expiresIn: SESSION_TTL_SECONDS });

      /*
       * The token travels two ways at once, on purpose.
       *
       * The httpOnly cookie is still set exactly as before: the browser client
       * never sees the token in JavaScript, which is what keeps an XSS bug from
       * walking off with a 30-day session.
       *
       * The body copy exists for the native (Flutter) client, where a cookie is
       * the wrong container -- it would need a cookie jar bolted onto the HTTP
       * client plus its own persistence on desktop. A native app stores the token
       * itself (Android Keystore via flutter_secure_storage) and sends it as
       * `Authorization: Bearer <token>`; @fastify/jwt already prefers that header
       * over the cookie, so the guard needs no change. Handing the token to a
       * native client is not a new exposure: that client is the only thing that
       * can read the response body anyway.
       *
       * `expiresIn` is echoed in seconds so the client can decide when to re-login
       * without having to parse the JWT payload itself.
       */
      reply
        .setCookie(SESSION_COOKIE_NAME, token, sessionCookieOptions(config))
        .status(200)
        .send({ ok: true, token, expiresIn: SESSION_TTL_SECONDS });
    });

    /*
     * Cheap "is my session still alive?" probe for app startup.
     *
     * The native client needs to choose between the board and the login screen
     * before it has any data, and it should not pay for a full `GET /board` (or
     * `GET /projects`) just to find out. This route does no work at all: by the
     * time the handler runs, the global guard has already verified the token and
     * answered 401 if it did not hold up, so reaching the handler IS the answer.
     *
     * The body stays deliberately empty of identity. The token carries a minimal
     * claim set on purpose -- the client already knows who it logged in as, and
     * echoing the email back would hand an attacker with a stolen token a fact
     * they did not have.
     */
    app.get("/auth/me", async (_request, reply) => {
      reply.status(200).send({ ok: true });
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
