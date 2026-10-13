import { FastifyInstance } from "fastify";
import { z } from "zod";
import { OWNER_SUBJECT } from "../lib/authConfig";
import { HttpError } from "../lib/errors";
import { prisma } from "../lib/prisma";
import { userIdOf } from "../lib/users";
import { computeStats } from "../domain/aiStats";
import {
  AI_LEVEL_MAX,
  AI_LEVEL_MIN,
  isLevelOverridden,
  LEVEL_RULES,
  levelRules,
  levelRulesVersion,
} from "../domain/aiLevels";
import { buildDictationMessages, DICTATION_PROMPT_VERSION } from "../domain/dictation";
import {
  buildNoteMessages,
  buildSandboxMessages,
  buildTaskTidyMessages,
  NOTE_PROMPT_VERSION,
  SANDBOX_PROMPT_VERSION,
  TASK_TIDY_PROMPT_VERSION,
} from "../domain/tidy";
import { ensurePromptOverridesLoaded, writeLevelOverride } from "../domain/promptOverrides";

/*
 * The owner's view into AI processing (14.10.2026): statistics from the
 * dataset, and the prompts -- every kind at every level, as the model reads
 * them -- with the level blocks editable. Under `/dictation/` because Caddy
 * forwards known prefixes only.
 *
 * Owner only, both: the dataset holds every user's words, and the prompts
 * decide what the owner's key is spent on.
 */

/** How many rows a statistics request reads at most. */
const STATS_ROW_LIMIT = 20_000;

const statsQuerySchema = z.object({
  /** The last N days; 0 for all time. */
  days: z.coerce.number().int().min(0).max(3650).default(30),
});

const levelParamSchema = z.object({
  level: z.coerce.number().int().min(AI_LEVEL_MIN).max(AI_LEVEL_MAX),
});

const levelBodySchema = z.object({
  /** The block's lines, or null to go back to the default. */
  rules: z.array(z.string().trim().min(1).max(400)).min(1).max(20).nullable(),
});

/** What the prompts are shown with: a fixed sample, not anybody's data. */
const SAMPLE = {
  text: "пример",
  timeZone: "Europe/Moscow",
  now: new Date("2026-10-14T09:00:00Z"),
};

function requireOwner(userId: string) {
  if (userId !== OWNER_SUBJECT) throw new HttpError(403, "Only the owner can see this");
}

async function describePrompts() {
  await ensurePromptOverridesLoaded();
  const suffix = levelRulesVersion();
  const levels: {
    level: number;
    rules: readonly string[];
    defaultRules: readonly string[];
    overridden: boolean;
  }[] = [];
  for (let level = AI_LEVEL_MIN; level <= AI_LEVEL_MAX; level++) {
    levels.push({
      level,
      rules: levelRules(level),
      defaultRules: LEVEL_RULES[level] ?? [],
      overridden: isLevelOverridden(level),
    });
  }
  const kinds = [
    {
      kind: "task",
      version: DICTATION_PROMPT_VERSION + suffix,
      build: (level: number) => buildDictationMessages({ ...SAMPLE, level }),
    },
    {
      kind: "task_tidy",
      version: TASK_TIDY_PROMPT_VERSION + suffix,
      build: (level: number) => buildTaskTidyMessages({ ...SAMPLE, level }),
    },
    {
      kind: "note",
      version: NOTE_PROMPT_VERSION + suffix,
      build: (level: number) => buildNoteMessages({ ...SAMPLE, level }),
    },
    {
      kind: "sandbox",
      version: SANDBOX_PROMPT_VERSION + suffix,
      build: (level: number) =>
        buildSandboxMessages({
          ...SAMPLE,
          level,
          projects: [{ id: "prj_example", name: "Пример проекта" }],
        }),
    },
  ].map(({ kind, version, build }) => ({
    kind,
    version,
    prompts: levels.map(({ level }) => {
      const [system, user] = build(level);
      return { level, system: system!.content, user: user!.content };
    }),
  }));
  return { levels, kinds };
}

export function dictationInsightRoutes() {
  return async function (app: FastifyInstance): Promise<void> {
    app.get("/dictation/stats", async (request, reply) => {
      requireOwner(userIdOf(request));
      const { days } = statsQuerySchema.parse(request.query);
      const since = days === 0 ? undefined : new Date(Date.now() - days * 24 * 60 * 60 * 1000);
      const rows = await prisma.dictationParse.findMany({
        where: since === undefined ? {} : { createdAt: { gte: since } },
        orderBy: { createdAt: "desc" },
        take: STATS_ROW_LIMIT,
        select: {
          kind: true,
          model: true,
          promptVersion: true,
          level: true,
          status: true,
          durationMs: true,
          result: true,
          linkedAt: true,
          finalTitle: true,
          finalDescription: true,
          finalContent: true,
        },
      });
      reply.send({ days, rows: rows.length, ...computeStats(rows) });
    });

    app.get("/dictation/prompts", async (request, reply) => {
      requireOwner(userIdOf(request));
      reply.send(await describePrompts());
    });

    app.put("/dictation/prompts/levels/:level", async (request, reply) => {
      requireOwner(userIdOf(request));
      const { level } = levelParamSchema.parse(request.params);
      const { rules } = levelBodySchema.parse(request.body);
      await writeLevelOverride(level, rules);
      reply.send(await describePrompts());
    });
  };
}
