import { Prisma } from "@prisma/client";

/*
 * The task as the API shows it (task editor, design/task-editor-spec.md §10).
 *
 * The row and the wire differ in two places, and only those:
 *
 * - the place reminder is four columns in the database (`locLat`, `locLng`,
 *   `locRadius`, `locLabel` -- four so that a CHECK can hold them together) and
 *   one `location` object, or null, everywhere else;
 * - `attachments` carries the pictures' metadata only. The files never travel
 *   with a task: the board is read on every cold start, and a picture is
 *   fetched when it is drawn (`GET /attachments/:id/thumb`).
 *
 * Everything else goes out exactly as stored, so every route that answers with
 * a task -- `GET /projects/:id/tasks`, `/board`, `/focus`, `POST`, `PATCH` --
 * passes its rows through `taskView` and nothing else.
 */

/** One item of a checklist, as stored and as sent. */
export interface ChecklistItem {
  id: string;
  text: string;
  done: boolean;
}

/** The place reminder, as the API shows it. */
export interface TaskLocation {
  lat: number;
  lng: number;
  radius: number;
  label: string;
}

/** What a task carries about each of its pictures. */
export const attachmentMetaSelect = {
  id: true,
  mime: true,
  width: true,
  height: true,
  sizeBytes: true,
  createdAt: true,
} as const satisfies Prisma.TaskAttachmentSelect;

/**
 * The `include` every task read uses, so that `taskView` has the pictures to
 * show. Oldest first: the strip on the editor grows to the right.
 */
export const taskInclude = {
  attachments: { select: attachmentMetaSelect, orderBy: { createdAt: "asc" } },
} as const satisfies Prisma.TaskInclude;

export type AttachmentMeta = Prisma.TaskAttachmentGetPayload<{
  select: typeof attachmentMetaSelect;
}>;

/** The columns `taskView` reads; any row that has them can be shown. */
interface TaskRowLike {
  checklist?: Prisma.JsonValue | null;
  locLat?: number | null;
  locLng?: number | null;
  locRadius?: number | null;
  locLabel?: string | null;
  attachments?: AttachmentMeta[];
}

/** The four columns as one object, or null when the task has no place. */
export function locationOf(row: TaskRowLike): TaskLocation | null {
  if (
    row.locLat === null ||
    row.locLat === undefined ||
    row.locLng === null ||
    row.locLng === undefined ||
    row.locRadius === null ||
    row.locRadius === undefined
  ) {
    return null;
  }
  return { lat: row.locLat, lng: row.locLng, radius: row.locRadius, label: row.locLabel ?? "" };
}

/** The stored checklist, or null for none (an empty list is stored as null too). */
export function checklistOf(row: TaskRowLike): ChecklistItem[] | null {
  const value = row.checklist;
  if (!Array.isArray(value) || value.length === 0) return null;
  return value as unknown as ChecklistItem[];
}

export type TaskView<T> = Omit<
  T,
  "locLat" | "locLng" | "locRadius" | "locLabel" | "checklist" | "attachments"
> & {
  checklist: ChecklistItem[] | null;
  location: TaskLocation | null;
  attachments: AttachmentMeta[];
};

/** A task row as the API answers with it. */
export function taskView<T extends TaskRowLike>(row: T): TaskView<T> {
  const rest = { ...row } as Record<string, unknown>;
  for (const column of ["locLat", "locLng", "locRadius", "locLabel"]) delete rest[column];
  return {
    ...rest,
    checklist: checklistOf(row),
    location: locationOf(row),
    attachments: row.attachments ?? [],
  } as TaskView<T>;
}

/**
 * The columns to write for a `location` from a request: `undefined` leaves
 * them alone, `null` clears all four, an object sets all four.
 */
export function locationColumns(location: TaskLocation | null | undefined):
  | {
      locLat: number | null;
      locLng: number | null;
      locRadius: number | null;
      locLabel: string | null;
    }
  | Record<string, never> {
  if (location === undefined) return {};
  if (location === null) return { locLat: null, locLng: null, locRadius: null, locLabel: null };
  return {
    locLat: location.lat,
    locLng: location.lng,
    locRadius: location.radius,
    locLabel: location.label,
  };
}

/**
 * The value to write for a `checklist` from a request: `undefined` leaves it
 * alone; `null` and `[]` both mean "no list" and are stored as SQL NULL
 * (`Prisma.DbNull` -- a plain `null` is refused for a `Json?` column).
 */
export function checklistColumn(
  checklist: ChecklistItem[] | null | undefined,
): { checklist: Prisma.InputJsonValue | typeof Prisma.DbNull } | Record<string, never> {
  if (checklist === undefined) return {};
  if (checklist === null || checklist.length === 0) return { checklist: Prisma.DbNull };
  return { checklist: checklist as unknown as Prisma.InputJsonValue };
}

/** Whether two checklists are the same list: same items, same order. */
export function sameChecklist(a: unknown, b: unknown): boolean {
  const left = Array.isArray(a) && a.length > 0 ? (a as ChecklistItem[]) : null;
  const right = Array.isArray(b) && b.length > 0 ? (b as ChecklistItem[]) : null;
  if (left === null || right === null) return left === right;
  if (left.length !== right.length) return false;
  return left.every((item, i) => {
    const other = right[i];
    return (
      other !== undefined &&
      item.id === other.id &&
      item.text === other.text &&
      item.done === other.done
    );
  });
}

/** Whether two places are the same place. */
export function sameLocation(a: unknown, b: unknown): boolean {
  const left = (a ?? null) as TaskLocation | null;
  const right = (b ?? null) as TaskLocation | null;
  if (left === null || right === null) return left === right;
  return (
    left.lat === right.lat &&
    left.lng === right.lng &&
    left.radius === right.radius &&
    (left.label ?? "") === (right.label ?? "")
  );
}
