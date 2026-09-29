import { describe, expect, it } from "vitest";
import { allocateTicks, courseHandicap, netScore } from "../../src/engines/handicap.js";
import { course18, front9 } from "./fixtures.js";

const holesWithTicks = (ticks: Record<number, number>) =>
  Object.entries(ticks)
    .filter(([, n]) => n > 0)
    .map(([hole]) => Number(hole))
    .sort((a, b) => a - b);

describe("courseHandicap", () => {
  it("applies slope and rating minus par", () => {
    // 15.4 * 131/113 = 17.853..., + (72.5 - 72) = 18.353... -> 18
    expect(courseHandicap(15.4, { slope: 131, courseRating: 72.5, par: 72 })).toBe(18);
  });

  it("equals the index on a neutral course", () => {
    expect(courseHandicap(12, { slope: 113, courseRating: 72, par: 72 })).toBe(12);
  });

  it("can go below zero for plus handicaps", () => {
    expect(courseHandicap(-2, { slope: 113, courseRating: 71, par: 72 })).toBe(-3);
  });
});

describe("allocateTicks", () => {
  it("gives the difference from the lowest handicap on the hardest holes (15 vs 7)", () => {
    const ticks = allocateTicks(
      [
        { userId: "zach", courseHandicap: 15 },
        { userId: "friend", courseHandicap: 7 },
      ],
      course18,
    );
    // Stroke indexes 1-8 are holes 5, 12, 4, 17, 8, 14, 1, 10.
    expect(holesWithTicks(ticks.zach!)).toEqual([1, 4, 5, 8, 10, 12, 14, 17]);
    expect(Object.values(ticks.zach!).reduce((a, b) => a + b, 0)).toBe(8);
    expect(holesWithTicks(ticks.friend!)).toEqual([]);
  });

  it("gives every hole a value, including zero", () => {
    const ticks = allocateTicks([{ userId: "a", courseHandicap: 5 }], course18);
    expect(Object.keys(ticks.a!)).toHaveLength(18);
    expect(Object.values(ticks.a!).every((n) => n === 0)).toBe(true);
  });

  it("wraps around when a player has more than 18 ticks", () => {
    const ticks = allocateTicks(
      [
        { userId: "high", courseHandicap: 22 },
        { userId: "low", courseHandicap: 2 },
      ],
      course18,
    );
    const high = ticks.high!;
    // 20 ticks: every hole gets 1, stroke indexes 1 and 2 (holes 5 and 12) get a 2nd.
    expect(high[5]).toBe(2);
    expect(high[12]).toBe(2);
    expect(high[4]).toBe(1);
    expect(Object.values(high).reduce((a, b) => a + b, 0)).toBe(20);
  });

  it("ranks by stroke index within the holes being played", () => {
    const ticks = allocateTicks(
      [
        { userId: "a", courseHandicap: 3 },
        { userId: "b", courseHandicap: 0 },
      ],
      front9,
    );
    // Front nine, hardest first: holes 5 (SI 1), 4 (SI 3), 8 (SI 5).
    expect(holesWithTicks(ticks.a!)).toEqual([4, 5, 8]);
  });

  it("measures everyone from the lowest handicap, including plus handicaps", () => {
    const ticks = allocateTicks(
      [
        { userId: "plus", courseHandicap: -2 },
        { userId: "mid", courseHandicap: 1 },
      ],
      course18,
    );
    expect(Object.values(ticks.mid!).reduce((a, b) => a + b, 0)).toBe(3);
    expect(Object.values(ticks.plus!).reduce((a, b) => a + b, 0)).toBe(0);
  });

  it("rejects duplicate stroke indexes", () => {
    const bad = [
      { hole: 1, par: 4, strokeIndex: 1 },
      { hole: 2, par: 4, strokeIndex: 1 },
    ];
    expect(() => allocateTicks([{ userId: "a", courseHandicap: 1 }], bad)).toThrow();
  });
});

describe("netScore", () => {
  it("subtracts ticks from gross", () => {
    expect(netScore(5, 1)).toBe(4);
    expect(netScore(4, 0)).toBe(4);
  });
});
