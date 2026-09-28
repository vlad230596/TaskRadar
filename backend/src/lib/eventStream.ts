import type { FastifyReply } from "fastify";

/**
 * A reply sent as Server-Sent Events rather than one JSON body.
 *
 * Only for a request that is slow for a reason outside this server -- today a
 * dictation parse, which waits on someone else's model. The point is not the
 * data (the result is one small object at the end) but that the phone hears
 * *something* every few seconds and can tell a slow answer from a dead one.
 *
 * THE REPLY IS HIJACKED
 *
 * Fastify's reply pipeline assumes one body; an event stream is many writes
 * over tens of seconds. So the raw response is taken over and Fastify's hooks
 * and error handler no longer apply -- which is why the caller must have done
 * everything that can fail as an ordinary HTTP error (validation, auth, "no
 * model configured") *before* opening the stream, and must turn every failure
 * after it into an `error` event itself.
 *
 * WHAT KEEPS IT UNBUFFERED
 *
 * `Cache-Control: no-transform` asks proxies not to compress or rewrite it
 * (Caddy's `encode` honours it), `X-Accel-Buffering: no` does the same for an
 * nginx, should one ever sit in front. The Caddy block also sets
 * `flush_interval -1` -- see deploy/Caddyfile.taskradar.example.
 */
export interface EventStream {
  /**
   * Writes one event. [data] is sent as JSON on one `data:` line. A no-op once
   * the stream is closed, so a late stage cannot write into a dead socket.
   */
  send(event: string, data?: Record<string, unknown>): void;
  /** Ends the response. Idempotent. */
  close(): void;
  /** Aborted when the client goes away before [close]. */
  readonly signal: AbortSignal;
}

export interface EventStreamOptions {
  /** Interval of `heartbeat` events while nothing else is said. */
  heartbeatMs: number;
}

/** The headers that make a response an unbuffered event stream. */
export const EVENT_STREAM_HEADERS = {
  "content-type": "text/event-stream; charset=utf-8",
  "cache-control": "no-cache, no-transform",
  connection: "keep-alive",
  "x-accel-buffering": "no",
} as const;

export function openEventStream(reply: FastifyReply, options: EventStreamOptions): EventStream {
  reply.hijack();
  const raw = reply.raw;
  raw.writeHead(200, EVENT_STREAM_HEADERS);
  // Headers out now, not with the first event: a proxy that waits for a body
  // before forwarding anything would otherwise hold back `accepted` too.
  raw.flushHeaders();

  const aborted = new AbortController();
  let closed = false;

  const write = (event: string, data: Record<string, unknown>) => {
    if (closed) return;
    raw.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  };

  const heartbeat = setInterval(() => write("heartbeat", {}), options.heartbeatMs);

  const finish = () => {
    if (closed) return;
    closed = true;
    clearInterval(heartbeat);
  };

  // `close` on the response, not the request: the request's fires as soon as
  // its body has been read, which is before anything here has started.
  raw.on("close", () => {
    if (!raw.writableFinished) aborted.abort();
    finish();
  });

  return {
    send: (event, data = {}) => write(event, data),
    close: () => {
      if (closed) return;
      finish();
      raw.end();
    },
    signal: aborted.signal,
  };
}

/** Whether the request asked for an event stream rather than one JSON body. */
export function wantsEventStream(accept: string | undefined): boolean {
  return (accept ?? "").toLowerCase().includes("text/event-stream");
}
