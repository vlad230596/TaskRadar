import { Prisma } from "@prisma/client";
import type { ParseKind } from "./parsePipeline";

/*
 * "Правил AI" on a task, a note or a sandbox line (14.10.2026).
 *
 * WHAT IS KEPT
 *
 * - `aiSource`: the words before the FIRST "Обработать". Set once and never
 *   overwritten: a second or third processing runs from the same source (the
 *   app never processes a result), so the first source is the one the user
 *   means by "what I said".
 * - `aiKind`: the kind of that first parse -- `task`, `task_tidy`, `note`,
 *   `sandbox` -- which tells the app how to put the source back.
 * - `aiResult`: the fields as the latest AI answer saved them. The app compares
 *   them with the row: equal means "as AI left it", different means "изменён
 *   после AI". Nothing on the server tracks edits for this.
 *
 * WHERE THE SOURCE COMES FROM
 *
 * Every save of an AI answer already names its dataset row
 * (`dictationParseId`), and the row has the words as sent (`inputText`). So the
 * client sends nothing new: the route that saves asks [aiMarkFields] for the
 * columns and writes them with the save itself.
 *
 * The row is matched on its owner and kind, like the dataset label
 * (`./dictationLink.ts`) -- but unlike the label, an already linked row still
 * counts: saving the same answer twice is still saving an AI answer.
 */

/** The three columns, as a write. */
export interface AiMarkData {
  aiSource?: string | null;
  aiKind?: string | null;
  aiResult?: Prisma.InputJsonValue | Prisma.NullTypes.DbNull;
}

/** "Вернуть исходник": the row is plain again. */
export function aiClearData(): AiMarkData {
  return { aiSource: null, aiKind: null, aiResult: Prisma.DbNull };
}

/**
 * The columns to write with a save of parse [parseId]'s answer, or nothing when
 * the id is not one of [userId]'s rows of [kinds]. [currentSource] is the row's
 * `aiSource` before this save (null for a new row); [snapshot] the fields as
 * this save leaves them.
 */
export async function aiMarkFields(
  tx: Pick<Prisma.TransactionClient, "dictationParse">,
  userId: string,
  parseId: string | undefined,
  kinds: readonly ParseKind[],
  currentSource: string | null,
  snapshot: Prisma.InputJsonObject,
): Promise<AiMarkData> {
  if (parseId === undefined) return {};
  const parse = await tx.dictationParse.findFirst({
    where: { id: parseId, userId, kind: { in: [...kinds] } },
    select: { inputText: true, kind: true },
  });
  if (parse === null) return {};
  return currentSource === null
    ? { aiSource: parse.inputText, aiKind: parse.kind, aiResult: snapshot }
    : { aiResult: snapshot };
}
