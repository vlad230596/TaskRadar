-- Task editor (design/task-editor-spec.md §10): checklist, place reminder,
-- picture attachments, link-preview cache.
--
-- Additive and safe against a live database: five nullable columns on
-- "tasks" (existing rows get NULL -- no list, no place), three new tables and
-- two CHECK constraints that every existing row already satisfies (all four
-- location columns are NULL on all of them).
--
-- The CHECKs are not in schema.prisma: Prisma has no syntax for them and
-- `migrate diff` ignores them, so this file is where they live. They hold the
-- database to what the API already enforces (src/schemas.ts), so a row written
-- by hand or by a future bug cannot become half a place.

-- AlterTable
ALTER TABLE "tasks" ADD COLUMN     "checklist" JSONB,
ADD COLUMN     "locLabel" TEXT,
ADD COLUMN     "locLat" DOUBLE PRECISION,
ADD COLUMN     "locLng" DOUBLE PRECISION,
ADD COLUMN     "locRadius" INTEGER;

-- A place is all four columns or none of them.
ALTER TABLE "tasks" ADD CONSTRAINT "tasks_location_all_or_none" CHECK (
  ("locLat" IS NULL AND "locLng" IS NULL AND "locRadius" IS NULL AND "locLabel" IS NULL)
  OR ("locLat" IS NOT NULL AND "locLng" IS NOT NULL AND "locRadius" IS NOT NULL AND "locLabel" IS NOT NULL)
);

-- And a place is somewhere on Earth, with the radius the picker offers.
ALTER TABLE "tasks" ADD CONSTRAINT "tasks_location_range" CHECK (
  "locLat" IS NULL OR (
    "locLat" BETWEEN -90 AND 90
    AND "locLng" BETWEEN -180 AND 180
    AND "locRadius" BETWEEN 100 AND 1000
    AND char_length("locLabel") <= 80
  )
);

-- CreateTable
CREATE TABLE "task_attachments" (
    "id" TEXT NOT NULL,
    "taskId" TEXT NOT NULL,
    "uploadKey" TEXT NOT NULL,
    "mime" TEXT NOT NULL,
    "sizeBytes" INTEGER NOT NULL,
    "width" INTEGER NOT NULL,
    "height" INTEGER NOT NULL,
    "sha256" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "task_attachments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "link_previews" (
    "url" TEXT NOT NULL,
    "title" TEXT,
    "siteName" TEXT,
    "failed" BOOLEAN NOT NULL DEFAULT false,
    "fetchedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "link_previews_pkey" PRIMARY KEY ("url")
);

-- CreateTable
CREATE TABLE "link_preview_usage" (
    "userId" TEXT NOT NULL,
    "day" TEXT NOT NULL,
    "count" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "link_preview_usage_pkey" PRIMARY KEY ("userId","day")
);

-- CreateIndex
CREATE INDEX "task_attachments_taskId_createdAt_idx" ON "task_attachments"("taskId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "task_attachments_taskId_uploadKey_key" ON "task_attachments"("taskId", "uploadKey");

-- AddForeignKey
ALTER TABLE "task_attachments" ADD CONSTRAINT "task_attachments_taskId_fkey" FOREIGN KEY ("taskId") REFERENCES "tasks"("id") ON DELETE CASCADE ON UPDATE CASCADE;
