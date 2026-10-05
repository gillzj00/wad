import { timingSafeEqual } from "node:crypto";

/**
 * Interim quota guard (ADR-0013, ADR-0014): the APIs deployed before auth
 * exists require the shared client token in this header. This is not
 * authentication; it goes away when the Cognito authorizer lands (M1.1).
 */
export const CLIENT_TOKEN_HEADER = "x-wad-client";

/** Whether `given` is the client token, compared in constant time. */
export function clientTokenMatches(given: unknown, expected: string): boolean {
  if (typeof given !== "string" || given.length === 0) return false;
  const a = Buffer.from(given);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}
