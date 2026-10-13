/*
 * How hard the model may work a text over (14.10.2026): "Лёгкая",
 * "Обычная", "Сильная".
 *
 * WHY A NUMBER
 *
 * The level travels and is stored as an integer, not a name: today there are
 * three, and the user expects a slider with more stops later. A new stop is a
 * new entry in [LEVEL_RULES] -- the request schema, the dataset column and the
 * app all take any integer in [AI_LEVEL_MIN, AI_LEVEL_MAX].
 *
 * WHAT CHANGES WITH THE LEVEL, AND WHAT NEVER DOES
 *
 * Only how freely the wording may change. The rules every level shares --
 * nothing invented, names and numbers exact, self-corrections resolved, no
 * dates the text did not have -- are [BASE_RULES], and they hold at "Сильная"
 * exactly as at "Лёгкая". A stronger level is a freer editor, never a writer.
 *
 * The prompt version (`promptVersion` on each kind) covers the rule texts of
 * all levels; the level itself is a column of its own on the dataset row, so
 * the statistics can compare levels within one prompt version.
 */

export const AI_LEVEL_MIN = 1;
export const AI_LEVEL_MAX = 3;
/** Today's behaviour before levels existed: the middle stop. */
export const AI_LEVEL_DEFAULT = 2;

/** What each level lets the model do to the wording. */
export const LEVEL_RULES: Readonly<Record<number, readonly string[]>> = {
  1: [
    "Сила обработки: ЛЁГКАЯ.",
    "- правь минимально: исправь только явные ошибки распознавания, опечатки и пунктуацию;",
    "- формулировки, порядок слов и мыслей оставь как у автора; не сокращай и не переписывай фразы;",
    "- название и описание собери из слов самого текста.",
  ],
  2: [
    "Сила обработки: ОБЫЧНАЯ.",
    "- исправь ошибки распознавания и пунктуацию;",
    "- можно слегка поправить построение фраз, чтобы читалось гладко, но не пересказывай своими словами;",
    "- если текст уже в порядке — верни его как есть.",
  ],
  3: [
    "Сила обработки: СИЛЬНАЯ.",
    "- можешь переформулировать, сокращать, объединять повторяющиеся мысли и менять порядок ради ясности;",
    "- пиши коротко и чётко, как записал бы аккуратный человек; длинные рассуждения сожми до сути;",
    "- но каждый факт, имя, число, ссылку и договорённость сохрани.",
  ],
};

/** The rules that hold at every level. */
function baseRules(opts: { dates: boolean }): string[] {
  return [
    "Очистка (при любой силе обработки):",
    "- убери слова-паразиты («ну», «так», «короче», «типа», «это самое», «в общем», «как его», «эээ») и повторы;",
    "- запиши термины как принято («ю эс би си» → «USB-C»);",
    "- при самоисправлении («в среду, нет, в четверг») оставь только исправленный вариант;",
    "- НЕ добавляй фактов, которых не было в тексте. Имена, числа, суммы, ссылки сохраняй точно;",
    ...(opts.dates
      ? ["- НЕ добавляй дат, дней недели, сроков и времени, которых нет в тексте;"]
      : []),
  ];
}

/** [level] clamped to the levels that exist; anything odd is the default. */
export function normaliseLevel(level: number | undefined): number {
  if (level === undefined || !Number.isInteger(level)) return AI_LEVEL_DEFAULT;
  return Math.min(AI_LEVEL_MAX, Math.max(AI_LEVEL_MIN, level));
}

/**
 * The cleanup block of a prompt at [level]. [dates]: whether to forbid dates
 * outright -- every kind but `task`, which reads reminders from a calendar.
 */
export function cleanupRules(level: number | undefined, opts: { dates: boolean }): string[] {
  return [...baseRules(opts), "", ...levelRules(normaliseLevel(level))];
}

// ---- The owner's edits (`./promptOverrides.ts`) ----

/*
 * The owner may rewrite a level's block from the app -- what "Обычная" means
 * is a matter of taste, and taste is tried, not argued. The edits live in the
 * database and are mirrored here, so the prompt builders stay synchronous.
 */
let overrides: Readonly<Record<number, readonly string[]>> = {};

/** Replaces the mirrored edits; `./promptOverrides.ts` calls it. */
export function setLevelOverrides(next: Readonly<Record<number, readonly string[]>>): void {
  overrides = next;
}

/** [level]'s block as the prompts use it: the owner's edit, or the default. */
export function levelRules(level: number): readonly string[] {
  return overrides[level] ?? LEVEL_RULES[level] ?? [];
}

/** Whether the owner has rewritten [level]'s block. */
export function isLevelOverridden(level: number): boolean {
  return overrides[level] !== undefined;
}

/**
 * Appended to every row's prompt version while any block is edited:
 * `+lv` and a short hash of the edits, so rows from different wordings are
 * never counted as one experiment -- the statistics split on it.
 */
export function levelRulesVersion(): string {
  const levels = Object.keys(overrides).sort();
  if (levels.length === 0) return "";
  const text = levels.map((level) => `${level}:${overrides[Number(level)]!.join("/")}`).join("|");
  let hash = 0;
  for (let i = 0; i < text.length; i++) hash = (Math.imul(hash, 31) + text.charCodeAt(i)) | 0;
  return `+lv${(hash >>> 0).toString(36)}`;
}
