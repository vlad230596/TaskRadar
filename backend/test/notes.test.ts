import { describe, it, expect, beforeAll, afterAll, beforeEach, vi } from "vitest";
import type { FastifyInstance } from "fastify";
import type { AuthConfig } from "../src/lib/authConfig";
import { inMemoryUsers, tokenFor, USER_A, USER_B } from "./support/users";

/*
 * The note routes, for what F15 added to them: a note saved from a "Причесать"
 * answer labels its dataset row with the note and what it says. Same shape as
 * the other route tests: no database here, Prisma is a small in-memory fake.
 *
 * Notes are owned through project -> scope -> userId. The fake evaluates that
 * owner filter against its rows, so the "another user's note / project / parse"
 * tests below exercise the filter itself rather than a stub that agrees.
 */
const prismaMock = vi.hoisted(() => ({
  project: { findFirst: vi.fn() },
  note: { findFirst: vi.fn(), findMany: vi.fn(), create: vi.fn(), update: vi.fn(), delete: vi.fn() },
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

interface NoteRow {
  id: string;
  projectId: string;
  title: string;
  content: string;
}

interface ProjectRow {
  id: string;
  name: string;
  scope: { userId: string };
}

interface ParseRow {
  id: string;
  userId: string;
  kind: string;
  linkedAt: Date | null;
  noteId?: string;
  finalTitle?: string | null;
}

let notes: NoteRow[] = [];
let projects: ProjectRow[] = [];
let parses: ParseRow[] = [];
let app: FastifyInstance;
/** User A's token -- what `call` sends unless told otherwise. */
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

const lastLink = () =>
  prismaMock.dictationParse.updateMany.mock.lastCall![0] as {
    where: unknown;
    data: Record<string, unknown>;
  };

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
  notes = [
    { id: "note-1", projectId: "prj-1", title: "Дача", content: "гвозди" },
    { id: "note-b1", projectId: "prj-b", title: "Гараж", content: "масло" },
  ];
  projects = [
    { id: "prj-1", name: "Дом", scope: { userId: USER_A.id } },
    { id: "prj-b", name: "Гараж", scope: { userId: USER_B.id } },
  ];
  parses = [
    { id: "dp-a", userId: USER_A.id, kind: "note", linkedAt: null },
    { id: "dp-b", userId: USER_B.id, kind: "note", linkedAt: null },
  ];
  for (const fn of Object.values(prismaMock.note)) fn.mockReset();
  prismaMock.project.findFirst.mockReset();
  prismaMock.dictationParse.updateMany.mockReset();
  prismaMock.$transaction.mockReset();

  // `{ id, scope: { userId } }` -- evaluated, and anything else is a loud failure.
  prismaMock.project.findFirst.mockImplementation(
    (args: { where: { id: string; scope: { userId: string } } }) => {
      if (Object.keys(args.where).sort().join() !== "id,scope") {
        throw new Error(`project.findFirst: unexpected where ${JSON.stringify(args.where)}`);
      }
      return (
        projects.find((p) => p.id === args.where.id && p.scope.userId === args.where.scope.userId) ??
        null
      );
    },
  );
  // A note is owned through its project: `{ id, project: { scope: { userId } } }`.
  prismaMock.note.findFirst.mockImplementation(
    (args: { where: { id: string; project: { scope: { userId: string } } } }) => {
      if (Object.keys(args.where).sort().join() !== "id,project") {
        throw new Error(`note.findFirst: unexpected where ${JSON.stringify(args.where)}`);
      }
      const note = notes.find((n) => n.id === args.where.id);
      const owner = projects.find((p) => p.id === note?.projectId);
      return note && owner?.scope.userId === args.where.project.scope.userId ? note : null;
    },
  );
  prismaMock.note.findMany.mockImplementation((args: { where: { projectId: string } }) =>
    notes.filter((n) => n.projectId === args.where.projectId),
  );
  prismaMock.note.delete.mockImplementation((args: { where: { id: string } }) => {
    const index = notes.findIndex((n) => n.id === args.where.id);
    return notes.splice(index, 1)[0]!;
  });
  // Labels the rows the way the database would: a parse of another user matches nothing.
  prismaMock.dictationParse.updateMany.mockImplementation(
    (args: {
      where: { id: string; userId: string; linkedAt: null; kind: { in: string[] } };
      data: Partial<ParseRow>;
    }) => {
      const hit = parses.filter(
        (p) =>
          p.id === args.where.id &&
          p.userId === args.where.userId &&
          p.linkedAt === null &&
          args.where.kind.in.includes(p.kind),
      );
      for (const p of hit) Object.assign(p, args.data);
      return { count: hit.length };
    },
  );
  prismaMock.note.create.mockImplementation((args: { data: Omit<NoteRow, "id"> }) => {
    const row = { id: `note-new-${notes.length}`, ...args.data };
    notes.push(row);
    return { ...row };
  });
  prismaMock.note.update.mockImplementation(
    (args: { where: { id: string }; data: Partial<NoteRow> }) => {
      const row = notes.find((n) => n.id === args.where.id)!;
      Object.assign(row, args.data);
      return { ...row };
    },
  );
  prismaMock.$transaction.mockImplementation((run: (tx: unknown) => unknown) => run(prismaMock));
});

describe("POST /projects/:projectId/notes", () => {
  it("labels a note made of a tidied answer with the note and its text", async () => {
    const res = await call("POST", "/projects/prj-1/notes", {
      title: "План",
      content: "- гвозди\n- краска",
      dictationParseId: "dp-2",
    });

    expect(res.statusCode).toBe(201);
    const note = res.json() as NoteRow;
    expect(lastLink().where).toEqual({
      id: "dp-2",
      userId: USER_A.id,
      linkedAt: null,
      kind: { in: ["note"] },
    });
    expect(lastLink().data).toMatchObject({
      noteId: note.id,
      finalTitle: "План",
      finalContent: "- гвозди\n- краска",
    });
    expect(lastLink().data.linkedAt).toBeInstanceOf(Date);
    // The note stores its own fields and nothing about the parse.
    const created = prismaMock.note.create.mock.calls[0]![0] as { data: object };
    expect(Object.keys(created.data).sort()).toEqual(["content", "projectId", "title"]);
  });

  it("touches no sample for a note that was typed", async () => {
    await call("POST", "/projects/prj-1/notes", { title: "Руками" });
    expect(prismaMock.dictationParse.updateMany).not.toHaveBeenCalled();
  });
});

describe("PATCH /notes/:id", () => {
  it("labels the sample with the note as saved", async () => {
    const res = await call("PATCH", "/notes/note-1", {
      content: "- гвозди, 100 шт.",
      dictationParseId: "dp-8",
    });

    expect(res.statusCode).toBe(200);
    expect(lastLink().data).toMatchObject({
      noteId: "note-1",
      finalTitle: "Дача",
      finalContent: "- гвозди, 100 шт.",
    });
  });

  it("refuses a body that carries only the sample's id", async () => {
    const res = await call("PATCH", "/notes/note-1", { dictationParseId: "dp-8" });
    expect(res.statusCode).toBe(400);
    expect(prismaMock.note.update).not.toHaveBeenCalled();
  });

  it("touches no sample for an ordinary edit", async () => {
    await call("PATCH", "/notes/note-1", { content: "руками" });
    expect(prismaMock.dictationParse.updateMany).not.toHaveBeenCalled();
    expect(notes[0]!.content).toBe("руками");
  });
});

describe("one user's notes are invisible to another", () => {
  // 404, not 403: the id of a note must not be confirmable by a stranger.
  const asB = (method: string, url: string, payload?: unknown) => call(method, url, payload, tokenB);

  it("404s for B on A's note, and changes nothing", async () => {
    const before = JSON.stringify(notes);

    expect((await asB("PATCH", "/notes/note-1", { content: "чужое" })).statusCode).toBe(404);
    expect((await asB("DELETE", "/notes/note-1")).statusCode).toBe(404);

    expect(JSON.stringify(notes)).toBe(before);
    expect(prismaMock.note.update).not.toHaveBeenCalled();
    expect(prismaMock.note.delete).not.toHaveBeenCalled();
    // ...while each owner can edit their own, and only their own.
    expect((await call("PATCH", "/notes/note-1", { content: "своё" })).statusCode).toBe(200);
    expect((await asB("PATCH", "/notes/note-b1", { content: "своё" })).statusCode).toBe(200);
    expect((await call("PATCH", "/notes/note-b1", { content: "чужое" })).statusCode).toBe(404);
  });

  it("will not create or list notes in someone else's project", async () => {
    const res = await asB("POST", "/projects/prj-1/notes", { title: "Подкинуто" });

    expect(res.statusCode).toBe(404);
    expect(notes.some((n) => n.title === "Подкинуто")).toBe(false);
    expect(prismaMock.$transaction).not.toHaveBeenCalled();
    expect((await asB("GET", "/projects/prj-1/notes")).statusCode).toBe(404);

    const mine = (await call("GET", "/projects/prj-1/notes")).json() as NoteRow[];
    expect(mine.map((n) => n.id)).toEqual(["note-1"]);
    const theirs = (await asB("GET", "/projects/prj-b/notes")).json() as NoteRow[];
    expect(theirs.map((n) => n.id)).toEqual(["note-b1"]);
  });

  it("does not link a sample of another user when a note is created with its id", async () => {
    // B saves a note in B's own project, carrying the id of A's parse.
    const res = await asB("POST", "/projects/prj-b/notes", { title: "План", dictationParseId: "dp-a" });

    expect(res.statusCode).toBe(201);
    expect(prismaMock.dictationParse.updateMany).toHaveBeenCalledTimes(1);
    expect(prismaMock.dictationParse.updateMany.mock.results[0]!.value).toEqual({ count: 0 });
    const parse = parses.find((p) => p.id === "dp-a")!;
    expect(parse.linkedAt).toBeNull();
    expect(parse.noteId).toBeUndefined();
    expect(parse.finalTitle).toBeUndefined();

    // Control: B's own parse is labelled by the same route.
    await asB("POST", "/projects/prj-b/notes", { title: "Свой", dictationParseId: "dp-b" });
    expect(parses.find((p) => p.id === "dp-b")!.finalTitle).toBe("Свой");
  });

  it("does not link a sample of another user when a note is edited with its id", async () => {
    const res = await call("PATCH", "/notes/note-1", { content: "новое", dictationParseId: "dp-b" });

    expect(res.statusCode).toBe(200);
    expect(notes.find((n) => n.id === "note-1")!.content).toBe("новое");
    expect(parses.find((p) => p.id === "dp-b")!.linkedAt).toBeNull();
  });
});
