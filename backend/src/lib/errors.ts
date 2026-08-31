/** Base class for errors that should be turned directly into an HTTP response. */
export class HttpError extends Error {
  constructor(
    public readonly statusCode: number,
    message: string,
    public readonly details?: unknown,
  ) {
    super(message);
    this.name = new.target.name;
  }
}

export class NotFoundError extends HttpError {
  constructor(entity: string) {
    super(404, `${entity} not found`);
  }
}

export class ConflictError extends HttpError {
  constructor(message: string) {
    super(409, message);
  }
}

export class ValidationError extends HttpError {
  constructor(details: unknown) {
    super(400, "Validation failed", details);
  }
}
