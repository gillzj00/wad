import { randomInt } from "node:crypto";

/** No 0/O, 1/I/L: the code is read aloud and typed on a phone. */
export const JOIN_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
export const JOIN_CODE_LENGTH = 6;

/** `pick(n)` returns a uniform integer in [0, n); the default is cryptographically secure. */
export function generateJoinCode(pick: (n: number) => number = randomInt): string {
  let code = "";
  for (let i = 0; i < JOIN_CODE_LENGTH; i++) code += JOIN_CODE_ALPHABET[pick(JOIN_CODE_ALPHABET.length)];
  return code;
}

/** Upper-cases and drops spaces and hyphens; null when the result cannot be a join code. */
export function normalizeJoinCode(raw: string): string | null {
  const code = raw.replace(/[\s-]/g, "").toUpperCase();
  if (code.length !== JOIN_CODE_LENGTH) return null;
  for (const ch of code) if (!JOIN_CODE_ALPHABET.includes(ch)) return null;
  return code;
}
