import { describe, it, expect } from "vitest";
import { PUBLIC_ROUTES, isPublicRoute, sessionCookieOptions } from "../src/lib/authGuard";
import { SESSION_TTL_SECONDS } from "../src/lib/authConfig";
import type { AuthConfig } from "../src/lib/authConfig";

const config: AuthConfig = {
  email: "owner@example.com",
  passwordHash: "$2b$04$zV5VFEALedx8Rfd/ucwUSOrHYSSr8xveuActiCTdzOmCsBSDTbYXO",
  jwtSecret: "a".repeat(64),
  cookieSecure: false,
};

describe("PUBLIC_ROUTES", () => {
  it("contains exactly the three intended public routes", () => {
    expect([...PUBLIC_ROUTES].sort()).toEqual(["GET /health", "POST /auth/login", "POST /auth/logout"]);
  });
});

describe("isPublicRoute", () => {
  it("recognises the public routes", () => {
    expect(isPublicRoute("GET", "/health")).toBe(true);
    expect(isPublicRoute("POST", "/auth/login")).toBe(true);
    expect(isPublicRoute("POST", "/auth/logout")).toBe(true);
  });

  it("treats the data routes as protected", () => {
    expect(isPublicRoute("GET", "/projects")).toBe(false);
    expect(isPublicRoute("POST", "/projects")).toBe(false);
    expect(isPublicRoute("GET", "/projects/:id")).toBe(false);
    expect(isPublicRoute("PATCH", "/tasks/:id")).toBe(false);
    expect(isPublicRoute("DELETE", "/notes/:id")).toBe(false);
  });

  it("is method-sensitive: the right path with the wrong method is not public", () => {
    expect(isPublicRoute("POST", "/health")).toBe(false);
    expect(isPublicRoute("GET", "/auth/login")).toBe(false);
    expect(isPublicRoute("DELETE", "/auth/logout")).toBe(false);
  });

  it("fails closed for an unresolved route", () => {
    // A 404 has no matched route pattern; it must not be treated as public.
    expect(isPublicRoute("GET", undefined)).toBe(false);
  });

  it("does not match near-miss paths", () => {
    expect(isPublicRoute("GET", "/health/")).toBe(false);
    expect(isPublicRoute("GET", "/healthz")).toBe(false);
    expect(isPublicRoute("POST", "/auth/login/extra")).toBe(false);
    expect(isPublicRoute("GET", "/")).toBe(false);
  });
});

describe("sessionCookieOptions", () => {
  it("marks the cookie httpOnly, lax and app-wide", () => {
    const options = sessionCookieOptions(config);
    expect(options.httpOnly).toBe(true);
    expect(options.sameSite).toBe("lax");
    expect(options.path).toBe("/");
  });

  it("matches the cookie lifetime to the token lifetime", () => {
    expect(sessionCookieOptions(config).maxAge).toBe(SESSION_TTL_SECONDS);
  });

  it("drives `secure` from the config rather than hardcoding it", () => {
    expect(sessionCookieOptions({ ...config, cookieSecure: false }).secure).toBe(false);
    expect(sessionCookieOptions({ ...config, cookieSecure: true }).secure).toBe(true);
  });
});
