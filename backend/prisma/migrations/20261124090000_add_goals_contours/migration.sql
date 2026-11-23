-- Goals, contours and ideas (design/goals-ideas-contract.md).
--
-- Additive and safe against a live database: two nullable columns on "users",
-- one on "tasks", four new tables, CHECK constraints that hold only for rows
-- of the new tables, and a backfill that runs inside the transaction Prisma
-- wraps around a migration. Take a backup first anyway (BACKUPS.md).
--
-- What the backfill does, and why:
--
-- * every existing user gets the contour «Основной» (2 slots, a 7-day window,
--   no schedule). The app assumes a user always has at least one contour --
--   it is where a task taken into work without naming a contour goes -- and
--   new users get theirs when they are created (src/domain/contours.ts);
-- * every task already in the working set (`focusedAt` set) is put into its
--   owner's «Основной», because each contour now has a working set of its own
--   and a task in no contour's set would vanish from the work screen.
--
-- The contour's id is derived from the user's ('contour_' || id) rather than
-- generated: it is unique because the user id is, it needs no extension, and
-- the task backfill can name it without a join back to "contours".

-- AlterTable
ALTER TABLE "users" ADD COLUMN     "activeContourId" TEXT,
ADD COLUMN     "activeContourUntil" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "tasks" ADD COLUMN     "focusContourId" TEXT;

-- CreateTable
CREATE TABLE "contours" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "slots" INTEGER NOT NULL DEFAULT 2,
    "windowDays" INTEGER NOT NULL DEFAULT 7,
    "schedule" JSONB,
    "position" DOUBLE PRECISION NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "contours_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "goals" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "contourId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "why" TEXT,
    "slottedAt" TIMESTAMP(3),
    "windowDays" INTEGER,
    "windowEndsAt" TIMESTAMP(3),
    "achievedAt" TIMESTAMP(3),
    "position" DOUBLE PRECISION NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "goals_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "goal_tasks" (
    "goalId" TEXT NOT NULL,
    "taskId" TEXT NOT NULL,
    "position" DOUBLE PRECISION NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "goal_tasks_pkey" PRIMARY KEY ("goalId","taskId")
);

-- CreateTable
CREATE TABLE "goal_ideas" (
    "goalId" TEXT NOT NULL,
    "noteId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "goal_ideas_pkey" PRIMARY KEY ("goalId","noteId")
);

-- CreateIndex
CREATE INDEX "contours_userId_position_idx" ON "contours"("userId", "position");

-- CreateIndex
CREATE INDEX "goals_userId_contourId_position_idx" ON "goals"("userId", "contourId", "position");

-- CreateIndex
CREATE INDEX "goals_contourId_idx" ON "goals"("contourId");

-- CreateIndex
CREATE INDEX "goal_tasks_taskId_idx" ON "goal_tasks"("taskId");

-- CreateIndex
CREATE INDEX "goal_ideas_noteId_idx" ON "goal_ideas"("noteId");

-- CreateIndex
CREATE INDEX "tasks_focusContourId_idx" ON "tasks"("focusContourId");

-- AddForeignKey
ALTER TABLE "users" ADD CONSTRAINT "users_activeContourId_fkey" FOREIGN KEY ("activeContourId") REFERENCES "contours"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "contours" ADD CONSTRAINT "contours_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "goals" ADD CONSTRAINT "goals_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "goals" ADD CONSTRAINT "goals_contourId_fkey" FOREIGN KEY ("contourId") REFERENCES "contours"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "goal_tasks" ADD CONSTRAINT "goal_tasks_goalId_fkey" FOREIGN KEY ("goalId") REFERENCES "goals"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "goal_tasks" ADD CONSTRAINT "goal_tasks_taskId_fkey" FOREIGN KEY ("taskId") REFERENCES "tasks"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "goal_ideas" ADD CONSTRAINT "goal_ideas_goalId_fkey" FOREIGN KEY ("goalId") REFERENCES "goals"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "goal_ideas" ADD CONSTRAINT "goal_ideas_noteId_fkey" FOREIGN KEY ("noteId") REFERENCES "notes"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tasks" ADD CONSTRAINT "tasks_focusContourId_fkey" FOREIGN KEY ("focusContourId") REFERENCES "contours"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- The bounds the API enforces (src/schemas.ts), held by the database too, so a
-- row written by hand cannot become a contour with no slots or a window of a
-- year. Not in schema.prisma: Prisma has no syntax for CHECK, and
-- `migrate diff` ignores them (same as tasks_location_* in 20261111100000).
ALTER TABLE "contours" ADD CONSTRAINT "contours_slots_range" CHECK ("slots" BETWEEN 1 AND 5);
ALTER TABLE "contours" ADD CONSTRAINT "contours_window_range" CHECK ("windowDays" BETWEEN 1 AND 90);
ALTER TABLE "goals" ADD CONSTRAINT "goals_window_range" CHECK ("windowDays" IS NULL OR "windowDays" BETWEEN 1 AND 90);

-- Backfill: one contour per existing user...
INSERT INTO "contours" ("id", "userId", "name", "slots", "windowDays", "position", "createdAt", "updatedAt")
SELECT 'contour_' || "id", "id", 'Основной', 2, 7, 1000, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM "users";

-- ...and the working set as it stands goes into it. A task's owner is the
-- owner of its project's scope.
UPDATE "tasks" AS t
SET "focusContourId" = 'contour_' || s."userId"
FROM "projects" AS p
JOIN "scopes" AS s ON s."id" = p."scopeId"
WHERE p."id" = t."projectId" AND t."focusedAt" IS NOT NULL;
