import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { PGlite } from "@electric-sql/pglite";

/*
 * Every committed migration, applied in order to a real (in-process, WASM)
 * PostgreSQL -- the development machine has no Docker, and the integration
 * workflow is the only other place migrations run. This catches SQL that does
 * not apply at all; integration-ci.yml still checks migrations against
 * schema.prisma (`migrate diff`) and runs `migrate deploy` for real.
 *
 * And the task editor's constraints (20261111100000), which live only in SQL.
 */
const migrationsDir = join(__dirname, "..", "prisma", "migrations");
let db: PGlite;

beforeAll(async () => {
  db = new PGlite();
  const names = readdirSync(migrationsDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();
  for (const name of names) {
    const sql = readFileSync(join(migrationsDir, name, "migration.sql"), "utf8");
    try {
      await db.exec(sql);
    } catch (error) {
      throw new Error(`migration ${name} failed: ${(error as Error).message}`, { cause: error });
    }
  }
}, 60_000);

afterAll(async () => {
  await db?.close();
});

async function seedTask(id: string): Promise<void> {
  const owner = (await db.query<{ id: string }>(`SELECT id FROM users LIMIT 1`)).rows[0]?.id;
  let userId = owner;
  if (userId === undefined) {
    userId = "u1";
    await db.query(
      `INSERT INTO users (id, email, name, "passwordHash") VALUES ($1, $2, 'U', 'x')`,
      [userId, `${id}@example.com`],
    );
  }
  await db.query(
    `INSERT INTO scopes (id, name, position, "userId", "updatedAt") VALUES ($1, 's', 1, $2, now())`,
    [`s-${id}`, userId],
  );
  await db.query(
    `INSERT INTO projects (id, name, "scopeId", "updatedAt") VALUES ($1, 'p', $2, now())`,
    [`p-${id}`, `s-${id}`],
  );
  await db.query(
    `INSERT INTO tasks (id, "projectId", title, position, "updatedAt") VALUES ($1, $2, 't', 1, now())`,
    [id, `p-${id}`],
  );
}

describe("migrations", () => {
  it("create the task editor's tables and columns", async () => {
    const columns = await db.query<{ column_name: string }>(
      `SELECT column_name FROM information_schema.columns WHERE table_name = 'tasks'`,
    );
    const names = columns.rows.map((r) => r.column_name);
    for (const column of ["checklist", "locLat", "locLng", "locRadius", "locLabel"]) {
      expect(names).toContain(column);
    }
    const tables = await db.query<{ table_name: string }>(
      `SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'`,
    );
    expect(tables.rows.map((r) => r.table_name)).toEqual(
      expect.arrayContaining(["task_attachments", "link_previews", "link_preview_usage"]),
    );
  });

  it("hold a place to all four columns or none", async () => {
    await seedTask("t-place");
    await db.query(
      `UPDATE tasks SET "locLat" = 55.7, "locLng" = 37.6, "locRadius" = 200, "locLabel" = 'Дом' WHERE id = 't-place'`,
    );
    await expect(
      db.query(`UPDATE tasks SET "locLabel" = NULL WHERE id = 't-place'`),
    ).rejects.toThrow(/tasks_location_all_or_none/);
    await expect(
      db.query(`UPDATE tasks SET "locRadius" = 50 WHERE id = 't-place'`),
    ).rejects.toThrow(/tasks_location_range/);
    await expect(db.query(`UPDATE tasks SET "locLat" = 91 WHERE id = 't-place'`)).rejects.toThrow(
      /tasks_location_range/,
    );
    await db.query(
      `UPDATE tasks SET "locLat" = NULL, "locLng" = NULL, "locRadius" = NULL, "locLabel" = NULL WHERE id = 't-place'`,
    );
  });

  it("make an upload key unique per task and drop pictures with their task", async () => {
    await seedTask("t-pics");
    const insert = (id: string, key: string) =>
      db.query(
        `INSERT INTO task_attachments (id, "taskId", "uploadKey", mime, "sizeBytes", width, height, sha256)
         VALUES ($1, 't-pics', $2, 'image/png', 1, 1, 1, 'x')`,
        [id, key],
      );
    await insert("a1", "key-00000001");
    await expect(insert("a2", "key-00000001")).rejects.toThrow(
      /task_attachments_taskId_uploadKey_key/,
    );
    await db.query(`DELETE FROM tasks WHERE id = 't-pics'`);
    const left = await db.query(`SELECT id FROM task_attachments WHERE "taskId" = 't-pics'`);
    expect(left.rows).toHaveLength(0);
  });
});
