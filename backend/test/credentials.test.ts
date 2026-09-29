import { describe, it, expect } from "vitest";
import { constantTimeEquals, normaliseEmail, verifyCredentials, verifyPassword } from "../src/lib/credentials";

/**
 * Known-value fixtures for a TEST-ONLY password. These are not the real owner
 * credentials -- the real password exists only in the gitignored
 * CREDENTIALS.local.md and its hash only in the gitignored .env.
 */
const TEST_PASSWORD = "test-password-not-the-real-one";

/** Hash of TEST_PASSWORD at cost factor 12, the factor used for the real password. */
const HASH_COST_12 = "$2b$12$z7Qc2.CvoVgGEjBfsFNQN.BRa5/FbH9mM62TpBkICjtNY46RM4yWi";

/** Same password at cost 4, used where a test only needs a valid hash quickly. */
const HASH_COST_4 = "$2b$04$zV5VFEALedx8Rfd/ucwUSOrHYSSr8xveuActiCTdzOmCsBSDTbYXO";

describe("verifyPassword", () => {
  it("accepts the correct password against a known cost-12 bcrypt hash", async () => {
    await expect(verifyPassword(TEST_PASSWORD, HASH_COST_12)).resolves.toBe(true);
  });

  it("rejects a wrong password", async () => {
    await expect(verifyPassword("wrong-password", HASH_COST_12)).resolves.toBe(false);
  });

  it("rejects a password that is merely a prefix of the correct one", async () => {
    await expect(verifyPassword(TEST_PASSWORD.slice(0, -1), HASH_COST_12)).resolves.toBe(false);
  });

  it("rejects an empty password", async () => {
    await expect(verifyPassword("", HASH_COST_12)).resolves.toBe(false);
  });

  it("confirms the stored hash really is cost factor 12", () => {
    expect(HASH_COST_12.startsWith("$2b$12$")).toBe(true);
  });
});

describe("normaliseEmail", () => {
  it("trims surrounding whitespace and lowercases", () => {
    expect(normaliseEmail("  Owner@Example.COM \n")).toBe("owner@example.com");
  });
});

describe("constantTimeEquals", () => {
  it("returns true for identical strings", () => {
    expect(constantTimeEquals("abc", "abc")).toBe(true);
  });

  it("returns false for different strings of equal length", () => {
    expect(constantTimeEquals("abc", "abd")).toBe(false);
  });

  it("returns false for strings of different length without throwing", () => {
    // timingSafeEqual would throw on mismatched buffer lengths; the sha256
    // pre-hash inside constantTimeEquals is what makes this safe.
    expect(constantTimeEquals("abc", "abcdefghijkl")).toBe(false);
  });
});

describe("verifyCredentials", () => {
  const user = { id: "user-1", passwordHash: HASH_COST_4, disabledAt: null };

  it("returns the user's id for the correct password", async () => {
    await expect(verifyCredentials(user, TEST_PASSWORD)).resolves.toBe("user-1");
  });

  it("returns null for a wrong password", async () => {
    await expect(verifyCredentials(user, "nope")).resolves.toBeNull();
  });

  it("returns null when there is no such user", async () => {
    await expect(verifyCredentials(null, TEST_PASSWORD)).resolves.toBeNull();
  });

  it("returns null for a disabled user even with the correct password", async () => {
    const disabled = { ...user, disabledAt: new Date(0) };
    await expect(verifyCredentials(disabled, TEST_PASSWORD)).resolves.toBeNull();
  });

  it("still performs the bcrypt comparison when there is no user or the user is disabled", async () => {
    /*
     * Guards the timing property that makes the generic 401 meaningful: if the
     * implementation short-circuited on a missing or disabled user it would skip
     * bcrypt and return almost instantly, letting an attacker distinguish
     * "unknown email" from "wrong password" by response time alone.
     *
     * Uses a cost-12 hash so the real work is unmistakably slow, then asserts that
     * the fast-path candidates cost a comparable amount of time to a wrong-password
     * attempt rather than being effectively free.
     */
    const cost12 = { ...user, passwordHash: HASH_COST_12 };

    const startWrongPassword = performance.now();
    await verifyCredentials(cost12, "nope");
    const wrongPasswordMs = performance.now() - startWrongPassword;

    const startNoUser = performance.now();
    await verifyCredentials(null, TEST_PASSWORD);
    const noUserMs = performance.now() - startNoUser;

    const startDisabled = performance.now();
    await verifyCredentials({ ...cost12, disabledAt: new Date(0) }, TEST_PASSWORD);
    const disabledMs = performance.now() - startDisabled;

    // A skipped bcrypt compare would be sub-millisecond; a real one at cost 12 is
    // tens to hundreds of ms. Assert neither path is a fast path.
    expect(noUserMs).toBeGreaterThan(wrongPasswordMs / 4);
    expect(disabledMs).toBeGreaterThan(wrongPasswordMs / 4);
  });
});
