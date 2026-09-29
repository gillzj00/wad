export type RoundErrorKind = "validation" | "not_found" | "forbidden" | "conflict";

export class RoundError extends Error {
  constructor(
    readonly kind: RoundErrorKind,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "RoundError";
  }
}

export const invalid = (code: string, message: string) => new RoundError("validation", code, message);
