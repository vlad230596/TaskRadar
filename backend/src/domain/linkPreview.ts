import { lookup as dnsLookup } from "node:dns";
import http from "node:http";
import https from "node:https";
import { BlockList, isIP } from "node:net";
import type { LookupFunction } from "node:net";

/*
 * The title of a page for a link card in the task editor
 * (design/task-editor-spec.md §5, §10).
 *
 * The server fetches a URL the user typed, which makes it the textbook SSRF
 * vector: "http://169.254.169.254/latest/meta-data/" or
 * "http://postgres:5432/" typed into a task would otherwise have this backend
 * read the cloud metadata service or poke the database network on the
 * user's behalf. So:
 *
 * - only http and https, no credentials in the URL;
 * - the host name is resolved here, and EVERY address it resolves to has to be
 *   public (`isBlockedAddress`): loopback, private, link-local (the metadata
 *   service), CGNAT, multicast, documentation and reserved ranges are refused,
 *   for IPv4 and IPv6, including IPv4 smuggled inside IPv6 (`::ffff:a.b.c.d`,
 *   NAT64, 6to4);
 * - the check happens inside the socket's own `lookup`, so the address that is
 *   checked is the address that is connected to. Resolving first and fetching
 *   by name afterwards would let a DNS answer with a zero TTL say "public" to
 *   the check and "127.0.0.1" to the connection (DNS rebinding);
 * - redirects are followed by hand, at most five, and each hop goes through all
 *   of the above again -- a public page answering `302 Location:
 *   http://10.0.0.1/` gets nowhere;
 * - 5 seconds for the whole exchange, redirects included, and at most 512 KB
 *   of body read; only HTML is parsed.
 *
 * What it reads: `og:title`, else `<title>`; and `og:site_name`.
 */

export interface LinkPreviewResult {
  title: string | null;
  siteName: string | null;
}

export class BlockedUrlError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "BlockedUrlError";
  }
}

// ---- Address policy ----

const blocked = new BlockList();
for (const [network, prefix] of [
  ["0.0.0.0", 8], // "this network"
  ["10.0.0.0", 8], // private
  ["100.64.0.0", 10], // CGNAT
  ["127.0.0.0", 8], // loopback
  ["169.254.0.0", 16], // link-local, incl. the 169.254.169.254 metadata service
  ["172.16.0.0", 12], // private
  ["192.0.0.0", 24], // IETF protocol assignments
  ["192.0.2.0", 24], // TEST-NET-1
  ["192.88.99.0", 24], // 6to4 relay anycast
  ["192.168.0.0", 16], // private
  ["198.18.0.0", 15], // benchmarking
  ["198.51.100.0", 24], // TEST-NET-2
  ["203.0.113.0", 24], // TEST-NET-3
  ["224.0.0.0", 4], // multicast
  ["240.0.0.0", 4], // reserved, incl. 255.255.255.255
] as const) {
  blocked.addSubnet(network, prefix, "ipv4");
}
for (const [network, prefix] of [
  ["::", 128], // unspecified
  ["::1", 128], // loopback
  ["100::", 64], // discard
  ["2001::", 32], // Teredo (tunnels to anywhere)
  ["2001:db8::", 32], // documentation
  ["fc00::", 7], // unique local, incl. fd00:ec2::254 (the AWS metadata service)
  ["fe80::", 10], // link-local
  ["fec0::", 10], // deprecated site-local
  ["ff00::", 8], // multicast
] as const) {
  blocked.addSubnet(network, prefix, "ipv6");
}

/** Expands an IPv6 address to its eight 16-bit groups, or null if it is not one. */
function ipv6Groups(address: string): number[] | null {
  let text = address.toLowerCase();
  const zone = text.indexOf("%");
  if (zone >= 0) text = text.slice(0, zone);
  // A trailing dotted IPv4 (::ffff:1.2.3.4) becomes two groups.
  const dotted = /(\d+\.\d+\.\d+\.\d+)$/.exec(text);
  if (dotted?.[1] !== undefined) {
    const octets = dotted[1].split(".").map(Number);
    if (octets.some((o) => o > 255)) return null;
    const [a = 0, b = 0, c = 0, d = 0] = octets;
    text = `${text.slice(0, dotted.index)}${((a << 8) | b).toString(16)}:${((c << 8) | d).toString(16)}`;
  }
  const halves = text.split("::");
  if (halves.length > 2) return null;
  const parse = (part: string | undefined) =>
    part === undefined || part === "" ? [] : part.split(":").map((g) => parseInt(g, 16));
  const head = parse(halves[0]);
  const tail = parse(halves[1]);
  const missing = 8 - head.length - tail.length;
  if (halves.length === 1 ? missing !== 0 : missing < 1) return null;
  const groups = [...head, ...Array<number>(halves.length === 1 ? 0 : missing).fill(0), ...tail];
  return groups.length === 8 && groups.every((g) => Number.isInteger(g) && g >= 0 && g <= 0xffff)
    ? groups
    : null;
}

function ipv4FromGroups(high: number, low: number): string {
  return `${high >> 8}.${high & 0xff}.${low >> 8}.${low & 0xff}`;
}

/**
 * Whether an address must not be fetched from. Anything that is not a valid IP
 * address is blocked too: the policy fails closed.
 */
export function isBlockedAddress(address: string): boolean {
  const family = isIP(address.split("%")[0] ?? "");
  if (family === 4) return blocked.check(address, "ipv4");
  if (family !== 6) return true;

  const groups = ipv6Groups(address);
  if (groups === null) return true;
  const [g0, g1, g2, g3, g4, g5, g6 = 0, g7 = 0] = groups;
  const embedded = ipv4FromGroups(g6, g7);
  // IPv4-mapped ::ffff:a.b.c.d and IPv4-compatible ::a.b.c.d: the IPv4 rules decide.
  if (g0 === 0 && g1 === 0 && g2 === 0 && g3 === 0 && g4 === 0 && (g5 === 0xffff || g5 === 0)) {
    if (g5 === 0 && g6 === 0 && (g7 === 0 || g7 === 1)) return true; // :: and ::1
    return isBlockedAddress(embedded);
  }
  // NAT64 64:ff9b::/96 -- the gateway would connect to the embedded IPv4.
  if (g0 === 0x64 && g1 === 0xff9b && g2 === 0 && g3 === 0 && g4 === 0 && g5 === 0) {
    return isBlockedAddress(embedded);
  }
  // 6to4 2002:AABB:CCDD::/16 embeds an IPv4 in the second and third groups.
  if (g0 === 0x2002) return isBlockedAddress(ipv4FromGroups(g1 ?? 0, g2 ?? 0));
  const canonical = groups.map((g) => g.toString(16)).join(":");
  return blocked.check(canonical, "ipv6");
}

// ---- Fetching ----

export interface FetchPreviewOptions {
  /** Whole exchange, redirects included. Default 5 s. */
  timeoutMs?: number;
  /** Body bytes read at most. Default 512 KB. */
  maxBytes?: number;
  maxRedirects?: number;
  /** Name resolution; tests substitute their own. Default: the system resolver. */
  resolve?: (hostname: string) => Promise<{ address: string; family: number }[]>;
  /** Address policy; tests may widen it to reach a local server. Default `isBlockedAddress`. */
  isBlocked?: (address: string) => boolean;
}

const DEFAULTS = { timeoutMs: 5000, maxBytes: 512 * 1024, maxRedirects: 5 };

function systemResolve(hostname: string): Promise<{ address: string; family: number }[]> {
  return new Promise((resolve, reject) => {
    dnsLookup(hostname, { all: true, verbatim: true }, (error, addresses) => {
      if (error) reject(error);
      else resolve(addresses);
    });
  });
}

/**
 * A `lookup` for the socket that refuses names resolving to any blocked
 * address. All addresses, not just the first: a name with one public and one
 * private A record would otherwise be a coin toss away from the private one.
 */
function guardedLookup(
  resolve: NonNullable<FetchPreviewOptions["resolve"]>,
  isBlocked: (address: string) => boolean,
): LookupFunction {
  return (hostname, options, callback) => {
    resolve(hostname).then(
      (addresses) => {
        const wanted =
          options.family === 4 || options.family === 6
            ? addresses.filter((a) => a.family === options.family)
            : addresses;
        if (addresses.length === 0 || wanted.length === 0) {
          callback(new BlockedUrlError(`${hostname} has no address`), "", 4);
          return;
        }
        const bad = addresses.find((a) => isBlocked(a.address));
        if (bad) {
          callback(new BlockedUrlError(`${hostname} resolves to a blocked address`), "", 4);
          return;
        }
        if (options.all) {
          (callback as unknown as (e: null, a: typeof wanted) => void)(null, wanted);
        } else {
          const first = wanted[0]!;
          callback(null, first.address, first.family);
        }
      },
      (error: NodeJS.ErrnoException) => callback(error, "", 4),
    );
  };
}

/** Checks the parts of a URL that need no network: scheme, credentials, literal IPs. */
export function checkUrl(
  raw: string,
  isBlocked: (address: string) => boolean = isBlockedAddress,
): URL {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new BlockedUrlError("Not a URL");
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new BlockedUrlError("Only http and https");
  }
  if (url.username !== "" || url.password !== "") {
    throw new BlockedUrlError("Credentials in the URL");
  }
  // A literal address never goes through `lookup`, so it is checked here.
  const host = url.hostname.replace(/^\[|\]$/g, "");
  if (isIP(host) !== 0 && isBlocked(host)) {
    throw new BlockedUrlError("Blocked address");
  }
  return url;
}

interface Response {
  status: number;
  location: string | undefined;
  contentType: string;
  body: Buffer;
}

function request(
  url: URL,
  lookup: LookupFunction,
  maxBytes: number,
  signal: AbortSignal,
): Promise<Response> {
  return new Promise((resolve, reject) => {
    const client = url.protocol === "https:" ? https : http;
    const req = client.request(
      url,
      {
        method: "GET",
        lookup,
        signal,
        // No connection reuse: every hop resolves (and is checked) afresh.
        agent: false,
        headers: {
          "User-Agent": "TaskRadarLinkPreview/1.0",
          Accept: "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1",
          "Accept-Language": "ru,en;q=0.8",
          "Accept-Encoding": "identity",
        },
      },
      (res) => {
        const status = res.statusCode ?? 0;
        const location = res.headers.location;
        const contentType = String(res.headers["content-type"] ?? "");
        if (status >= 300 && status < 400) {
          res.destroy();
          resolve({ status, location, contentType, body: Buffer.alloc(0) });
          return;
        }
        if (!/^\s*(text\/html|application\/xhtml\+xml)/i.test(contentType)) {
          res.destroy();
          resolve({ status, location, contentType, body: Buffer.alloc(0) });
          return;
        }
        const chunks: Buffer[] = [];
        let size = 0;
        let done = false;
        const finish = () => {
          if (done) return;
          done = true;
          resolve({ status, location, contentType, body: Buffer.concat(chunks) });
        };
        res.on("data", (chunk: Buffer) => {
          if (done) return;
          const room = maxBytes - size;
          chunks.push(chunk.length > room ? chunk.subarray(0, room) : chunk);
          size += Math.min(chunk.length, room);
          if (size >= maxBytes) {
            finish();
            res.destroy();
          }
        });
        res.on("end", finish);
        res.on("error", (error) => (done ? undefined : reject(error)));
        res.on("close", finish);
      },
    );
    req.on("error", reject);
    req.end();
  });
}

/**
 * Fetches a page and reads its title, or answers null when there is none to
 * show (not HTML, an error status, no title). Throws {@link BlockedUrlError}
 * for a URL the policy refuses; network errors and the timeout throw too.
 */
export async function fetchLinkPreview(
  raw: string,
  options: FetchPreviewOptions = {},
): Promise<LinkPreviewResult | null> {
  const timeoutMs = options.timeoutMs ?? DEFAULTS.timeoutMs;
  const maxBytes = options.maxBytes ?? DEFAULTS.maxBytes;
  const maxRedirects = options.maxRedirects ?? DEFAULTS.maxRedirects;
  const isBlocked = options.isBlocked ?? isBlockedAddress;
  const lookup = guardedLookup(options.resolve ?? systemResolve, isBlocked);

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(new Error("Link preview timed out")), timeoutMs);
  try {
    let url = checkUrl(raw, isBlocked);
    for (let hop = 0; ; hop++) {
      const response = await request(url, lookup, maxBytes, controller.signal);
      if (response.status >= 300 && response.status < 400) {
        if (response.location === undefined || hop >= maxRedirects) return null;
        url = checkUrl(new URL(response.location, url).href, isBlocked);
        continue;
      }
      if (response.status < 200 || response.status >= 300 || response.body.length === 0) {
        return null;
      }
      const preview = parseHtmlPreview(response.body, response.contentType);
      return preview.title === null && preview.siteName === null ? null : preview;
    }
  } finally {
    clearTimeout(timer);
  }
}

// ---- Parsing ----

const MAX_TITLE = 300;

const NAMED_ENTITIES: Readonly<Record<string, string>> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  nbsp: " ",
  laquo: "«",
  raquo: "»",
  mdash: "—",
  ndash: "–",
  hellip: "…",
};

export function decodeEntities(text: string): string {
  return text.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (whole, name: string) => {
    if (name[0] === "#") {
      const code =
        name[1] === "x" || name[1] === "X" ? parseInt(name.slice(2), 16) : Number(name.slice(1));
      return Number.isInteger(code) && code > 0 && code <= 0x10ffff
        ? String.fromCodePoint(code)
        : whole;
    }
    return NAMED_ENTITIES[name.toLowerCase()] ?? whole;
  });
}

function clean(text: string | undefined): string | null {
  if (text === undefined) return null;
  const value = decodeEntities(text).replace(/\s+/g, " ").trim();
  if (value === "") return null;
  return value.length > MAX_TITLE ? `${value.slice(0, MAX_TITLE - 1)}…` : value;
}

/** The charset a page says it is in: the header first, then `<meta>`. */
function charsetOf(head: string, contentType: string): string {
  const fromHeader = /charset=["']?([\w-]+)/i.exec(contentType)?.[1];
  const fromMeta =
    /<meta[^>]+charset=["']?([\w-]+)/i.exec(head)?.[1] ??
    /<meta[^>]+content=["'][^"']*charset=([\w-]+)/i.exec(head)?.[1];
  return (fromHeader ?? fromMeta ?? "utf-8").toLowerCase();
}

/** The content of a `<meta property|name="key" content="...">`, in either attribute order. */
function metaContent(html: string, key: string): string | undefined {
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const tags = html.match(/<meta\b[^>]*>/gi) ?? [];
  for (const tag of tags) {
    if (!new RegExp(`(?:property|name)\\s*=\\s*["']${escaped}["']`, "i").test(tag)) continue;
    const content =
      /content\s*=\s*"([^"]*)"/i.exec(tag)?.[1] ?? /content\s*=\s*'([^']*)'/i.exec(tag)?.[1];
    if (content !== undefined) return content;
  }
  return undefined;
}

/** Reads the title and site name out of an HTML document. */
export function parseHtmlPreview(body: Buffer, contentType = ""): LinkPreviewResult {
  const ascii = body.toString("latin1");
  let html: string;
  try {
    html = new TextDecoder(charsetOf(ascii.slice(0, 4096), contentType)).decode(body);
  } catch {
    html = body.toString("utf8");
  }
  const title =
    clean(metaContent(html, "og:title")) ??
    clean(metaContent(html, "twitter:title")) ??
    clean(/<title[^>]*>([\s\S]*?)<\/title>/i.exec(html)?.[1]);
  const siteName = clean(metaContent(html, "og:site_name"));
  return { title, siteName };
}
