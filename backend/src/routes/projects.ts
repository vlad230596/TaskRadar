import { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma";
import { NotFoundError, ConflictError } from "../lib/errors";
import { canHardDeleteProject } from "../domain/projectDeleteGuard";
import {
  createProjectSchema,
  updateProjectSchema,
  listProjectsQuerySchema,
  idParamSchema,
} from "../schemas";

/*
 * Loads a project by id, or answers 404. **Archived projects are returned like
 * any other** -- this checks existence and nothing else.
 *
 * It used to be called `getActiveProjectOrThrow`, which was wrong in the one way
 * a name can be: it described a filter the function never had. Nothing read
 * `archivedAt` here, so every route built on it -- `GET /projects/:id`, the task
 * and note routes, archive/unarchive/delete, and now `PATCH /projects/:id` --
 * has always worked on archived projects too. Comments elsewhere took the old
 * name at face value and claimed a restriction the code did not implement; the
 * rename is so that reading the call site tells the truth.
 *
 * WHY archived projects stay readable *and* writable, deliberately:
 *
 * The archive here is the reversible half of the pair borrowed from Trello
 * (`project-tracker-brief.md`: reversible archive, irreversible delete reachable
 * only behind it; see also B6 in `flutter-migration-plan.md`). "Reversible"
 * means an archived project is a live row that can come back, not a tombstone --
 * so freezing its contents would be a second, unstated meaning of archiving that
 * nothing else in the product implies. Two concrete cases depend on it:
 *
 * - the client opens a task from a reminder notification that was armed weeks
 *   earlier, in a project archived since. A 404 there would dead-end the one
 *   feature this product exists for;
 * - the archive screen is exactly where a badly named old project is looked at,
 *   so renaming it there must work without an unarchive/rename/re-archive dance.
 *
 * What *is* gated stays gated, and by its own guard rather than by this helper:
 * `DELETE` refuses an unarchived project (`canHardDeleteProject`), and the
 * board/list queries filter on `archivedAt` themselves so an archived project
 * still leaves the board and stops raising reminders.
 */
export async function getProjectOrThrow(projectId: string) {
  const project = await prisma.project.findUnique({ where: { id: projectId } });
  if (!project) {
    throw new NotFoundError("Project");
  }
  return project;
}

export async function projectRoutes(app: FastifyInstance): Promise<void> {
  app.post("/projects", async (request, reply) => {
    const body = createProjectSchema.parse(request.body);
    const project = await prisma.project.create({ data: { name: body.name } });
    reply.status(201).send(project);
  });

  app.get("/projects", async (request, reply) => {
    const query = listProjectsQuerySchema.parse(request.query);
    const showArchived = query.archived === "true";

    const projects = await prisma.project.findMany({
      where: {
        archivedAt: showArchived ? { not: null } : null,
      },
      orderBy: { createdAt: "asc" },
    });
    reply.send(projects);
  });

  app.get("/projects/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const project = await getProjectOrThrow(id);
    reply.send(project);
  });

  /*
   * Rename. The only mutable field a project has, and until now it had none at
   * all -- a project could be created, read, archived, unarchived and deleted,
   * so a typo in a name was permanent short of deleting the project and losing
   * its tasks and notes with it.
   *
   * ARCHIVED PROJECTS CAN BE RENAMED, on purpose.
   *
   * The tempting alternative is to reject a rename on an archived project the
   * way `DELETE` insists on archiving first -- "archived means frozen". Two
   * things in this codebase say otherwise.
   *
   * First, archiving here is explicitly the reversible half of a pair borrowed
   * from Trello (project-tracker-brief.md: "в Trello архив списка обратим, а
   * удаление возможно только после архивации и необратимо"). Reversible means
   * the project is still a live row that can come back, not a tombstone. The
   * irreversible operation is the one that needs a gate, and it already has one.
   *
   * Second, `getProjectOrThrow` does not filter on `archivedAt` -- see the note
   * on it above, including why it is no longer called "Active" -- and every route
   * that uses it therefore already works on archived projects: `GET /projects/:id`
   * returns them, and tasks and notes can be created and edited inside them.
   * Forbidding rename alone would make this the single route in the app where
   * archiving freezes something, which is a rule nobody could infer from the
   * others.
   *
   * The practical case settles it: the archive screen is exactly where an old,
   * badly named project is looked at, and the only reason to rename one is to
   * make it findable later. Refusing here would just force an
   * unarchive/rename/re-archive dance that changes `archivedAt` -- i.e. edits
   * more state than the rename itself -- to achieve the same result.
   *
   * `archivedAt` is not in the update payload, so a rename cannot resurrect a
   * project or archive it as a side effect; `/archive` and `/unarchive` stay the
   * only routes that move a project between the two states.
   */
  app.patch("/projects/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const body = updateProjectSchema.parse(request.body);
    // Existence is checked first so a missing project answers 404 rather than
    // whatever Prisma raises for an update against no rows (P2025, which the
    // error handler would turn into an opaque 500).
    await getProjectOrThrow(id);

    const project = await prisma.project.update({
      where: { id },
      data: { name: body.name },
    });
    reply.send(project);
  });

  app.post("/projects/:id/archive", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    await getProjectOrThrow(id);
    const project = await prisma.project.update({
      where: { id },
      data: { archivedAt: new Date() },
    });
    reply.send(project);
  });

  app.post("/projects/:id/unarchive", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    await getProjectOrThrow(id);
    const project = await prisma.project.update({
      where: { id },
      data: { archivedAt: null },
    });
    reply.send(project);
  });

  app.delete("/projects/:id", async (request, reply) => {
    const { id } = idParamSchema.parse(request.params);
    const project = await getProjectOrThrow(id);

    if (!canHardDeleteProject(project)) {
      throw new ConflictError("Project must be archived before it can be deleted");
    }

    await prisma.project.delete({ where: { id } });
    reply.status(204).send();
  });
}
