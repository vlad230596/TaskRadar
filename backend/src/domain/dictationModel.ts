import { prisma } from "../lib/prisma";

/*
 * Which model parses dictation (F14): `LLM_MODEL` from `.env`, unless one was
 * chosen in the app.
 *
 * WHY THE APP CAN CHANGE THE MODEL BUT NOT THE KEY
 *
 * Trying a different model is the everyday change -- a free one stops being
 * free, a faster one appears -- and asking for SSH access to the server to
 * make it is out of proportion with the change. The key is the other way
 * round: it is the credential that costs money when leaked, it lives in a
 * root-only file on purpose, and an app that could read or write it would put
 * it one stolen phone away from anybody.
 */

export const DICTATION_MODEL_KEY = "dictation.model";

/** The model chosen in the app, or `null` when none was. */
export async function readDictationModelOverride(): Promise<string | null> {
  const row = await prisma.appSetting.findUnique({ where: { key: DICTATION_MODEL_KEY } });
  return row?.value ?? null;
}

/** Saves [model] as the choice, or clears the choice for `null`. */
export async function writeDictationModelOverride(model: string | null): Promise<void> {
  if (model === null) {
    await prisma.appSetting.deleteMany({ where: { key: DICTATION_MODEL_KEY } });
    return;
  }
  await prisma.appSetting.upsert({
    where: { key: DICTATION_MODEL_KEY },
    create: { key: DICTATION_MODEL_KEY, value: model },
    update: { value: model },
  });
}

/**
 * The model to parse with right now. One primary-key read per dictation --
 * nothing next to the seconds a model takes to answer -- and in exchange a
 * change made in the app applies to the very next dictation, with no cache to
 * go stale and no restart.
 */
export async function resolveDictationModel(defaultModel: string): Promise<string> {
  return (await readDictationModelOverride()) ?? defaultModel;
}
