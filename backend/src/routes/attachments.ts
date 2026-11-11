import { randomUUID } from "node:crypto";
import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { FastifyInstance, FastifyReply } from "fastify";
import fastifyMultipart from "@fastify/multipart";
import { prisma } from "../lib/prisma";
import { userIdOf } from "../lib/users";
import { HttpError, NotFoundError } from "../lib/errors";
import { isUniqueConstraintViolation } from "../lib/prismaErrors";
import { idParamSchema, uploadKeySchema } from "../schemas";
import { getTaskOrThrow } from "./tasks";
import { attachmentMetaSelect } from "../domain/taskView";
import {
  EXTENSION,
  ImageMime,
  UnsupportedImageError,
  prepareImage,
} from "../domain/attachmentImage";
import { AttachmentLimits, AttachmentStore } from "../domain/attachmentStore";

/*
 * Pictures on a task (task editor, design/task-editor-spec.md §10).
 *
 *   POST   /tasks/:id/attachments   multipart: `uploadKey`, `file`
 *   GET    /attachments/:id         the original
 *   GET    /attachments/:id/thumb   512 px WebP
 *   DELETE /attachments/:id
 *
 * Every read checks the owner in the database (attachment -> task -> project
 * -> scope -> user) and answers 404 for someone else's, exactly like a missing
 * one -- the files are never reachable any other way. The bytes go out with a
 * year of private caching: an attachment never changes (a new picture is a new
 * id), so the phone fetches each one once.
 *
 * Statuses of the upload, as the outbox reads them:
 *   201 a new attachment; 200 the same `uploadKey` again -- the attachment it
 *   already made (an upload replayed after a lost answer);
 *   413 the file is over the size limit, or the user over their quota;
 *   415 not a PNG, JPEG or WebP by its bytes (or not a readable one);
 *   409 the task already has the maximum number of pictures.
 */

export interface AttachmentFeature {
  store: AttachmentStore;
  limits: AttachmentLimits;
}

/** What the API says about an attachment -- the same shape a task carries. */
function view(row: {
  id: string;
  mime: string;
  width: number;
  height: number;
  sizeBytes: number;
  createdAt: Date;
}) {
  return {
    id: row.id,
    mime: row.mime,
    width: row.width,
    height: row.height,
    sizeBytes: row.sizeBytes,
    createdAt: row.createdAt,
  };
}

const IMMUTABLE = "private, max-age=31536000, immutable";

async function ownedAttachment(userId: string, id: string) {
  const row = await prisma.taskAttachment.findFirst({
    where: { id, task: { project: { scope: { userId } } } },
  });
  if (!row) throw new NotFoundError("Attachment");
  return row;
}

/** Sends one file of an attachment, with the caching headers; 404 if the file is gone. */
async function sendFile(
  reply: FastifyReply,
  ifNoneMatch: string | undefined,
  path: string,
  mime: string,
  sha256: string,
): Promise<void> {
  const etag = `"${sha256}"`;
  let size: number;
  try {
    size = (await stat(path)).size;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT")
      throw new NotFoundError("Attachment file");
    throw error;
  }
  reply.header("Cache-Control", IMMUTABLE).header("ETag", etag);
  if (ifNoneMatch !== undefined && ifNoneMatch.split(",").some((tag) => tag.trim() === etag)) {
    reply.status(304).send();
    return;
  }
  reply.header("Content-Length", size).type(mime).send(createReadStream(path));
}

export function attachmentRoutes(feature: AttachmentFeature) {
  const { store, limits } = feature;

  return async function routes(app: FastifyInstance): Promise<void> {
    /*
     * Multipart is registered here, inside this plugin's own context, so only
     * these routes accept it; every other route keeps refusing a body that is
     * not JSON. The limits make busboy stop reading, not just complain after:
     * one file of at most `maxBytes`, and a couple of short fields.
     */
    await app.register(fastifyMultipart, {
      limits: {
        fileSize: limits.maxBytes,
        files: 1,
        fields: 4,
        fieldSize: 1024,
        parts: 6,
        headerPairs: 100,
      },
    });

    app.post("/tasks/:id/attachments", async (request, reply) => {
      const { id: taskId } = idParamSchema.parse(request.params);
      const userId = userIdOf(request);
      await getTaskOrThrow(userId, taskId);

      if (!request.isMultipart()) {
        throw new HttpError(415, "Expected multipart/form-data with `uploadKey` and `file`");
      }

      let rawKey: string | undefined;
      let bytes: Buffer | undefined;
      for await (const part of request.parts()) {
        if (part.type === "file") {
          // toBuffer() throws a 413 (RequestFileTooLargeError) past `maxBytes`.
          const data = await part.toBuffer();
          if (part.fieldname === "file") bytes = data;
        } else if (part.fieldname === "uploadKey") {
          rawKey = String(part.value);
        }
      }
      const uploadKey = uploadKeySchema.parse(rawKey);
      if (bytes === undefined || bytes.length === 0) {
        throw new HttpError(400, "The `file` part is missing or empty");
      }

      // A replay of an upload that already landed: the attachment it made.
      const known = await prisma.taskAttachment.findUnique({
        where: { taskId_uploadKey: { taskId, uploadKey } },
      });
      if (known) {
        reply.status(200).send(view(known));
        return;
      }

      const count = await prisma.taskAttachment.count({ where: { taskId } });
      if (count >= limits.perTask) {
        throw new HttpError(409, `A task can have at most ${limits.perTask} pictures`);
      }

      let image;
      try {
        image = await prepareImage(bytes, limits.maxPixels);
      } catch (error) {
        if (error instanceof UnsupportedImageError) throw new HttpError(415, error.message);
        throw error;
      }

      const used = await prisma.taskAttachment.aggregate({
        where: { task: { project: { scope: { userId } } } },
        _sum: { sizeBytes: true },
      });
      if ((used._sum.sizeBytes ?? 0) + image.data.length > limits.userQuotaBytes) {
        throw new HttpError(413, "Attachment storage quota exceeded");
      }

      /*
       * Files first, row second: a row is never there without its files. A
       * crash in between leaves files with no row, which the daily sweep
       * removes (src/scripts/sweepAttachments.ts) -- the cheap failure,
       * unlike a row whose picture 404s forever.
       *
       * The count and the quota above are read outside any lock, so two
       * uploads racing can each pass and end one picture over. For one
       * person's phone sending its queue in order, that is not a real case.
       */
      const id = randomUUID().replaceAll("-", "");
      const ext = EXTENSION[image.mime as ImageMime];
      await store.write(userId, id, ext, image.data, image.thumb);
      try {
        const created = await prisma.taskAttachment.create({
          data: {
            id,
            taskId,
            uploadKey,
            mime: image.mime,
            sizeBytes: image.data.length,
            width: image.width,
            height: image.height,
            sha256: image.sha256,
          },
          select: attachmentMetaSelect,
        });
        reply.status(201).send(view(created));
      } catch (error) {
        await store.remove(userId, id, ext).catch(() => undefined);
        // The same upload twice at once: the loser answers with the winner's row.
        if (!isUniqueConstraintViolation(error)) throw error;
        const raced = await prisma.taskAttachment.findUnique({
          where: { taskId_uploadKey: { taskId, uploadKey } },
        });
        if (!raced) throw error;
        reply.status(200).send(view(raced));
      }
    });

    app.get("/attachments/:id", async (request, reply) => {
      const { id } = idParamSchema.parse(request.params);
      const userId = userIdOf(request);
      const row = await ownedAttachment(userId, id);
      const ext = EXTENSION[row.mime as ImageMime] ?? "bin";
      await sendFile(
        reply,
        request.headers["if-none-match"],
        store.originalPath(userId, row.id, ext),
        row.mime,
        row.sha256,
      );
      // A stream is written after the handler resolves: returning the reply says so.
      return reply;
    });

    app.get("/attachments/:id/thumb", async (request, reply) => {
      const { id } = idParamSchema.parse(request.params);
      const userId = userIdOf(request);
      const row = await ownedAttachment(userId, id);
      await sendFile(
        reply,
        request.headers["if-none-match"],
        store.thumbPath(userId, row.id),
        "image/webp",
        row.sha256,
      );
      return reply;
    });

    /*
     * The row goes now; the files after it, best effort. A file that cannot
     * be removed is an orphan for the sweep, never a reason to keep a picture
     * the user deleted on the screen.
     */
    app.delete("/attachments/:id", async (request, reply) => {
      const { id } = idParamSchema.parse(request.params);
      const userId = userIdOf(request);
      const row = await ownedAttachment(userId, id);
      await prisma.taskAttachment.delete({ where: { id: row.id } });
      const ext = EXTENSION[row.mime as ImageMime] ?? "bin";
      await store.remove(userId, row.id, ext).catch((error: unknown) => {
        request.log.warn({ err: error, attachmentId: row.id }, "attachment files not removed");
      });
      reply.status(204).send();
    });
  };
}
