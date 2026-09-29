import { describe, expect, it } from "vitest";
import { generateJoinCode, JOIN_CODE_ALPHABET, JOIN_CODE_LENGTH, normalizeJoinCode } from "../../../src/services/rounds/joinCode.js";

describe("join codes", () => {
  it("leaves out characters that are easily confused", () => {
    for (const ch of "0O1IL") expect(JOIN_CODE_ALPHABET).not.toContain(ch);
    expect(new Set(JOIN_CODE_ALPHABET).size).toBe(JOIN_CODE_ALPHABET.length);
  });

  it("builds the code from the picks, one per character", () => {
    const bounds: number[] = [];
    let next = 0;
    const code = generateJoinCode((n) => {
      bounds.push(n);
      return next++;
    });
    expect(code).toBe(JOIN_CODE_ALPHABET.slice(0, JOIN_CODE_LENGTH));
    expect(bounds).toEqual(Array(JOIN_CODE_LENGTH).fill(JOIN_CODE_ALPHABET.length));
  });

  it("generates codes of the right length from the alphabet by default", () => {
    const codes = Array.from({ length: 200 }, () => generateJoinCode());
    for (const code of codes) expect(normalizeJoinCode(code)).toBe(code);
    expect(new Set(codes).size).toBeGreaterThan(190);
  });

  it("normalizes what a player types", () => {
    expect(normalizeJoinCode(" abc-d2f ")).toBe("ABCD2F");
    expect(normalizeJoinCode("ABC D2F")).toBe("ABCD2F");
  });

  it("rejects codes of the wrong length or with characters outside the alphabet", () => {
    expect(normalizeJoinCode("ABCD2")).toBeNull();
    expect(normalizeJoinCode("ABCD2FG")).toBeNull();
    expect(normalizeJoinCode("ABCD0F")).toBeNull();
    expect(normalizeJoinCode("ABC#2F")).toBeNull();
    expect(normalizeJoinCode("")).toBeNull();
  });
});
