import { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma";
import { userIdOf } from "../lib/users";
import { HttpError } from "../lib/errors";
import { utcDay } from "../lib/aiLimit";
import { linkPreviewQuerySchema } from "../schemas";
import { LinkPreviewResult, fetchLinkPreview } from "../domain/linkPreview";

/*
 * `GET /link-preview?url=...` (task editor, design/task-editor-spec.md §5, §10):
 * the title of a page, for the link cards under a task's description.
 *
 *   200 { url, title, siteName }   a title or a site name was found
 *   204                            nothing to show -- the card shows the domain
 *   429                            the day's previews are spent
 *
 * Answers are cached in `link_previews` for everyone: 30 days for a title, a
 * day for a failure (a page that was down gets another chance tomorrow). A
 * cached answer costs nothing; a fetch costs one of the user's previews for the
 * day, counted apart from the AI requests (`link_preview_usage`). The fetch
 * itself, and why it is safe to point at a URL a user typed, is in
 * ../domain/linkPreview.ts.
 *
 * Nothing about links is stored on the task: the client finds them in the text.
 */

export interface LinkPreviewFeature {
  /** Fetches a page's preview; tests substitute their own. */
  fetch: (url: string) => Promise<LinkPreviewResult | null>;
  /** Fetches one user may cause per UTC day. */
  dailyLimit: number;
  now?: () => Date;
}

export const DEFAULT_LINK_PREVIEW_DAILY_LIMIT = 100;
const SUCCESS_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const FAILURE_TTL_MS = 24 * 60 * 60 * 1000;

export function loadLinkPreviewDailyLimit(env: NodeJS.ProcessEnv = process.env): number {
  const value = Number(env.LINK_PREVIEW_DAILY_LIMIT);
  return Number.isInteger(value) && value > 0 ? value : DEFAULT_LINK_PREVIEW_DAILY_LIMIT;
}

export function defaultLinkPreviewFeature(): LinkPreviewFeature {
  return { fetch: (url) => fetchLinkPreview(url), dailyLimit: loadLinkPreviewDailyLimit() };
}

/** The cache key: the URL as the parser writes it, without the fragment. */
export function cacheKey(raw: string): string {
  const url = new URL(raw);
  url.hash = "";
  return url.href;
}

export function linkPreviewRoutes(feature: LinkPreviewFeature) {
  const now = feature.now ?? (() => new Date());

  return async function routes(app: FastifyInstance): Promise<void> {
    app.get("/link-preview", async (request, reply) => {
      const { url: raw } = linkPreviewQuerySchema.parse(request.query);
      const userId = userIdOf(request);
      const url = cacheKey(raw);
      const at = now();

      const send = (row: { title: string | null; siteName: string | null; failed: boolean }) => {
        if (row.failed || (row.title === null && row.siteName === null)) {
          reply.status(204).send();
        } else {
          reply.send({ url, title: row.title, siteName: row.siteName });
        }
      };

      const cached = await prisma.linkPreview.findUnique({ where: { url } });
      if (cached) {
        const ttl = cached.failed ? FAILURE_TTL_MS : SUCCESS_TTL_MS;
        if (at.getTime() - cached.fetchedAt.getTime() < ttl) {
          send(cached);
          return;
        }
      }

      const usage = await prisma.linkPreviewUsage.upsert({
        where: { userId_day: { userId, day: utcDay(at) } },
        create: { userId, day: utcDay(at), count: 1 },
        update: { count: { increment: 1 } },
        select: { count: true },
      });
      if (usage.count > feature.dailyLimit) {
        throw new HttpError(
          429,
          `Daily link preview limit reached (${feature.dailyLimit}). It resets at 00:00 UTC.`,
        );
      }

      let result: LinkPreviewResult | null;
      try {
        result = await feature.fetch(url);
      } catch (error) {
        // Refused by the SSRF policy, unreachable, timed out: all "no preview".
        request.log.info({ url, err: error }, "link preview failed");
        result = null;
      }

      const row = {
        title: result?.title ?? null,
        siteName: result?.siteName ?? null,
        failed: result === null,
        fetchedAt: at,
      };
      await prisma.linkPreview.upsert({ where: { url }, create: { url, ...row }, update: row });
      send(row);
    });
  };
}
