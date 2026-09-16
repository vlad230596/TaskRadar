import { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma";

/**
 * Build metadata, read from the environment rather than from package.json.
 *
 * The image bakes these in at build time (`ARG APP_VERSION` -> `ENV APP_VERSION`
 * in backend/Dockerfile, fed by the release workflow), which is the only place
 * that knows the release version: package.json's `version` field is not bumped
 * per release and would therefore report a stale number forever.
 *
 * The fallbacks are the same strings the deploy stack uses for "not a release
 * build" (`${APP_VERSION:-dev}` / `${BUILD_DATE:-unknown}` in compose.prod.yaml),
 * so a developer running `npm run dev` gets `{"version":"dev"}` instead of a
 * crash or an empty string. They match CashFlow's `/version` for the same reason.
 */
const DEV_VERSION = "dev";
const UNKNOWN_BUILD_DATE = "unknown";

export async function healthRoutes(app: FastifyInstance): Promise<void> {
  /*
   * Liveness. Deliberately static and deliberately NOT touching the database.
   *
   * The question this answers is "is this process alive and serving HTTP", and
   * that has to stay answerable while PostgreSQL is down -- otherwise a database
   * outage becomes indistinguishable from a crashed process, and any supervisor
   * wired to it would start killing a perfectly healthy container in the middle
   * of an outage it cannot fix by restarting.
   *
   * The body is `{"status":"ok"}` and must stay that exact string: the deploy
   * script greps for it (`scripts/deploy-production.sh`) and integration CI
   * asserts it.
   */
  app.get("/health", async () => {
    return { status: "ok" };
  });

  /*
   * Readiness. The question this answers is a different one: "can this process
   * actually serve a request right now", which for this app means "is the
   * database reachable". Every route except these three hits PostgreSQL, so a
   * backend that cannot reach it serves nothing but 500s while looking perfectly
   * healthy to a liveness probe. That is exactly the state compose.prod.yaml's
   * healthcheck used to call healthy.
   *
   * `SELECT 1` and nothing more: it touches no table, so it keeps working before
   * the first migration and cannot be slowed down by data volume, while still
   * proving the whole chain (DNS, TCP, credentials, database exists, connection
   * pool has capacity).
   */
  app.get("/ready", async (request, reply) => {
    try {
      await prisma.$queryRaw`SELECT 1`;
    } catch (error) {
      /*
       * The error is logged here and answered here rather than rethrown, and
       * that is the whole point of the try/catch.
       *
       * A driver error from Prisma carries the connection string -- host, port,
       * database name and, depending on the failure, the user -- in its message.
       * The central error handler would redact it (its 5xx branch sends a fixed
       * body precisely because "a server-side message may well carry a
       * connection string"), but 503 is not a status any route raises today, and
       * relying on a blanket redaction for a route whose entire job is to report
       * database failure is the kind of coupling that breaks quietly later.
       * Answering locally makes the redaction visible at the place that needs it.
       *
       * No explicit timeout is wired up: both ways this can hang are already
       * bounded by Prisma itself -- an unreachable server fails on the driver's
       * connect timeout, an exhausted pool fails on `pool_timeout` -- and the
       * callers bound it again from the outside (`timeout: 3s` on the Docker
       * healthcheck, `--max-time` on curl in the deploy script).
       */
      request.log.error({ err: error }, "readiness probe failed");
      reply.status(503).send({
        error: "ServiceUnavailable",
        message: "Database unavailable",
      });
      return reply;
    }

    return { status: "ready" };
  });

  /*
   * What is actually running. Public on purpose: the deploy script and any
   * future uptime check must be able to ask without credentials, the same way
   * CashFlow's `/version` is public.
   *
   * Nothing here is derived from the request or from disk. Only these two
   * values are exposed -- no NODE_ENV, no paths, no dependency or runtime
   * versions, no git SHA -- because everything else either narrows down which
   * known CVEs to try or describes the inside of the container. The release
   * version alone is already a hint to an attacker; it is published in the git
   * tag and the GHCR package anyway, and being unable to tell over the network
   * which release is live is the worse trade.
   *
   * Read per request rather than captured at module load so tests can vary the
   * environment without re-importing the module. The cost is two property reads.
   *
   * `buildDate` is camelCase, unlike CashFlow's `build_date`: every JSON field
   * this API emits is camelCase (`archivedAt`, `remindAt`, `isCurrent`), and a
   * lone snake_case key would be the one field a generated client has to special
   * case.
   */
  app.get("/version", async () => {
    return {
      version: process.env.APP_VERSION || DEV_VERSION,
      buildDate: process.env.BUILD_DATE || UNKNOWN_BUILD_DATE,
    };
  });
}
