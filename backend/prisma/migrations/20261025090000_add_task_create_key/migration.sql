-- Offline outbox: an idempotency key on a created task.
--
-- The phone keeps task creations made with no network in a queue and sends
-- them later. A retry has to be safe even when the first attempt reached the
-- server and only the reply was lost -- from the phone both look like a
-- timeout -- so the client stamps each queued create with a key and
-- `POST /projects/:projectId/tasks` answers a known key with the task it
-- already made. Same design as `inbox_items.captureKey`
-- (20260917120000_add_inbox_capture_key).
--
-- Unique per project rather than per user: a task carries no userId, a project
-- belongs to one user, and a task never moves between projects -- see the note
-- on `@@unique([projectId, createKey])` in schema.prisma.
--
-- Additive and safe to run against a live database: a nullable column plus a
-- unique index. Existing rows get NULL, and Postgres treats each NULL in a
-- unique index as distinct, so every task created without a key keeps working.

-- AlterTable
ALTER TABLE "tasks" ADD COLUMN "createKey" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "tasks_projectId_createKey_key" ON "tasks"("projectId", "createKey");
