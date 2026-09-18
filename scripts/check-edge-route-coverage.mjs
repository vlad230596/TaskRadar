#!/usr/bin/env node
/*
 * Does Caddy's path allowlist still cover every route the backend serves?
 *
 * WHY THIS EXISTS
 *
 * `deploy/Caddyfile.taskradar.example` refuses anything outside an explicit
 * `@api path ...` list, which is the right posture for an origin that serves one
 * JSON API -- but it makes the edge a second place where routes are declared,
 * and the two drift silently. They drifted: `/scopes` (F7) and `/inbox` (F8)
 * were added to `backend/src/routes/` and never to the matcher, so the sandbox
 * answered 404 to every capture on a real phone while every test, including the
 * integration workflow, passed. A 404 from Caddy is byte-for-byte a 404 from
 * Fastify, so from the client it looks exactly like a client bug.
 *
 * The comment in the Caddyfile already warned about this ("TRAP: this list has
 * to be updated when a new top-level route is added") and pointed at the
 * integration workflow as the thing that would catch it. That was never true:
 * the workflow probed three hand-written paths, and a prefix nobody thought to
 * probe is precisely the prefix nobody thought to add. So the check is derived
 * from the source of truth instead of restated next to it.
 *
 * WHAT IT CHECKS
 *
 * For every `app.get("/x/:id", ...)` in `backend/src/routes/`, the top-level
 * segment `/x` has to appear in the matcher -- as `/x` when the backend serves
 * that exact path, and as `/x/*` when it serves anything below it. Caddy's
 * `path` matcher is exact unless the pattern ends in `*`, which is why the two
 * forms are counted separately rather than treated as one.
 *
 * Both Caddyfiles are checked, and their matcher lines must be identical: the
 * CI one exists only to exercise the production one, and a difference between
 * them means the check is testing something nobody deploys.
 *
 * Exits non-zero with the missing prefixes listed. Run it from anywhere:
 *
 *     node scripts/check-edge-route-coverage.mjs
 */

import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const routesDir = join(repoRoot, "backend", "src", "routes");
// Written with forward slashes because they end up in the failure message;
// `join` normalises them for the actual read on Windows.
const caddyfiles = ["deploy/Caddyfile.taskradar.example", "deploy/Caddyfile.ci"];

/** Every `app.<method>("<path>")` in the route modules. */
function declaredRoutes() {
  // Deliberately a regex over the source rather than booting Fastify and
  // reading `printRoutes()`: booting needs a database URL, a JWT secret and a
  // built `node_modules`, which would turn a check that must run everywhere
  // into one that only runs where the backend already runs.
  const call = /\bapp\.(get|post|put|patch|delete)\(\s*"([^"]+)"/g;
  const paths = new Set();

  for (const file of readdirSync(routesDir).filter((f) => f.endsWith(".ts"))) {
    const source = readFileSync(join(routesDir, file), "utf8");
    for (const [, , path] of source.matchAll(call)) paths.add(path);
  }

  if (paths.size === 0) {
    throw new Error(`No routes found in ${routesDir} -- has the shape changed?`);
  }
  return [...paths];
}

/** The patterns the two Caddy files allow through, by file. */
function matchers() {
  const line = /^\s*@api\s+path\s+(.+)$/m;

  return caddyfiles.map((relative) => {
    const source = readFileSync(join(repoRoot, relative), "utf8");
    const found = source.match(line);
    if (!found) {
      throw new Error(`No '@api path' matcher in ${relative}`);
    }
    return { file: relative, patterns: found[1].trim().split(/\s+/) };
  });
}

/**
 * The matcher patterns a route needs.
 *
 * `/inbox` needs the literal `/inbox`; `/inbox/:id/file` needs `/inbox/*`. A
 * route deeper than one segment never needs the bare prefix, and vice versa,
 * because Caddy's `path` is exact without a trailing `*`.
 */
function requiredPattern(routePath) {
  const segments = routePath.split("/").filter(Boolean);
  const top = `/${segments[0]}`;
  return segments.length > 1 ? `${top}/*` : top;
}

const routes = declaredRoutes();
const required = new Map();
for (const route of routes) {
  const pattern = requiredPattern(route);
  if (!required.has(pattern)) required.set(pattern, []);
  required.get(pattern).push(route);
}

const problems = [];
const files = matchers();

for (const { file, patterns } of files) {
  const allowed = new Set(patterns);
  for (const [pattern, examples] of required) {
    if (allowed.has(pattern)) continue;
    problems.push(
      `${file}: missing '${pattern}' -- the backend serves ${examples.sort().join(", ")}`,
    );
  }
}

// An allowlist entry with no route behind it is not a 404 waiting to happen, so
// it is reported as a note rather than a failure: /ready and /version are real
// routes declared in health.ts, but a leftover from a deleted feature is worth
// seeing without blocking a deploy on it.
const everyRequired = new Set(required.keys());
const stale = files[0].patterns.filter((p) => !everyRequired.has(p));

const [production, ci] = files;
if (production.patterns.join(" ") !== ci.patterns.join(" ")) {
  problems.push(
    `${ci.file} allows a different set of paths than ${production.file}; ` +
      "the CI ingress exists to exercise the production one, so they must match.",
  );
}

if (stale.length > 0) {
  console.log(`Note: allowed but not served by any route: ${stale.join(" ")}`);
}

if (problems.length > 0) {
  console.error("Caddy's allowlist does not cover the API:\n");
  for (const problem of problems) console.error(`  ${problem}`);
  console.error(
    "\nAdd the prefix to the '@api path' line in BOTH files under deploy/, then " +
      "re-paste the site block into the shared Caddyfile on the VDS " +
      "(see DEPLOYMENT.md) -- the file on the server is not deployed by CI.",
  );
  process.exit(1);
}

console.log(
  `Caddy allows every path the backend serves (${routes.length} routes, ` +
    `${required.size} prefixes).`,
);
