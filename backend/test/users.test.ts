import { describe, it, expect, vi, beforeEach } from "vitest";

const prismaMock = vi.hoisted(() => ({
  user: { upsert: vi.fn(), findUnique: vi.fn() },
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));

// Belt and braces, as in the other tests that mock the client.
process.env.DATABASE_URL ??= "postgresql://placeholder:placeholder@localhost:5432/placeholder";

import { ensureOwner, prismaUserStore } from "../src/lib/users";
import type { AuthConfig } from "../src/lib/authConfig";

const config: AuthConfig = {
  email: "owner@example.com",
  passwordHash: "$2b$04$zV5VFEALedx8Rfd/ucwUSOrHYSSr8xveuActiCTdzOmCsBSDTbYXO",
  jwtSecret: "a".repeat(64),
  cookieSecure: false,
};

beforeEach(() => {
  prismaMock.user.upsert.mockReset();
  prismaMock.user.findUnique.mockReset();
});

describe("ensureOwner", () => {
  it("upserts the user with id 'owner' from the config", async () => {
    prismaMock.user.upsert.mockResolvedValue({});
    await ensureOwner(config);

    expect(prismaMock.user.upsert).toHaveBeenCalledTimes(1);
    const args = prismaMock.user.upsert.mock.calls[0]?.[0] as {
      where: unknown;
      create: unknown;
      update: unknown;
    };
    expect(args.where).toEqual({ id: "owner" });
    expect(args.create).toEqual({
      id: "owner",
      email: config.email,
      name: "Owner",
      passwordHash: config.passwordHash,
    });
    // An existing row keeps its name; only the credentials follow `.env`.
    expect(args.update).toEqual({ email: config.email, passwordHash: config.passwordHash });
  });
});

describe("prismaUserStore", () => {
  it("looks a user up by the normalised email", async () => {
    prismaMock.user.findUnique.mockResolvedValue(null);
    await expect(prismaUserStore.findByEmail("  Owner@Example.COM ")).resolves.toBeNull();
    expect(prismaMock.user.findUnique).toHaveBeenCalledWith(
      expect.objectContaining({ where: { email: "owner@example.com" } }),
    );
  });

  it("treats a missing or disabled user as inactive", async () => {
    prismaMock.user.findUnique.mockResolvedValueOnce(null);
    await expect(prismaUserStore.isActive("gone")).resolves.toBe(false);
    prismaMock.user.findUnique.mockResolvedValueOnce({ disabledAt: new Date(0) });
    await expect(prismaUserStore.isActive("off")).resolves.toBe(false);
    prismaMock.user.findUnique.mockResolvedValueOnce({ disabledAt: null });
    await expect(prismaUserStore.isActive("on")).resolves.toBe(true);
  });
});
