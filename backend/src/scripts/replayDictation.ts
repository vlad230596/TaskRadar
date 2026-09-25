/*
 * Replays the dictation dataset (F14) against a model and the current prompt,
 * and scores the answers against what the user actually saved.
 *
 * The "request test" before switching models or shipping a prompt change: run
 * it with the candidate, compare the summary with the baseline line (the
 * answers the dataset already holds), and only then change the model in the
 * app or release the prompt.
 *
 * USAGE (inside the production container, where the database and the key are)
 *
 *   docker exec taskradar-backend-1 node dist/scripts/replayDictation.js \
 *     [--model vendor/model] [--limit 50] [--since 2026-09-01] \
 *     [--all] [--delay-ms 0] [--json]
 *
 *   --model     the model to replay with; default: the one in use right now
 *   --limit     the most recent N samples; default: all of them
 *   --since     only samples parsed on or after this date
 *   --all       include samples never saved as a task (no label): they are
 *               replayed for success rate and latency only
 *   --delay-ms  pause between requests, for rate-limited free models
 *   --json      one JSON object per sample, then the summary, instead of the
 *               table -- for keeping a run or diffing two
 *
 * Locally: `npx tsx src/scripts/replayDictation.ts ...` with DATABASE_URL and
 * LLM_* in the environment.
 *
 * WHAT IT DOES NOT DO
 *
 * It writes nothing. A replay is an experiment about the dataset, and feeding
 * its answers back into the dataset would make the next replay score models
 * against each other instead of against the user.
 *
 * Each sample is replayed at the moment it was originally parsed at
 * (`requestedAt`), in its original zone, so "в пятницу" means the same Friday
 * it meant then. Samples from an older prompt are replayed with the *current*
 * prompt -- that is the point -- and the table marks them.
 */
import { parseArgs } from "node:util";
import { prisma } from "../lib/prisma";
import { loadLlmConfig } from "../lib/llmConfig";
import { createOpenAiCompatibleClient } from "../lib/llmClient";
import {
  DICTATION_PROMPT_VERSION,
  ParsedDictation,
  createDictationParser,
} from "../domain/dictation";
import { resolveDictationModel } from "../domain/dictationModel";
import {
  SampleLabel,
  SampleScore,
  labelRemindDate,
  quantile,
  scoreSample,
  summarise,
} from "../domain/dictationReplay";

const { values: args } = parseArgs({
  options: {
    model: { type: "string" },
    limit: { type: "string" },
    since: { type: "string" },
    all: { type: "boolean", default: false },
    "delay-ms": { type: "string", default: "0" },
    json: { type: "boolean", default: false },
  },
});

function percent(rate: number): string {
  return `${Math.round(rate * 100)}%`.padStart(4);
}

/** [text] on one line, cut to [width]; padded to it only for a middle column. */
function clip(text: string | null, width: number, pad = true): string {
  const flat = (text ?? "—").replace(/\s+/g, " ");
  if (flat.length > width) return `${flat.slice(0, width - 1)}…`;
  return pad ? flat.padEnd(width) : flat;
}

async function main(): Promise<void> {
  const config = loadLlmConfig();
  if (config === null) {
    throw new Error("No model configured: set LLM_BASE_URL, LLM_API_KEY and LLM_MODEL.");
  }
  const model = args.model ?? (await resolveDictationModel(config.model));
  const parse = createDictationParser(createOpenAiCompatibleClient(config), async () => model);
  const delayMs = Number(args["delay-ms"]);

  const rows = await prisma.dictationParse.findMany({
    where: {
      ...(args.all ? {} : { finalTitle: { not: null } }),
      ...(args.since === undefined ? {} : { createdAt: { gte: new Date(args.since) } }),
    },
    orderBy: { createdAt: "desc" },
    ...(args.limit === undefined ? {} : { take: Number(args.limit) }),
  });
  rows.reverse();

  if (rows.length === 0) {
    console.log(
      args.all
        ? "The dataset is empty."
        : "No labelled samples yet: none has been saved as a task. Use --all to replay the rest.",
    );
    return;
  }

  const candidate: SampleScore[] = [];
  const baseline: SampleScore[] = [];
  const latencies: number[] = [];
  const baselineLatencies: number[] = [];

  if (!args.json) {
    console.log(
      `Replaying ${rows.length} sample(s) with ${model}, prompt v${DICTATION_PROMPT_VERSION}\n`,
    );
  }

  for (const [index, row] of rows.entries()) {
    const trace = await parse({
      text: row.inputText,
      timeZone: row.timeZone,
      now: row.requestedAt,
    });
    latencies.push(trace.durationMs);
    baselineLatencies.push(row.durationMs);

    const label: SampleLabel | null =
      row.finalTitle === null
        ? null
        : {
            title: row.finalTitle,
            description: row.finalDescription,
            remindDate: labelRemindDate(row.finalRemindAt),
          };
    const score = label === null ? null : scoreSample(trace.result, label);
    if (label !== null && score !== null) {
      candidate.push(score);
      baseline.push(scoreSample(row.result as ParsedDictation | null, label));
    }

    if (args.json) {
      console.log(
        JSON.stringify({
          id: row.id,
          input: row.inputText,
          label,
          original: { model: row.model, promptVersion: row.promptVersion, result: row.result },
          replay: {
            model,
            promptVersion: DICTATION_PROMPT_VERSION,
            result: trace.result,
            error: trace.error,
            rawReply: trace.rawReply,
            durationMs: trace.durationMs,
          },
          score,
        }),
      );
    } else {
      const mark =
        score === null
          ? trace.result === null
            ? "FAIL"
            : " -- "
          : !score.ok
            ? "FAIL"
            : score.titleExact && score.remindExact
              ? " ok "
              : "DIFF";
      const older =
        row.promptVersion === DICTATION_PROMPT_VERSION ? "" : ` (was v${row.promptVersion})`;
      console.log(`${String(index + 1).padStart(3)} ${mark} ${trace.durationMs}ms${older}`);
      console.log(`    сказано:   ${clip(row.inputText, 100, false)}`);
      if (label !== null) {
        console.log(
          `    сохранено: ${clip(label.title, 60)} | ${clip(label.remindDate, 10)} | ${clip(label.description, 50, false)}`,
        );
      }
      console.log(
        trace.result === null
          ? `    модель:    ошибка: ${trace.error}`
          : `    модель:    ${clip(trace.result.title, 60)} | ${clip(trace.result.remindDate, 10)} | ${clip(trace.result.description, 50, false)}`,
      );
    }

    if (delayMs > 0 && index < rows.length - 1) {
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }

  const summary = {
    model,
    promptVersion: DICTATION_PROMPT_VERSION,
    replay: {
      ...summarise(candidate),
      p50Ms: quantile(latencies, 0.5),
      p95Ms: quantile(latencies, 0.95),
    },
    baseline: {
      ...summarise(baseline),
      p50Ms: quantile(baselineLatencies, 0.5),
      p95Ms: quantile(baselineLatencies, 0.95),
    },
  };

  if (args.json) {
    console.log(JSON.stringify({ summary }));
    return;
  }

  const line = (name: string, s: typeof summary.replay) =>
    `${name.padEnd(10)} ok ${percent(s.okRate)}  title= ${percent(s.titleExactRate)}  ` +
    `title~ ${percent(s.titleSimilarityMean)}  descr= ${percent(s.descriptionExactRate)}  ` +
    `remind= ${percent(s.remindExactRate)}  p50 ${s.p50Ms}ms  p95 ${s.p95Ms}ms`;

  console.log(`\nScored against what was saved (${summary.replay.samples} labelled sample(s)):`);
  console.log(line("replay", summary.replay));
  console.log(line("baseline", summary.baseline));
  console.log(
    "\nbaseline = the answers the dataset already holds (their own models and prompt versions).",
  );
}

main()
  .catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
