import type { UserRecord, UserStore } from "../../src/lib/users";

/** Password of every test user. */
export const TEST_PASSWORD = "test-password-not-the-real-one";
/** bcrypt hash of TEST_PASSWORD at cost 4 -- fast, since tests log in repeatedly. */
export const TEST_HASH = "$2b$04$zV5VFEALedx8Rfd/ucwUSOrHYSSr8xveuActiCTdzOmCsBSDTbYXO";

/** The person most tests act as. Also what `baseConfig.email` says. */
export const USER_A = { id: "user-a", email: "owner@example.com", name: "Anna" } as const;
/** A second person, for "cannot see / touch someone else's data" tests. */
export const USER_B = { id: "user-b", email: "second@example.com", name: "Boris" } as const;
/** An account that exists but is switched off. */
export const USER_DISABLED = { id: "user-off", email: "off@example.com", name: "Off" } as const;

/**
 * An in-memory {@link UserStore} holding USER_A, USER_B and USER_DISABLED, all
 * with TEST_PASSWORD. Pass it as `buildApp({ users })` so login and the guard
 * need no database. `disable(id)` flips an account off mid-test, to check that
 * a token issued earlier stops working.
 */
export function inMemoryUsers(): UserStore & { disable(id: string): void } {
  const rows = new Map<string, UserRecord & { email: string }>();
  for (const u of [USER_A, USER_B, USER_DISABLED]) {
    rows.set(u.id, {
      id: u.id,
      email: u.email,
      name: u.name,
      passwordHash: TEST_HASH,
      disabledAt: u.id === USER_DISABLED.id ? new Date(0) : null,
    });
  }
  return {
    async findByEmail(email) {
      const wanted = email.trim().toLowerCase();
      return [...rows.values()].find((u) => u.email === wanted) ?? null;
    },
    async isActive(id) {
      const u = rows.get(id);
      return u !== undefined && u.disabledAt === null;
    },
    disable(id) {
      const u = rows.get(id);
      if (u) u.disabledAt = new Date();
    },
  };
}

/**
 * Logs in through `POST /auth/login` and returns the Bearer token, so a test
 * can act as that user. The app must have been built with `users: inMemoryUsers()`.
 */
export async function tokenFor(
  app: { inject: (opts: { method: "POST"; url: string; payload: unknown }) => Promise<{ statusCode: number; json: () => unknown }> },
  email: string = USER_A.email,
): Promise<string> {
  const res = await app.inject({
    method: "POST",
    url: "/auth/login",
    payload: { email, password: TEST_PASSWORD },
  });
  if (res.statusCode !== 200) throw new Error(`login as ${email} failed: ${res.statusCode}`);
  return (res.json() as { token: string }).token;
}
