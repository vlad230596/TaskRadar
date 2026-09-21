-- The task journal and the working set (F11): the data behind the three modes.
--
-- Two additive changes and one backfill:
--
--   1. `task_events` -- a row per thing that happened to a task, so the history
--      mode can ask "how long did this hang in blocked" and "what did I close
--      last week", which `tasks.updatedAt` cannot answer because it is
--      overwritten in place;
--   2. `tasks.focusedAt` -- nullable, so every existing task is simply not in
--      the working set, which is the correct starting state;
--   3. a `created` event for every task that already exists.
--
-- Written by hand rather than generated, for the backfill. Without it the "life
-- of this task" section is empty for every task in the live database -- eleven
-- of them at the time of writing -- and an empty journal on a task that plainly
-- exists reads as a bug rather than as "this started being recorded today".

-- CreateEnum
CREATE TYPE "TaskEventKind" AS ENUM ('created', 'status', 'focused', 'unfocused');

-- AlterTable
ALTER TABLE "tasks" ADD COLUMN     "focusedAt" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "task_events" (
    "id" TEXT NOT NULL,
    "taskId" TEXT NOT NULL,
    "kind" "TaskEventKind" NOT NULL,
    "fromStatus" "TaskStatus",
    "toStatus" "TaskStatus",
    "at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "task_events_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "task_events_taskId_at_idx" ON "task_events"("taskId", "at");

-- AddForeignKey: CASCADE, because these events are the task's own history and
-- not an audit trail -- see the note on the model in schema.prisma.
ALTER TABLE "task_events" ADD CONSTRAINT "task_events_taskId_fkey" FOREIGN KEY ("taskId") REFERENCES "tasks"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Backfill: one `created` event per existing task, stamped with that task's own
-- `createdAt` rather than with now(). Stamping it now would tell the history
-- screen that every task in the database was born the day this migration ran,
-- which is exactly the number that screen exists to show.
--
-- `toStatus` is the task's CURRENT status, and that deserves a word. The honest
-- position is that nothing before this table existed is knowable: a task that
-- is `blocked` today may have been pending for a month first, and there is no
-- record of it anywhere. Two ways to be wrong were available -- claim it
-- started `pending` and invent a transition at `updatedAt` to explain today's
-- status, or claim the status it has now has been its status all along. The
-- second is chosen because it invents nothing: the journal and the task row
-- agree, no transition that never happened appears on any screen, and the worst
-- it can say is that an old task's first interval is longer than it really was.
-- Every task created from here on records its transitions as they happen.
--
-- The id is a uuid rather than a cuid (the client generates cuids; Postgres has
-- no cuid function). Opaque either way -- and the shape makes a backfilled row
-- recognisable in a dump, which is useful precisely because these are the rows
-- whose contents are an approximation.
INSERT INTO "task_events" ("id", "taskId", "kind", "fromStatus", "toStatus", "at")
SELECT gen_random_uuid()::text, "id", 'created', NULL, "status", "createdAt"
FROM "tasks";
