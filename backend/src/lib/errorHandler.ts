import { FastifyError, FastifyReply, FastifyRequest } from "fastify";
import { ZodError } from "zod";
import { HttpError } from "./errors";

/**
 * PascalCase `error` names for the client-error statuses this app can plausibly
 * produce, keyed by status code.
 *
 * The body of a 4xx coming from Fastify must look like every other error body in
 * this app (`{ error, message }`), so the framework's own shape
 * (`{ statusCode, code, error, message }`, with `error` spelled "Bad Request")
 * is not reused. The names below follow the spelling the app already uses
 * elsewhere -- "Unauthorized" is exactly what `authGuard` sends, so a client can
 * switch on `error` without caring which layer produced the response.
 *
 * Deliberately NOT the Fastify `code` (e.g. "FST_ERR_CTP_EMPTY_JSON_BODY"):
 * that is a framework implementation detail, and pinning it in the public error
 * contract would make a Fastify upgrade a breaking API change for the clients.
 */
const CLIENT_ERROR_NAMES: Readonly<Record<number, string>> = {
  400: "BadRequest",
  401: "Unauthorized",
  403: "Forbidden",
  404: "NotFound",
  405: "MethodNotAllowed",
  406: "NotAcceptable",
  409: "Conflict",
  413: "PayloadTooLarge",
  414: "UriTooLong",
  415: "UnsupportedMediaType",
  422: "UnprocessableEntity",
  429: "TooManyRequests",
};

/** Fallback name for a 4xx with no entry in the map above. */
const GENERIC_CLIENT_ERROR_NAME = "ClientError";

/**
 * Returns the status code of an error that carries a *client* (4xx) status, or
 * `undefined` for anything else.
 *
 * `statusCode` is the convention Fastify and its plugins use to say "the caller
 * got this wrong, and here is the code to answer with". Only 4xx is honoured:
 * a 5xx (or a nonsensical/non-integer value) means either the server broke or the
 * error is not trustworthy, and both must fall through to the opaque 500 branch.
 */
function clientErrorStatus(error: unknown): number | undefined {
  const statusCode = (error as { statusCode?: unknown }).statusCode;
  if (typeof statusCode !== "number" || !Number.isInteger(statusCode)) {
    return undefined;
  }
  return statusCode >= 400 && statusCode <= 499 ? statusCode : undefined;
}

/**
 * Central Fastify error handler.
 *
 * - ZodError (thrown by `schema.parse()` in route handlers) -> 400 with the
 *   flattened list of issues.
 * - HttpError (and subclasses NotFoundError/ConflictError/ValidationError)
 *   -> whatever statusCode they carry.
 * - Any other error carrying a 4xx `statusCode` -> that status, in the same
 *   `{ error, message }` shape. These are the errors Fastify itself throws for a
 *   malformed request (empty or invalid JSON body, unsupported content type,
 *   oversized body): the caller is at fault, and answering 500 both lies to the
 *   client and buries a real outage under noise in the error log.
 * - Anything else -> 500, logged, no internals leaked to the client.
 */
export function registerErrorHandler(app: {
  setErrorHandler: (
    handler: (error: FastifyError | Error, request: FastifyRequest, reply: FastifyReply) => void,
  ) => void;
}): void {
  app.setErrorHandler((error, request, reply) => {
    if (error instanceof ZodError) {
      reply.status(400).send({
        error: "ValidationError",
        message: "Validation failed",
        details: error.issues,
      });
      return;
    }

    if (error instanceof HttpError) {
      const body: Record<string, unknown> = {
        error: error.name,
        message: error.message,
      };
      if (error.details !== undefined) {
        body.details = error.details;
      }
      reply.status(error.statusCode).send(body);
      return;
    }

    const clientStatus = clientErrorStatus(error);
    if (clientStatus !== undefined) {
      const name = CLIENT_ERROR_NAMES[clientStatus] ?? GENERIC_CLIENT_ERROR_NAME;

      /*
       * The framework's message is forwarded as-is, and that is a considered
       * decision rather than convenience. Every 4xx message Fastify can raise at
       * request time describes the *request* -- "Body cannot be empty when
       * content-type is set to 'application/json'", "Body is not valid JSON...",
       * "Unsupported Media Type", "Request body is too large", "'<x>' is not a
       * valid url component" -- so none of them exposes a path, a query, a
       * credential or a stack. That is precisely the detail a client needs to fix
       * its own call, and withholding it is what turned this into a support
       * puzzle in the first place.
       *
       * The 5xx side keeps its blanket redaction: a server-side message may well
       * carry a connection string or a SQL fragment, so it never leaves the
       * process. Nothing beyond these two fields is sent either -- no `code`, no
       * `stack`, no `details` -- so an error object with an unexpectedly rich
       * payload cannot leak through this branch.
       */
      const message =
        typeof error.message === "string" && error.message.length > 0 ? error.message : name;

      /*
       * Logged at `info`, not `error`. A client sending a malformed body is
       * routine traffic, not an incident; leaving these at `error` level is what
       * makes the log useless for finding genuine breakage. The error is still
       * recorded, so a puzzling 4xx remains diagnosable server-side.
       */
      request.log.info({ err: error, statusCode: clientStatus }, "client error");

      reply.status(clientStatus).send({ error: name, message });
      return;
    }

    request.log.error(error);
    reply.status(500).send({
      error: "InternalServerError",
      message: "Something went wrong",
    });
  });
}
