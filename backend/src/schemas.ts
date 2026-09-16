import { z } from "zod";

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

// ---- Projects ----

export const createProjectSchema = z.object({
  name: z.string().trim().min(1, "name is required"),
});

/**
 * Body of `PATCH /projects/:id`.
 *
 * Intentionally the very same schema object as `createProjectSchema`, not a
 * copy: a name that is acceptable when a project is created must stay acceptable
 * when it is corrected, and aliasing makes the two impossible to drift apart
 * (same trim, same "name is required", same 400 body).
 *
 * `name` is required rather than optional-with-a-refine, unlike
 * `updateNoteSchema` and `updateTaskSchema`. Those carry several editable fields
 * and need "at least one of them"; a project has exactly one, so making it
 * optional would only buy the ability to send `{}` and have nothing happen. If a
 * second editable field is ever added, this stops being an alias and grows the
 * same optional/refine shape as the others.
 */
export const updateProjectSchema = createProjectSchema;

export const listProjectsQuerySchema = z.object({
  archived: z.enum(["true", "false"]).optional(),
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
