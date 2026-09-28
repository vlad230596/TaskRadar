/**
 * How a sandbox line becomes a task's title and description (F8, revised).
 *
 * WHY THIS EXISTS
 *
 * Filing used to put the whole line into `title`. That is right for what the
 * sandbox was designed around -- "Спросить про кабель" -- and wrong for what
 * dictation now puts there: a minute of speech is three or four sentences, and
 * a task whose title is a paragraph breaks every list it is drawn in (the board
 * shows one or two lines of it, the rest is simply gone from view). So a long
 * line is split: its first sentence names the task, the rest describes it.
 *
 * WHY ON THE SERVER
 *
 * So every client files the same line into the same task. A rule that lived in
 * the Flutter client would have to be repeated in the web one, and the day the
 * two disagreed the same dictated sentence would become a different task
 * depending on which screen filed it.
 *
 * WHAT IT DELIBERATELY DOES NOT DO
 *
 * Rewrite anything. The split only cuts; every word the user said ends up in
 * either the title or the description. Tidying the wording ("Причесать") is a
 * separate, AI-assisted step a client can run *before* filing and send its
 * result as an explicit `title`/`description` -- see `POST /inbox/:id/file`.
 */

/** Lines at or under this length are filed whole, exactly as before. */
export const INBOX_TITLE_LIMIT = 120;

/**
 * A sentence end shorter than this is not taken as the title's end: "Т.е.",
 * "Да." or "Итак." at the start of dictation is a lead-in, not a task name.
 */
const MIN_TITLE_LENGTH = 10;

export interface TaskTextParts {
  title: string;
  description: string | null;
}

/**
 * Splits [text] into a title and a description.
 *
 * - `text.length <= 120`: the whole (trimmed) text is the title, no description.
 * - otherwise the title is the first sentence if it ends within 120 characters
 *   (a `.`, `!`, `?` or `…` followed by whitespace, or a line break); failing
 *   that, the text up to the last word boundary before 120 characters, marked
 *   with `…` so it does not read as a finished sentence; failing even that (one
 *   120-character word), a hard cut. The remainder, trimmed, is the description.
 *
 * A trailing full stop is dropped from a sentence title -- task titles in this
 * product are names, not sentences -- while `!`, `?` and `…` are kept, because
 * they change what the title means.
 */
export function splitInboxText(text: string): TaskTextParts {
  const trimmed = text.trim();
  if (trimmed.length <= INBOX_TITLE_LIMIT) {
    return { title: trimmed, description: null };
  }

  const sentenceEnd = findSentenceEnd(trimmed);
  if (sentenceEnd !== null) {
    let title = trimmed.slice(0, sentenceEnd).trim();
    if (title.endsWith(".") && !title.endsWith("...")) title = title.slice(0, -1);
    return withRest(title, trimmed.slice(sentenceEnd));
  }

  const window = trimmed.slice(0, INBOX_TITLE_LIMIT + 1);
  const lastSpace = window.search(/\s\S*$/);
  if (lastSpace >= MIN_TITLE_LENGTH) {
    return withRest(`${trimmed.slice(0, lastSpace).trimEnd()}…`, trimmed.slice(lastSpace));
  }

  return withRest(trimmed.slice(0, INBOX_TITLE_LIMIT), trimmed.slice(INBOX_TITLE_LIMIT));
}

/**
 * The index just past the first sentence that ends within the limit, or null.
 * A line break always ends a sentence: dictation that was edited into lines
 * was edited that way on purpose.
 */
function findSentenceEnd(text: string): number | null {
  const pattern = /[.!?…]+(?=\s)|\r?\n/g;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(text)) !== null) {
    const end = match.index + match[0].length;
    if (end > INBOX_TITLE_LIMIT) return null;
    if (text.slice(0, match.index).trim().length >= MIN_TITLE_LENGTH) return end;
  }
  return null;
}

function withRest(title: string, rest: string): TaskTextParts {
  const description = rest.trim();
  return { title, description: description.length > 0 ? description : null };
}
