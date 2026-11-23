import { Prisma } from "@prisma/client";

/*
 * Contours (design/goals-ideas-contract.md): sets of goal slots that are in
 * force at different times -- "Работа", "Личное".
 *
 * The one invariant the server keeps is that a user always has at least one.
 * Three places make it true -- the migration that introduced contours gave
 * every user «Основной», creating a user creates one (`DEFAULT_CONTOUR`
 * below, used by src/scripts/user.ts and `ensureOwner`), and
 * `DELETE /contours/:id` refuses the last -- and `defaultContour` is the
 * backstop for a database that somehow lost it anyway: it makes one rather
 * than answer "no contour" to a phone that only wanted to take a task into
 * work.
 */

/** What a new user starts with, and what the migration gave everyone. */
export const DEFAULT_CONTOUR = {
  name: "Основной",
  slots: 2,
  windowDays: 7,
  position: 1000,
} as const;

/** Anything that can run Prisma queries: the client or a transaction. */
type Db = Pick<Prisma.TransactionClient, "contour">;

/**
 * The user's default contour -- the first by position -- creating «Основной»
 * when there is none. The default is where a task taken into work without
 * naming a contour goes, and where `create_goal` puts a goal an agent did not
 * place.
 */
export async function defaultContour(db: Db, userId: string) {
  const first = await db.contour.findFirst({ where: { userId }, orderBy: { position: "asc" } });
  if (first !== null) return first;
  return db.contour.create({ data: { userId, ...DEFAULT_CONTOUR } });
}

/** One of [userId]'s contours, or null -- the same for someone else's and for none. */
export function ownedContour(db: Db, userId: string, contourId: string) {
  return db.contour.findFirst({ where: { id: contourId, userId } });
}
