-- The tidying kinds' dataset rows get linked to what was saved (F15), as the
-- `task` rows already are: `note` rows to the note (`noteId`, and its body in
-- `finalContent`), `sandbox` rows to the inbox line they stayed as
-- (`inboxItemId`, `finalContent`). `task_tidy` rows reuse `taskId` and
-- `finalTitle`/`finalDescription`, which need nothing new.
--
-- Additive and safe to run against a live database: three nullable columns,
-- two indexes, two foreign keys that null themselves when the note or the line
-- goes -- the row, like one whose task was deleted, stays in the dataset.

-- AlterTable
ALTER TABLE "dictation_parses" ADD COLUMN     "finalContent" TEXT,
ADD COLUMN     "inboxItemId" TEXT,
ADD COLUMN     "noteId" TEXT;

-- CreateIndex
CREATE INDEX "dictation_parses_noteId_idx" ON "dictation_parses"("noteId");

-- CreateIndex
CREATE INDEX "dictation_parses_inboxItemId_idx" ON "dictation_parses"("inboxItemId");

-- AddForeignKey
ALTER TABLE "dictation_parses" ADD CONSTRAINT "dictation_parses_noteId_fkey" FOREIGN KEY ("noteId") REFERENCES "notes"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "dictation_parses" ADD CONSTRAINT "dictation_parses_inboxItemId_fkey" FOREIGN KEY ("inboxItemId") REFERENCES "inbox_items"("id") ON DELETE SET NULL ON UPDATE CASCADE;
