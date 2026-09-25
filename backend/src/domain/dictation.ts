import { z } from "zod";
import { ChatMessage, CompleteJson, UpstreamModelError } from "../lib/llmClient";

/*
 * Dictation -> task (F14): the words as spoken, turned into a task as it would
 * have been typed.
 *
 * WHAT THE MODEL IS FOR, AND WHAT IT IS NOT
 *
 * The phone already recognises speech on the device (GigaAM). What comes out is
 * accurate and unusable as a title: "так, короче, надо бы позвонить в сервис,
 * ну, насчёт машины, спросить, готова ли, и сколько стоят колодки". The model
 * does three small things with that -- drops the filler, splits it into a
 * short title that starts with a verb and a description with the rest, and
 * picks out "напомни в пятницу" -- and nothing else. It needs no world
 * knowledge, which is why a 7-14B model is enough and why the prompt is mostly
 * rules and examples.
 *
 * DATES ARE LOOKED UP, NOT COMPUTED
 *
 * "В пятницу" is where small models fail, and they fail confidently: the
 * arithmetic from "today is Wednesday the 23rd" to "Friday is the 25th" is
 * exactly the step a model gets wrong one time in ten. So the prompt carries a
 * table of the next two weeks, one row per day with its weekday, and the model
 * only has to find the row. The reply is then checked here anyway -- a date in
 * the past or years away is dropped rather than trusted.
 *
 * WHY THE TIME IS RETURNED WHEN NOTHING STORES IT
 *
 * Reminders have day granularity today (`app/lib/domain/reminders.dart`). The
 * time is extracted anyway because it costs nothing in the prompt, and a
 * client that learns to use it later should not need the server to change.
 */

export interface ParsedDictation {
  title: string;
  description: string | null;
  /** Calendar date `YYYY-MM-DD` in the caller's time zone, or null. */
  remindDate: string | null;
  /** Wall-clock `HH:MM`, only ever present together with [remindDate]. */
  remindTime: string | null;
}

export interface DictationInput {
  text: string;
  /** IANA zone of the device that dictated, e.g. `Europe/Moscow`. */
  timeZone: string;
  now: Date;
}

/**
 * Everything one parse did, successful or not -- what the dataset row keeps
 * (`DictationParse` in prisma/schema.prisma).
 */
export interface DictationTrace {
  model: string;
  promptVersion: string;
  /** The reply as received; null when none arrived. */
  rawReply: string | null;
  /** Null when the parse failed. */
  result: ParsedDictation | null;
  /** Why it failed; null when it did not. */
  error: string | null;
  durationMs: number;
}

/** Never throws for a model failure: the failure is part of the trace. */
export type DictationParser = (input: DictationInput) => Promise<DictationTrace>;

/**
 * Which prompt a dataset row was produced with. Bump it whenever
 * [buildDictationMessages] changes what it asks -- rules, examples, calendar
 * format -- so that rows from different prompts are never compared as if they
 * were the same experiment.
 */
export const DICTATION_PROMPT_VERSION = "1";

/** How far ahead the calendar in the prompt reaches. */
const CALENDAR_DAYS = 14;

/** A reminder further out than this is a misheard number, not a plan. */
const MAX_REMIND_AHEAD_DAYS = 366;

const WEEKDAYS = [
  "воскресенье",
  "понедельник",
  "вторник",
  "среда",
  "четверг",
  "пятница",
  "суббота",
] as const;

/** Whether [timeZone] is an IANA zone this runtime knows. */
export function isValidTimeZone(timeZone: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone });
    return true;
  } catch {
    return false;
  }
}

/** The calendar date of [now] as seen in [timeZone], as `YYYY-MM-DD`. */
export function localDate(now: Date, timeZone: string): string {
  // `en-CA` formats dates as ISO `YYYY-MM-DD`, which saves assembling the parts.
  return new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
}

/**
 * [date] moved by [days]. Date-only arithmetic in UTC, where there is no
 * daylight-saving hour to fall into.
 */
function addDays(date: string, days: number): string {
  const moved = new Date(`${date}T00:00:00Z`);
  moved.setUTCDate(moved.getUTCDate() + days);
  return moved.toISOString().slice(0, 10);
}

function weekdayOf(date: string): string {
  return WEEKDAYS[new Date(`${date}T00:00:00Z`).getUTCDay()]!;
}

interface CalendarRow {
  date: string;
  weekday: string;
  note: string | null;
}

function calendar(today: string): CalendarRow[] {
  const notes = ["сегодня", "завтра", "послезавтра"];
  return Array.from({ length: CALENDAR_DAYS }, (_, offset) => {
    const date = addDays(today, offset);
    return { date, weekday: weekdayOf(date), note: notes[offset] ?? null };
  });
}

/**
 * The nearest date after today that falls on [weekday]: what "в пятницу" means
 * when said on any day, including a Friday.
 */
function nextWeekday(rows: CalendarRow[], weekday: string): string {
  return rows.slice(1).find((row) => row.weekday === weekday)!.date;
}

/**
 * The prompt. Russian, because the dictation is, and a model asked in English
 * to write Russian titles drifts into translated phrasing.
 *
 * The examples are built from the real calendar rather than written out with
 * fixed dates: an example that says "в пятницу -> 2026-01-16" while the table
 * says Friday is the 25th teaches the model to copy the example.
 */
export function buildDictationMessages(input: DictationInput): ChatMessage[] {
  const today = localDate(input.now, input.timeZone);
  const rows = calendar(today);
  const table = rows
    .map((row) => `${row.date} — ${row.weekday}${row.note ? ` (${row.note})` : ""}`)
    .join("\n");

  const friday = nextWeekday(rows, "пятница");
  const tomorrow = rows[1]!.date;

  const examples: { input: string; output: ParsedDictation }[] = [
    {
      input:
        "Так, короче, надо бы позвонить в сервис, ну, насчёт машины, спросить, готова ли она, и сколько там стоит замена колодок.",
      output: {
        title: "Позвонить в сервис насчёт машины",
        description: "Спросить, готова ли, и сколько стоит замена колодок.",
        remindDate: null,
        remindTime: null,
      },
    },
    {
      input:
        "Эээ, заказать кабель для монитора, этот, как его, ю эс би си, метра два. Напомни в пятницу проверить, пришёл ли.",
      output: {
        title: "Заказать кабель USB-C для монитора",
        description: "Длина около двух метров. Проверить, пришёл ли.",
        remindDate: friday,
        remindTime: null,
      },
    },
    {
      input: "Отчёт по налогам, то есть декларацию. Завтра в десять напомни.",
      output: {
        title: "Подготовить налоговую декларацию",
        description: null,
        remindDate: tomorrow,
        remindTime: "10:00",
      },
    },
    {
      input:
        "Купить на дачу: саморезы, нет, не саморезы, гвозди, потом краску белую и ещё перчатки, в общем, вот.",
      output: {
        title: "Купить материалы для дачи",
        description: "- гвозди\n- белая краска\n- перчатки",
        remindDate: null,
        remindTime: null,
      },
    },
  ];

  const system = [
    "Ты превращаешь надиктованный текст в задачу для личного трекера.",
    "Текст получен распознаванием речи: в нём есть слова-паразиты, повторы, самоисправления и ошибки распознавания.",
    "",
    "Верни ОДИН JSON-объект с ключами:",
    '- "title": название задачи;',
    '- "description": описание или null;',
    '- "remindDate": дата напоминания "YYYY-MM-DD" или null;',
    '- "remindTime": время напоминания "HH:MM" или null.',
    "",
    "Название:",
    "- начинается с глагола в неопределённой форме: «Позвонить», «Купить», «Проверить», «Написать»;",
    "- коротко и просто, до 60 символов, без точки в конце;",
    "- отвечает на вопрос «что сделать», без подробностей.",
    "",
    "Описание:",
    "- всё полезное, что не вошло в название: детали, условия, кому, сколько;",
    "- если перечисляется несколько пунктов — список строками, каждая начинается с «- »;",
    "- если добавить нечего — null. Не повторяй название.",
    "",
    "Очистка:",
    "- убери слова-паразиты («ну», «так», «короче», «типа», «это самое», «в общем», «как его», «эээ»);",
    "- при самоисправлении («в среду, нет, в четверг») оставь только исправленный вариант;",
    "- исправь очевидные ошибки распознавания и запиши термины как принято («ю эс би си» → «USB-C»);",
    "- НЕ добавляй фактов, которых не было в тексте. Имена, числа и суммы сохраняй точно.",
    "",
    "Напоминание:",
    "- только если человек явно просит напомнить или вернуться к задаче в определённый день («напомни», «спросить в пятницу», «вернуться во вторник»);",
    "- дату бери ТОЛЬКО из календаря ниже, ничего не вычисляй сам;",
    "- день недели («в пятницу») — ближайший такой день ПОСЛЕ сегодняшнего;",
    "- время — только если названо явно, иначе null; без даты время не ставь;",
    "- просьбу о напоминании в название и описание не переноси.",
    "",
    `Календарь (часовой пояс ${input.timeZone}):`,
    table,
    "",
    "Примеры:",
    ...examples.map(
      (example) => `Текст: ${example.input}\nОтвет: ${JSON.stringify(example.output)}`,
    ),
  ].join("\n");

  return [
    { role: "system", content: system },
    { role: "user", content: input.text },
  ];
}

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const TIME_PATTERN = /^([01]\d|2[0-3]):[0-5]\d$/;

/**
 * Lenient on purpose: a key that is missing or of the wrong type becomes null
 * rather than failing the whole reply, because a title with no reminder is
 * still worth having. Only the title is required -- without one there is no
 * task.
 */
const modelReplySchema = z.object({
  title: z.string(),
  description: z.string().nullish().catch(null),
  remindDate: z.string().nullish().catch(null),
  remindTime: z.string().nullish().catch(null),
});

function isRealDate(date: string): boolean {
  if (!DATE_PATTERN.test(date)) return false;
  const parsed = new Date(`${date}T00:00:00Z`);
  // Rejects 2026-02-30, which `Date` would otherwise roll into March.
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === date;
}

/**
 * The model's reply, checked and tidied. Throws [UpstreamModelError] when there
 * is nothing usable in it; drops, rather than trusts, a reminder that makes no
 * sense.
 */
export function interpretModelReply(content: string, today: string): ParsedDictation {
  let json: unknown;
  try {
    json = JSON.parse(content);
  } catch {
    throw new UpstreamModelError("reply content is not JSON");
  }

  const parsed = modelReplySchema.safeParse(json);
  if (!parsed.success) {
    throw new UpstreamModelError("reply has no title");
  }

  const title = parsed.data.title.trim().replace(/[.。]+$/, "");
  if (title === "") {
    throw new UpstreamModelError("reply has an empty title");
  }

  const description = parsed.data.description?.trim() || null;

  const rawDate = parsed.data.remindDate?.trim() ?? "";
  const remindDate =
    isRealDate(rawDate) && rawDate >= today && rawDate <= addDays(today, MAX_REMIND_AHEAD_DAYS)
      ? rawDate
      : null;

  const rawTime = parsed.data.remindTime?.trim() ?? "";
  const remindTime = remindDate !== null && TIME_PATTERN.test(rawTime) ? rawTime : null;

  return {
    title: title.charAt(0).toUpperCase() + title.slice(1),
    description,
    remindDate,
    remindTime,
  };
}

/**
 * [resolveModel] is asked on every parse, so a model chosen in the app takes
 * effect on the next dictation. See `./dictationModel.ts`.
 */
export function createDictationParser(
  complete: CompleteJson,
  resolveModel: () => Promise<string>,
  clock: () => number = Date.now,
): DictationParser {
  return async (input) => {
    const model = await resolveModel();
    const started = clock();
    let rawReply: string | null = null;
    try {
      rawReply = await complete(buildDictationMessages(input), model);
      const result = interpretModelReply(rawReply, localDate(input.now, input.timeZone));
      return trace(model, rawReply, result, null, clock() - started);
    } catch (error) {
      if (!(error instanceof UpstreamModelError)) throw error;
      return trace(model, rawReply, null, error.reason, clock() - started);
    }
  };
}

function trace(
  model: string,
  rawReply: string | null,
  result: ParsedDictation | null,
  error: string | null,
  durationMs: number,
): DictationTrace {
  return {
    model,
    promptVersion: DICTATION_PROMPT_VERSION,
    rawReply,
    result,
    error,
    durationMs,
  };
}
