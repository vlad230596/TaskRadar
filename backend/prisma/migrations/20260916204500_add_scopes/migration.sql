-- Scopes (F7): projects are grouped into spaces, and the board shows one at a
-- time.
--
-- Written by hand rather than generated, for one reason: `Project.scopeId` is
-- NOT NULL and production already holds projects. A generated migration would
-- either refuse to run or add the column with no way to fill it. The order
-- below -- create the table, seed exactly one scope, add the column nullable,
-- backfill it, then make it NOT NULL -- is what makes this safe to apply to a
-- database with rows in it.
--
-- It seeds the default scope on an empty database too (CI, a fresh clone).
-- That is deliberate: the client's board always shows exactly one scope, and
-- `POST /projects` without a `scopeId` falls back to the first one, so a
-- database with zero scopes is a database where nothing can be created. One
-- scope always exists from the moment the schema does.

-- CreateTable
CREATE TABLE "scopes" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "position" DOUBLE PRECISION NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "scopes_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "scopes_position_idx" ON "scopes"("position");

-- The default scope. Its id is fixed and readable rather than a cuid so that
-- this row is recognisable in a database dump and so that re-running this
-- migration against a database that already has it would collide loudly
-- instead of quietly creating a second one. `position` matches POSITION_GAP in
-- src/domain/position.ts, which is where new scopes are appended from.
INSERT INTO "scopes" ("id", "name", "position", "createdAt", "updatedAt")
VALUES ('scope_default_0001', 'Основной', 1000, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- AlterTable: nullable first, so existing rows survive the ALTER.
ALTER TABLE "projects" ADD COLUMN "scopeId" TEXT;

-- Backfill. Every project that existed before scopes did belongs to the
-- default scope; the owner can move them afterwards from the UI.
UPDATE "projects" SET "scopeId" = 'scope_default_0001' WHERE "scopeId" IS NULL;

-- ...and only now is the column required.
ALTER TABLE "projects" ALTER COLUMN "scopeId" SET NOT NULL;

-- CreateIndex
CREATE INDEX "projects_scopeId_idx" ON "projects"("scopeId");

-- AddForeignKey: RESTRICT, so the database itself refuses to delete a scope
-- that still holds projects. The route answers 409 before this fires; this is
-- the backstop that makes "deleting a scope cannot lose a project" a property
-- of the schema rather than of one code path.
ALTER TABLE "projects" ADD CONSTRAINT "projects_scopeId_fkey" FOREIGN KEY ("scopeId") REFERENCES "scopes"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
