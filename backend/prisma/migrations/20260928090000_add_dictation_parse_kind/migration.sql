-- What each dataset row was parsed into (F15): `task` for every row so far,
-- and now also `task_tidy`, `note` and `sandbox` -- the "Причесать" kinds, each
-- with its own prompt. A replay compares rows of one kind only.
--
-- Additive and safe to run against a live database: a column with a default,
-- so every existing row becomes `task`, which is what all of them were.

-- AlterTable
ALTER TABLE "dictation_parses" ADD COLUMN "kind" TEXT NOT NULL DEFAULT 'task';

-- CreateIndex
CREATE INDEX "dictation_parses_kind_createdAt_idx" ON "dictation_parses"("kind", "createdAt");
