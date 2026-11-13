import { FastifyInstance, FastifyPluginAsync, FastifyReply } from "fastify";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { authenticateAgentToken, bearerAgentToken } from "../lib/agentTokens";
import type { UserStore } from "../lib/users";
import { createTaskRadarMcpServer, McpContext } from "../mcp/taskradarMcp";

/**
 * The MCP endpoint for coding agents: Streamable HTTP, stateless, JSON answers.
 *
 *     claude mcp add --transport http taskradar https://<host>/mcp \
 *       --header "Authorization: Bearer trk_..."
 *
 * AUTH. A personal agent token (../lib/agentTokens.ts), checked here on every
 * request -- the session guard skips this path (`SELF_AUTHENTICATED_ROUTES`).
 * A JWT is not accepted here, and a token is not accepted anywhere else.
 *
 * STATELESS. A new MCP server and transport per POST, no session id, and
 * `enableJsonResponse`: each request is one JSON-RPC exchange with one JSON
 * answer. There is nothing to notify a client about between requests, so the
 * standalone SSE stream (GET) and session teardown (DELETE) answer 405, which
 * is what the protocol says a server without them should answer. It also
 * means nothing here depends on which backend instance a request lands on.
 *
 * WRITES go through the app's own routes, called in-process with a session
 * token for the agent token's user that lives one minute and never leaves the
 * server (`callApi` below). See ../mcp/taskradarMcp.ts for why.
 */

/** Lifetime of the in-process session token behind one tool call. */
const INTERNAL_TOKEN_TTL_SECONDS = 60;

function unauthorized(reply: FastifyReply): void {
  reply
    .status(401)
    .header("www-authenticate", 'Bearer realm="taskradar-mcp"')
    .send({ error: "Unauthorized", message: "Unauthorized" });
}

function methodNotAllowed(reply: FastifyReply): void {
  reply
    .status(405)
    .header("allow", "POST")
    .send({
      jsonrpc: "2.0",
      error: {
        code: -32000,
        message: "Method not allowed: this MCP endpoint is stateless, use POST",
      },
      id: null,
    });
}

export function mcpRoutes(users: UserStore): FastifyPluginAsync {
  return async function register(app: FastifyInstance): Promise<void> {
    app.post("/mcp", async (request, reply) => {
      const token = bearerAgentToken(request.headers.authorization);
      const userId = token === null ? null : await authenticateAgentToken(token, users);
      if (userId === null) {
        unauthorized(reply);
        return reply;
      }

      const internalToken = () =>
        app.jwt.sign({ sub: userId }, { expiresIn: INTERNAL_TOKEN_TTL_SECONDS });
      const context: McpContext = {
        userId,
        async callApi(method, url, payload) {
          const res = await app.inject({
            method,
            url,
            ...(payload === undefined ? {} : { payload }),
            headers: { authorization: `Bearer ${internalToken()}` },
          });
          let body: unknown;
          try {
            body = res.body === "" ? null : res.json();
          } catch {
            body = { message: res.body };
          }
          return { status: res.statusCode, body };
        },
        async fetchBytes(url) {
          const res = await app.inject({
            method: "GET",
            url,
            headers: { authorization: `Bearer ${internalToken()}` },
          });
          return { status: res.statusCode, body: res.rawPayload };
        },
      };

      const server = createTaskRadarMcpServer(context);
      // No `sessionIdGenerator`: that is what makes the transport stateless.
      const transport = new StreamableHTTPServerTransport({ enableJsonResponse: true });

      // From here on the SDK writes the response itself.
      reply.hijack();
      reply.raw.on("close", () => {
        void transport.close();
        void server.close();
      });
      try {
        await server.connect(transport);
        await transport.handleRequest(request.raw, reply.raw, request.body);
      } catch (error) {
        request.log.error(error, "MCP request failed");
        if (!reply.raw.headersSent) {
          reply.raw.writeHead(500, { "content-type": "application/json" });
          reply.raw.end(
            JSON.stringify({
              jsonrpc: "2.0",
              error: { code: -32603, message: "Internal server error" },
              id: null,
            }),
          );
        }
      }
      return reply;
    });

    app.get("/mcp", async (_request, reply) => {
      methodNotAllowed(reply);
      return reply;
    });

    app.delete("/mcp", async (_request, reply) => {
      methodNotAllowed(reply);
      return reply;
    });
  };
}
