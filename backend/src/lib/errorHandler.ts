import { FastifyError, FastifyReply, FastifyRequest } from "fastify";
import { ZodError } from "zod";
import { HttpError } from "./errors";

/**
 * Central Fastify error handler.
 *
 * - ZodError (thrown by `schema.parse()` in route handlers) -> 400 with the
 *   flattened list of issues.
 * - HttpError (and subclasses NotFoundError/ConflictError/ValidationError)
 *   -> whatever statusCode they carry.
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

    request.log.error(error);
    reply.status(500).send({
      error: "InternalServerError",
      message: "Something went wrong",
    });
  });
}
