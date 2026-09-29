import { describe, expect, it } from "vitest";
import { settle } from "../../src/engines/settlement.js";

const applyTransfers = (positions: Record<string, number>, transfers: { from: string; to: string; amountCents: number }[]) => {
  const left = { ...positions };
  for (const t of transfers) {
    left[t.from] = (left[t.from] ?? 0) + t.amountCents;
    left[t.to] = (left[t.to] ?? 0) - t.amountCents;
  }
  return left;
};

describe("settle", () => {
  it("nets every game into one position per player", () => {
    const skins = { a: 1500, b: -500, c: -500, d: -500 };
    const wad = { a: -900, b: 2700, c: -900, d: -900 };
    const greenies = { a: 1500, b: -500, c: -500, d: -500 };
    const { positions } = settle(skins, wad, greenies);
    expect(positions).toEqual({ a: 2100, b: 1700, c: -1900, d: -1900 });
  });

  it("produces transfers that zero out every position", () => {
    const { positions, transfers } = settle({ a: 2100, b: 1700, c: -1900, d: -1900 });
    expect(Object.values(applyTransfers(positions, transfers)).every((v) => v === 0)).toBe(true);
    expect(transfers.length).toBeLessThanOrEqual(3);
    expect(transfers.every((t) => t.amountCents > 0 && Number.isInteger(t.amountCents))).toBe(true);
  });

  it("pays a single winner directly from each loser", () => {
    const { transfers } = settle({ a: 3000, b: -1000, c: -1000, d: -1000 });
    expect(transfers).toEqual([
      { from: "b", to: "a", amountCents: 1000 },
      { from: "c", to: "a", amountCents: 1000 },
      { from: "d", to: "a", amountCents: 1000 },
    ]);
  });

  it("returns no transfers when everyone is even", () => {
    expect(settle({ a: 0, b: 0 }).transfers).toEqual([]);
  });

  it("is deterministic regardless of key order", () => {
    const one = settle({ a: 500, b: 500, c: -500, d: -500 }).transfers;
    const two = settle({ d: -500, c: -500, b: 500, a: 500 }).transfers;
    expect(one).toEqual(two);
  });

  it("rejects positions that do not sum to zero", () => {
    expect(() => settle({ a: 100, b: -50 })).toThrow();
  });
});
