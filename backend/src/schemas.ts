import { z } from "zod";
import { HISTORY_RANGES } from "./domain/history";

export const taskStatusSchema = z.enum(["pending", "done", "blocked"]);

// ---- Auth ----

/**
 * Login payload.
 *
 * `email` is intentionally a plain non-empty string rather than a strict email
 * format check: it is compared against one configured address anyway, and keeping
 * every bad credential a uniform 401 avoids a second response class (400) that
 * would behave differently for some wrong inputs than others.
 *
 * The max lengths bound the work done per request -- bcrypt only reads the first
 * 72 bytes of a password, so there is no reason to hash a huge submitted string.
 */
export const loginSchema = z.object({
  email: z.string().trim().min(1, "email is required").max(320),
  password: z.string().min(1, "password is required").max(512),
});

// ---- Params ----

export const idParamSchema = z.object({
  id: z.string().min(1),
});

export const projectIdParamSchema = z.object({
  projectId: z.string().min(1),
});

// ---- Scopes ----

/**
 * A scope is a space projects live in: "work at company A", "home", "the
 * dacha". The board shows exactly one at a time (F7).
 *
 * One field, same shape as a project's name and for the same reasons -- see the
 * note on `updateProjectSchema` below about when an alias stops being enough.
 */
export const createScopeSchema = z.object({
  name: z.string().trim().min(1, "name is required"),
});

export const updateScopeSchema = createScopeSchema;

/**
 * Body of `PATCH /scopes/:id/position`.
 *
 * Deliberately identical in shape to `updateTaskPositionSchema`: both answer
 * "put this between those two", both take neighbours **by id** rather than a
 * target index, and both accept `null` for "no neighbour on that side". Naming
 * the neighbours by id is what survives a rebalance -- see
 * src/domain/position.ts.
 */
export const updateScopePositionSchema = z
  .object({
    beforeScopeId: z.string().min(1).nullable().optional(),
    afterScopeId: z.string().min(1).nullable().optional(),
  })
  .refine((body) => body.beforeScopeId !== undefined || body.afterScopeId !== undefined, {
    message:
      "At least one of beforeScopeId/afterScopeId must be provided (use null for 'no neighbour on that side')",
  });

// ---- Projects ----

export const createProjectSchema = z.object({
  name: z.string().trim().min(1, "name is required"),
  /**
   * Which scope the project is created in (F7).
   *
   * Optional, and the route falls back to the first scope by position. That
   * default is not laziness about validation: it keeps `POST /projects {name}`
   * -- a curl one-liner, a seed script, anything written before scopes existed
   * -- working exactly as it did, and there is always at least one scope for it
   * to mean (the migration seeds one). The client always sends it, because the
   * board it was created from is already showing one specific scope.
   */
  scopeId: z.string().min(1).optional(),
});

/**
 * Body of `PATCH /projects/:id`: rename, move to another scope, or both.
 *
 * This used to be an alias of `createProjectSchema`, with a note saying it
 * would stop being one as soon as a project had a second editable field. F7 is
 * that moment: a project can now be moved between scopes, and a PATCH that
 * demanded a `name` in order to change a `scopeId` would force every move to
 * rewrite the name too.
 *
 * The rules that made the alias worth having are kept by construction -- the
 * `name` rule below is the same trim and the same message as when a project is
 * created, so a name that is acceptable at creation stays acceptable at
 * correction. What changes is that both fields are optional and at least one
 * must be present, which is the shape `updateTaskSchema` and `updateNoteSchema`
 * already use.
 *
 * `archivedAt` is still not here: `/archive` and `/unarchive` remain the only
 * routes that move a project between those two states, so neither a rename nor
 * a move between scopes can resurrect or hide a project as a side effect.
 */
export const updateProjectSchema = z
  .object({
    name: z.string().trim().min(1, "name is required").optional(),
    scopeId: z.string().min(1).optional(),
  })
  .refine((body) => Object.keys(body).length > 0, {
    message: "At least one field must be provided",
  });

/**
 * Query for `GET /projects`, and (aliased below) for `GET /board`.
 *
 * `scopeId` filters to one space. It is optional, and **the Flutter client does
 * not use it for the board** -- it asks for every project and filters locally.
 * That is deliberate and worth stating here, because the parameter existing
 * invites the opposite: local reminders are armed from the board snapshot, so a
 * server-filtered board would silently stop raising reminders for every scope
 * the user is not currently looking at. Switching scopes also becomes instant
 * and offline-capable when the whole board is already in memory. The filter
 * stays for curl, for scripts, and for a future client that pages.
 */
export const listProjectsQuerySchema = z.object({
  archived: z.enum(["true", "false"]).optional(),
  scopeId: z.string().min(1).optional(),
});

// ---- Board ----

/**
 * Query for `GET /board`.
 *
 * Intentionally the very same schema object as `listProjectsQuerySchema`, not a
 * copy: `/board` is `GET /projects` with the tasks already attached, so the two
 * must accept and reject exactly the same `archived` values forever. Aliasing
 * makes that impossible to get wrong, and puts the note here -- where anyone
 * editing the projects query will read it -- rather than in the board route.
 */
export const boardQuerySchema = listProjectsQuerySchema;

// ---- Tasks ----

export const createTaskSchema = z.object({
  title: z.string().trim().min(1, "title is required"),
  description: z.string().nullable().optional(),
  status: taskStatusSchema.optional(),
  remindAt: z.coerce.date().nullable().optional(),
});

export const updateTaskSchema = z
  .object({
    title: z.string().trim().min(1, "title is required").optional(),
    description: z.string().nullable().optional(),
    status: taskStatusSchema.optional(),
    remindAt: z.coerce.date().nullable().optional(),
  })
  .refine((body) => Object.keys(body).length > 0, {
    message: "At least one field must be provided",
  });

export const updateTaskPositionSchema = z
  .object({
    beforeTaskId: z.string().min(1).nullable().optional(),
    afterTaskId: z.string().min(1).nullable().optional(),
  })
  .refine((body) => body.beforeTaskId !== undefined || body.afterTaskId !== undefined, {
    message: "At least one of beforeTaskId/afterTaskId must be provided (use null for 'no neighbour on that side')",
  });

// ---- History (F11) ----

/**
 * Query for `GET /history` -- the whole history screen in one response.
 *
 * `range` is the period the two counting blocks cover. A closed set of three
 * rather than a free number of days, because the screen offers exactly three
 * buttons and an arbitrary window would have to define what "48 days" means for
 * the bar chart's axis. "Висит дольше всего" ignores it entirely -- a task that
 * has hung for two months is the answer to that question whatever window is
 * selected -- which is stated here because the parameter's name suggests
 * otherwise.
 *
 * `tzOffsetMinutes` is the client's own UTC offset, in the sign JavaScript's
 * `Date.getTimezoneOffset()` does NOT use (this is minutes to ADD to UTC, so
 * Moscow is +180). The server stores instants and the screen shows days, and
 * only the client knows which days those are; the default of 0 keeps `curl
 * /history` meaningful without it. Bounded at ±14h because that is the widest
 * real offset, so a nonsense value is a 400 rather than a chart shifted by a
 * year.
 *
 * `staleLimit` is how many of the longest-hanging tasks to return. Capped
 * because this is the one block whose cost grows with the number of open tasks:
 * each row replays that task's journal.
 */
export const historyQuerySchema = z.object({
  range: z.enum(HISTORY_RANGES).default("30d"),
  tzOffsetMinutes: z.coerce.number().int().min(-840).max(840).default(0),
  staleLimit: z.coerce.number().int().min(1).max(50).default(5),
});

// ---- Inbox (F8) ----

/**
 * A captured line of text, before it is anything else.
 *
 * One field, and the same trim/non-empty rule as a task title -- because that
 * is what it becomes when it is filed. Deliberately *not* `createTaskSchema`
 * aliased: an inbox item has no status, no description and no reminder date,
 * and accepting them here would be accepting a second, parallel way to create
 * work that never reaches a project.
 */
export const createInboxItemSchema = z.object({
  text: z.string().trim().min(1, "text is required"),

  /**
   * Idempotency key for offline capture (F8.1), generated by the client.
   *
   * Optional, and that is the whole contract change F8.1 asks for. A client
   * with a queue (the phone) stamps every line it captures with a key it keeps
   * next to the text, so that replaying a request whose answer was lost yields
   * the same row instead of a twin. A client without a queue (curl, a browser
   * at a desk) sends nothing and gets the old behaviour.
   *
   * The bounds are a sanity check rather than a format: any string the client
   * can keep stable is a valid key -- a UUID today -- and pinning the format
   * here would mean a client that changed its generator needed a server
   * release.
   */
  captureKey: z.string().trim().min(8, "captureKey is too short").max(100).optional(),
});

/** Body of `PATCH /inbox/:id`. Only the text; the key is set once, at capture. */
export const updateInboxItemSchema = z.object({
  text: z.string().trim().min(1, "text is required"),
});

/** Body of `POST /inbox/:id/file`: which project the item becomes a task in. */
export const fileInboxItemSchema = z.object({
  projectId: z.string().min(1, "projectId is required"),
});

// ---- Notes ----

export const createNoteSchema = z.object({
  title: z.string().trim().min(1, "title is required"),
  content: z.string().optional().default(""),
});

export const updateNoteSchema = z
  .object({
    title: z.string().trim().min(1, "title is required").optional(),
    content: z.string().optional(),
  })
  .refine((body) => Object.keys(body).length > 0, {
    message: "At least one field must be provided",
  });
