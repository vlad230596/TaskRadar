import { randomBytes } from "node:crypto";
import { mkdir, readdir, rename, rm, stat, unlink, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";

/*
 * Where attachment files live (task editor, design/task-editor-spec.md §10).
 *
 * One directory per user under `ATTACHMENTS_DIR` -- the `attachments-data`
 * volume in compose.prod.yaml, mounted at /var/lib/taskradar/attachments --
 * with two files per attachment:
 *
 *     <userId>/<attachmentId>.<png|jpg|webp>   the original, metadata stripped
 *     <userId>/<attachmentId>.thumb.webp       512 px thumbnail
 *
 * The user directory is what makes the sweep (src/scripts/sweepAttachments.ts)
 * and a by-hand look at the volume legible; access control is NOT the path's
 * job -- every read goes through the API, which checks the owner in the
 * database first. Caddy never sees this directory.
 *
 * Writes go to a temporary name and are renamed into place, so a crash in the
 * middle leaves a `.tmp-` file the sweep removes, never a half-written image
 * under a real name.
 */

/** Limits, from the environment (§10, §12: decided 11.11.2026). */
export interface AttachmentLimits {
  /** Largest upload, bytes. `ATTACHMENT_MAX_BYTES`, default 10 MB. */
  maxBytes: number;
  /** Pictures per task. `ATTACHMENT_MAX_PER_TASK`, default 30. */
  perTask: number;
  /** Total stored per user, bytes. `ATTACHMENT_USER_QUOTA_BYTES`, default 2 GB. */
  userQuotaBytes: number;
  /** Decode bound, pixels. `ATTACHMENT_MAX_PIXELS`, default 100 M. */
  maxPixels: number;
}

export const DEFAULT_ATTACHMENT_LIMITS: AttachmentLimits = {
  maxBytes: 10 * 1024 * 1024,
  perTask: 30,
  userQuotaBytes: 2 * 1024 * 1024 * 1024,
  maxPixels: 100_000_000,
};

function positiveInt(raw: string | undefined, fallback: number): number {
  if (raw === undefined || raw.trim() === "") return fallback;
  const value = Number(raw);
  return Number.isSafeInteger(value) && value > 0 ? value : fallback;
}

export function loadAttachmentLimits(env: NodeJS.ProcessEnv = process.env): AttachmentLimits {
  const d = DEFAULT_ATTACHMENT_LIMITS;
  return {
    maxBytes: positiveInt(env.ATTACHMENT_MAX_BYTES, d.maxBytes),
    perTask: positiveInt(env.ATTACHMENT_MAX_PER_TASK, d.perTask),
    userQuotaBytes: positiveInt(env.ATTACHMENT_USER_QUOTA_BYTES, d.userQuotaBytes),
    maxPixels: positiveInt(env.ATTACHMENT_MAX_PIXELS, d.maxPixels),
  };
}

/**
 * `ATTACHMENTS_DIR`, or `attachments-data` under the working directory for a
 * development run (git-ignored). Production sets it in compose.prod.yaml.
 */
export function loadAttachmentsDir(env: NodeJS.ProcessEnv = process.env): string {
  const raw = env.ATTACHMENTS_DIR;
  return resolve(raw !== undefined && raw.trim() !== "" ? raw : "attachments-data");
}

/** Ids and user ids become path segments: nothing but a safe alphabet gets through. */
const SAFE_SEGMENT = /^[A-Za-z0-9_-]{1,100}$/;

function segment(value: string): string {
  if (!SAFE_SEGMENT.test(value)) throw new Error(`Unsafe path segment: ${JSON.stringify(value)}`);
  return value;
}

export interface AttachmentStore {
  readonly root: string;
  originalPath(userId: string, id: string, ext: string): string;
  thumbPath(userId: string, id: string): string;
  /** Writes both files, each atomically. */
  write(userId: string, id: string, ext: string, original: Buffer, thumb: Buffer): Promise<void>;
  /** Removes both files; a file that is already gone is not an error. */
  remove(userId: string, id: string, ext: string): Promise<void>;
}

export function fileAttachmentStore(root: string): AttachmentStore {
  const userDir = (userId: string) => join(root, segment(userId));
  const originalPath = (userId: string, id: string, ext: string) =>
    join(userDir(userId), `${segment(id)}.${segment(ext)}`);
  const thumbPath = (userId: string, id: string) =>
    join(userDir(userId), `${segment(id)}.thumb.webp`);

  async function writeAtomically(path: string, data: Buffer): Promise<void> {
    const temp = `${path}.tmp-${randomBytes(6).toString("hex")}`;
    try {
      await writeFile(temp, data, { flag: "wx" });
      await rename(temp, path);
    } catch (error) {
      await rm(temp, { force: true });
      throw error;
    }
  }

  return {
    root,
    originalPath,
    thumbPath,
    async write(userId, id, ext, original, thumb) {
      await mkdir(userDir(userId), { recursive: true });
      await writeAtomically(originalPath(userId, id, ext), original);
      await writeAtomically(thumbPath(userId, id), thumb);
    },
    async remove(userId, id, ext) {
      await rm(originalPath(userId, id, ext), { force: true });
      await rm(thumbPath(userId, id), { force: true });
    },
  };
}

// ---- The sweep (src/scripts/sweepAttachments.ts) ----

/** One file found on the volume. */
export interface StoredFile {
  /** Relative to the root, `/`-separated: `<userId>/<name>`. */
  path: string;
  /** The attachment id the name belongs to, or null for a name that is no attachment's. */
  attachmentId: string | null;
  modifiedAt: Date;
}

/**
 * What an attachment's file name says about whose it is: `<id>.<ext>`,
 * `<id>.thumb.webp`, or a temporary file of either. Anything else is null.
 */
export function attachmentIdOf(name: string): string | null {
  const match = /^([A-Za-z0-9_-]+)\.(?:png|jpg|webp|thumb\.webp)(?:\.tmp-[0-9a-f]+)?$/.exec(name);
  return match?.[1] ?? null;
}

/** Every file under the root, two levels deep (user directory, file). */
export async function listStoredFiles(root: string): Promise<StoredFile[]> {
  let users: string[];
  try {
    users = await readdir(root);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw error;
  }
  const files: StoredFile[] = [];
  for (const user of users) {
    const dir = join(root, user);
    if (!(await stat(dir)).isDirectory()) continue;
    for (const name of await readdir(dir)) {
      const info = await stat(join(dir, name));
      if (!info.isFile()) continue;
      files.push({
        path: `${user}/${name}`,
        attachmentId: attachmentIdOf(name),
        modifiedAt: info.mtime,
      });
    }
  }
  return files;
}

/**
 * How long a file with no row is left alone. An upload writes its files
 * *before* its row (so that a row never points at nothing), and a sweep
 * running in between must not take them.
 */
export const SWEEP_GRACE_MS = 6 * 60 * 60 * 1000;

/**
 * Which files the sweep removes: those whose attachment has no row and that
 * are older than the grace period. Files whose name is not an attachment's are
 * left alone and reported -- the sweep deletes only what it understands.
 */
export function planSweep(
  files: readonly StoredFile[],
  existingIds: ReadonlySet<string>,
  now: Date,
  graceMs: number = SWEEP_GRACE_MS,
): { remove: StoredFile[]; unknown: StoredFile[] } {
  const remove: StoredFile[] = [];
  const unknown: StoredFile[] = [];
  for (const file of files) {
    if (file.attachmentId === null) {
      unknown.push(file);
      continue;
    }
    if (existingIds.has(file.attachmentId)) continue;
    if (now.getTime() - file.modifiedAt.getTime() < graceMs) continue;
    remove.push(file);
  }
  return { remove, unknown };
}

/** Deletes one swept file, by its relative path. */
export async function removeStoredFile(root: string, path: string): Promise<void> {
  const [user, name] = path.split("/");
  if (user === undefined || name === undefined) return;
  try {
    await unlink(join(root, segment(user), name));
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
}
