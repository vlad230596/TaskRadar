import { describe, it, expect, beforeAll, afterAll, beforeEach, vi } from "vitest";
import type { FastifyInstance } from "fastify";
import type { AuthConfig } from "../src/lib/authConfig";

/*
 * The note routes, for what F15 added to them: a note saved from a "Причесать"
 * answer labels its dataset row with the note and what it says. Same shape as
 * the other route tests: no database here, Prisma is a small in-memory fake.
 */
const prismaMock = vi.hoisted(() => ({
  project: { findUnique: vi.fn() },
  note: { findUnique: vi.fn(), create: vi.fn(), update: vi.fn() },
  dictationParse: { updateMany: vi.fn() },
  $transaction: vi.fn(),
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));

process.env.DATABASE_URL ??= "postgresql://placeholder:placeholder@localhost:5432/placeholder";

const TEST_PASSWORD = "test-password-not-the-real-one";
const baseConfig: AuthConfig = {
  email: "owner@example.com",
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

let notes: NoteRow[] = [];
let app: FastifyInstance;
let token: string;

function call(method: string, url: string, payload?: unknown) {
  return app.inject({
    method: method as "POST",
    url,
    headers: { authorization: `Bearer ${token}` },
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
  app = await buildApp({ authConfig: baseConfig, logger: false });
  await app.ready();
  const login = await app.inject({
    method: "POST",
    url: "/auth/login",
    payload: { email: baseConfig.email, password: TEST_PASSWORD },
  });
  token = (login.json() as { token: string }).token;
});

afterAll(async () => {
  await app?.close();
});

beforeEach(() => {
  notes = [{ id: "note-1", projectId: "prj-1", title: "Дача", content: "гвозди" }];
  for (const fn of Object.values(prismaMock.note)) fn.mockReset();
  prismaMock.project.findUnique.mockReset();
  prismaMock.dictationParse.updateMany.mockReset();
  prismaMock.dictationParse.updateMany.mockResolvedValue({ count: 1 });
  prismaMock.$transaction.mockReset();

  prismaMock.project.findUnique.mockImplementation((args: { where: { id: string } }) =>
    args.where.id === "prj-1" ? { id: "prj-1", name: "Дом" } : null,
  );
  prismaMock.note.findUnique.mockImplementation(
    (args: { where: { id: string } }) => notes.find((n) => n.id === args.where.id) ?? null,
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
    expect(lastLink().where).toEqual({ id: "dp-2", linkedAt: null, kind: { in: ["note"] } });
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
