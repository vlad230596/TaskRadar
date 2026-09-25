import { ParsedDictation } from "./dictation";

/*
 * Scoring a replay of the dictation dataset (F14) -- the pure half of
 * `../scripts/replayDictation.ts`.
 *
 * WHAT A SAMPLE IS SCORED AGAINST
 *
 * The label is what the user saved from the dictation screen: the proposal
 * after their corrections (`final*` on `DictationParse`). Not the task as it
 * is now -- a task edited a week later for reasons that have nothing to do
 * with the dictation would make the label drift -- and not the original
 * model's answer, which is the baseline being compared, not the truth.
 *
 * WHY SIMILARITY AS WELL AS EXACT MATCH
 *
 * Titles are short and exact match is the honest headline number, but it
 * scores "Позвонить в сервис насчёт машины" against "Позвонить в сервис по
 * поводу машины" the same as against "Купить хлеб". The similarity is there so
 * a model that is nearly right can be told apart from one that is wrong.
 */

/** What a labelled sample says the answer should have been. */
export interface SampleLabel {
  title: string;
  description: string | null;
  /** `YYYY-MM-DD`, or null for no reminder. */
  remindDate: string | null;
}

export interface SampleScore {
  ok: boolean;
  titleExact: boolean;
  /** 0..1, 1 for identical after normalisation. */
  titleSimilarity: number;
  descriptionExact: boolean;
  remindExact: boolean;
}

/**
 * The form two texts are compared in: case, `ё`, runs of whitespace and
 * trailing punctuation are not what a prompt is being judged on.
 */
export function normalise(text: string | null): string {
  return (text ?? "")
    .toLowerCase()
    .replace(/ё/g, "е")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/[.!?;:,…\s]+$/u, "");
}

function levenshtein(a: string, b: string): number {
  const previous = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    let diagonal = previous[0]!;
    previous[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const above = previous[j]!;
      previous[j] = Math.min(
        above + 1,
        previous[j - 1]! + 1,
        diagonal + (a[i - 1] === b[j - 1] ? 0 : 1),
      );
      diagonal = above;
    }
  }
  return previous[b.length]!;
}

/** 1 minus the edit distance over the longer length, after [normalise]. */
export function similarity(a: string | null, b: string | null): number {
  const x = normalise(a);
  const y = normalise(b);
  const longest = Math.max(x.length, y.length);
  return longest === 0 ? 1 : 1 - levenshtein(x, y) / longest;
}

/**
 * The label's reminder as a calendar date. `finalRemindAt` is stored the way
 * every `remindAt` is -- UTC midnight of the picked day -- so the date is its
 * ISO prefix, read as-is (see `app/lib/domain/reminders.dart` for why it must
 * never be converted to a local time first).
 */
export function labelRemindDate(finalRemindAt: Date | null): string | null {
  return finalRemindAt === null ? null : finalRemindAt.toISOString().slice(0, 10);
}

export function scoreSample(result: ParsedDictation | null, label: SampleLabel): SampleScore {
  if (result === null) {
    return {
      ok: false,
      titleExact: false,
      titleSimilarity: 0,
      descriptionExact: false,
      remindExact: false,
    };
  }
  return {
    ok: true,
    titleExact: normalise(result.title) === normalise(label.title),
    titleSimilarity: similarity(result.title, label.title),
    descriptionExact: normalise(result.description) === normalise(label.description),
    remindExact: (result.remindDate ?? null) === label.remindDate,
  };
}

export interface ReplaySummary {
  samples: number;
  okRate: number;
  titleExactRate: number;
  titleSimilarityMean: number;
  descriptionExactRate: number;
  remindExactRate: number;
}

export function summarise(scores: SampleScore[]): ReplaySummary {
  const n = scores.length;
  const rate = (pick: (score: SampleScore) => boolean) =>
    n === 0 ? 0 : scores.filter(pick).length / n;
  return {
    samples: n,
    okRate: rate((s) => s.ok),
    titleExactRate: rate((s) => s.titleExact),
    titleSimilarityMean: n === 0 ? 0 : scores.reduce((sum, s) => sum + s.titleSimilarity, 0) / n,
    descriptionExactRate: rate((s) => s.descriptionExact),
    remindExactRate: rate((s) => s.remindExact),
  };
}

/** The [fraction] quantile (0..1) of [values], nearest-rank; 0 for none. */
export function quantile(values: number[], fraction: number): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const rank = Math.min(sorted.length - 1, Math.max(0, Math.ceil(fraction * sorted.length) - 1));
  return sorted[rank]!;
}
