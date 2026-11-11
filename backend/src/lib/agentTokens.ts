import { createHash, randomBytes } from "node:crypto";
import { prisma } from "./prisma";
import type { UserStore } from "./users";

/**
 * Personal API tokens for coding agents (the MCP endpoint, `POST /mcp`).
 *
 * A token is `trk_` and 43 base64url characters of randomness (256 bits). Only
 * its SHA-256 is stored -- see `AgentToken` in prisma/schema.prisma for why a
 * fast hash is the right one here -- so a database dump hands nobody a working
 * token.
 *
 * THE SCOPE IS MCP ONLY. Nothing in the session guard (./authGuard.ts) reads
 * these tokens: sent to `/board` one is simply a JWT that does not verify, and
 * the answer is the same 401 as for any garbage. That is deliberate. A token
 * pasted into an agent's config lives in a dotfile on a laptop, and what it
 * can reach should be the few non-destructive things the MCP tools expose,
 * not the whole API with its deletes.
 */

/** Marks a string as one of these tokens, so it is recognisable in a config. */
export const AGENT_TOKEN_PREFIX = "trk_";

/** How many leading characters of a token the list shows. */
const DISPLAY_PREFIX_LENGTH = AGENT_TOKEN_PREFIX.length + 6;

/** `lastUsedAt` is refreshed no more often than this, to keep reads read-only. */
const LAST_USED_RESOLUTION_MS = 60_000;

/** Hex SHA-256 of a token: what is stored and looked up. */
export function hashAgentToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

/** A new random token, its hash and the prefix shown in the list. */
export function generateAgentToken(): { token: string; tokenHash: string; prefix: string } {
  const token = AGENT_TOKEN_PREFIX + randomBytes(32).toString("base64url");
  return { token, tokenHash: hashAgentToken(token), prefix: token.slice(0, DISPLAY_PREFIX_LENGTH) };
}

/**
 * The token in an `Authorization: Bearer <token>` header, or null when the
 * header is missing, is another scheme, or does not carry one of these tokens.
 * The shape check is cheap and keeps a JWT (or anything else) from costing a
 * database lookup.
 */
export function bearerAgentToken(header: string | undefined): string | null {
  if (header === undefined) return null;
  const token = /^Bearer\s+(\S+)\s*$/i.exec(header)?.[1];
  if (token === undefined || !token.startsWith(AGENT_TOKEN_PREFIX) || token.length > 200)
    return null;
  return token;
}

/**
 * The user a token acts for, or null. Null for an unknown token, a revoked
 * one, and one whose user is disabled -- all the same to the caller, which
 * answers one opaque 401 for every case.
 *
 * Marks the token used when the last mark is older than a minute.
 */
export async function authenticateAgentToken(
  token: string,
  users: UserStore,
  now: Date = new Date(),
): Promise<string | null> {
  const row = await prisma.agentToken.findUnique({
    where: { tokenHash: hashAgentToken(token) },
    select: { id: true, userId: true, revokedAt: true, lastUsedAt: true },
  });
  if (row === null || row.revokedAt !== null) return null;
  if (!(await users.isActive(row.userId))) return null;

  if (
    row.lastUsedAt === null ||
    now.getTime() - row.lastUsedAt.getTime() > LAST_USED_RESOLUTION_MS
  ) {
    await prisma.agentToken.update({ where: { id: row.id }, data: { lastUsedAt: now } });
  }
  return row.userId;
}
