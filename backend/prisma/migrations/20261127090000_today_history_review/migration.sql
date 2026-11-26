-- «Сегодня», История, пересмотр и ритм (design/today-history-contract.md).
--
-- Additive and safe against a live database: columns with defaults or NULL,
-- one enum value, one new table, CHECK constraints every existing row already
-- satisfies (the new columns hold their defaults or NULL), and two backfills
-- that write only "tasks"."doneAt" and "task_events"."revokedAt", both new.
-- Take a backup first anyway (BACKUPS.md).
--
-- Task dates ("remindAt" / "remindTime") are deliberately NOT touched: past
-- ones land in «С прошлых дней» on the first day (the owner's decision), and
-- the times of future ones stay.

-- AlterEnum. Not used anywhere below, which is what lets Postgres add it
-- inside the migration's transaction.
ALTER TYPE "TaskEventKind" ADD VALUE 'reopened';

-- AlterTable
ALTER TABLE "users" ADD COLUMN     "laterHorizonDays" INTEGER NOT NULL DEFAULT 10,
ADD COLUMN     "reviewTime" TEXT NOT NULL DEFAULT '09:00',
ADD COLUMN     "reviewWeekday" INTEGER NOT NULL DEFAULT 1;

-- AlterTable
ALTER TABLE "projects" ADD COLUMN     "rhythmClosedPerWeek" INTEGER,
ADD COLUMN     "rhythmMaxOpen" INTEGER;

-- AlterTable
ALTER TABLE "tasks" ADD COLUMN     "doneAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "task_events" ADD COLUMN     "contourId" TEXT,
ADD COLUMN     "revokedAt" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "reviews" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "periodStart" TIMESTAMP(3) NOT NULL,
    "periodEnd" TIMESTAMP(3) NOT NULL,
    "monthly" BOOLEAN NOT NULL DEFAULT false,
    "closedCount" INTEGER NOT NULL,
    "byProject" JSONB NOT NULL,
    "achievedGoals" JSONB NOT NULL,
    "summary" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "reviews_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "reviews_userId_periodEnd_idx" ON "reviews"("userId", "periodEnd");

-- CreateIndex
CREATE INDEX "tasks_doneAt_idx" ON "tasks"("doneAt");

-- AddForeignKey
ALTER TABLE "reviews" ADD CONSTRAINT "reviews_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "task_events" ADD CONSTRAINT "task_events_contourId_fkey" FOREIGN KEY ("contourId") REFERENCES "contours"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- The bounds the API enforces (src/schemas.ts), held by the database too.
-- Not in schema.prisma: Prisma has no syntax for CHECK, and `migrate diff`
-- ignores them (same as contours_slots_range in 20261124090000).
ALTER TABLE "users" ADD CONSTRAINT "users_later_horizon_range" CHECK ("laterHorizonDays" BETWEEN 1 AND 90);
ALTER TABLE "users" ADD CONSTRAINT "users_review_weekday_range" CHECK ("reviewWeekday" BETWEEN 1 AND 7);
ALTER TABLE "users" ADD CONSTRAINT "users_review_time_format" CHECK ("reviewTime" ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$');
ALTER TABLE "projects" ADD CONSTRAINT "projects_rhythm_closed_range" CHECK ("rhythmClosedPerWeek" IS NULL OR "rhythmClosedPerWeek" BETWEEN 1 AND 50);
ALTER TABLE "projects" ADD CONSTRAINT "projects_rhythm_open_range" CHECK ("rhythmMaxOpen" IS NULL OR "rhythmMaxOpen" BETWEEN 1 AND 500);
ALTER TABLE "reviews" ADD CONSTRAINT "reviews_summary_length" CHECK ("summary" IS NULL OR char_length("summary") <= 300);

-- Backfill 1: «закрыл и передумал — это не закрытие», applied to the journal
-- as it stands. Every `status -> done` row that a later `status` row took back
-- out of done (until now a plain PATCH did that silently) is revoked at the
-- moment it was taken out -- by the FIRST such row after it, so a task closed,
-- reopened, closed and reopened again revokes each closing by its own exit.
-- A closing nothing followed (the task is still done) stays.
UPDATE "task_events" AS e
SET "revokedAt" = (
  SELECT MIN(x."at") FROM "task_events" AS x
  WHERE x."taskId" = e."taskId"
    AND x."kind" = 'status'
    AND x."fromStatus" = 'done'
    AND x."at" > e."at"
)
WHERE e."kind" = 'status'
  AND e."toStatus" = 'done'
  AND EXISTS (
    SELECT 1 FROM "task_events" AS x
    WHERE x."taskId" = e."taskId"
      AND x."kind" = 'status'
      AND x."fromStatus" = 'done'
      AND x."at" > e."at"
  );

-- Backfill 2: "doneAt" of every task that is done now -- the moment of its
-- last closing that still counts, or "updatedAt" when the journal has none
-- (a task created as done).
UPDATE "tasks" AS t
SET "doneAt" = COALESCE(
  (
    SELECT MAX(e."at") FROM "task_events" AS e
    WHERE e."taskId" = t."id"
      AND e."kind" = 'status'
      AND e."toStatus" = 'done'
      AND e."revokedAt" IS NULL
  ),
  t."updatedAt"
)
WHERE t."status" = 'done';
