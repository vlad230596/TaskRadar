import { describe, expect, it } from "vitest";
import { buildDictationMessages, interpretModelReply } from "../src/domain/dictation";
import {
  buildNoteMessages,
  buildSandboxMessages,
  buildTaskTidyMessages,
  interpretSandboxReply,
  interpretTaskTidyReply,
} from "../src/domain/tidy";
import { fitTitle, shortTitleFrom, TITLE_LIMIT } from "../src/domain/titleLimit";

const input = {
  text: "текст",
  timeZone: "Europe/Moscow",
  now: new Date("2026-11-26T10:00:00.000Z"),
};

const longTitle =
  "Так как мы знаем всю историю начислений, мы можем автоматически проверять отпускные, если будем отмечать отпуск в приложении";

describe("the title limit", () => {
  it("is stated, as one number, in every prompt that asks for a title", () => {
    const prompts = {
      dictation: buildDictationMessages(input)[0]!.content,
      task_tidy: buildTaskTidyMessages(input)[0]!.content,
      note: buildNoteMessages(input)[0]!.content,
      sandbox: buildSandboxMessages({ ...input, projects: [] })[0]!.content,
    };
    for (const [kind, prompt] of Object.entries(prompts)) {
      expect(prompt, kind).toContain(`не длиннее ${TITLE_LIMIT} символов`);
      expect(prompt, kind).toContain("не обрывай его многоточием");
      // No other figure for the title left behind.
      expect(prompt, kind).not.toMatch(/до (60|120) символов/);
    }
  });

  it("leaves a title within the limit as the model wrote it", () => {
    expect(fitTitle("Купить гвозди", "Для дачи.")).toEqual({
      title: "Купить гвозди",
      body: "Для дачи.",
    });
  });

  it("moves an over-long title into the body whole, and gives a short one", () => {
    const fitted = fitTitle(longTitle, "Расчёт в лайв-режиме.");
    expect(fitted.title.length).toBeLessThanOrEqual(TITLE_LIMIT);
    expect(fitted.body).toBe(`${longTitle}.\n\nРасчёт в лайв-режиме.`);
    expect(fitTitle(longTitle, null).body).toBe(`${longTitle}.`);
  });

  it("never makes a title longer than the limit, the mark included", () => {
    for (const text of [longTitle, "а".repeat(300), `${"слово ".repeat(40)}`]) {
      expect(shortTitleFrom(text)!.length).toBeLessThanOrEqual(TITLE_LIMIT);
    }
  });

  it("holds every kind's reply to it, losing no words", () => {
    const dictated = interpretModelReply(
      JSON.stringify({ title: longTitle, description: null }),
      "2026-11-26",
    );
    expect(dictated.title.length).toBeLessThanOrEqual(TITLE_LIMIT);
    expect(dictated.description).toContain(longTitle);

    const tidied = interpretTaskTidyReply(
      JSON.stringify({ title: longTitle, description: "Детали." }),
      longTitle,
    );
    expect(tidied.title.length).toBeLessThanOrEqual(TITLE_LIMIT);
    expect(tidied.description).toBe(`${longTitle}.\n\nДетали.`);

    const line = interpretSandboxReply(
      JSON.stringify({ text: longTitle, title: longTitle, description: null }),
      [],
      longTitle,
    );
    expect(line.title.length).toBeLessThanOrEqual(TITLE_LIMIT);
    expect(line.description).toContain(longTitle);
  });
});
