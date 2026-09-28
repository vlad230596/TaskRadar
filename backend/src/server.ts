import path from "node:path";
import dotenv from "dotenv";

// Load environment variables from the repo-root .env (one level up from backend/).
// This is the single source of truth for secrets: DATABASE_URL, AUTH_EMAIL,
// AUTH_PASSWORD_HASH, JWT_SECRET and COOKIE_SECURE all come from there.
dotenv.config({ path: path.resolve(__dirname, "..", "..", ".env") });

import { buildApp } from "./app";
import { ensureOwner } from "./lib/users";
import { loadAuthConfig } from "./lib/authConfig";

const PORT = process.env.PORT ? Number(process.env.PORT) : 3001;
const HOST = "0.0.0.0";

async function main(): Promise<void> {
  // buildApp() validates the auth configuration and throws if it is missing or
  // malformed, so a misconfigured deployment fails here instead of starting up as
  // an app nobody can log into.
  const authConfig = loadAuthConfig();
  // The first user's login comes from .env; put it on their row before anyone
  // can try to log in.
  await ensureOwner(authConfig);
  const app = await buildApp({ authConfig });

  try {
    await app.listen({ port: PORT, host: HOST });
    app.log.info(`TaskRadar backend listening on http://${HOST}:${PORT}`);
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }
}

main().catch((err: unknown) => {
  // No logger yet if buildApp() itself failed (e.g. invalid auth config).
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
