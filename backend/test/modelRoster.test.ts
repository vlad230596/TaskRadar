import { describe, it, expect, vi } from "vitest";
import {
  afterAttempt,
  COOLDOWN_MS,
  DISABLE_WINDOW_MS,
  eligible,
  planMulti,
  planSingle,
  RosterEntry,
} from "../src/domain/modelRoster";
import { runMulti, runSingle, type MultiOutcome } from "../src/domain/modelRouter";
import { UpstreamModelError } from "../src/lib/llmClient";

/*
 * The roster's rules as agreed: start with the model that answered last,
 * race the top one back in, skip a model on three failures, switch it off on
 * six within a week, never probe in the background.
 */

const NOW = new Date("2026-10-14T12:00:00Z");
const ago = (ms: number) => new Date(NOW.getTime() - ms);
const MIN = 60_000;

function entry(name: string, overrides: Partial<RosterEntry> = {}): RosterEntry {
  return {
    id: name,
    name,
    label: null,
    baseUrl: null,
    apiKeyEnv: null,
    enabled: true,
    autoDisabledAt: null,
    consecutiveFailures: 0,
    failStreakStartedAt: null,
    lastSuccessAt: null,
    lastFailureAt: null,
    ...overrides,
  };
}

const names = (entries: RosterEntry[]) => entries.map((e) => e.name);

describe("planSingle", () => {
  it("asks the top alone when it is the one that answered last", () => {
    const plan = planSingle(
      [entry("a", { lastSuccessAt: ago(MIN) }), entry("b", { lastSuccessAt: ago(10 * MIN) })],
      NOW,
    );
    expect(names(plan.first)).toEqual(["a"]);
    expect(names(plan.fallback)).toEqual(["b"]);
  });

  it("asks the top alone when nothing has answered yet", () => {
    const plan = planSingle([entry("a"), entry("b")], NOW);
    expect(names(plan.first)).toEqual(["a"]);
    expect(names(plan.fallback)).toEqual(["b"]);
  });

  it("races a top that failed lately against the one that answered last", () => {
    const plan = planSingle(
      [
        entry("a", {
          consecutiveFailures: 1,
          lastSuccessAt: ago(60 * MIN),
          lastFailureAt: ago(MIN),
        }),
        entry("b", { lastSuccessAt: ago(MIN) }),
        entry("c"),
      ],
      NOW,
    );
    expect(names(plan.first)).toEqual(["a", "b"]);
    expect(names(plan.fallback)).toEqual(["c"]);
  });

  it("skips a model with three failures in a row, until the cooldown is over", () => {
    const failing = entry("a", { consecutiveFailures: 3, lastFailureAt: ago(MIN) });
    const good = entry("b", { lastSuccessAt: ago(MIN) });
    expect(names(planSingle([failing, good], NOW).first)).toEqual(["b"]);

    const rested = { ...failing, lastFailureAt: ago(COOLDOWN_MS + MIN) };
    expect(names(planSingle([rested, good], NOW).first)).toEqual(["a", "b"]);
  });

  it("leaves out switched-off models, by the owner or by their failures", () => {
    const list = [
      entry("a", { enabled: false }),
      entry("b", { autoDisabledAt: ago(MIN) }),
      entry("c"),
    ];
    expect(names(eligible(list, NOW))).toEqual(["c"]);
  });

  it("still asks someone when every usable model is cooling down", () => {
    const list = [
      entry("a", { consecutiveFailures: 3, lastFailureAt: ago(MIN) }),
      entry("b", { consecutiveFailures: 4, lastFailureAt: ago(MIN) }),
    ];
    expect(names(planSingle(list, NOW).first)).toEqual(["a"]);
  });
});

describe("planMulti", () => {
  it("takes the first two worth asking", () => {
    const list = [entry("a", { enabled: false }), entry("b"), entry("c"), entry("d")];
    expect(names(planMulti(list, NOW))).toEqual(["b", "c"]);
  });
});

describe("afterAttempt", () => {
  it("a success clears the streak", () => {
    const update = afterAttempt(
      entry("a", { consecutiveFailures: 2, failStreakStartedAt: ago(MIN) }),
      true,
      NOW,
    );
    expect(update).toEqual({
      consecutiveFailures: 0,
      failStreakStartedAt: null,
      lastSuccessAt: NOW,
    });
  });

  it("counts failures in a row and switches the model off on the sixth within a week", () => {
    let model = entry("a");
    for (let i = 0; i < 5; i++) {
      model = { ...model, ...afterAttempt(model, false, NOW) };
      expect(model.autoDisabledAt).toBeNull();
    }
    const sixth = afterAttempt(model, false, NOW);
    expect(sixth.consecutiveFailures).toBe(6);
    expect(sixth.autoDisabledAt).toEqual(NOW);
    expect(sixth.autoDisabledReason).toContain("6 неудач подряд");
  });

  it("starts the count over when the streak is older than a week", () => {
    const old = entry("a", {
      consecutiveFailures: 5,
      failStreakStartedAt: ago(DISABLE_WINDOW_MS + MIN),
    });
    const update = afterAttempt(old, false, NOW);
    expect(update.consecutiveFailures).toBe(1);
    expect(update.autoDisabledAt).toBeUndefined();
  });
});

describe("runSingle", () => {
  const fail = (category: "provider_down" | "cancelled" = "provider_down") =>
    Promise.reject(new UpstreamModelError("down", category));

  it("the first success of a race wins, and both outcomes are recorded", async () => {
    let releaseSlow!: (value: string) => void;
    const record = vi.fn(async () => {});
    const result = await runSingle(
      { first: [entry("top"), entry("good")], fallback: [] },
      {
        attempt: (e) =>
          e.name === "good"
            ? Promise.resolve("from good")
            : new Promise<string>((resolve) => (releaseSlow = resolve)),
        record,
      },
    );
    expect(result).toBe("from good");
    // The loser is left to finish, so the roster learns whether it is back.
    releaseSlow("from top");
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(record.mock.calls.map(([e, ok]) => [(e as RosterEntry).name, ok])).toEqual([
      ["good", true],
      ["top", true],
    ]);
  });

  it("falls back in order when the first ones fail", async () => {
    const record = vi.fn(async () => {});
    const asked: string[] = [];
    const result = await runSingle(
      { first: [entry("a")], fallback: [entry("b"), entry("c")] },
      {
        attempt: (e) => {
          asked.push(e.name);
          return e.name === "c" ? Promise.resolve("from c") : fail();
        },
        record,
      },
    );
    expect(result).toBe("from c");
    expect(asked).toEqual(["a", "b", "c"]);
    expect(record.mock.calls.map(([, ok]) => ok)).toEqual([false, false, true]);
  });

  it("a cancellation stops everything and teaches the roster nothing", async () => {
    const record = vi.fn(async () => {});
    const attempt = vi.fn(() => fail("cancelled"));
    await expect(
      runSingle({ first: [entry("a")], fallback: [entry("b")] }, { attempt, record }),
    ).rejects.toMatchObject({ category: "cancelled" });
    expect(attempt).toHaveBeenCalledTimes(1);
    expect(record).not.toHaveBeenCalled();
  });

  it("with nothing to ask, says so", async () => {
    await expect(
      runSingle({ first: [], fallback: [] }, { attempt: vi.fn(), record: vi.fn() }),
    ).rejects.toMatchObject({ category: "model_not_found" });
  });
});

describe("runMulti", () => {
  it("hears each model as it settles, and answers with the first success", async () => {
    const outcomes: MultiOutcome<string>[] = [];
    const result = await runMulti(
      [entry("slow"), entry("fast"), entry("broken")],
      {
        attempt: async (e) => {
          if (e.name === "broken") throw new UpstreamModelError("down", "provider_down");
          await new Promise((resolve) => setTimeout(resolve, e.name === "slow" ? 20 : 0));
          return `from ${e.name}`;
        },
        record: async () => {},
      },
      (outcome) => outcomes.push(outcome),
    );
    expect(result).toBe("from fast");
    expect(outcomes.map((o) => [o.entry.name, o.ok])).toEqual([
      ["broken", false],
      ["fast", true],
      ["slow", true],
    ]);
  });

  it("fails only when every model failed", async () => {
    await expect(
      runMulti(
        [entry("a"), entry("b")],
        {
          attempt: async () => {
            throw new UpstreamModelError("down", "provider_down");
          },
          record: async () => {},
        },
        () => {},
      ),
    ).rejects.toBeInstanceOf(UpstreamModelError);
  });
});
