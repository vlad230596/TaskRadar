-- What AI processing started from: see src/domain/aiMark.ts.
ALTER TABLE "tasks" ADD COLUMN "aiSource" TEXT, ADD COLUMN "aiKind" TEXT, ADD COLUMN "aiResult" JSONB;
ALTER TABLE "notes" ADD COLUMN "aiSource" TEXT, ADD COLUMN "aiKind" TEXT, ADD COLUMN "aiResult" JSONB;
ALTER TABLE "inbox_items" ADD COLUMN "aiSource" TEXT, ADD COLUMN "aiKind" TEXT, ADD COLUMN "aiResult" JSONB;
