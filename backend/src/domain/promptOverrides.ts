import { prisma } from "../lib/prisma";
import { AI_LEVEL_MAX, AI_LEVEL_MIN, setLevelOverrides } from "./aiLevels";

/*
 * The owner's edits of the level blocks (`./aiLevels.ts`), kept in
 * `app_settings` as one JSON value: `{ "2": ["line", ...], ... }`. Read once,
 * on the first parse, and again after every edit; between them the prompts
 * read the mirror in `./aiLevels.ts`.
 */

export const LEVEL_OVERRIDES_KEY = "prompt.levels";

type Overrides = Record<number, string[]>;

function parse(value: string | undefined | null): Overrides {
  if (!value) return {};
  try {
    const json = JSON.parse(value) as Record<string, unknown>;
    const out: Overrides = {};
    for (const [key, lines] of Object.entries(json)) {
      const level = Number(key);
      if (!Number.isInteger(level) || level < AI_LEVEL_MIN || level > AI_LEVEL_MAX) continue;
      if (!Array.isArray(lines) || !lines.every((line) => typeof line === "string")) continue;
      out[level] = lines as string[];
    }
    return out;
  } catch {
    return {};
  }
}

let loaded: Promise<void> | null = null;

/** Loads the edits into the prompts, once; a failure means the defaults. */
export function ensurePromptOverridesLoaded(): Promise<void> {
  loaded ??= (async () => {
    try {
      const row = await prisma.appSetting.findUnique({ where: { key: LEVEL_OVERRIDES_KEY } });
      setLevelOverrides(parse(row?.value));
    } catch {
      loaded = null;
    }
  })();
  return loaded;
}

/** Sets [level]'s block to [rules], or back to the default for null. */
export async function writeLevelOverride(level: number, rules: string[] | null): Promise<void> {
  const row = await prisma.appSetting.findUnique({ where: { key: LEVEL_OVERRIDES_KEY } });
  const all = parse(row?.value);
  if (rules === null) delete all[level];
  else all[level] = rules;
  if (Object.keys(all).length === 0) {
    await prisma.appSetting.deleteMany({ where: { key: LEVEL_OVERRIDES_KEY } });
  } else {
    const value = JSON.stringify(all);
    await prisma.appSetting.upsert({
      where: { key: LEVEL_OVERRIDES_KEY },
      create: { key: LEVEL_OVERRIDES_KEY, value },
      update: { value },
    });
  }
  setLevelOverrides(all);
  loaded = Promise.resolve();
}
