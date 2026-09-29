import { describe, it, expect } from "vitest";
import { generatePassword, parseEmail } from "../src/domain/userAdmin";

describe("generatePassword", () => {
  it("is 16 characters long", () => {
    expect(generatePassword()).toHaveLength(16);
  });

  it("uses only characters that are easy to read off a screen", () => {
    // No 0/O, 1/l/I: the password is typed on a phone.
    for (let i = 0; i < 200; i += 1) {
      expect(generatePassword()).toMatch(/^[abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789]+$/);
    }
  });

  it("does not repeat itself", () => {
    const seen = new Set(Array.from({ length: 200 }, () => generatePassword()));
    expect(seen.size).toBe(200);
  });
});

describe("parseEmail", () => {
  it("trims and lowercases", () => {
    expect(parseEmail("  Boris@Example.COM \n")).toBe("boris@example.com");
  });

  it("rejects junk", () => {
    for (const junk of ["", "   ", "no-at-sign", "@example.com", "a@b", "a b@example.com", "a@@example.com"]) {
      expect(() => parseEmail(junk), JSON.stringify(junk)).toThrow(/not an email address/);
    }
  });

  it("rejects a missing value", () => {
    expect(() => parseEmail(undefined)).toThrow(/not an email address/);
  });
});
