-- A model's own sampling temperature: see src/lib/llmClient.ts. Null keeps
-- the server's default, so every existing entry behaves as before.
ALTER TABLE "llm_models" ADD COLUMN "temperature" DOUBLE PRECISION;
