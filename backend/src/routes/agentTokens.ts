import { FastifyInstance } from "fastify";
import { z } from "zod";
import { prisma } from "../lib/prisma";
import { userIdOf } from "../lib/users";
import { NotFoundError, ValidationError } from "../lib/errors";
import { generateAgentToken } from "../lib/agentTokens";
import { idParamSchema } from "../schemas";

/**
 * Personal API tokens for coding agents: create, list, revoke.
 *
 * These routes sit behind the ordinary session guard -- a token is managed
 * from the app by someone who is logged in, never by another token. The token
 * itself only opens `POST /mcp` (see ../lib/agentTokens.ts).
 */

const createAgentTokenSchema = z
  .object({
    name: z.string().trim().max(60, "name is too long").nullable().optional(),
  })
  .optional();

/** More than this many live tokens is a sign of a leak, not of a need. */
const MAX_LIVE_TOKENS = 20;

/** A token as the list shows it: never the token, never its hash. */
const listedFields = {
  id: true,
  name: true,
  prefix: true,
  createdAt: true,
  lastUsedAt: true,
} as const;

export async function agentTokenRoutes(app: FastifyInstance): Promise<void> {
  /** Live tokens, newest first. Revoked ones are gone from here for good. */
  app.get("/agent-tokens", async (request, reply) => {
    const tokens = await prisma.agentToken.findMany({
      where: { userId: userIdOf(request), revokedAt: null },
      orderBy: { createdAt: "desc" },
      select: listedFields,
    });
    reply.send(tokens);
  });

  /**
   * A new token. The answer is the only place the plain token ever appears:
   * it is not stored, and no later request can return it.
   */
  app.post("/agent-tokens", async (request, reply) => {
    const userId = userIdOf(request);
    const body = createAgentTokenSchema.parse(request.body ?? undefined);
    const name = body?.name ? body.name : null;

    const live = await prisma.agentToken.count({ where: { userId, revokedAt: null } });
    if (live >= MAX_LIVE_TOKENS) {
      throw new ValidationError(`At most ${MAX_LIVE_TOKENS} tokens; revoke one first`);
    }

    const { token, tokenHash, prefix } = generateAgentToken();
    const created = await prisma.agentToken.create({
      data: { userId, name, tokenHash, prefix },
      select: listedFields,
    });
    reply.status(201).send({ ...created, token });
  });

  /**
   * Revoke. The row stays (`revokedAt`), the token stops working on the very
   * next request -- the MCP endpoint looks it up every time. Someone else's
   * token and an already revoked one are both a 404.
   */
  app.delete("/agent-tokens/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const result = await prisma.agentToken.updateMany({
      where: { id, userId: userIdOf(request), revokedAt: null },
      data: { revokedAt: new Date() },
    });
    if (result.count === 0) throw new NotFoundError("Token");
    reply.status(204).send();
  });
}
