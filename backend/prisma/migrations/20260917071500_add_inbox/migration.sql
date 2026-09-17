-- The sandbox (F8): captured lines of text that have not been filed into a
-- project yet.
--
-- Purely additive -- a new table and nothing else. No existing column changes,
-- no backfill, no guard that has to hold while the migration runs. That is the
-- point of the shape chosen in schema.prisma: an inbox built out of a reserved
-- project or a nullable `tasks.projectId` would have had to alter tables that
-- production is actively writing to.

-- CreateTable
CREATE TABLE "inbox_items" (
    "id" TEXT NOT NULL,
    "text" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "inbox_items_pkey" PRIMARY KEY ("id")
);

-- CreateIndex: the list is read in capture order, oldest first.
CREATE INDEX "inbox_items_createdAt_idx" ON "inbox_items"("createdAt");
