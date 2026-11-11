/*
 * Removes attachment files that no row points at any more (task editor,
 * design/task-editor-spec.md §10).
 *
 * Deleting a task, a project or an unfiled task removes the attachment rows by
 * cascade, but not the files: the database cannot reach the volume, and doing
 * it in every delete route would turn a one-row delete into file system work
 * that can fail halfway. So the files stay until this runs.
 *
 * USAGE (inside the production container, where the database and the volume are)
 *
 *   docker compose -f compose.prod.yaml exec -T backend node dist/scripts/sweepAttachments.js
 *   ... sweepAttachments.js --dry-run     only report
 *
 * It runs daily from the attachments exporter (scripts/export-production-attachments.sh),
 * i.e. on the same schedule as the backup, right before the volume is archived.
 *
 * Safe by construction:
 * - it deletes only files whose name is an attachment's (`<id>.<ext>`,
 *   `<id>.thumb.webp`, their `.tmp-` files) and whose id has no row;
 * - a file younger than six hours is left alone -- an upload writes its files
 *   a moment before its row (SWEEP_GRACE_MS in ../domain/attachmentStore.ts);
 * - any error reading the database stops it before anything is deleted.
 */
import { prisma } from "../lib/prisma";
import {
  listStoredFiles,
  loadAttachmentsDir,
  planSweep,
  removeStoredFile,
} from "../domain/attachmentStore";

async function main(): Promise<void> {
  const dryRun = process.argv.includes("--dry-run");
  const root = loadAttachmentsDir();
  const files = await listStoredFiles(root);

  const ids = [...new Set(files.flatMap((f) => (f.attachmentId === null ? [] : [f.attachmentId])))];
  const existing = new Set<string>();
  // In batches, so a large volume does not become one enormous IN (...).
  for (let i = 0; i < ids.length; i += 1000) {
    const rows = await prisma.taskAttachment.findMany({
      where: { id: { in: ids.slice(i, i + 1000) } },
      select: { id: true },
    });
    for (const row of rows) existing.add(row.id);
  }

  const plan = planSweep(files, existing, new Date());
  for (const file of plan.unknown)
    console.log(`left alone (not an attachment's name): ${file.path}`);
  for (const file of plan.remove) {
    if (dryRun) {
      console.log(`would remove ${file.path}`);
    } else {
      await removeStoredFile(root, file.path);
    }
  }
  console.log(
    `${root}: ${files.length} files, ${existing.size} attachments in use, ` +
      `${plan.remove.length} orphaned files ${dryRun ? "found (dry run)" : "removed"}`,
  );
}

main()
  .catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
