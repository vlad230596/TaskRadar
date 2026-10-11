import { describe, it, expect, beforeAll, afterAll, beforeEach, vi } from "vitest";
import type { FastifyInstance } from "fastify";
import type { AuthConfig } from "../src/lib/authConfig";
import { inMemoryUsers, tokenFor, USER_A, USER_B } from "./support/users";

/*
 * Task categories: their own routes, and the `categoryId` a task carries.
 * Same shape as the other route tests: no database here, Prisma is a small
 * in-memory fake that evaluates the owner filters it is sent and throws on any
 * `where` it does not recognise.
 *
 * Categories are owned through project -> scope -> userId; the seed holds a
 * second user's project and category, so the "another user's" cases exercise
 * the filter itself.
 */
const prismaMock = vi.hoisted(() => ({
  project: { findFirst: vi.fn() },
  taskCategory: {
    findFirst: vi.fn(),
    findMany: vi.fn(),
    aggregate: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
  },
  task: { findFirst: vi.fn(), aggregate: vi.fn(), create: vi.fn(), update: vi.fn() },
  taskEvent: { create: vi.fn() },
  dictationParse: { updateMany: vi.fn() },
  $transaction: vi.fn(),
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));

process.env.DATABASE_URL ??= "postgresql://placeholder:placeholder@localhost:5432/placeholder";

const baseConfig: AuthConfig = {
  email: USER_A.email,
  passwordHash: "$2b$04$zV5VFEALedx8Rfd/ucwUSOrHYSSr8xveuActiCTdzOmCsBSDTbYXO",
  jwtSecret: "test-jwt-secret-".repeat(4),
  cookieSecure: false,
};

interface ProjectRow {
  id: string;
  scope: { userId: string };
}

interface CategoryRow {
  id: string;
  projectId: string;
  name: string;
  position: number;
}

interface TaskRow {
  id: string;
  projectId: string;
  title: string;
  status: "pending" | "done" | "blocked";
  categoryId: string | null;
  remindAt: Date | null;
  focusedAt: Date | null;
}

let projects: ProjectRow[] = [];
let categories: CategoryRow[] = [];
let tasks: TaskRow[] = [];
let app: FastifyInstance;
let token: string;
let tokenB: string;

function call(method: string, url: string, payload?: unknown, bearer?: string) {
  return app.inject({
    method: method as "POST",
    url,
    headers: { authorization: `Bearer ${bearer ?? token}` },
    ...(payload === undefined ? {} : { payload: payload as Record<string, unknown> }),
  });
}

const ownerOf = (projectId: string) => projects.find((p) => p.id === projectId)?.scope.userId;

beforeAll(async () => {
  const { buildApp } = await import("../src/app");
  app = await buildApp({ authConfig: baseConfig, users: inMemoryUsers(), logger: false });
  await app.ready();
  token = await tokenFor(app, USER_A.email);
  tokenB = await tokenFor(app, USER_B.email);
});

afterAll(async () => {
  await app?.close();
});

beforeEach(() => {
  projects = [
    { id: "prj-1", scope: { userId: USER_A.id } },
    { id: "prj-2", scope: { userId: USER_A.id } },
    { id: "prj-b", scope: { userId: USER_B.id } },
  ];
  categories = [
    { id: "cat-2", projectId: "prj-1", name: "Документы", position: 2000 },
    { id: "cat-1", projectId: "prj-1", name: "Кухня", position: 1000 },
    { id: "cat-other", projectId: "prj-2", name: "Чужой проект", position: 1000 },
    { id: "cat-b", projectId: "prj-b", name: "Гараж", position: 1000 },
  ];
  tasks = [
    {
      id: "tsk-1",
      projectId: "prj-1",
      title: "Починить кран",
      status: "pending",
      categoryId: null,
      remindAt: null,
      focusedAt: null,
    },
  ];

  for (const group of [prismaMock.taskCategory, prismaMock.task, prismaMock.taskEvent]) {
    for (const fn of Object.values(group)) fn.mockReset();
  }
  prismaMock.project.findFirst.mockReset();
  prismaMock.$transaction.mockReset();

  prismaMock.project.findFirst.mockImplementation(
    (args: { where: { id: string; scope: { userId: string } } }) => {
      if (Object.keys(args.where).sort().join() !== "id,scope") {
        throw new Error(`project.findFirst: unexpected where ${JSON.stringify(args.where)}`);
      }
      return projects.find((p) => p.id === args.where.id && p.scope.userId === args.where.scope.userId) ?? null;
    },
  );

  // Three shapes: by owner (`id, project`), by project (`id, projectId`), and
  // the name clash check (`projectId, name[, id: { not }]`).
  prismaMock.taskCategory.findFirst.mockImplementation(
    (args: {
      where: {
        id?: string | { not: string };
        projectId?: string;
        project?: { scope: { userId: string } };
        name?: { equals: string; mode: "insensitive" };
      };
    }) => {
      const where = args.where;
      const keys = Object.keys(where).sort().join();
      if (keys === "id,project") {
        const row = categories.find((c) => c.id === where.id);
        return row && ownerOf(row.projectId) === where.project!.scope.userId ? row : null;
      }
      if (keys === "id,projectId") {
        return categories.find((c) => c.id === where.id && c.projectId === where.projectId) ?? null;
      }
      if (keys === "name,projectId" || keys === "id,name,projectId") {
        const except = typeof where.id === "object" ? where.id.not : undefined;
        return (
          categories.find(
            (c) =>
              c.projectId === where.projectId &&
              c.id !== except &&
              c.name.toLowerCase() === where.name!.equals.toLowerCase(),
          ) ?? null
        );
      }
      throw new Error(`taskCategory.findFirst: unexpected where ${JSON.stringify(where)}`);
    },
  );
  prismaMock.taskCategory.findMany.mockImplementation(
    (args: { where: { projectId: string }; orderBy: { position: "asc" } }) =>
      categories.filter((c) => c.projectId === args.where.projectId).sort((a, b) => a.position - b.position),
  );
  prismaMock.taskCategory.aggregate.mockImplementation((args: { where: { projectId: string } }) => {
    const mine = categories.filter((c) => c.projectId === args.where.projectId);
    return { _max: { position: mine.length ? Math.max(...mine.map((c) => c.position)) : null } };
  });
  prismaMock.taskCategory.create.mockImplementation((args: { data: Omit<CategoryRow, "id"> }) => {
    const row = { id: `cat-new-${categories.length}`, ...args.data };
    categories.push(row);
    return { ...row };
  });
  prismaMock.taskCategory.update.mockImplementation(
    (args: { where: { id: string }; data: Partial<CategoryRow> }) => {
      const row = categories.find((c) => c.id === args.where.id)!;
      Object.assign(row, args.data);
      return { ...row };
    },
  );
  // What the foreign key does: the category goes, its tasks are ungrouped.
  prismaMock.taskCategory.delete.mockImplementation((args: { where: { id: string } }) => {
    const index = categories.findIndex((c) => c.id === args.where.id);
    for (const t of tasks) if (t.categoryId === args.where.id) t.categoryId = null;
    return categories.splice(index, 1)[0]!;
  });

  prismaMock.task.findFirst.mockImplementation(
    (args: { where: { id: string; project: { scope: { userId: string } } } }) => {
      const row = tasks.find((t) => t.id === args.where.id);
      return row && ownerOf(row.projectId) === args.where.project.scope.userId ? { ...row } : null;
    },
  );
  prismaMock.task.aggregate.mockImplementation(() => ({ _max: { position: 1000 } }));
  prismaMock.task.create.mockImplementation((args: { data: Omit<TaskRow, "id"> }) => {
    const row = { id: `tsk-new-${tasks.length}`, status: "pending" as const, focusedAt: null, ...args.data };
    tasks.push(row);
    return { ...row };
  });
  prismaMock.task.update.mockImplementation((args: { where: { id: string }; data: Partial<TaskRow> }) => {
    const row = tasks.find((t) => t.id === args.where.id)!;
    Object.assign(row, args.data);
    return { ...row };
  });
  prismaMock.taskEvent.create.mockImplementation(() => ({}));
  prismaMock.$transaction.mockImplementation((run: (tx: unknown) => unknown) => run(prismaMock));
});

describe("GET /projects/:projectId/categories", () => {
  it("lists the project's own categories in position order", async () => {
    const res = await call("GET", "/projects/prj-1/categories");
    expect(res.statusCode).toBe(200);
    expect(res.json().map((c: CategoryRow) => c.name)).toEqual(["Кухня", "Документы"]);
  });

  it("404s for another user's project", async () => {
    const res = await call("GET", "/projects/prj-b/categories");
    expect(res.statusCode).toBe(404);
  });
});

describe("POST /projects/:projectId/categories", () => {
  it("appends a trimmed name after the last category", async () => {
    const res = await call("POST", "/projects/prj-1/categories", { name: "  Закупки " });
    expect(res.statusCode).toBe(201);
    expect(res.json()).toMatchObject({ projectId: "prj-1", name: "Закупки", position: 3000 });
  });

  it("refuses a name the project already has, whatever its case", async () => {
    const res = await call("POST", "/projects/prj-1/categories", { name: "кухня" });
    expect(res.statusCode).toBe(409);
    expect(prismaMock.taskCategory.create).not.toHaveBeenCalled();
  });

  it("allows the same name in another project", async () => {
    const res = await call("POST", "/projects/prj-2/categories", { name: "Кухня" });
    expect(res.statusCode).toBe(201);
  });

  it("refuses an empty name", async () => {
    const res = await call("POST", "/projects/prj-1/categories", { name: "   " });
    expect(res.statusCode).toBe(400);
  });

  it("404s for another user's project", async () => {
    const res = await call("POST", "/projects/prj-b/categories", { name: "Моё" });
    expect(res.statusCode).toBe(404);
  });
});

describe("PATCH /categories/:id", () => {
  it("renames", async () => {
    const res = await call("PATCH", "/categories/cat-1", { name: "Ванная" });
    expect(res.statusCode).toBe(200);
    expect(res.json().name).toBe("Ванная");
  });

  it("lets a category keep its own name in another case", async () => {
    const res = await call("PATCH", "/categories/cat-1", { name: "КУХНЯ" });
    expect(res.statusCode).toBe(200);
  });

  it("refuses the name of a sibling", async () => {
    const res = await call("PATCH", "/categories/cat-1", { name: "документы" });
    expect(res.statusCode).toBe(409);
  });

  it("404s for another user's category", async () => {
    const res = await call("PATCH", "/categories/cat-b", { name: "Моё" });
    expect(res.statusCode).toBe(404);
  });
});

describe("DELETE /categories/:id", () => {
  it("removes the category and leaves its tasks ungrouped", async () => {
    tasks[0]!.categoryId = "cat-1";
    const res = await call("DELETE", "/categories/cat-1");
    expect(res.statusCode).toBe(204);
    expect(categories.some((c) => c.id === "cat-1")).toBe(false);
    expect(tasks[0]).toMatchObject({ id: "tsk-1", categoryId: null });
  });

  it("404s for another user's category, and B may delete their own", async () => {
    expect((await call("DELETE", "/categories/cat-b")).statusCode).toBe(404);
    expect((await call("DELETE", "/categories/cat-b", undefined, tokenB)).statusCode).toBe(204);
  });
});

describe("a task's category", () => {
  it("is set when the task is created", async () => {
    const res = await call("POST", "/projects/prj-1/tasks", { title: "Плитка", categoryId: "cat-1" });
    expect(res.statusCode).toBe(201);
    expect(res.json().categoryId).toBe("cat-1");
  });

  it("is null for a task created without one", async () => {
    const res = await call("POST", "/projects/prj-1/tasks", { title: "Плитка" });
    expect(res.json().categoryId).toBeNull();
  });

  it("is changed and cleared through PATCH", async () => {
    let res = await call("PATCH", "/tasks/tsk-1", { categoryId: "cat-2" });
    expect(res.statusCode).toBe(200);
    expect(res.json().categoryId).toBe("cat-2");

    res = await call("PATCH", "/tasks/tsk-1", { categoryId: null });
    expect(res.statusCode).toBe(200);
    expect(res.json().categoryId).toBeNull();
  });

  it("must be a category of the task's own project", async () => {
    const other = await call("PATCH", "/tasks/tsk-1", { categoryId: "cat-other" });
    expect(other.statusCode).toBe(400);
    const foreign = await call("POST", "/projects/prj-1/tasks", { title: "Плитка", categoryId: "cat-b" });
    expect(foreign.statusCode).toBe(400);
    expect(prismaMock.task.create).not.toHaveBeenCalled();
    expect(tasks[0]!.categoryId).toBeNull();
  });
});
