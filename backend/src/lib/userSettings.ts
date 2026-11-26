import { Prisma } from "@prisma/client";
import { DEFAULT_LATER_HORIZON_DAYS } from "../domain/today";

/*
 * The owner's settings kept on the server so every device shares them
 * (design/today-history-contract.md): the «Позже» horizon and when the weekly
 * review falls due. Columns on `User`, with database defaults, so a user who
 * never opened the settings has them too.
 */

export const DEFAULT_REVIEW_WEEKDAY = 1;
export const DEFAULT_REVIEW_TIME = "09:00";

export interface UserSettings {
  laterHorizonDays: number;
  reviewWeekday: number;
  reviewTime: string;
  /** When the user was created: the first review counts from it. */
  createdAt: Date;
}

type Db = Pick<Prisma.TransactionClient, "user">;

/**
 * [userId]'s settings. A row that somehow lacks them (or a user gone between
 * the auth check and this read) gets the defaults rather than an error: these
 * only shape what is shown, and a 500 for a missing horizon would be worse
 * than ten days.
 */
export async function settingsOf(db: Db, userId: string): Promise<UserSettings> {
  const row = await db.user.findUnique({
    where: { id: userId },
    select: { laterHorizonDays: true, reviewWeekday: true, reviewTime: true, createdAt: true },
  });
  return {
    laterHorizonDays: row?.laterHorizonDays ?? DEFAULT_LATER_HORIZON_DAYS,
    reviewWeekday: row?.reviewWeekday ?? DEFAULT_REVIEW_WEEKDAY,
    reviewTime: row?.reviewTime ?? DEFAULT_REVIEW_TIME,
    createdAt: row?.createdAt ?? new Date(0),
  };
}

/** The settings as `GET /settings` answers them. */
export function settingsView(settings: UserSettings) {
  return {
    laterHorizonDays: settings.laterHorizonDays,
    reviewWeekday: settings.reviewWeekday,
    reviewTime: settings.reviewTime,
  };
}
