import { Prisma } from "@prisma/client";

/*
 * An in-memory Prisma for route tests that read across many tables
 * (design/today-history-contract.md: «Сегодня», История, пересмотр).
 *
 * The same idea as the fakes in goals.test.ts and tasks.test.ts -- rows that
 * really change, `where` filters that are EVALUATED (an owner filter that the
 * fake skipped would let a leak pass), `$transaction` that rolls back -- made
 * generic over a small relation map, so `include` / `select` of relations,
 * date ranges and `take` work the way the routes use them. Anything it does
 * not understand throws, rather than quietly answering with every row.
 *
 * Usage: `const prismaMock = vi.hoisted(() => ({}))`, mock the prisma module
 * with it, then `const fake = installFakeDb(prismaMock)` and `fake.load({...})`
 * in a `beforeEach`.
 */

/* eslint-disable @typescript-eslint/no-explicit-any */
export type Row = Record<string, any>;

/** Every column of each model with its default. A `where` on anything else throws. */
export const COLUMNS: Record<string, Row> = {
  user: {
    id: null,
    activeContourId: null,
    activeContourUntil: null,
    laterHorizonDays: 10,
    reviewWeekday: 1,
    reviewTime: "09:00",
    createdAt: null,
  },
  scope: { id: null, userId: null, name: "", position: 0, createdAt: null, updatedAt: null },
  project: {
    id: null,
    name: "",
    scopeId: null,
    archivedAt: null,
    rhythmClosedPerWeek: null,
    rhythmMaxOpen: null,
    createdAt: null,
    updatedAt: null,
  },
  task: {
    id: null,
    projectId: null,
    title: "",
    description: null,
    status: "pending",
    position: 0,
    categoryId: null,
    remindAt: null,
    remindTime: null,
    focusedAt: null,
    focusContourId: null,
    doneAt: null,
    aiSource: null,
    aiKind: null,
    aiResult: null,
    createKey: null,
    checklist: null,
    locLat: null,
    locLng: null,
    locRadius: null,
    locLabel: null,
    createdAt: null,
    updatedAt: null,
  },
  taskEvent: {
    id: null,
    taskId: null,
    kind: null,
    fromStatus: null,
    toStatus: null,
    contourId: null,
    revokedAt: null,
    at: null,
  },
  taskAttachment: { id: null, taskId: null, createdAt: null },
  taskCategory: { id: null, projectId: null, name: "", position: 0 },
  note: { id: null, projectId: null, title: "", content: "", createdAt: null, updatedAt: null },
  contour: {
    id: null,
    userId: null,
    name: "",
    slots: 2,
    windowDays: 7,
    schedule: null,
    position: 0,
    createdAt: null,
    updatedAt: null,
  },
  goal: {
    id: null,
    userId: null,
    contourId: null,
    title: "",
    why: null,
    slottedAt: null,
    windowDays: null,
    windowEndsAt: null,
    achievedAt: null,
    position: 0,
    createdAt: null,
    updatedAt: null,
  },
  goalTask: { goalId: null, taskId: null, position: 0, createdAt: null },
  goalIdea: { goalId: null, noteId: null, createdAt: null },
  review: {
    id: null,
    userId: null,
    periodStart: null,
    periodEnd: null,
    monthly: false,
    closedCount: 0,
    byProject: null,
    achievedGoals: null,
    summary: null,
    createdAt: null,
  },
  inboxItem: { id: null, userId: null, text: "", createdAt: null, updatedAt: null },
  dictationParse: { id: null, userId: null },
};

export type ModelName = keyof typeof COLUMNS;

/** To-one relations: model -> field -> [target model, foreign key on this row]. */
const TO_ONE: Record<string, Record<string, [string, string]>> = {
  task: { project: ["project", "projectId"], focusContour: ["contour", "focusContourId"] },
  project: { scope: ["scope", "scopeId"] },
  scope: { user: ["user", "userId"] },
  taskEvent: { task: ["task", "taskId"], contour: ["contour", "contourId"] },
  goal: { contour: ["contour", "contourId"] },
  goalTask: { goal: ["goal", "goalId"], task: ["task", "taskId"] },
  goalIdea: { goal: ["goal", "goalId"], note: ["note", "noteId"] },
  note: { project: ["project", "projectId"] },
  review: { user: ["user", "userId"] },
};

/** To-many relations: model -> field -> [target model, foreign key on the target]. */
const TO_MANY: Record<string, Record<string, [string, string]>> = {
  task: {
    attachments: ["taskAttachment", "taskId"],
    goalLinks: ["goalTask", "taskId"],
    events: ["taskEvent", "taskId"],
  },
  project: { tasks: ["task", "projectId"], notes: ["note", "projectId"], categories: ["taskCategory", "projectId"] },
  goal: { tasks: ["goalTask", "goalId"], ideas: ["goalIdea", "goalId"] },
  note: { goalLinks: ["goalIdea", "noteId"] },
};

const COMPOUND_KEYS: Record<string, string[]> = {
  goalId_taskId: ["goalId", "taskId"],
  goalId_noteId: ["goalId", "noteId"],
  projectId_createKey: ["projectId", "createKey"],
};

const FNS = [
  "findFirst",
  "findFirstOrThrow",
  "findMany",
  "findUnique",
  "findUniqueOrThrow",
  "create",
  "update",
  "updateMany",
  "delete",
  "deleteMany",
  "count",
  "aggregate",
] as const;

function value(v: unknown): unknown {
  return v instanceof Date ? v.getTime() : v;
}

function condOk(actual: unknown, cond: unknown): boolean {
  if (cond === null) return actual === null || actual === undefined;
  if (cond instanceof Date) return actual instanceof Date && actual.getTime() === cond.getTime();
  if (typeof cond !== "object") return actual === cond;
  for (const [op, arg] of Object.entries(cond as Row)) {
    if (arg === undefined) continue;
    const a = value(actual);
    const b = value(arg);
    if (op === "equals") {
      if (!condOk(actual, arg)) return false;
    } else if (op === "not") {
      if (arg === null ? actual === null || actual === undefined : condOk(actual, arg)) return false;
    } else if (op === "in") {
      if (!(arg as unknown[]).some((x) => value(x) === a)) return false;
    } else if (op === "notIn") {
      if ((arg as unknown[]).some((x) => value(x) === a)) return false;
    } else if (op === "gte" || op === "gt" || op === "lte" || op === "lt") {
      if (actual === null || actual === undefined) return false;
      const x = a as number;
      const y = b as number;
      if (op === "gte" && !(x >= y)) return false;
      if (op === "gt" && !(x > y)) return false;
      if (op === "lte" && !(x <= y)) return false;
      if (op === "lt" && !(x < y)) return false;
    } else {
      throw new Error(`fake: unknown operator ${op}`);
    }
  }
  return true;
}

function compare(x: unknown, y: unknown): number {
  const a = value(x) as number | string | null | undefined;
  const b = value(y) as number | string | null | undefined;
  if (a === b) return 0;
  if (a === null || a === undefined) return 1;
  if (b === null || b === undefined) return -1;
  return a < b ? -1 : 1;
}

export interface FakeDb {
  /** The tables. Rows are mutated in place by the routes. */
  tables: Record<string, Row[]>;
  /** Replaces every table: unlisted ones become empty. Fills column defaults. */
  load(seed: Partial<Record<ModelName, Row[]>>): void;
  /** A row by id. */
  byId(model: ModelName, id: unknown): Row | undefined;
}

/** Fills [mock] (the object `vi.hoisted` made) with a fake per model and `$transaction`. */
export function installFakeDb(mock: Row): FakeDb {
  let tables: Record<string, Row[]> = {};
  let seq = 0;

  const byId = (model: string, id: unknown) => tables[model]!.find((r) => r.id === id);

  function matches(model: string, row: Row, where: Row = {}): boolean {
    for (const [key, cond] of Object.entries(where)) {
      if (cond === undefined) continue;
      if (key === "OR") {
        if (!(cond as Row[]).some((one) => matches(model, row, one))) return false;
        continue;
      }
      if (key === "AND") {
        const all = Array.isArray(cond) ? cond : [cond];
        if (!all.every((one: Row) => matches(model, row, one))) return false;
        continue;
      }
      if (key === "NOT") {
        const all = Array.isArray(cond) ? cond : [cond];
        if (all.some((one: Row) => matches(model, row, one))) return false;
        continue;
      }
      if (COMPOUND_KEYS[key]) {
        for (const column of COMPOUND_KEYS[key]) if (row[column] !== (cond as Row)[column]) return false;
        continue;
      }
      const one = TO_ONE[model]?.[key];
      if (one) {
        const target = byId(one[0], row[one[1]]);
        if (cond === null) {
          if (target !== undefined) return false;
          continue;
        }
        if (!target || !matches(one[0], target, cond as Row)) return false;
        continue;
      }
      if (!(key in COLUMNS[model]!)) throw new Error(`fake ${model}: unsupported where key ${key}`);
      if (!condOk(row[key], cond)) return false;
    }
    return true;
  }

  function sortRows(model: string, rows: Row[], orderBy: unknown): Row[] {
    const list = (orderBy === undefined ? [] : Array.isArray(orderBy) ? orderBy : [orderBy]) as Row[];
    return [...rows].sort((a, b) => {
      for (const one of list) {
        for (const [key, dir] of Object.entries(one)) {
          let x: unknown;
          let y: unknown;
          let direction = dir as string;
          if (typeof dir === "object") {
            const [[field, nested]] = Object.entries(dir as Row) as [[string, string]];
            const rel = TO_ONE[model]?.[key];
            if (!rel) throw new Error(`fake ${model}: orderBy through ${key}`);
            x = byId(rel[0], a[rel[1]])?.[field];
            y = byId(rel[0], b[rel[1]])?.[field];
            direction = nested;
          } else {
            x = a[key];
            y = b[key];
          }
          const c = compare(x, y);
          if (c !== 0) return direction === "desc" ? -c : c;
        }
      }
      return 0;
    });
  }

  function page(rows: Row[], args: Row): Row[] {
    const skip = (args.skip as number | undefined) ?? 0;
    const take = args.take as number | undefined;
    return rows.slice(skip, take === undefined ? undefined : skip + take);
  }

  /** A row in the shape an `include` / `select` asks for: relations attached, recursively. */
  function shape(model: string, row: Row, args: Row = {}): Row {
    const spec = (args.include ?? args.select) as Row | undefined;
    const out: Row = { ...row };
    if (spec === undefined) return out;
    for (const [key, want] of Object.entries(spec)) {
      if (!want) continue;
      if (key === "_count") {
        const counts: Row = {};
        for (const [rel, on] of Object.entries((want as Row).select as Row)) {
          if (!on) continue;
          const many = TO_MANY[model]?.[rel];
          if (!many) throw new Error(`fake ${model}: _count of ${rel}`);
          counts[rel] = tables[many[0]]!.filter((r) => r[many[1]] === row.id).length;
        }
        out._count = counts;
        continue;
      }
      const one = TO_ONE[model]?.[key];
      if (one) {
        const target = byId(one[0], row[one[1]]);
        out[key] = target === undefined ? null : shape(one[0], target, want === true ? {} : (want as Row));
        continue;
      }
      const many = TO_MANY[model]?.[key];
      if (many) {
        const nested = want === true ? {} : (want as Row);
        const rows = tables[many[0]]!.filter(
          (r) => r[many[1]] === row.id && matches(many[0], r, nested.where as Row | undefined),
        );
        out[key] = page(sortRows(many[0], rows, nested.orderBy), nested).map((r) => shape(many[0], r, nested));
        continue;
      }
      if (!(key in COLUMNS[model]!)) throw new Error(`fake ${model}: include/select of ${key}`);
    }
    return out;
  }

  function stored(data: Row): Row {
    const out: Row = {};
    for (const [key, v] of Object.entries(data)) {
      if (v === undefined) continue;
      out[key] = v === Prisma.DbNull || v === Prisma.JsonNull ? null : v;
    }
    return out;
  }

  function unique(model: string, where: Row): Row | undefined {
    return tables[model]!.find((r) => matches(model, r, where));
  }

  for (const model of Object.keys(COLUMNS)) {
    const m: Row = {};
    m.findMany = async (args: Row = {}) =>
      page(sortRows(model, tables[model]!.filter((r) => matches(model, r, args.where)), args.orderBy), args).map(
        (r) => shape(model, r, args),
      );
    m.findFirst = async (args: Row = {}) => {
      const row = sortRows(model, tables[model]!.filter((r) => matches(model, r, args.where)), args.orderBy)[0];
      return row === undefined ? null : shape(model, row, args);
    };
    m.findFirstOrThrow = async (args: Row = {}) => {
      const row = await m.findFirst(args);
      if (row === null) throw new Error(`fake ${model}: findFirstOrThrow found nothing`);
      return row;
    };
    m.findUnique = async (args: Row) => {
      const row = unique(model, args.where);
      return row === undefined ? null : shape(model, row, args);
    };
    m.findUniqueOrThrow = async (args: Row) => {
      const row = unique(model, args.where);
      if (row === undefined) throw new Error(`fake ${model}: findUniqueOrThrow found nothing`);
      return shape(model, row, args);
    };
    m.create = async (args: Row) => {
      const now = new Date();
      const row: Row = { ...COLUMNS[model], id: `${model}-${++seq}`, ...stored(args.data) };
      if ("createdAt" in COLUMNS[model]! && row.createdAt === null) row.createdAt = now;
      if ("updatedAt" in COLUMNS[model]!) row.updatedAt = now;
      if ("at" in COLUMNS[model]! && row.at === null) row.at = now;
      if (!("id" in COLUMNS[model]!)) delete row.id;
      tables[model]!.push(row);
      return shape(model, row, args);
    };
    m.update = async (args: Row) => {
      const row = unique(model, args.where);
      if (row === undefined) throw new Error(`fake ${model}: update against no row`);
      Object.assign(row, stored(args.data));
      if ("updatedAt" in COLUMNS[model]!) row.updatedAt = new Date();
      return shape(model, row, args);
    };
    m.updateMany = async (args: Row) => {
      const rows = tables[model]!.filter((r) => matches(model, r, args.where));
      for (const row of rows) Object.assign(row, stored(args.data));
      return { count: rows.length };
    };
    m.delete = async (args: Row) => {
      const row = unique(model, args.where);
      if (row === undefined) throw new Error(`fake ${model}: delete against no row`);
      tables[model] = tables[model]!.filter((r) => r !== row);
      return row;
    };
    m.deleteMany = async (args: Row = {}) => {
      const rows = tables[model]!.filter((r) => matches(model, r, args.where));
      tables[model] = tables[model]!.filter((r) => !rows.includes(r));
      return { count: rows.length };
    };
    m.count = async (args: Row = {}) => tables[model]!.filter((r) => matches(model, r, args.where)).length;
    m.aggregate = async (args: Row) => {
      const rows = tables[model]!.filter((r) => matches(model, r, args.where));
      const max: Row = {};
      for (const field of Object.keys((args._max as Row) ?? {})) {
        const values = rows.map((r) => r[field]).filter((v) => v !== null && v !== undefined);
        max[field] = values.length > 0 ? Math.max(...values) : null;
      }
      return { _max: max };
    };
    for (const fn of FNS) if (typeof m[fn] !== "function") throw new Error(`fake: ${fn} missing`);
    mock[model] = m;
  }

  mock.$transaction = async (run: unknown) => {
    if (Array.isArray(run)) return Promise.all(run);
    const snapshot = Object.fromEntries(
      Object.entries(tables).map(([model, rows]) => [model, rows.map((r) => ({ ...r }))]),
    );
    try {
      return await (run as (tx: unknown) => Promise<unknown>)(mock);
    } catch (error) {
      tables = snapshot;
      throw error;
    }
  };

  return {
    get tables() {
      return tables;
    },
    load(seed) {
      seq = 0;
      tables = {};
      for (const model of Object.keys(COLUMNS)) {
        tables[model] = ((seed as Row)[model] ?? []).map((row: Row) => ({ ...COLUMNS[model], ...row }));
      }
    },
    byId,
  };
}
/* eslint-enable @typescript-eslint/no-explicit-any */
