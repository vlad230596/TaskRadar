import type { Prisma } from "@prisma/client";
import type { ParseKind } from "./parsePipeline";

/*
 * Labelling a dataset row with what was saved (F14, F15).
 *
 * A parse's answer is a proposal: the client shows it, the user corrects it,
 * and it is saved through the ordinary route for whatever it is -- a task, a
 * note, a sandbox line. That route is the one place that knows what was
 * finally kept, so it is the one that labels the row, when the client sends
 * the row's id along as `dictationParseId`. The label is what a replay of the
 * input is scored against (`./dictationReplay.ts`).
 *
 * WHY `updateMany`, AND WHY ONLY UNLABELLED ROWS
 *
 * `updateMany` with `linkedAt: null` turns an unknown id, a row of another
 * kind, and a row that is already labelled into a no-op rather than an error:
 * failing to label a sample must never fail saving what the user saved. And a
 * retried request -- or the same answer saved twice -- must not relabel the
 * row with a later edit: the label is the first save of the answer, the moment
 * the user decided it was right.
 *
 * WHY THE KIND IS CHECKED
 *
 * The id comes from the client. A `note` row labelled with a task would be a
 * sample whose input and label are different kinds of thing, and a replay of
 * notes would score the model against a task title.
 */

/** What a saved answer can be labelled with. Fields left out stay as they are. */
export interface ParseLabel {
  taskId?: string;
  noteId?: string;
  inboxItemId?: string;
  finalTitle?: string | null;
  finalDescription?: string | null;
  finalRemindAt?: Date | null;
  finalContent?: string | null;
}

/**
 * Labels row [parseId] with [label], if it is an unlabelled row of one of
 * [kinds]. Meant to run inside the transaction that saves the thing itself.
 */
export async function linkDictationParse(
  tx: Pick<Prisma.TransactionClient, "dictationParse">,
  userId: string,
  parseId: string,
  kinds: readonly ParseKind[],
  label: ParseLabel,
): Promise<void> {
  await tx.dictationParse.updateMany({
    where: { id: parseId, userId, linkedAt: null, kind: { in: [...kinds] } },
    data: { ...label, linkedAt: new Date() },
  });
}
