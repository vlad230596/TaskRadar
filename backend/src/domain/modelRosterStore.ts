import { prisma } from "../lib/prisma";
import { afterAttempt, RosterEntry } from "./modelRoster";
import { resolveDictationModel } from "./dictationModel";

/*
 * The roster in the database (`LlmModel` in prisma/schema.prisma). The rules
 * live in `./modelRoster.ts`; this is reading, writing and recording.
 */

/** What the owner sends to set the list: everything but the health. */
export interface RosterInput {
  /** An existing entry keeps its health; a new one starts clean. */
  id?: string | undefined;
  name: string;
  label?: string | null | undefined;
  baseUrl?: string | null | undefined;
  apiKeyEnv?: string | null | undefined;
  /** Absent keeps what is stored: an app that predates the field must not wipe it. */
  temperature?: number | null | undefined;
  enabled: boolean;
}

/** The roster as stored, in the owner's order. */
export async function readRoster(): Promise<RosterEntry[]> {
  return prisma.llmModel.findMany({ orderBy: { position: "asc" } });
}

/**
 * The roster to plan with. With nothing stored, the one model the server used
 * before rosters existed -- the `dictation.model` setting or `LLM_MODEL` --
 * as a single entry with no id, whose health is not recorded.
 */
export async function rosterForParsing(defaultModel: string): Promise<RosterEntry[]> {
  const stored = await readRoster();
  if (stored.length > 0) return stored;
  return [
    {
      id: null,
      name: await resolveDictationModel(defaultModel),
      label: null,
      baseUrl: null,
      apiKeyEnv: null,
      temperature: null,
      enabled: true,
      autoDisabledAt: null,
      consecutiveFailures: 0,
      failStreakStartedAt: null,
      lastSuccessAt: null,
      lastFailureAt: null,
    },
  ];
}

/**
 * Records one attempt's outcome on [entry]. Read fresh and written in one
 * transaction: two parses finishing together must not both count from the
 * same old streak.
 */
export async function recordAttempt(entry: RosterEntry, ok: boolean, now = new Date()) {
  const id = entry.id;
  if (id === null) return;
  await prisma.$transaction(async (tx) => {
    const current = await tx.llmModel.findUnique({ where: { id } });
    if (current === null) return;
    await tx.llmModel.update({ where: { id }, data: afterAttempt(current, ok, now) });
  });
}

/**
 * Replaces the list with [input], in that order. Entries named by id keep
 * their health; ids not in [input] are removed.
 */
export async function writeRoster(input: readonly RosterInput[]): Promise<RosterEntry[]> {
  await prisma.$transaction(async (tx) => {
    const keep = input.flatMap((entry) => (entry.id === undefined ? [] : [entry.id]));
    await tx.llmModel.deleteMany({ where: { id: { notIn: keep } } });
    for (const [position, entry] of input.entries()) {
      const fields = {
        position,
        name: entry.name,
        label: entry.label ?? null,
        baseUrl: entry.baseUrl ?? null,
        apiKeyEnv: entry.apiKeyEnv ?? null,
        enabled: entry.enabled,
        ...(entry.temperature === undefined ? {} : { temperature: entry.temperature }),
      };
      if (entry.id === undefined) {
        await tx.llmModel.create({ data: fields });
      } else {
        await tx.llmModel.updateMany({ where: { id: entry.id }, data: fields });
      }
    }
  });
  return readRoster();
}

/** "Включить снова": an automatically switched-off model, back with a clean slate. */
export async function reenableModel(id: string): Promise<RosterEntry[]> {
  await prisma.llmModel.updateMany({
    where: { id },
    data: {
      enabled: true,
      autoDisabledAt: null,
      autoDisabledReason: null,
      consecutiveFailures: 0,
      failStreakStartedAt: null,
    },
  });
  return readRoster();
}
