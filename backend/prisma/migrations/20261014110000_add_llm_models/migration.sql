-- The owner's list of models to parse with: see src/domain/modelRoster.ts.
CREATE TABLE "llm_models" (
    "id" TEXT NOT NULL,
    "position" INTEGER NOT NULL,
    "name" TEXT NOT NULL,
    "label" TEXT,
    "baseUrl" TEXT,
    "apiKeyEnv" TEXT,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "autoDisabledAt" TIMESTAMP(3),
    "autoDisabledReason" TEXT,
    "consecutiveFailures" INTEGER NOT NULL DEFAULT 0,
    "failStreakStartedAt" TIMESTAMP(3),
    "lastSuccessAt" TIMESTAMP(3),
    "lastFailureAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "llm_models_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "llm_models_position_idx" ON "llm_models"("position");
