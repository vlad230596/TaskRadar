-- Multi-user: a users table, an owner on every tree of data, and a per-user
-- daily counter for AI requests.
--
-- Everything that exists now belongs to the one person who used the app until
-- today. They become the first user, with the fixed id 'owner' -- the `sub`
-- claim of every token already issued -- so nobody is logged out and no row
-- loses its owner. The placeholder email and hash below cannot be logged into
-- (a bcrypt hash never equals '!'); on startup the server replaces them with
-- AUTH_EMAIL / AUTH_PASSWORD_HASH from .env (see `ensureOwner`), so the old
-- login keeps working unchanged.
--
-- Safe on a live database: new columns are added nullable, backfilled, and only
-- then made NOT NULL, all inside the transaction Prisma wraps around a
-- migration. Take a backup first anyway (BACKUPS.md).

-- CreateTable
CREATE TABLE "users" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "disabledAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ai_usage" (
    "userId" TEXT NOT NULL,
    "day" TEXT NOT NULL,
    "count" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "ai_usage_pkey" PRIMARY KEY ("userId","day")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- The first user: whoever owned the data until now.
INSERT INTO "users" ("id", "email", "name", "passwordHash")
VALUES ('owner', 'owner@taskradar.invalid', 'Owner', '!');

-- AlterTable: add the owner columns nullable...
ALTER TABLE "scopes" ADD COLUMN "userId" TEXT;
ALTER TABLE "inbox_items" ADD COLUMN "userId" TEXT;
ALTER TABLE "dictation_parses" ADD COLUMN "userId" TEXT;

-- ...hand every existing row to the owner...
UPDATE "scopes" SET "userId" = 'owner';
UPDATE "inbox_items" SET "userId" = 'owner';
UPDATE "dictation_parses" SET "userId" = 'owner';

-- ...and only then require it.
ALTER TABLE "scopes" ALTER COLUMN "userId" SET NOT NULL;
ALTER TABLE "inbox_items" ALTER COLUMN "userId" SET NOT NULL;
ALTER TABLE "dictation_parses" ALTER COLUMN "userId" SET NOT NULL;

-- The capture key is unique per user now, not across the whole table.
DROP INDEX "inbox_items_captureKey_key";
DROP INDEX "scopes_position_idx";
DROP INDEX "inbox_items_createdAt_idx";

-- CreateIndex
CREATE INDEX "scopes_userId_position_idx" ON "scopes"("userId", "position");
CREATE INDEX "inbox_items_userId_createdAt_idx" ON "inbox_items"("userId", "createdAt");
CREATE UNIQUE INDEX "inbox_items_userId_captureKey_key" ON "inbox_items"("userId", "captureKey");
CREATE INDEX "dictation_parses_userId_createdAt_idx" ON "dictation_parses"("userId", "createdAt");

-- AddForeignKey
ALTER TABLE "scopes" ADD CONSTRAINT "scopes_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "inbox_items" ADD CONSTRAINT "inbox_items_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "dictation_parses" ADD CONSTRAINT "dictation_parses_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "ai_usage" ADD CONSTRAINT "ai_usage_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
