import { describe, it, expect, beforeAll, afterAll, beforeEach, vi } from "vitest";
import { existsSync, mkdtempSync, readdirSync, rmSync, unlinkSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { crc32 } from "node:zlib";
import { randomBytes } from "node:crypto";
import sharp from "sharp";
import type { FastifyInstance } from "fastify";
import type { AuthConfig } from "../src/lib/authConfig";
import { inMemoryUsers, tokenFor, USER_A, USER_B } from "./support/users";
import { sniffImage, stripPngMetadata, stripWebpMetadata } from "../src/domain/attachmentImage";
import {
  DEFAULT_ATTACHMENT_LIMITS,
  attachmentIdOf,
  fileAttachmentStore,
  loadAttachmentLimits,
  planSweep,
  type AttachmentLimits,
} from "../src/domain/attachmentStore";

/*
 * Pictures on a task (task editor, design/task-editor-spec.md §10), through the
 * routes, with real files in a temporary directory and real image processing
 * (sharp). Prisma is a fake over two small tables, evaluating the owner filters
 * the routes send -- the same approach as the other route tests.
 */
const prismaMock = vi.hoisted(() => ({
  task: { findFirst: vi.fn() },
  taskAttachment: {
    findUnique: vi.fn(),
    findFirst: vi.fn(),
    count: vi.fn(),
    aggregate: vi.fn(),
    create: vi.fn(),
    delete: vi.fn(),
  },
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));

process.env.DATABASE_URL ??= "postgresql://placeholder:placeholder@localhost:5432/placeholder";

const baseConfig: AuthConfig = {
  email: USER_A.email,
  passwordHash: "$2b$04$zV5VFEALedx8Rfd/ucwUSOrHYSSr8xveuActiCTdzOmCsBSDTbYXO",
  jwtSecret: "test-jwt-secret-".repeat(4),
  cookieSecure: false,
};

interface Row {
  id: string;
  taskId: string;
  uploadKey: string;
  mime: string;
  sizeBytes: number;
  width: number;
  height: number;
  sha256: string;
  createdAt: Date;
}

const TASK_OWNER: Record<string, string> = {
  "t-a": USER_A.id,
  "t-a2": USER_A.id,
  "t-b": USER_B.id,
};
let rows: Row[] = [];

type OwnerWhere = { project: { scope: { userId: string } } };

function installFakes(): void {
  rows = [];
  prismaMock.task.findFirst.mockImplementation(
    ({ where }: { where: { id: string } & OwnerWhere }) => {
      const owner = TASK_OWNER[where.id];
      return owner !== undefined && owner === where.project.scope.userId
        ? { id: where.id, projectId: "p" }
        : null;
    },
  );
  prismaMock.taskAttachment.findUnique.mockImplementation(
    ({ where }: { where: { taskId_uploadKey: { taskId: string; uploadKey: string } } }) =>
      rows.find(
        (r) =>
          r.taskId === where.taskId_uploadKey.taskId &&
          r.uploadKey === where.taskId_uploadKey.uploadKey,
      ) ?? null,
  );
  prismaMock.taskAttachment.findFirst.mockImplementation(
    ({ where }: { where: { id: string; task: OwnerWhere } }) =>
      rows.find(
        (r) => r.id === where.id && TASK_OWNER[r.taskId] === where.task.project.scope.userId,
      ) ?? null,
  );
  prismaMock.taskAttachment.count.mockImplementation(
    ({ where }: { where: { taskId: string } }) =>
      rows.filter((r) => r.taskId === where.taskId).length,
  );
  prismaMock.taskAttachment.aggregate.mockImplementation(
    ({ where }: { where: { task: OwnerWhere } }) => {
      const mine = rows.filter((r) => TASK_OWNER[r.taskId] === where.task.project.scope.userId);
      return {
        _sum: { sizeBytes: mine.length ? mine.reduce((s, r) => s + r.sizeBytes, 0) : null },
      };
    },
  );
  prismaMock.taskAttachment.create.mockImplementation(
    ({ data }: { data: Omit<Row, "createdAt"> }) => {
      if (rows.some((r) => r.taskId === data.taskId && r.uploadKey === data.uploadKey)) {
        throw Object.assign(new Error("Unique constraint failed"), { code: "P2002" });
      }
      const row = { ...data, createdAt: new Date("2026-11-11T10:00:00.000Z") };
      rows.push(row);
      return { ...row };
    },
  );
  prismaMock.taskAttachment.delete.mockImplementation(({ where }: { where: { id: string } }) => {
    const index = rows.findIndex((r) => r.id === where.id);
    if (index < 0) throw new Error("delete against no row");
    return rows.splice(index, 1)[0];
  });
}

// ---- Images ----

function pngChunk(type: string, data: Buffer): Buffer {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "latin1"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
}

/** A PNG with text and EXIF chunks inserted before IEND. */
async function pngWithMetadata(): Promise<Buffer> {
  const plain = await sharp({
    create: { width: 64, height: 32, channels: 3, background: { r: 200, g: 10, b: 10 } },
  })
    .png()
    .toBuffer();
  const iend = plain.length - 12;
  return Buffer.concat([
    plain.subarray(0, iend),
    pngChunk("tEXt", Buffer.from("Comment\0secret place", "latin1")),
    pngChunk("eXIf", Buffer.from("MM\0*fake-gps", "latin1")),
    plain.subarray(iend),
  ]);
}

/** A JPEG whose EXIF says "rotate 90°" and carries a description. */
async function jpegWithExif(): Promise<Buffer> {
  return sharp({
    create: { width: 80, height: 40, channels: 3, background: { r: 10, g: 200, b: 10 } },
  })
    .jpeg()
    .withExif({ IFD0: { ImageDescription: "secret place" } })
    .withMetadata({ orientation: 6 })
    .toBuffer();
}

async function webpWithExif(): Promise<Buffer> {
  return sharp({
    create: { width: 30, height: 20, channels: 3, background: { r: 10, g: 10, b: 200 } },
  })
    .webp({ quality: 80 })
    .withExif({ IFD0: { ImageDescription: "secret place" } })
    .toBuffer();
}

// ---- Requests ----

const BOUNDARY = "----taskradar-test-boundary";

function multipart(
  parts: { name: string; value: string | Buffer; filename?: string; type?: string }[],
) {
  const chunks: Buffer[] = [];
  for (const part of parts) {
    const disposition = part.filename
      ? `form-data; name="${part.name}"; filename="${part.filename}"`
      : `form-data; name="${part.name}"`;
    const headers =
      `--${BOUNDARY}\r\nContent-Disposition: ${disposition}\r\n` +
      (part.type ? `Content-Type: ${part.type}\r\n` : "") +
      "\r\n";
    chunks.push(
      Buffer.from(headers),
      Buffer.isBuffer(part.value) ? part.value : Buffer.from(part.value),
      Buffer.from("\r\n"),
    );
  }
  chunks.push(Buffer.from(`--${BOUNDARY}--\r\n`));
  return Buffer.concat(chunks);
}

let root: string;
let app: FastifyInstance;
let token: string;
let tokenB: string;
const limits: AttachmentLimits = { ...DEFAULT_ATTACHMENT_LIMITS };

function upload(
  taskId: string,
  file: Buffer,
  /** null: send no `uploadKey` part at all. */
  uploadKey: string | null = "upload-key-0001",
  bearer = token,
  type = "image/png",
) {
  const parts: Parameters<typeof multipart>[0] = [];
  if (uploadKey !== null) parts.push({ name: "uploadKey", value: uploadKey });
  parts.push({ name: "file", value: file, filename: "picture", type });
  return app.inject({
    method: "POST",
    url: `/tasks/${taskId}/attachments`,
    headers: {
      authorization: `Bearer ${bearer}`,
      "content-type": `multipart/form-data; boundary=${BOUNDARY}`,
    },
    payload: multipart(parts),
  });
}

function get(url: string, bearer = token, extra: Record<string, string> = {}) {
  return app.inject({
    method: "GET",
    url,
    headers: { authorization: `Bearer ${bearer}`, ...extra },
  });
}

beforeAll(async () => {
  root = mkdtempSync(join(tmpdir(), "taskradar-attachments-"));
  const { buildApp } = await import("../src/app");
  app = await buildApp({
    authConfig: baseConfig,
    users: inMemoryUsers(),
    logger: false,
    attachments: { store: fileAttachmentStore(root), limits },
    linkPreview: { fetch: async () => null, dailyLimit: 1 },
  });
  await app.ready();
  token = await tokenFor(app, USER_A.email);
  tokenB = await tokenFor(app, USER_B.email);
});

afterAll(async () => {
  await app?.close();
  rmSync(root, { recursive: true, force: true });
});

beforeEach(() => {
  Object.assign(limits, DEFAULT_ATTACHMENT_LIMITS);
  rmSync(root, { recursive: true, force: true });
  installFakes();
});

function filesOf(userId: string): string[] {
  const dir = join(root, userId);
  return existsSync(dir) ? readdirSync(dir).sort() : [];
}

describe("POST /tasks/:id/attachments", () => {
  it("stores a PNG byte for byte minus its metadata, with a WebP thumbnail", async () => {
    const original = await pngWithMetadata();
    const res = await upload("t-a", original);

    expect(res.statusCode).toBe(201);
    const body = res.json() as Row;
    expect(body).toMatchObject({ mime: "image/png", width: 64, height: 32 });
    expect(Object.keys(body).sort()).toEqual([
      "createdAt",
      "height",
      "id",
      "mime",
      "sizeBytes",
      "width",
    ]);

    expect(filesOf(USER_A.id)).toEqual([`${body.id}.png`, `${body.id}.thumb.webp`]);
    const stored = await readFile(join(root, USER_A.id, `${body.id}.png`));
    expect(stored.includes(Buffer.from("secret place"))).toBe(false);
    expect(stored.includes(Buffer.from("eXIf"))).toBe(false);
    expect(stored.length).toBe(body.sizeBytes);
    // The pixels are the same file the phone chose, not a re-encode.
    expect(stored).toEqual(stripPngMetadata(original));
    expect(rows[0]!.sha256).toMatch(/^[0-9a-f]{64}$/);
  });

  it("re-encodes a JPEG without EXIF, with the orientation applied to the pixels", async () => {
    const res = await upload("t-a", await jpegWithExif(), "upload-key-0001", token, "image/jpeg");
    expect(res.statusCode).toBe(201);
    const body = res.json() as Row;
    // 80x40 with "rotate 90°" is a 40x80 picture.
    expect(body).toMatchObject({ mime: "image/jpeg", width: 40, height: 80 });
    const stored = await readFile(join(root, USER_A.id, `${body.id}.jpg`));
    const meta = await sharp(stored).metadata();
    expect(meta.exif).toBeUndefined();
    expect(meta.orientation).toBeUndefined();
    expect(stored.includes(Buffer.from("secret place"))).toBe(false);
  });

  it("drops EXIF from a WebP", async () => {
    const res = await upload("t-a", await webpWithExif(), "upload-key-0001", token, "image/webp");
    expect(res.statusCode).toBe(201);
    const body = res.json() as Row;
    expect(body).toMatchObject({ mime: "image/webp", width: 30, height: 20 });
    const stored = await readFile(join(root, USER_A.id, `${body.id}.webp`));
    expect(stored.includes(Buffer.from("secret place"))).toBe(false);
    expect((await sharp(stored).metadata()).exif).toBeUndefined();
  });

  it("makes the thumbnail at most 512 px on its long side", async () => {
    const big = await sharp({
      create: { width: 1200, height: 600, channels: 3, background: { r: 1, g: 2, b: 3 } },
    })
      .png()
      .toBuffer();
    const body = (await upload("t-a", big)).json() as Row;
    const thumb = await readFile(join(root, USER_A.id, `${body.id}.thumb.webp`));
    const meta = await sharp(thumb).metadata();
    expect(meta.format).toBe("webp");
    expect([meta.width, meta.height]).toEqual([512, 256]);
  });

  it("answers a replayed upload with the attachment it already made", async () => {
    const png = await pngWithMetadata();
    const first = await upload("t-a", png, "same-key-0001");
    const again = await upload("t-a", png, "same-key-0001");
    expect(first.statusCode).toBe(201);
    expect(again.statusCode).toBe(200);
    expect((again.json() as Row).id).toBe((first.json() as Row).id);
    expect(rows).toHaveLength(1);
    expect(filesOf(USER_A.id)).toHaveLength(2);
  });

  it("decides the type from the bytes, not from what the client says", async () => {
    const gif = Buffer.from("GIF89a\x01\x00\x01\x00\x00\x00\x00;", "latin1");
    const res = await upload("t-a", gif, "upload-key-0001", token, "image/png");
    expect(res.statusCode).toBe(415);

    const text = await upload("t-a", Buffer.from("<svg xmlns='http://www.w3.org/2000/svg'/>"));
    expect(text.statusCode).toBe(415);
    expect(rows).toHaveLength(0);
    expect(filesOf(USER_A.id)).toEqual([]);
  });

  it("refuses a file that only starts like a PNG", async () => {
    const fake = Buffer.concat([
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      Buffer.from("not really"),
    ]);
    expect((await upload("t-a", fake)).statusCode).toBe(415);
    const jpegHead = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);
    expect((await upload("t-a", jpegHead, "upload-key-0001", token, "image/jpeg")).statusCode).toBe(
      415,
    );
  });

  it("refuses a picture with more pixels than the decode bound", async () => {
    limits.maxPixels = 1000;
    const res = await upload("t-a", await pngWithMetadata()); // 64 x 32 = 2048 px
    expect(res.statusCode).toBe(415);
  });

  it("refuses a file over the size limit with 413", async () => {
    limits.maxBytes = 1024;
    // The plugin's limit is fixed when it is registered: rebuild for this case.
    const { buildApp } = await import("../src/app");
    const small = await buildApp({
      authConfig: baseConfig,
      users: inMemoryUsers(),
      logger: false,
      attachments: { store: fileAttachmentStore(root), limits: { ...limits } },
      linkPreview: { fetch: async () => null, dailyLimit: 1 },
    });
    try {
      const noise = await sharp(randomBytes(64 * 64 * 3), {
        raw: { width: 64, height: 64, channels: 3 },
      })
        .png()
        .toBuffer();
      expect(noise.length).toBeGreaterThan(1024);
      const res = await small.inject({
        method: "POST",
        url: "/tasks/t-a/attachments",
        headers: {
          authorization: `Bearer ${await tokenFor(small, USER_A.email)}`,
          "content-type": `multipart/form-data; boundary=${BOUNDARY}`,
        },
        payload: multipart([
          { name: "uploadKey", value: "upload-key-0001" },
          { name: "file", value: noise, filename: "x.png", type: "image/png" },
        ]),
      });
      expect(res.statusCode).toBe(413);
      expect(rows).toHaveLength(0);
    } finally {
      await small.close();
    }
  });

  it("refuses an upload past the user's quota with 413, counting only their pictures", async () => {
    const png = await pngWithMetadata();
    const size = stripPngMetadata(png).length;
    limits.userQuotaBytes = size * 2;

    expect((await upload("t-a", png, "upload-key-0001")).statusCode).toBe(201);
    // Another user's pictures do not count against this one.
    expect((await upload("t-b", png, "upload-key-0001", tokenB)).statusCode).toBe(201);
    expect((await upload("t-a2", png, "upload-key-0002")).statusCode).toBe(201);
    const over = await upload("t-a", png, "upload-key-0003");
    expect(over.statusCode).toBe(413);
    expect(rows.filter((r) => TASK_OWNER[r.taskId] === USER_A.id)).toHaveLength(2);
  });

  it("refuses a picture past the per-task limit with 409", async () => {
    limits.perTask = 2;
    const png = await pngWithMetadata();
    expect((await upload("t-a", png, "upload-key-0001")).statusCode).toBe(201);
    expect((await upload("t-a", png, "upload-key-0002")).statusCode).toBe(201);
    expect((await upload("t-a", png, "upload-key-0003")).statusCode).toBe(409);
    // A replay of one already there is still answered.
    expect((await upload("t-a", png, "upload-key-0002")).statusCode).toBe(200);
    // Another task has room.
    expect((await upload("t-a2", png, "upload-key-0003")).statusCode).toBe(201);
  });

  it("needs an uploadKey and a file", async () => {
    const png = await pngWithMetadata();
    expect((await upload("t-a", png, null)).statusCode).toBe(400);
    expect((await upload("t-a", png, "short")).statusCode).toBe(400);
    const noFile = await app.inject({
      method: "POST",
      url: "/tasks/t-a/attachments",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": `multipart/form-data; boundary=${BOUNDARY}`,
      },
      payload: multipart([{ name: "uploadKey", value: "upload-key-0001" }]),
    });
    expect(noFile.statusCode).toBe(400);
  });

  it("refuses a body that is not multipart with 415", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/tasks/t-a/attachments",
      headers: { authorization: `Bearer ${token}` },
      payload: { uploadKey: "upload-key-0001" },
    });
    expect(res.statusCode).toBe(415);
  });

  it("answers 404 for another user's task, and 401 without a token", async () => {
    const png = await pngWithMetadata();
    expect((await upload("t-b", png)).statusCode).toBe(404);
    expect((await upload("t-nope", png)).statusCode).toBe(404);
    const anonymous = await app.inject({
      method: "POST",
      url: "/tasks/t-a/attachments",
      headers: { "content-type": `multipart/form-data; boundary=${BOUNDARY}` },
      payload: multipart([{ name: "uploadKey", value: "upload-key-0001" }]),
    });
    expect(anonymous.statusCode).toBe(401);
    expect(rows).toHaveLength(0);
  });
});

describe("GET /attachments/:id and /thumb", () => {
  it("serves the original and the thumbnail with immutable private caching", async () => {
    const created = (await upload("t-a", await pngWithMetadata())).json() as Row;
    const stored = await readFile(join(root, USER_A.id, `${created.id}.png`));

    const res = await get(`/attachments/${created.id}`);
    expect(res.statusCode).toBe(200);
    expect(res.headers["content-type"]).toBe("image/png");
    expect(res.headers["cache-control"]).toBe("private, max-age=31536000, immutable");
    expect(res.headers.etag).toBe(`"${rows[0]!.sha256}"`);
    expect(res.rawPayload).toEqual(stored);

    const thumb = await get(`/attachments/${created.id}/thumb`);
    expect(thumb.statusCode).toBe(200);
    expect(thumb.headers["content-type"]).toBe("image/webp");
    expect(sniffImage(thumb.rawPayload)).toBe("image/webp");
  });

  it("answers 304 to a matching If-None-Match", async () => {
    const created = (await upload("t-a", await pngWithMetadata())).json() as Row;
    const etag = `"${rows[0]!.sha256}"`;
    const res = await get(`/attachments/${created.id}`, token, { "if-none-match": etag });
    expect(res.statusCode).toBe(304);
    expect(res.rawPayload.length).toBe(0);
  });

  it("answers 404 for another user's picture, an unknown id, and a missing file", async () => {
    const created = (await upload("t-a", await pngWithMetadata())).json() as Row;
    expect((await get(`/attachments/${created.id}`, tokenB)).statusCode).toBe(404);
    expect((await get(`/attachments/${created.id}/thumb`, tokenB)).statusCode).toBe(404);
    expect((await get(`/attachments/nope`)).statusCode).toBe(404);

    unlinkSync(join(root, USER_A.id, `${created.id}.thumb.webp`));
    expect((await get(`/attachments/${created.id}/thumb`)).statusCode).toBe(404);
  });

  it("needs a token", async () => {
    const created = (await upload("t-a", await pngWithMetadata())).json() as Row;
    const res = await app.inject({ method: "GET", url: `/attachments/${created.id}` });
    expect(res.statusCode).toBe(401);
  });
});

describe("DELETE /attachments/:id", () => {
  it("removes the row and both files", async () => {
    const created = (await upload("t-a", await pngWithMetadata())).json() as Row;
    const res = await app.inject({
      method: "DELETE",
      url: `/attachments/${created.id}`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(204);
    expect(rows).toHaveLength(0);
    expect(filesOf(USER_A.id)).toEqual([]);

    const again = await app.inject({
      method: "DELETE",
      url: `/attachments/${created.id}`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(again.statusCode).toBe(404);
  });

  it("does not let another user delete it", async () => {
    const created = (await upload("t-a", await pngWithMetadata())).json() as Row;
    const res = await app.inject({
      method: "DELETE",
      url: `/attachments/${created.id}`,
      headers: { authorization: `Bearer ${tokenB}` },
    });
    expect(res.statusCode).toBe(404);
    expect(rows).toHaveLength(1);
    expect(filesOf(USER_A.id)).toHaveLength(2);
  });
});

describe("image helpers", () => {
  it("sniffs the three types and nothing else", async () => {
    expect(sniffImage(await pngWithMetadata())).toBe("image/png");
    expect(sniffImage(await jpegWithExif())).toBe("image/jpeg");
    expect(sniffImage(await webpWithExif())).toBe("image/webp");
    expect(sniffImage(Buffer.from("GIF89a"))).toBeNull();
    expect(sniffImage(Buffer.from("RIFF\0\0\0\0WAVE"))).toBeNull();
    expect(sniffImage(Buffer.alloc(0))).toBeNull();
  });

  it("keeps a simple WebP as it is and clears the EXIF flag of an extended one", async () => {
    const simple = await sharp({
      create: { width: 4, height: 4, channels: 3, background: { r: 0, g: 0, b: 0 } },
    })
      .webp()
      .toBuffer();
    expect(stripWebpMetadata(simple)).toEqual(simple);

    const stripped = stripWebpMetadata(await webpWithExif());
    expect(stripped.toString("latin1", 12, 16)).toBe("VP8X");
    expect(stripped[20]! & 0x08).toBe(0);
    expect(stripped.readUInt32LE(4)).toBe(stripped.length - 8);
    expect((await sharp(stripped).metadata()).width).toBe(30);
  });
});

describe("limits and the sweep", () => {
  it("reads the limits from the environment, with the decided defaults", () => {
    expect(loadAttachmentLimits({})).toEqual({
      maxBytes: 10 * 1024 * 1024,
      perTask: 30,
      userQuotaBytes: 2 * 1024 * 1024 * 1024,
      maxPixels: 100_000_000,
    });
    expect(
      loadAttachmentLimits({
        ATTACHMENT_MAX_BYTES: "5",
        ATTACHMENT_MAX_PER_TASK: "3",
        ATTACHMENT_USER_QUOTA_BYTES: "nonsense",
      }),
    ).toMatchObject({ maxBytes: 5, perTask: 3, userQuotaBytes: 2 * 1024 * 1024 * 1024 });
  });

  it("knows which names are an attachment's", () => {
    expect(attachmentIdOf("abc123.png")).toBe("abc123");
    expect(attachmentIdOf("abc123.thumb.webp")).toBe("abc123");
    expect(attachmentIdOf("abc123.jpg.tmp-0a1b2c")).toBe("abc123");
    expect(attachmentIdOf("notes.txt")).toBeNull();
    expect(attachmentIdOf("../evil.png")).toBeNull();
  });

  it("removes only old files of attachments that no longer exist", () => {
    const now = new Date("2026-11-11T12:00:00.000Z");
    const old = new Date("2026-11-10T00:00:00.000Z");
    const fresh = new Date("2026-11-11T11:30:00.000Z");
    const files = [
      { path: "u/kept.png", attachmentId: "kept", modifiedAt: old },
      { path: "u/kept.thumb.webp", attachmentId: "kept", modifiedAt: old },
      { path: "u/gone.png", attachmentId: "gone", modifiedAt: old },
      { path: "u/gone.thumb.webp", attachmentId: "gone", modifiedAt: old },
      { path: "u/uploading.png", attachmentId: "uploading", modifiedAt: fresh },
      { path: "u/README", attachmentId: null, modifiedAt: old },
    ];
    const plan = planSweep(files, new Set(["kept"]), now);
    expect(plan.remove.map((f) => f.path)).toEqual(["u/gone.png", "u/gone.thumb.webp"]);
    expect(plan.unknown.map((f) => f.path)).toEqual(["u/README"]);
  });
});
