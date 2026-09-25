-- Server-side preferences the app can change (F14), starting with the model
-- that parses dictation. The API key is not one of them: it stays in `.env`.
--
-- Additive and safe to run against a live database: a new, empty table that
-- nothing reads until a value is saved from the app. With no row, the server
-- uses LLM_MODEL from `.env`, exactly as before this migration.

-- CreateTable
CREATE TABLE "app_settings" (
    "key" TEXT NOT NULL,
    "value" TEXT NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "app_settings_pkey" PRIMARY KEY ("key")
);
