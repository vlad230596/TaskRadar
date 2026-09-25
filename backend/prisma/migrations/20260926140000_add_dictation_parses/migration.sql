-- The dictation dataset (F14): one row per press of "Разобрать" -- input,
-- model, raw reply, parsed result, duration -- linked to the task it became,
-- with a snapshot of what the user kept. Replayed against other models and
-- prompts before they are switched on.
--
-- Additive and safe to run against a live database: a new table, and a foreign
-- key that nulls itself when a task is deleted, so deleting tasks keeps working
-- exactly as before.

-- CreateTable
CREATE TABLE "dictation_parses" (
    "id" TEXT NOT NULL,
    "inputText" TEXT NOT NULL,
    "timeZone" TEXT NOT NULL,
    "requestedAt" TIMESTAMP(3) NOT NULL,
    "model" TEXT NOT NULL,
    "promptVersion" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "rawReply" TEXT,
    "result" JSONB,
    "error" TEXT,
    "durationMs" INTEGER NOT NULL,
    "taskId" TEXT,
    "finalTitle" TEXT,
    "finalDescription" TEXT,
    "finalRemindAt" TIMESTAMP(3),
    "linkedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "dictation_parses_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "dictation_parses_createdAt_idx" ON "dictation_parses"("createdAt");

-- CreateIndex
CREATE INDEX "dictation_parses_taskId_idx" ON "dictation_parses"("taskId");

-- AddForeignKey
ALTER TABLE "dictation_parses" ADD CONSTRAINT "dictation_parses_taskId_fkey" FOREIGN KEY ("taskId") REFERENCES "tasks"("id") ON DELETE SET NULL ON UPDATE CASCADE;
