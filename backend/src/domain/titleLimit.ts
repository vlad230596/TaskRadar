/**
 * The one length limit for a title the AI writes -- a task's, a note's, a
 * sandbox line's -- and the rules every prompt states with it.
 *
 * Why one number, stated to the model: the model splits the text into a title
 * and a body itself, so it has to know where the title ends. When each prompt
 * said its own figure (60 here, 80 there) and the client cut at 120 behind
 * them, nobody could say what a title may be, and a title the model made too
 * long was cut mechanically -- "…когда берём отпуск в…" in the title,
 * "приложении. И сразу…" in the body. Now every prompt says [TITLE_LIMIT], and
 * a reply is checked against the same number ([fitTitle]).
 *
 * The cut the app makes when no AI is involved (`./inboxSplit.ts`, 120) is a
 * different thing: it shapes raw words the user typed, not an answer.
 */
export const TITLE_LIMIT = 80;

/**
 * The title rules every prompt includes. [restField] is the reply key the rest
 * goes to: "description" for a task, "content" for a note.
 */
export function titleLimitRules(restField: string): string[] {
  return [
    `- не длиннее ${TITLE_LIMIT} символов — это жёсткий предел, длиннее заголовок не поместится;`,
    `- если суть не умещается в ${TITLE_LIMIT} символов — сформулируй её короче, а подробности перенеси в "${restField}";`,
    "- заголовок — законченная фраза: не обрывай его многоточием и не дели предложение между заголовком и текстом.",
  ];
}

/** A title as the lists draw it: no full stop, a capital first letter. */
export function tidyTitle(value: string): string {
  const title = value.trim().replace(/[.。]+$/, "");
  return title.charAt(0).toUpperCase() + title.slice(1);
}

/**
 * A title of at most [TITLE_LIMIT] characters made from [text], without taking
 * anything out of the text itself -- the caller keeps it whole.
 *
 * The first line, without a list mark or a heading's `#`, if it is short
 * enough; else its first sentence; else its words up to the limit, marked
 * with `…`; a single word longer than the limit is cut hard.
 */
export function shortTitleFrom(text: string): string | null {
  const line =
    text
      .split(/\r?\n/)
      .map((row) => row.replace(/^\s*(?:#+|[-*+]|\d+[.)])\s+/, "").trim())
      .find((row) => row !== "") ?? "";
  if (line === "") return null;
  if (line.length <= TITLE_LIMIT) return tidyTitle(line) || null;

  const sentence = /^(.{10,}?[.!?…])(?=\s)/u.exec(line)?.[1];
  if (sentence !== undefined && sentence.length <= TITLE_LIMIT) {
    return tidyTitle(sentence) || null;
  }

  const window = line.slice(0, TITLE_LIMIT - 1);
  const lastSpace = window.search(/\s\S*$/);
  const cut = lastSpace >= 10 ? window.slice(0, lastSpace) : window;
  return `${tidyTitle(cut.replace(/[\s,;:—–-]+$/u, ""))}…`;
}

/**
 * A model's title and body, held to [TITLE_LIMIT].
 *
 * A title within the limit is the model's, untouched. One over it -- the model
 * ignored the rule -- is not trusted as a title, and not thrown away either:
 * the title becomes [shortTitleFrom] of it, and the whole long title goes to
 * the top of the body, so not a word of the answer is lost.
 */
export function fitTitle(
  title: string,
  body: string | null,
): { title: string; body: string | null } {
  if (title.length <= TITLE_LIMIT) return { title, body };
  const short = shortTitleFrom(title) ?? title.slice(0, TITLE_LIMIT);
  const long = /[.!?…]$/u.test(title) ? title : `${title}.`;
  return { title: short, body: body === null ? long : `${long}\n\n${body}` };
}
