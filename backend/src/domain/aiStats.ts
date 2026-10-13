/*
 * What the dataset says about AI processing (14.10.2026), for the owner's
 * statistics screen: how each model does, and how well each level lands.
 *
 * "LANDS" IS MEASURED BY WHAT WAS SAVED
 *
 * A parse whose answer was saved untouched hit the mark; one saved with
 * corrections came close; one never saved missed or was abandoned. The label
 * on the row (`finalTitle`, `finalDescription`, `finalContent`, see
 * `./dictationLink.ts`) is compared with the answer (`result`), field by
 * field, blind to surrounding spaces.
 *
 * Pure: the route reads the rows, this counts them.
 */

export interface StatsRow {
  kind: string;
  model: string;
  promptVersion: string;
  level: number | null;
  status: string;
  durationMs: number;
  result: unknown;
  linkedAt: Date | null;
  finalTitle: string | null;
  finalDescription: string | null;
  finalContent: string | null;
}

export interface ModelStats {
  model: string;
  total: number;
  ok: number;
  failed: number;
  /** Mean duration of successful parses; null without any. */
  avgDurationMs: number | null;
}

export interface LevelStats {
  kind: string;
  level: number | null;
  promptVersion: string;
  /** Successful parses. */
  answered: number;
  savedAsIs: number;
  savedEdited: number;
  notSaved: number;
}

export interface AiStats {
  models: ModelStats[];
  levels: LevelStats[];
}

const norm = (value: unknown) => (typeof value === "string" ? value.trim() : "");

/** Whether the label differs from the answer in any field the kind saves. */
function edited(row: StatsRow): boolean {
  const result = (row.result ?? {}) as Record<string, unknown>;
  switch (row.kind) {
    case "note":
      // A note keeps its body; a task's description tidied as a note too.
      return norm(row.finalContent) !== norm(result.content);
    case "sandbox":
      // Filed as a task, or kept as a line: whichever label it got.
      if (row.finalTitle !== null) {
        return (
          norm(row.finalTitle) !== norm(result.title) ||
          norm(row.finalDescription) !== norm(result.description)
        );
      }
      return norm(row.finalContent) !== norm(result.text);
    default:
      return (
        norm(row.finalTitle) !== norm(result.title) ||
        norm(row.finalDescription) !== norm(result.description)
      );
  }
}

export function computeStats(rows: readonly StatsRow[]): AiStats {
  const models = new Map<string, ModelStats & { durationSum: number }>();
  const levels = new Map<string, LevelStats>();

  for (const row of rows) {
    const model = models.get(row.model) ?? {
      model: row.model,
      total: 0,
      ok: 0,
      failed: 0,
      avgDurationMs: null,
      durationSum: 0,
    };
    model.total += 1;
    if (row.status === "ok") {
      model.ok += 1;
      model.durationSum += row.durationMs;
    } else {
      model.failed += 1;
    }
    models.set(row.model, model);

    if (row.status !== "ok") continue;
    const key = `${row.kind}|${row.level ?? ""}|${row.promptVersion}`;
    const level = levels.get(key) ?? {
      kind: row.kind,
      level: row.level,
      promptVersion: row.promptVersion,
      answered: 0,
      savedAsIs: 0,
      savedEdited: 0,
      notSaved: 0,
    };
    level.answered += 1;
    if (row.linkedAt === null) level.notSaved += 1;
    else if (edited(row)) level.savedEdited += 1;
    else level.savedAsIs += 1;
    levels.set(key, level);
  }

  return {
    models: [...models.values()]
      .map(({ durationSum, ...stats }) => ({
        ...stats,
        avgDurationMs: stats.ok === 0 ? null : Math.round(durationSum / stats.ok),
      }))
      .sort((a, b) => b.total - a.total),
    levels: [...levels.values()].sort(
      (a, b) =>
        a.kind.localeCompare(b.kind) ||
        (a.level ?? 0) - (b.level ?? 0) ||
        a.promptVersion.localeCompare(b.promptVersion),
    ),
  };
}
