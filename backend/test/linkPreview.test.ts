import { describe, it, expect, beforeAll, afterAll, beforeEach, vi } from "vitest";
import http from "node:http";
import type { AddressInfo } from "node:net";
import type { FastifyInstance } from "fastify";
import type { AuthConfig } from "../src/lib/authConfig";
import { inMemoryUsers, tokenFor, USER_A, USER_B } from "./support/users";
import {
  BlockedUrlError,
  checkUrl,
  decodeEntities,
  fetchLinkPreview,
  isBlockedAddress,
  parseHtmlPreview,
} from "../src/domain/linkPreview";
import type { LinkPreviewResult } from "../src/domain/linkPreview";

/*
 * `GET /link-preview` (task editor, design/task-editor-spec.md §5, §10): the
 * SSRF policy, the fetcher against a real local HTTP server, and the route's
 * cache and daily limit over a fake Prisma.
 */
const prismaMock = vi.hoisted(() => ({
  linkPreview: { findUnique: vi.fn(), upsert: vi.fn() },
  linkPreviewUsage: { upsert: vi.fn() },
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));

process.env.DATABASE_URL ??= "postgresql://placeholder:placeholder@localhost:5432/placeholder";

describe("isBlockedAddress", () => {
  it.each([
    "127.0.0.1",
    "127.1.2.3",
    "10.0.0.5",
    "172.16.0.1",
    "172.31.255.255",
    "192.168.1.1",
    "169.254.169.254", // cloud metadata
    "169.254.0.1",
    "100.64.0.1",
    "0.0.0.0",
    "224.0.0.1",
    "255.255.255.255",
    "198.18.0.1",
    "::1",
    "::",
    "fe80::1",
    "fe80::1%eth0",
    "fc00::1",
    "fd00:ec2::254", // AWS metadata over IPv6
    "ff02::1",
    "::ffff:127.0.0.1", // IPv4-mapped
    "::ffff:7f00:1", // the same, in hex
    "::ffff:169.254.169.254",
    "::ffff:10.0.0.1",
    "64:ff9b::7f00:1", // NAT64 to loopback
    "64:ff9b::a9fe:a9fe", // NAT64 to the metadata service
    "2002:7f00:1::1", // 6to4 of loopback
    "2001:db8::1",
    "not an address",
    "",
  ])("blocks %s", (address) => {
    expect(isBlockedAddress(address)).toBe(true);
  });

  it.each([
    "93.184.216.34",
    "8.8.8.8",
    "172.32.0.1",
    "100.128.0.1",
    "2606:4700:4700::1111",
    "2a00:1450:4010:c05::64",
    "::ffff:8.8.8.8",
    "64:ff9b::808:808",
  ])("allows %s", (address) => {
    expect(isBlockedAddress(address)).toBe(false);
  });
});

describe("checkUrl", () => {
  it.each([
    "ftp://example.com/",
    "file:///etc/passwd",
    "gopher://example.com/",
    "http://user:pass@example.com/",
    "http://127.0.0.1/",
    "http://[::1]/",
    "http://[::ffff:127.0.0.1]:8080/",
    "http://169.254.169.254/latest/meta-data/",
    "http://2130706433/", // 127.0.0.1 as one number -- the URL parser normalises it
    "http://0x7f.1/",
    "not a url",
  ])("refuses %s", (url) => {
    expect(() => checkUrl(url)).toThrow(BlockedUrlError);
  });

  it("lets a public URL through to the resolver", () => {
    expect(checkUrl("https://example.com/path?q=1").hostname).toBe("example.com");
  });
});

describe("parseHtmlPreview", () => {
  it("prefers og:title and reads og:site_name", () => {
    const html = `<html><head><title>Plain</title>
      <meta content="Сайт" property="og:site_name">
      <meta property="og:title" content="Open &amp; Graph"></head></html>`;
    expect(parseHtmlPreview(Buffer.from(html), "text/html; charset=utf-8")).toEqual({
      title: "Open & Graph",
      siteName: "Сайт",
    });
  });

  it("falls back to <title>, collapsing whitespace", () => {
    const html = "<title>\n  Hello\n   world &#8212; &#x41;  </title>";
    expect(parseHtmlPreview(Buffer.from(html))).toEqual({
      title: "Hello world — A",
      siteName: null,
    });
  });

  it("decodes a page in windows-1251", () => {
    // "Привет" in cp1251.
    const title = Buffer.from([0xcf, 0xf0, 0xe8, 0xe2, 0xe5, 0xf2]);
    const html = Buffer.concat([
      Buffer.from('<meta charset="windows-1251"><title>'),
      title,
      Buffer.from("</title>"),
    ]);
    expect(parseHtmlPreview(html).title).toBe("Привет");
  });

  it("caps a very long title", () => {
    const title = parseHtmlPreview(Buffer.from(`<title>${"x".repeat(1000)}</title>`)).title!;
    expect(title.length).toBe(300);
  });

  it("decodes entities but leaves unknown ones alone", () => {
    expect(decodeEntities("a &laquo;b&raquo; &unknown; &#0;")).toBe("a «b» &unknown; &#0;");
  });
});

describe("fetchLinkPreview against a local server", () => {
  let server: http.Server;
  let port: number;
  let handler: (req: http.IncomingMessage, res: http.ServerResponse) => void;

  beforeAll(async () => {
    server = http.createServer((req, res) => handler(req, res));
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    port = (server.address() as AddressInfo).port;
  });

  afterAll(async () => {
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  });

  /*
   * "site.test" is the local server, and is the ONE loopback address the
   * policy lets through; "inside.test" resolves to a private address and
   * "mixed.test" to a public and a private one. Everything else is the real
   * policy.
   */
  const resolve = async (host: string) => {
    if (host === "site.test") return [{ address: "127.0.0.1", family: 4 }];
    if (host === "inside.test") return [{ address: "10.1.2.3", family: 4 }];
    if (host === "mixed.test") {
      return [
        { address: "127.0.0.1", family: 4 },
        { address: "192.168.0.10", family: 4 },
      ];
    }
    throw Object.assign(new Error(`ENOTFOUND ${host}`), { code: "ENOTFOUND" });
  };
  const isBlocked = (address: string) => address !== "127.0.0.1" && isBlockedAddress(address);
  const options = { resolve, isBlocked, timeoutMs: 1000 };
  const site = () => `http://site.test:${port}`;

  it("reads the title of a page", async () => {
    handler = (_req, res) => {
      res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
      res.end("<html><head><title>Локальная страница</title></head></html>");
    };
    expect(await fetchLinkPreview(`${site()}/page`, options)).toEqual({
      title: "Локальная страница",
      siteName: null,
    });
  });

  it("refuses the same server when the policy is the real one", async () => {
    handler = (_req, res) => res.end("<title>should not be read</title>");
    await expect(fetchLinkPreview(`${site()}/`, { resolve, timeoutMs: 1000 })).rejects.toThrow(
      BlockedUrlError,
    );
    await expect(
      fetchLinkPreview(`http://127.0.0.1:${port}/`, { timeoutMs: 1000 }),
    ).rejects.toThrow(BlockedUrlError);
  });

  it("refuses a name that resolves to a private address, or to any private address", async () => {
    await expect(fetchLinkPreview(`http://inside.test:${port}/`, options)).rejects.toThrow(
      /blocked address/,
    );
    await expect(fetchLinkPreview(`http://mixed.test:${port}/`, options)).rejects.toThrow(
      /blocked address/,
    );
  });

  it("follows a redirect to a public page", async () => {
    handler = (req, res) => {
      if (req.url === "/start") {
        res.writeHead(302, { location: "/end" });
        res.end();
      } else {
        res.writeHead(200, { "content-type": "text/html" });
        res.end("<title>After redirect</title>");
      }
    };
    expect((await fetchLinkPreview(`${site()}/start`, options))?.title).toBe("After redirect");
  });

  it.each([
    ["a literal private address", "http://10.0.0.1/"],
    ["the metadata service", "http://169.254.169.254/latest/meta-data/"],
    ["a name pointing inside", "http://inside.test/"],
    ["IPv6 loopback", "http://[::1]/"],
    ["another scheme", "file:///etc/passwd"],
  ])("does not follow a redirect to %s", async (_name, location) => {
    handler = (_req, res) => {
      res.writeHead(301, { location });
      res.end();
    };
    await expect(fetchLinkPreview(`${site()}/`, options)).rejects.toThrow(BlockedUrlError);
  });

  it("gives up after five redirects", async () => {
    let hops = 0;
    handler = (_req, res) => {
      hops++;
      res.writeHead(302, { location: `/loop${hops}` });
      res.end();
    };
    expect(await fetchLinkPreview(`${site()}/`, options)).toBeNull();
    expect(hops).toBe(6);
  });

  it("reads at most maxBytes of the body", async () => {
    handler = (_req, res) => {
      res.writeHead(200, { "content-type": "text/html" });
      res.write(`<html>${" ".repeat(2000)}`);
      res.end("<title>Too far down</title>");
    };
    expect(await fetchLinkPreview(`${site()}/`, { ...options, maxBytes: 1000 })).toBeNull();
    expect((await fetchLinkPreview(`${site()}/`, options))?.title).toBe("Too far down");
  });

  it("does not parse what is not HTML, or an error page", async () => {
    handler = (_req, res) => {
      res.writeHead(200, { "content-type": "image/png" });
      res.end("<title>png</title>");
    };
    expect(await fetchLinkPreview(`${site()}/`, options)).toBeNull();
    handler = (_req, res) => {
      res.writeHead(404, { "content-type": "text/html" });
      res.end("<title>Not found</title>");
    };
    expect(await fetchLinkPreview(`${site()}/`, options)).toBeNull();
  });

  it("times out on a server that never answers", async () => {
    handler = () => undefined;
    await expect(fetchLinkPreview(`${site()}/`, { ...options, timeoutMs: 200 })).rejects.toThrow();
  });
});

describe("GET /link-preview", () => {
  const baseConfig: AuthConfig = {
    email: USER_A.email,
    passwordHash: "$2b$04$zV5VFEALedx8Rfd/ucwUSOrHYSSr8xveuActiCTdzOmCsBSDTbYXO",
    jwtSecret: "test-jwt-secret-".repeat(4),
    cookieSecure: false,
  };
  let app: FastifyInstance;
  let token: string;
  let tokenB: string;
  let now = new Date("2026-11-11T12:00:00.000Z");
  const fetches: string[] = [];
  let answer: LinkPreviewResult | null | Error = null;
  let cache: Map<
    string,
    { url: string; title: string | null; siteName: string | null; failed: boolean; fetchedAt: Date }
  >;
  let usage: Map<string, number>;

  beforeAll(async () => {
    const { buildApp } = await import("../src/app");
    app = await buildApp({
      authConfig: baseConfig,
      users: inMemoryUsers(),
      logger: false,
      linkPreview: {
        fetch: async (url) => {
          fetches.push(url);
          if (answer instanceof Error) throw answer;
          return answer;
        },
        dailyLimit: 3,
        now: () => now,
      },
    });
    await app.ready();
    token = await tokenFor(app, USER_A.email);
    tokenB = await tokenFor(app, USER_B.email);
  });

  afterAll(async () => {
    await app?.close();
  });

  beforeEach(() => {
    now = new Date("2026-11-11T12:00:00.000Z");
    fetches.length = 0;
    answer = { title: "Example", siteName: "Site" };
    cache = new Map();
    usage = new Map();
    prismaMock.linkPreview.findUnique.mockImplementation(
      ({ where }: { where: { url: string } }) => cache.get(where.url) ?? null,
    );
    prismaMock.linkPreview.upsert.mockImplementation(
      ({
        where,
        create,
      }: {
        where: { url: string };
        create: {
          url: string;
          title: string | null;
          siteName: string | null;
          failed: boolean;
          fetchedAt: Date;
        };
      }) => {
        cache.set(where.url, { ...create });
        return create;
      },
    );
    prismaMock.linkPreviewUsage.upsert.mockImplementation(
      ({ where }: { where: { userId_day: { userId: string; day: string } } }) => {
        const key = `${where.userId_day.userId}/${where.userId_day.day}`;
        usage.set(key, (usage.get(key) ?? 0) + 1);
        return { count: usage.get(key) };
      },
    );
  });

  function preview(url: string, bearer = token) {
    return app.inject({
      method: "GET",
      url: `/link-preview?url=${encodeURIComponent(url)}`,
      headers: { authorization: `Bearer ${bearer}` },
    });
  }

  it("answers the title and caches it without the fragment", async () => {
    const res = await preview("https://example.com/a#section");
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      url: "https://example.com/a",
      title: "Example",
      siteName: "Site",
    });

    const again = await preview("https://example.com/a#other");
    expect(again.statusCode).toBe(200);
    expect(fetches).toEqual(["https://example.com/a"]);
    // A cache hit is free.
    expect(usage.get(`${USER_A.id}/2026-11-11`)).toBe(1);
  });

  it("answers 204 when there is nothing to show, and remembers the failure for a day", async () => {
    answer = new BlockedUrlError("blocked");
    expect((await preview("http://internal.example/")).statusCode).toBe(204);
    expect((await preview("http://internal.example/")).statusCode).toBe(204);
    expect(fetches).toHaveLength(1);

    now = new Date(now.getTime() + 25 * 60 * 60 * 1000);
    answer = { title: "Back up", siteName: null };
    const later = await preview("http://internal.example/");
    expect(later.statusCode).toBe(200);
    expect(fetches).toHaveLength(2);
  });

  it("keeps a title for 30 days", async () => {
    await preview("https://example.com/");
    now = new Date(now.getTime() + 29 * 24 * 60 * 60 * 1000);
    await preview("https://example.com/");
    expect(fetches).toHaveLength(1);
    now = new Date(now.getTime() + 2 * 24 * 60 * 60 * 1000);
    await preview("https://example.com/");
    expect(fetches).toHaveLength(2);
  });

  it("answers 429 past the day's limit, per user", async () => {
    for (const n of [1, 2, 3])
      expect((await preview(`https://example.com/${n}`)).statusCode).toBe(200);
    expect((await preview("https://example.com/4")).statusCode).toBe(429);
    expect((await preview("https://example.com/4", tokenB)).statusCode).toBe(200);
    // Cached links still answer.
    expect((await preview("https://example.com/1")).statusCode).toBe(200);
  });

  it.each([
    "",
    "not a url",
    "ftp://example.com/",
    "javascript:alert(1)",
    `https://e.com/${"a".repeat(2100)}`,
  ])("refuses %j with 400", async (url) => {
    expect((await preview(url)).statusCode).toBe(400);
    expect(fetches).toHaveLength(0);
  });

  it("needs a token", async () => {
    const res = await app.inject({
      method: "GET",
      url: "/link-preview?url=https%3A%2F%2Fexample.com",
    });
    expect(res.statusCode).toBe(401);
  });
});
