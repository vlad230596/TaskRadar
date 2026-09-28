import { describe, it, expect } from "vitest";
import { INBOX_TITLE_LIMIT, splitInboxText } from "../src/domain/inboxSplit";

/** Words until the text is at least [length] characters long. */
function words(length: number, word = "слово"): string {
  const parts: string[] = [];
  while (parts.join(" ").length < length) parts.push(word);
  return parts.join(" ");
}

describe("splitInboxText", () => {
  it("leaves a line of up to 120 characters whole, as today", () => {
    const text = "а".repeat(INBOX_TITLE_LIMIT);
    expect(splitInboxText(text)).toEqual({ title: text, description: null });
    expect(splitInboxText("  Купить лампочки. Две штуки.  ")).toEqual({
      title: "Купить лампочки. Две штуки.",
      description: null,
    });
  });

  it("cuts a long line at the end of its first sentence", () => {
    const rest = words(150);
    const result = splitInboxText(`Починить забор на даче. ${rest}`);
    expect(result).toEqual({ title: "Починить забор на даче", description: rest });
  });

  it("keeps a question or exclamation mark, which change what the title means", () => {
    const rest = words(150);
    expect(splitInboxText(`Продлить страховку до марта? ${rest}`).title).toBe("Продлить страховку до марта?");
    expect(splitInboxText(`Не забыть про день рождения! ${rest}`).title).toBe("Не забыть про день рождения!");
  });

  it("treats a line break as a sentence end", () => {
    const rest = words(150);
    expect(splitInboxText(`Список к ремонту\n${rest}`)).toEqual({ title: "Список к ремонту", description: rest });
  });

  it("skips a short lead-in like «Да.» rather than making it the title", () => {
    const rest = words(150);
    expect(splitInboxText(`Итак. Позвонить сантехнику завтра. ${rest}`).title).toBe(
      "Итак. Позвонить сантехнику завтра",
    );
  });

  it("falls back to a word boundary, marked with an ellipsis, when the first sentence is too long", () => {
    const text = words(300);
    const { title, description } = splitInboxText(text);
    expect(title.endsWith("…")).toBe(true);
    expect(title.length).toBeLessThanOrEqual(INBOX_TITLE_LIMIT + 1);
    // Cut between words, never inside one, and nothing lost.
    expect(title.slice(0, -1).split(" ").every((w) => w === "слово")).toBe(true);
    expect(`${title.slice(0, -1)} ${description}`).toBe(text);
  });

  it("hard-cuts a single word longer than the limit", () => {
    const text = "x".repeat(200);
    expect(splitInboxText(text)).toEqual({ title: "x".repeat(120), description: "x".repeat(80) });
  });

  it("does not take a sentence end past the limit", () => {
    const text = `${words(130)}. хвост`;
    const { title } = splitInboxText(text);
    expect(title.endsWith("…")).toBe(true);
  });
});
