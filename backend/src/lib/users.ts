import type { FastifyRequest } from "fastify";
import { prisma } from "./prisma";
import { AuthConfig, OWNER_SUBJECT } from "./authConfig";
import { normaliseEmail } from "./credentials";

/** What login and the guard need to know about a user. */
export interface UserRecord {
  id: string;
  name: string;
  passwordHash: string;
  disabledAt: Date | null;
}

/**
 * Where users are looked up. An interface so route tests can supply people
 * without a database; production uses {@link prismaUserStore}.
 */
export interface UserStore {
  findByEmail(email: string): Promise<UserRecord | null>;
  /** True while the user exists and is not disabled. Asked on every request. */
  isActive(id: string): Promise<boolean>;
}

export const prismaUserStore: UserStore = {
  async findByEmail(email) {
    return prisma.user.findUnique({
      where: { email: normaliseEmail(email) },
      select: { id: true, name: true, passwordHash: true, disabledAt: true },
    });
  },
  async isActive(id) {
    const user = await prisma.user.findUnique({
      where: { id },
      select: { disabledAt: true },
    });
    return user !== null && user.disabledAt === null;
  },
};

/** The id of the person a request belongs to. Only valid behind the auth guard. */
export function userIdOf(request: FastifyRequest): string {
  return request.user.sub;
}

/**
 * Writes `AUTH_EMAIL` / `AUTH_PASSWORD_HASH` onto the first user (id `owner`),
 * creating the row when the database predates the migration that seeds it.
 * Called once at startup, so the credentials in `.env` stay the source of truth
 * for that one account.
 */
export async function ensureOwner(config: AuthConfig): Promise<void> {
  await prisma.user.upsert({
    where: { id: OWNER_SUBJECT },
    create: {
      id: OWNER_SUBJECT,
      email: config.email,
      name: "Owner",
      passwordHash: config.passwordHash,
    },
    update: { email: config.email, passwordHash: config.passwordHash },
  });
}
