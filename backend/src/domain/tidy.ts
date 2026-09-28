import { z } from "zod";
import { ChatMessage, CompleteJson, UpstreamModelError } from "../lib/llmClient";
import type { DictationInput } from "./dictation";
import { createKindParser, KindParser, ParseSpec } from "./parsePipeline";

/*
 * "Причесать" (F15): text that is already somewhere -- a task, a note, a
 * sandbox line -- tidied by the model, as the kinds `task_tidy`, `note` and
 * `sandbox` of `POST /dictation/parse`. `task` (a new dictation into a
 * proposed task, with a reminder) is `./dictation.ts`.
 *
 * WHAT THESE PROMPTS ARE FOR, AND WHAT THEY ARE NOT
 *
 * Tidying, not writing. The text came from speech recognition or a thumb:
 * misheard words, no punctuation, "ну", "короче", the same thing said twice.
 * The model fixes that and gives the text a shape -- a title and a
 * description, paragraphs and lists -- and adds nothing. There is no
 * instruction box: "rewrite this more formally" is not a thing the product
 * offers, and a prompt that took one would be a prompt that invents.
 *
 * WHY THE DATES ARE CHECKED AND NOT TRUSTED
 *
 * The one fact a small model likes to add is a date -- "до пятницы", "завтра"
 * -- because task-shaped text in its training usually has one. A tidied task
 * with a deadline the user never said is worse than no tidying, so a
 * `task_tidy` reply that names a day, a date or a time the source did not is
 * refused outright (see [inventedDateTerm]), and the client keeps the text as
 * it was.
 *
 * WHY THE SANDBOX GETS THE PROJECT LIST FROM HERE
 *
 * The model picks a project for a sandbox line by name, so it needs the names.
 * They are read from the database by the route (`../routes/dictation.ts`),
 * never taken from the request: a client could send any list, and the id that
 * comes back is used to file a task. The reply's id is then checked against
 * the same list, and an id that is not on it is not a suggestion.
 */

/** A project a sandbox line could go to: what the model is shown. */
export interface ProjectChoice {
  id: string;
  name: string;
}

/** `sandbox`: the line, and the projects that exist. */
export interface SandboxInput extends DictationInput {
  projects: ProjectChoice[];
}

/** `task_tidy`: the task's own text, tidied into its two fields. */
export interface TidiedTask {
  title: string;
  description: string | null;
}

/** `note`: the body as markdown, and a title only when the note had none. */
export interface TidiedNote {
  title: string | null;
  content: string;
}

/** `sandbox`: the line tidied, and the project it most likely belongs to. */
export interface TidiedLine {
  text: string;
  /** One of the ids the model was shown, or null. */
  projectId: string | null;
  /** That project's name as the database has it, for the chip; null with it. */
  projectName: string | null;
}

/** See `DICTATION_PROMPT_VERSION` in `./dictation.ts` for what bumping means. */
export const TASK_TIDY_PROMPT_VERSION = "tidy-1";
export const NOTE_PROMPT_VERSION = "note-1";
export const SANDBOX_PROMPT_VERSION = "sandbox-1";

/** The rules every tidying prompt shares, word for word. */
const CLEANUP_RULES = [
  "Очистка:",
  "- исправь ошибки распознавания речи и пунктуацию, запиши термины как принято («ю эс би си» → «USB-C»);",
  "- убери слова-паразиты («ну», «так», «короче», «типа», «это самое», «в общем», «как его», «эээ») и повторы;",
  "- при самоисправлении («в среду, нет, в четверг») оставь только исправленный вариант;",
  "- НЕ добавляй фактов, которых не было в тексте. Имена, числа, суммы, ссылки сохраняй точно;",
  "- НЕ добавляй дат, дней недели, сроков и времени, которых нет в тексте;",
  "- если текст уже в порядке — верни его как есть.",
];

function parseJsonObject(content: string): unknown {
  try {
    return JSON.parse(content);
  } catch {
    throw new UpstreamModelError("reply content is not JSON");
  }
}

/** Trimmed, and null for nothing at all. */
function textOrNull(value: string | null | undefined): string | null {
  const trimmed = value?.trim() ?? "";
  return trimmed === "" ? null : trimmed;
}

/** A title as the lists draw it: no full stop, a capital first letter. */
function tidyTitle(value: string): string {
  const title = value.trim().replace(/[.。]+$/, "");
  return title.charAt(0).toUpperCase() + title.slice(1);
}

// ---- Dates the source did not say ----

/*
 * What counts as naming a day. Words are matched as words: JavaScript's `\b`
 * does not know Cyrillic, so the edges are spelled out -- otherwise "сред"
 * would find "средство" and "ма" every "мама".
 */
const WORD_EDGE_BEFORE = "(?<![а-яёa-z])";
const WORD_EDGE_AFTER = "(?![а-яёa-z])";

const DATE_WORDS: RegExp[] = [
  "сегодня",
  "завтра[а-яё]*",
  "послезавтра",
  "вчера",
  "понедельник[а-яё]*",
  "вторник[а-яё]*",
  "сред[ауые]",
  "четверг[а-яё]*",
  "пятниц[а-яё]*",
  "суббот[а-яё]*",
  "воскресень[а-яё]*",
  "выходны[а-яё]*",
  "январ[а-яё]*",
  "феврал[а-яё]*",
  "марта?",
  "апрел[а-яё]*",
  "ма[йяе]",
  "июн[а-яё]*",
  "июл[а-яё]*",
  "август[а-яё]*",
  "сентябр[а-яё]*",
  "октябр[а-яё]*",
  "ноябр[а-яё]*",
  "декабр[а-яё]*",
].map((word) => new RegExp(`${WORD_EDGE_BEFORE}${word}${WORD_EDGE_AFTER}`, "u"));

/** `25.09`, `25/09/2026`, `2026-09-25`, `10:00` -- compared as written. */
const DATE_NUMBERS =
  /(?<!\d)(\d{4}-\d{2}-\d{2}|\d{1,2}[./]\d{2}(?:[./]\d{2,4})?|\d{1,2}:\d{2})(?!\d)/gu;

function normalise(text: string): string {
  return text.toLowerCase().replace(/ё/g, "е");
}

/**
 * The first day, date or time [output] names that [source] does not, or
 * null. "В пятницу" in both is fine -- the tidying kept it; "до пятницы" in the
 * output alone is the model inventing a deadline.
 */
export function inventedDateTerm(source: string, output: string): string | null {
  const from = normalise(source);
  const to = normalise(output);
  for (const word of DATE_WORDS) {
    const found = to.match(word);
    if (found !== null && !word.test(from)) return found[0];
  }
  for (const found of to.matchAll(DATE_NUMBERS)) {
    if (!from.includes(found[0])) return found[0];
  }
  return null;
}

// ---- task_tidy ----

export function buildTaskTidyMessages(input: DictationInput): ChatMessage[] {
  const system = [
    "Ты приводишь в порядок текст уже существующей задачи в личном трекере.",
    "Текст мог быть надиктован: в нём бывают ошибки распознавания, слова-паразиты и повторы.",
    "Твоя работа — только причесать и разложить по полям. Смысл не меняй.",
    "",
    "Верни ОДИН JSON-объект с ключами:",
    '- "title": название задачи;',
    '- "description": описание или null.',
    "",
    "Название:",
    "- коротко, до 80 символов, без точки в конце;",
    "- по возможности начинается с глагола («Позвонить», «Купить», «Проверить»), если это не меняет смысл.",
    "",
    "Описание:",
    "- всё, что не вошло в название: детали, условия, кому, сколько;",
    "- несколько пунктов — список строками, каждая начинается с «- »;",
    "- если добавить нечего — null. Не повторяй название.",
    "",
    ...CLEANUP_RULES,
    "",
    "Напоминаний не ставь и о сроках ничего не придумывай: этой задаче они не нужны.",
    "",
    "Пример:",
    "Текст: ну короче надо это позвонить в сервис насчёт машины спросить готова ли она и сколько там колодки стоят колодки",
    `Ответ: ${JSON.stringify({
      title: "Позвонить в сервис насчёт машины",
      description: "Спросить, готова ли, и сколько стоят колодки.",
    })}`,
  ].join("\n");

  return [
    { role: "system", content: system },
    { role: "user", content: input.text },
  ];
}

const taskTidyReplySchema = z.object({
  title: z.string(),
  description: z.string().nullish().catch(null),
});

/**
 * The reply, checked. Refused -- [UpstreamModelError] -- when it has no title
 * or names a date [source] did not: see the note at the top of this file.
 */
export function interpretTaskTidyReply(content: string, source: string): TidiedTask {
  const parsed = taskTidyReplySchema.safeParse(parseJsonObject(content));
  if (!parsed.success) throw new UpstreamModelError("reply has no title");

  const title = tidyTitle(parsed.data.title);
  if (title === "") throw new UpstreamModelError("reply has an empty title");
  const description = textOrNull(parsed.data.description);

  const invented = inventedDateTerm(source, `${title}\n${description ?? ""}`);
  if (invented !== null) {
    throw new UpstreamModelError(`reply invents a date: ${invented}`);
  }
  return { title, description };
}

export const taskTidySpec: ParseSpec<DictationInput, TidiedTask> = {
  promptVersion: TASK_TIDY_PROMPT_VERSION,
  build: buildTaskTidyMessages,
  interpret: (content, input) => interpretTaskTidyReply(content, input.text),
};

// ---- note ----

export function buildNoteMessages(input: DictationInput): ChatMessage[] {
  const title = input.noteTitle?.trim() ?? "";
  const system = [
    "Ты приводишь в порядок заметку в личном трекере. Заметка пишется в Markdown.",
    "Текст мог быть надиктован: в нём бывают ошибки распознавания, слова-паразиты и повторы.",
    "",
    "Верни ОДИН JSON-объект с ключами:",
    '- "title": заголовок заметки или null;',
    '- "content": текст заметки в Markdown.',
    "",
    "Текст:",
    "- разбей на абзацы по смыслу, абзацы разделяй пустой строкой;",
    "- перечисления оформи списком: каждая строка начинается с «- »;",
    "- сохрани ВСЁ, что было сказано: каждый факт, имя, число, ссылку; не сокращай до пересказа;",
    "- не добавляй заголовков разделов, выводов и советов от себя.",
    "",
    ...CLEANUP_RULES,
    "",
    "Заголовок:",
    title === ""
      ? "- у заметки нет заголовка: предложи короткий, до 60 символов, без точки в конце."
      : `- у заметки уже есть заголовок («${title}»): верни "title": null.`,
    "",
    "Напоминаний и сроков не ставь.",
  ].join("\n");

  return [
    { role: "system", content: system },
    { role: "user", content: input.text },
  ];
}

const noteReplySchema = z.object({
  title: z.string().nullish().catch(null),
  content: z.string(),
});

/**
 * The reply, checked. A title is kept only when the note had none -- whatever
 * the model says, a title the user wrote is not replaced from here.
 */
export function interpretNoteReply(content: string, noteTitle?: string): TidiedNote {
  const parsed = noteReplySchema.safeParse(parseJsonObject(content));
  if (!parsed.success) throw new UpstreamModelError("reply has no content");

  const body = parsed.data.content.trim();
  if (body === "") throw new UpstreamModelError("reply has empty content");

  const hadTitle = (noteTitle?.trim() ?? "") !== "";
  const suggested = textOrNull(parsed.data.title);
  return {
    title: hadTitle || suggested === null ? null : tidyTitle(suggested) || null,
    content: body,
  };
}

export const noteSpec: ParseSpec<DictationInput, TidiedNote> = {
  promptVersion: NOTE_PROMPT_VERSION,
  build: buildNoteMessages,
  interpret: (content, input) => interpretNoteReply(content, input.noteTitle),
};

// ---- sandbox ----

export function buildSandboxMessages(input: SandboxInput): ChatMessage[] {
  const projects =
    input.projects.length === 0
      ? '(проектов нет — верни "projectId": null)'
      : input.projects.map((project) => `- ${project.id} — ${project.name}`).join("\n");

  const system = [
    "Ты приводишь в порядок строчку из «песочницы» личного трекера — записанную на ходу мысль, которую потом разложат по проектам.",
    "Строчка могла быть надиктована: в ней бывают ошибки распознавания, слова-паразиты и повторы.",
    "",
    "Верни ОДИН JSON-объект с ключами:",
    '- "text": строчка, приведённая в порядок;',
    '- "projectId": id проекта из списка ниже, к которому она скорее всего относится, или null.',
    "",
    "Текст:",
    "- одна мысль остаётся одной строчкой: не дели на название и описание, не делай списков без нужды;",
    "- сохрани всё, что было сказано.",
    "",
    ...CLEANUP_RULES,
    "",
    "Проект:",
    "- только id из списка, символ в символ; ничего не выдумывай;",
    "- если ни один проект явно не подходит — null. Лучше null, чем догадка.",
    "",
    "Проекты (id — название):",
    projects,
  ].join("\n");

  return [
    { role: "system", content: system },
    { role: "user", content: input.text },
  ];
}

const sandboxReplySchema = z.object({
  text: z.string(),
  projectId: z.string().nullish().catch(null),
});

/** The reply, checked. An id that is not one of [projects] becomes null. */
export function interpretSandboxReply(content: string, projects: ProjectChoice[]): TidiedLine {
  const parsed = sandboxReplySchema.safeParse(parseJsonObject(content));
  if (!parsed.success) throw new UpstreamModelError("reply has no text");

  const text = parsed.data.text.trim();
  if (text === "") throw new UpstreamModelError("reply has empty text");

  const id = parsed.data.projectId?.trim() ?? "";
  const project = projects.find((choice) => choice.id === id) ?? null;
  return { text, projectId: project?.id ?? null, projectName: project?.name ?? null };
}

export const sandboxSpec: ParseSpec<SandboxInput, TidiedLine> = {
  promptVersion: SANDBOX_PROMPT_VERSION,
  build: buildSandboxMessages,
  interpret: (content, input) => interpretSandboxReply(content, input.projects),
};

// ---- All three ----

/** The parsers for the tidying kinds, one per kind. */
export interface TidyParsers {
  task_tidy: KindParser<DictationInput, TidiedTask>;
  note: KindParser<DictationInput, TidiedNote>;
  sandbox: KindParser<SandboxInput, TidiedLine>;
}

export function createTidyParsers(
  complete: CompleteJson,
  resolveModel: () => Promise<string>,
  clock: () => number = Date.now,
): TidyParsers {
  return {
    task_tidy: createKindParser(taskTidySpec, complete, resolveModel, clock),
    note: createKindParser(noteSpec, complete, resolveModel, clock),
    sandbox: createKindParser(sandboxSpec, complete, resolveModel, clock),
  };
}
