-- A reminder can now carry a time of day, not only a date.
--
-- `remindTime` is local wall-clock "HH:MM", next to `remindAt` (still a
-- calendar date stored as UTC midnight). Null means "the day only": the app
-- fires it at the hour from its settings, exactly as before. Nullable and
-- unbackfilled, so every existing reminder keeps its old behaviour.

-- AlterTable
ALTER TABLE "tasks" ADD COLUMN "remindTime" TEXT;
