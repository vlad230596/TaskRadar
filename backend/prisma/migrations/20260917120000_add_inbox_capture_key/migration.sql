-- Offline capture (F8.1): an idempotency key on a captured line.
--
-- The client keeps unsent lines in a queue on the device and retries them when
-- the network comes back. A retry has to be safe even when the *first* attempt
-- reached the server and only the reply was lost, because from the phone's side
-- those two failures look identical -- so the client stamps each line with a key
-- and the server upserts on it instead of creating a second row.
--
-- Additive and safe to run against a live database: a nullable column plus a
-- unique index. Existing rows get NULL, and Postgres treats each NULL in a
-- unique index as distinct, so every line captured before this migration (and
-- every line captured later without a key, e.g. by curl) keeps working.

-- AlterTable
ALTER TABLE "inbox_items" ADD COLUMN "captureKey" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "inbox_items_captureKey_key" ON "inbox_items"("captureKey");
