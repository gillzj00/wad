import { describe, expect, it } from "vitest";
import { scoreWolf, type WolfInput, type WolfResult } from "../../src/engines/wolf.js";
import type { HoleEvents, Player, Score, WolfEvent } from "../../src/shared/types.js";
import { course18, front9 } from "./fixtures.js";

// Pars: 4 5 3 4 4 3 5 4 4 / 4 3 5 4 4 5 3 4 4. Stroke index 1 is hole 5, 2 is hole 12.

const player = (userId: string, courseHandicap = 0): Player => ({ userId, displayName: userId, courseHandicap });
const scratch = [player("a"), player("b"), player("c"), player("d")];
const ORDER = ["a", "b", "c", "d"];
const LONE: WolfEvent = { choice: "lone" };
const partner = (partnerUserId: string): WolfEvent => ({ choice: "partner", partnerUserId });

interface HoleSpec {
  /** Gross scores for a, b, c, d; null is no score. Left out: everyone makes par. */
  gross?: (number | null)[];
  /** Null is nothing recorded. Left out: see `play`. */
  wolf?: WolfEvent | null;
}

/**
 * A round where, unless a hole says otherwise, everyone makes gross par and
 * the Wolf goes alone on holes 1 to 16, which ties every one of those holes.
 * Nothing is recorded on 17 and 18 unless the hole says so.
 */
function play(spec: Record<number, HoleSpec> = {}, overrides: Partial<WolfInput> = {}): WolfResult {
  const players = overrides.players ?? scratch;
  const scores: Score[] = [];
  const holeEvents: HoleEvents[] = [];
  for (const h of course18) {
    const s = spec[h.hole] ?? {};
    players.forEach((p, i) => {
      const gross = s.gross ? s.gross[i]! : h.par;
      if (gross !== null) scores.push({ hole: h.hole, userId: p.userId, gross });
    });
    const wolf = s.wolf === undefined ? (h.hole <= 16 ? LONE : null) : s.wolf;
    if (wolf !== null) holeEvents.push({ hole: h.hole, wadMakers: [], greenieWinner: null, wolf });
  }
  const result = scoreWolf({ players, teeOrder: ORDER, holes: course18, scores, holeEvents, pointCents: 100, ...overrides });
  if (result === null) throw new Error("wolf is unavailable");
  return result;
}

const hole = (result: WolfResult, n: number) => result.holes[n - 1]!;
const sum = (values: number[]) => values.reduce((x, y) => x + y, 0);
const NONE = { a: 0, b: 0, c: 0, d: 0 };

describe("scoreWolf: points", () => {
  // Hole 1 is a par 4 and a is the Wolf. One player makes 3, the rest make 4.
  // Deltas at 100 a point are 100 * (4 * own points - total points).
  it.each([
    // a and b: 3 against 4. 2 points each, total 4: a, b 100 * (8 - 4); c, d 100 * (0 - 4).
    ["the Wolf and partner win", partner("b"), "a", "won_by_wolf_side", { a: 2, b: 2, c: 0, d: 0 }, { a: 400, b: 400, c: -400, d: -400 }],
    // c and d: 3 against 4. 3 points each, total 6: c, d 100 * (12 - 6); a, b 100 * (0 - 6).
    ["the Wolf and partner lose", partner("b"), "c", "won_by_opponents", { a: 0, b: 0, c: 3, d: 3 }, { a: -600, b: -600, c: 600, d: 600 }],
    // a alone: 3 against 4. 4 points, total 4: a 100 * (16 - 4); the others 100 * (0 - 4).
    ["the Lone Wolf wins", LONE, "a", "won_by_wolf_side", { a: 4, b: 0, c: 0, d: 0 }, { a: 1200, b: -400, c: -400, d: -400 }],
    // b, c, d: 3 against 4. 1 point each, total 3: each 100 * (4 - 3); a 100 * (0 - 3).
    ["the Lone Wolf loses", LONE, "c", "won_by_opponents", { a: 0, b: 1, c: 1, d: 1 }, { a: -300, b: 100, c: 100, d: 100 }],
  ])("%s", (_name, wolf, birdie, status, points, deltas) => {
    const gross = ORDER.map((id) => (id === birdie ? 3 : 4));
    const result = play({ 1: { gross, wolf } });
    expect(hole(result, 1)).toMatchObject({ hole: 1, wolfUserId: "a", status, invalidReason: null, points });
    expect(result.points).toEqual(points);
    expect(result.deltas).toEqual(deltas);
  });

  it("reports the sides and their net best balls", () => {
    // a 6, b 4, c 5, d 7 on hole 1. Wolf a with d: min(6, 7) = 6. b and c: min(4, 5) = 4.
    const result = play({ 1: { gross: [6, 4, 5, 7], wolf: partner("d") } });
    expect(hole(result, 1)).toEqual({
      hole: 1,
      wolfUserId: "a",
      status: "won_by_opponents",
      invalidReason: null,
      choice: "partner",
      partnerUserId: "d",
      lastPlace: null,
      wolfSide: ["a", "d"],
      opponents: ["b", "c"],
      wolfSideNet: 6,
      opponentsNet: 4,
      net: { a: 6, b: 4, c: 5, d: 7 },
      points: { a: 0, b: 3, c: 3, d: 0 },
    });
  });

  it("gives no points for a tied hole and carries nothing to the next", () => {
    // Hole 1: a and b 4, c and d 4: tied. Hole 2 (par 5): Wolf b with a, b makes 4: 2 points each, not more.
    const result = play({ 1: { wolf: partner("b") }, 2: { gross: [5, 4, 5, 5], wolf: partner("a") } });
    expect(hole(result, 1)).toMatchObject({ status: "tied", wolfSideNet: 4, opponentsNet: 4, points: NONE });
    expect(hole(result, 2)).toMatchObject({ status: "won_by_wolf_side", points: { a: 2, b: 2, c: 0, d: 0 } });
    expect(result.points).toEqual({ a: 2, b: 2, c: 0, d: 0 });
  });

  it("compares net best balls, so ticks can change the winner", () => {
    // Handicaps 0, 0, 0, 2: d gets a tick on stroke indexes 1 and 2, holes 5 and 12.
    const players = [player("a"), player("b"), player("c"), player("d", 2)];
    // Hole 5 (par 4), Wolf a with b. Gross a 4, b 5, c 5, d 4: gross best balls tie 4 to 4.
    // Net d is 3, so c and d win 3 to 4: 3 points each.
    // Hole 12 (par 5), Wolf d alone. Gross a 5, b 5, c 5, d 6: gross d loses.
    // Net d is 5, so the hole is tied 5 to 5.
    const result = play({ 5: { gross: [4, 5, 5, 4], wolf: partner("b") }, 12: { gross: [5, 5, 5, 6] } }, { players });
    expect(hole(result, 5)).toMatchObject({ status: "won_by_opponents", wolfSideNet: 4, opponentsNet: 3, net: { a: 4, b: 5, c: 5, d: 3 } });
    expect(hole(result, 12)).toMatchObject({ wolfUserId: "d", status: "tied", wolfSideNet: 5, opponentsNet: 5 });
    expect(result.points).toEqual({ a: 0, b: 0, c: 3, d: 3 });
  });

  it("allocates ticks relative to the lowest handicap, like skins", () => {
    // Handicaps 10, 10, 10, 12 give the same ticks as 0, 0, 0, 2.
    const players = [player("a", 10), player("b", 10), player("c", 10), player("d", 12)];
    const result = play({ 5: { gross: [4, 5, 5, 4], wolf: partner("b") } }, { players });
    expect(hole(result, 5).net).toEqual({ a: 4, b: 5, c: 5, d: 3 });
  });
});

describe("scoreWolf: who the Wolf is", () => {
  it("rotates through the tee order on holes 1 to 16", () => {
    const result = play();
    expect(result.holes.slice(0, 16).map((h) => h.wolfUserId)).toEqual([
      ...["a", "b", "c", "d"],
      ...["a", "b", "c", "d"],
      ...["a", "b", "c", "d"],
      ...["a", "b", "c", "d"],
    ]);
  });

  it("uses the tee order it is given, not the order of the players", () => {
    const result = play({}, { teeOrder: ["c", "a", "d", "b"] });
    expect(result.teeOrder).toEqual(["c", "a", "d", "b"]);
    expect(result.holes.slice(0, 5).map((h) => h.wolfUserId)).toEqual(["c", "a", "d", "b", "c"]);
  });

  it("accepts a recorded Wolf on holes 1 to 16 that agrees with the rotation", () => {
    const result = play({ 2: { gross: [5, 4, 5, 5], wolf: { choice: "lone", wolfUserId: "b" } } });
    expect(hole(result, 2)).toMatchObject({ wolfUserId: "b", status: "won_by_wolf_side", points: { a: 0, b: 4, c: 0, d: 0 } });
  });

  // Holes 1, 2, 4, 6 and 8 are won; the other holes up to 16 are tied.
  //   hole 1  Wolf a alone makes 3: a +4                      a 4  b 0  c 0  d 0
  //   hole 2  Wolf b alone makes 4 on the par 5: b +4         a 4  b 4  c 0  d 0
  //   hole 4  Wolf d with c, d makes 3: c +2, d +2            a 4  b 4  c 2  d 2
  //   hole 6  Wolf b alone makes 4 on the par 3: a, c, d +1   a 5  b 4  c 3  d 3
  //   hole 8  Wolf d alone makes 3: d +4                      a 5  b 4  c 3  d 7
  const through16: Record<number, HoleSpec> = {
    1: { gross: [3, 4, 4, 4] },
    2: { gross: [5, 4, 5, 5] },
    4: { gross: [4, 4, 4, 3], wolf: partner("c") },
    6: { gross: [3, 4, 3, 3] },
    8: { gross: [4, 4, 4, 3] },
  };

  it("makes the player in last place after hole 16 the Wolf on 17", () => {
    const result = play({ ...through16, 17: { wolf: LONE } });
    expect(result.points).toEqual({ a: 5, b: 4, c: 3, d: 7 });
    expect(hole(result, 17)).toMatchObject({ wolfUserId: "c", lastPlace: ["c"], status: "tied" });
  });

  it("works out the Wolf on 18 again from the standings after 17", () => {
    // Hole 17: Wolf c alone makes 3 and wins 4: a 5, b 4, c 7, d 7. Last place is now b.
    const result = play({ ...through16, 17: { gross: [4, 4, 3, 4], wolf: LONE }, 18: { gross: [4, 3, 4, 4], wolf: partner("c") } });
    expect(hole(result, 17)).toMatchObject({ wolfUserId: "c", status: "won_by_wolf_side", points: { a: 0, b: 0, c: 4, d: 0 } });
    // Hole 18: Wolf b with c, b makes 3: b +2, c +2.
    expect(hole(result, 18)).toMatchObject({ wolfUserId: "b", lastPlace: ["b"], status: "won_by_wolf_side", wolfSide: ["b", "c"] });
    expect(result.points).toEqual({ a: 5, b: 6, c: 9, d: 7 });
    expect(result.complete).toBe(true);
    // Total 27: a 100 * (20 - 27), b 100 * (24 - 27), c 100 * (36 - 27), d 100 * (28 - 27).
    expect(result.deltas).toEqual({ a: -700, b: -300, c: 900, d: 100 });
  });

  it("accepts a recorded Wolf who is the only player in last place", () => {
    const result = play({ ...through16, 17: { gross: [4, 4, 3, 4], wolf: { choice: "lone", wolfUserId: "c" } } });
    expect(hole(result, 17)).toMatchObject({ wolfUserId: "c", status: "won_by_wolf_side" });
  });

  // Hole 17: Wolf c with a, c makes 3: a +2, c +2 gives a 7, b 4, c 5, d 7, and b is last alone.
  // Instead c loses alone to a 3 by d: a, b, d +1 gives a 6, b 5, c 3, d 8, and c is last again.
  // For a tie: Wolf c with b, b makes 3: b +2, c +2 gives a 5, b 6, c 5, d 7. a and c are tied for last.
  const tiedAfter17: Record<number, HoleSpec> = { ...through16, 17: { gross: [4, 3, 4, 4], wolf: partner("b") } };

  it("does not pick a Wolf when players are tied for last place: the hole needs one recorded", () => {
    // All scores and a choice are in, and the hole still scores nothing.
    const result = play({ ...tiedAfter17, 18: { gross: [3, 4, 4, 4], wolf: LONE } });
    expect(result.points).toEqual({ a: 5, b: 6, c: 5, d: 7 });
    expect(hole(result, 18)).toMatchObject({
      wolfUserId: null,
      status: "needs_wolf",
      lastPlace: ["a", "c"],
      wolfSide: null,
      points: NONE,
    });
    expect(result.complete).toBe(false);
  });

  it.each([
    // a alone makes 3 against 4: a +4 gives a 9, b 6, c 5, d 7.
    ["a", "won_by_wolf_side", { a: 9, b: 6, c: 5, d: 7 }],
    // c alone makes 4 against a's 3: a, b, d +1 gives a 6, b 7, c 5, d 8.
    ["c", "won_by_opponents", { a: 6, b: 7, c: 5, d: 8 }],
  ])("accepts recorded Wolf %s, who is among those tied for last place", (wolfUserId, status, points) => {
    const result = play({ ...tiedAfter17, 18: { gross: [3, 4, 4, 4], wolf: { choice: "lone", wolfUserId } } });
    expect(hole(result, 18)).toMatchObject({ wolfUserId, status, lastPlace: ["a", "c"] });
    expect(result.points).toEqual(points);
    expect(result.complete).toBe(true);
  });

  it("needs a Wolf on 17 when all four are level after 16", () => {
    const result = play({ 17: { wolf: LONE } });
    expect(hole(result, 17)).toMatchObject({ status: "needs_wolf", lastPlace: ["a", "b", "c", "d"], wolfUserId: null });
    // Hole 18 depends on the standings after 17.
    expect(hole(result, 18)).toMatchObject({ status: "pending", lastPlace: null, wolfUserId: null });
  });

  it("lets the Wolf be recorded before the choice on a hole that needs one", () => {
    const result = play({ 17: { wolf: { wolfUserId: "b" } } });
    expect(hole(result, 17)).toMatchObject({ status: "pending", wolfUserId: "b", choice: null });
  });
});

describe("scoreWolf: invalid records", () => {
  // Hole 1, Wolf a, and a makes 3: every one of these would pay if it were scored.
  const gross = [3, 4, 4, 4];

  it.each([
    ["the partner is the Wolf", 1, partner("a"), "partner_is_wolf"],
    ["the partner is not in the round", 1, partner("z"), "partner_not_a_player"],
    ["a recorded Wolf on holes 1 to 16 contradicts the rotation", 1, { choice: "lone", wolfUserId: "b" }, "wolf_contradicts_rotation"],
    ["a recorded Wolf is not in the round", 1, { choice: "lone", wolfUserId: "z" }, "wolf_not_a_player"],
    ["a partner and lone are both recorded", 1, { choice: "lone", partnerUserId: "b" }, "partner_and_lone"],
    ["a partner is recorded as the choice without naming one", 1, { choice: "partner" }, "partner_missing"],
  ] as [string, number, WolfEvent, string][])("%s", (_name, n, wolf, reason) => {
    const result = play({ [n]: { gross, wolf } });
    expect(hole(result, n)).toMatchObject({ status: "invalid", invalidReason: reason, wolfSide: null, opponents: null, points: NONE });
    expect(result.points).toEqual(NONE);
    expect(result.deltas).toEqual(NONE);
    expect(result.complete).toBe(false);
  });

  // After 16: a 4 (hole 1), b 4 (hole 2), c 4 (hole 3, par 3), d 0. d is last alone.
  const dLast: Record<number, HoleSpec> = { 1: { gross: [3, 4, 4, 4] }, 2: { gross: [5, 4, 5, 5] }, 3: { gross: [3, 3, 2, 3] } };
  // After 16: a 4, b 4, c 0, d 0. c and d are tied for last.
  const cdLast: Record<number, HoleSpec> = { 1: { gross: [3, 4, 4, 4] }, 2: { gross: [5, 4, 5, 5] } };

  it("a recorded Wolf on 17 who is not in last place", () => {
    const result = play({ ...dLast, 17: { gross: [3, 4, 4, 4], wolf: { choice: "lone", wolfUserId: "a" } } });
    expect(hole(result, 17)).toMatchObject({ status: "invalid", invalidReason: "wolf_not_in_last_place", wolfUserId: null, lastPlace: ["d"], points: NONE });
    expect(result.points).toEqual({ a: 4, b: 4, c: 4, d: 0 });
  });

  it("a recorded Wolf on 17 who is not among those tied for last place", () => {
    const result = play({ ...cdLast, 17: { gross: [3, 4, 4, 4], wolf: { choice: "lone", wolfUserId: "a" } } });
    expect(hole(result, 17)).toMatchObject({ status: "invalid", invalidReason: "wolf_not_in_last_place", lastPlace: ["c", "d"], points: NONE });
    expect(result.points).toEqual({ a: 4, b: 4, c: 0, d: 0 });
  });

  it("a recorded Wolf on 18 who was last after 16 and is not after 17", () => {
    // Hole 17: Wolf d alone makes 3: d +4 and all four have 4. Recorded Wolf on 18 must be one of them; z is not.
    // With c, d tied after 16 instead: Wolf d (recorded) alone wins 17: a 4, b 4, c 0, d 4. c is last alone on 18.
    const result = play({
      ...cdLast,
      17: { gross: [4, 4, 4, 3], wolf: { choice: "lone", wolfUserId: "d" } },
      18: { gross: [4, 4, 4, 3], wolf: { choice: "lone", wolfUserId: "d" } },
    });
    expect(hole(result, 17)).toMatchObject({ status: "won_by_wolf_side", wolfUserId: "d" });
    expect(hole(result, 18)).toMatchObject({ status: "invalid", invalidReason: "wolf_not_in_last_place", lastPlace: ["c"] });
    expect(result.points).toEqual({ a: 4, b: 4, c: 0, d: 4 });
  });

  it("an invalid record stays invalid while scores are missing", () => {
    const result = play({ 1: { gross: [3, null, 4, 4], wolf: partner("a") } });
    expect(hole(result, 1)).toMatchObject({ status: "invalid", invalidReason: "partner_is_wolf", net: null });
  });
});

describe("scoreWolf: pending holes", () => {
  it("is pending until all four players have a score", () => {
    const result = play({ 1: { gross: [3, 4, null, 4] } });
    expect(hole(result, 1)).toMatchObject({ status: "pending", wolfUserId: "a", choice: "lone", net: null, wolfSide: null, points: NONE });
  });

  it("is pending until the Wolf's choice is recorded", () => {
    const result = play({ 1: { gross: [3, 4, 4, 4], wolf: null } });
    expect(hole(result, 1)).toMatchObject({ status: "pending", wolfUserId: "a", choice: null, net: { a: 3, b: 4, c: 4, d: 4 }, points: NONE });
    expect(result.points).toEqual(NONE);
  });

  it("scores a later hole on 1 to 16 while an earlier one is pending, and pays only scored holes", () => {
    // Hole 3 has no choice. Hole 4 (Wolf d) is scored all the same: d alone makes 3 and wins 4.
    const result = play({ 3: { gross: [3, 3, 2, 3], wolf: null }, 4: { gross: [4, 4, 4, 3] }, 17: { wolf: LONE }, 18: { wolf: LONE } });
    expect(hole(result, 3).status).toBe("pending");
    expect(hole(result, 4)).toMatchObject({ status: "won_by_wolf_side", wolfUserId: "d" });
    expect(result.points).toEqual({ a: 0, b: 0, c: 0, d: 4 });
    // Total 4: d 100 * (16 - 4), the others 100 * (0 - 4). Hole 3 would give c 4 points and is not counted.
    expect(result.deltas).toEqual({ a: -400, b: -400, c: -400, d: 1200 });
    expect(result.complete).toBe(false);
    // The standings after 16 are not known, so 17 and 18 cannot name their Wolf.
    expect(hole(result, 17)).toMatchObject({ status: "pending", wolfUserId: null, lastPlace: null });
    expect(hole(result, 18)).toMatchObject({ status: "pending", wolfUserId: null, lastPlace: null });
  });

  it("keeps 17 and 18 pending behind an invalid hole", () => {
    const result = play({ 9: { wolf: partner("a") }, 17: { wolf: LONE } });
    expect(hole(result, 9).status).toBe("invalid");
    expect(hole(result, 17)).toMatchObject({ status: "pending", lastPlace: null });
  });

  it("keeps 18 pending while 17 is not scored", () => {
    // After 16: a 4, the others 0 and tied for last, so 17 has no Wolf until one is recorded.
    const result = play({ 1: { gross: [3, 4, 4, 4] }, 17: { wolf: LONE }, 18: { wolf: { choice: "lone", wolfUserId: "b" } } });
    expect(hole(result, 17)).toMatchObject({ status: "needs_wolf", lastPlace: ["b", "c", "d"] });
    expect(hole(result, 18)).toMatchObject({ status: "pending", wolfUserId: null, lastPlace: null });
  });

  it("has nothing but pending holes and zero money before anything is recorded", () => {
    const result = scoreWolf({ players: scratch, teeOrder: ORDER, holes: course18, scores: [], holeEvents: [], pointCents: 100 })!;
    expect(result.holes).toHaveLength(18);
    expect(result.holes.every((h) => h.status === "pending")).toBe(true);
    expect(result.points).toEqual(NONE);
    expect(result.deltas).toEqual(NONE);
    expect(result.complete).toBe(false);
  });
});

describe("scoreWolf: money", () => {
  it.each([
    [100, { a: 1200, b: -400, c: -400, d: -400 }],
    [25, { a: 300, b: -100, c: -100, d: -100 }],
    [1, { a: 12, b: -4, c: -4, d: -4 }],
    [0, { a: 0, b: 0, c: 0, d: 0 }],
  ])("pays pointCents * (4 * own - total) at %i cents a point", (pointCents, deltas) => {
    // a has 4 points and the total is 4: a gets 12 point values, the others lose 4.
    const result = play({ 1: { gross: [3, 4, 4, 4] } }, { pointCents });
    expect(result.deltas).toEqual(deltas);
  });

  it("equals every pair settling the difference in their points", () => {
    const result = play({ 1: { gross: [3, 4, 4, 4] }, 2: { gross: [5, 5, 4, 5] }, 3: { gross: [3, 3, 3, 2], wolf: partner("a") } });
    // Hole 1: a +4. Hole 2: Wolf b alone loses: a, c, d +1. Hole 3: Wolf c with a lose to d's 2: b, d +3.
    expect(result.points).toEqual({ a: 5, b: 3, c: 1, d: 4 });
    const pairwise = Object.fromEntries(ORDER.map((id) => [id, sum(ORDER.map((other) => 100 * (result.points[id]! - result.points[other]!)))]));
    // a: 2 + 4 + 1 = 7 points up; b: -2 + 2 - 1 = -1; c: -4 - 2 - 3 = -9; d: -1 + 1 + 3 = 3.
    expect(pairwise).toEqual({ a: 700, b: -100, c: -900, d: 300 });
    expect(result.deltas).toEqual(pairwise);
  });

  it("rejects a point value that is not whole cents", () => {
    expect(() => play({}, { pointCents: 12.5 })).toThrow("integer cents");
    expect(() => play({}, { pointCents: -100 })).toThrow("integer cents");
  });
});

describe("scoreWolf: a full round", () => {
  // Handicaps 0, 0, 0, 2: d gets a tick on holes 5 and 12. Tee order a, b, c, d. 100 cents a point.
  //
  //  hole par Wolf choice     gross a b c d  Wolf side v opponents (net)   points          a  b  c  d
  //   1   4   a    with b     4 5 5 5        a,b 4 v c,d 5                 a, b +2          2  2  0  0
  //   2   5   b    alone      5 5 6 6        b 5 v a,c,d 5                 tied             2  2  0  0
  //   3   3   c    with d     3 3 4 4        c,d 4 v a,b 3                 a, b +3          5  5  0  0
  //   4   4   d    alone      5 5 5 4        d 4 v a,b,c 5                 d +4             5  5  0  4
  //   5   4   a    with c     4 5 5 5        a,c 4 v b,d 4 (d nets 4)      tied             5  5  0  4
  //   6   3   b    alone      4 4 3 4        b 4 v a,c,d 3                 a, c, d +1       6  5  1  5
  //   7   5   c    with a     5 5 5 5        a,c 5 v b,d 5                 tied             6  5  1  5
  //   8   4   d    with c     5 5 4 5        c,d 4 v a,b 5                 c, d +2          6  5  3  7
  //   9   4   a    alone      3 4 4 4        a 3 v b,c,d 4                 a +4            10  5  3  7
  //  10   4   b    with c     5 5 5 4        b,c 5 v a,d 4                 a, d +3         13  5  3 10
  //  11   3   c    alone      3 4 2 4        c 2 v a,b,d 3                 c +4            13  5  7 10
  //  12   5   d    with b     5 6 5 5        b,d 4 v a,c 5 (d nets 4)      b, d +2         13  7  7 12
  //  13   4   a    with d     4 4 5 5        a,d 4 v b,c 4                 tied            13  7  7 12
  //  14   4   b    alone      4 3 4 4        b 3 v a,c,d 4                 b +4            13 11  7 12
  //  15   5   c    with b     5 5 6 4        b,c 5 v a,d 4                 a, d +3         16 11  7 15
  //  16   3   d    alone      3 3 3 4        d 4 v a,b,c 3                 a, b, c +1      17 12  8 15
  //  17   4   c (last, 8)     alone          4 5 3 4: c 3 v a,b,d 4        c +4            17 12 12 15
  //  18   4   b and c are tied for last on 12; b is recorded as the Wolf, with a
  //                           4 4 5 5        a,b 4 v c,d 5                 a, b +2         19 14 12 15
  //
  // Total 60 points. Deltas: a 100 * (76 - 60) = 1600; b 100 * (56 - 60) = -400;
  // c 100 * (48 - 60) = -1200; d 100 * (60 - 60) = 0. Sum 0.
  // The same by pairs: a is 5 up on b, 7 on c and 4 on d, 16 points, 1600.
  const players = [player("a"), player("b"), player("c"), player("d", 2)];
  const round: Record<number, HoleSpec> = {
    1: { gross: [4, 5, 5, 5], wolf: partner("b") },
    2: { gross: [5, 5, 6, 6], wolf: LONE },
    3: { gross: [3, 3, 4, 4], wolf: partner("d") },
    4: { gross: [5, 5, 5, 4], wolf: LONE },
    5: { gross: [4, 5, 5, 5], wolf: partner("c") },
    6: { gross: [4, 4, 3, 4], wolf: LONE },
    7: { gross: [5, 5, 5, 5], wolf: partner("a") },
    8: { gross: [5, 5, 4, 5], wolf: partner("c") },
    9: { gross: [3, 4, 4, 4], wolf: LONE },
    10: { gross: [5, 5, 5, 4], wolf: partner("c") },
    11: { gross: [3, 4, 2, 4], wolf: LONE },
    12: { gross: [5, 6, 5, 5], wolf: partner("b") },
    13: { gross: [4, 4, 5, 5], wolf: partner("d") },
    14: { gross: [4, 3, 4, 4], wolf: LONE },
    15: { gross: [5, 5, 6, 4], wolf: partner("b") },
    16: { gross: [3, 3, 3, 4], wolf: LONE },
    17: { gross: [4, 5, 3, 4], wolf: LONE },
    18: { gross: [4, 4, 5, 5], wolf: { choice: "partner", partnerUserId: "a", wolfUserId: "b" } },
  };

  it("matches the hand-computed result", () => {
    const result = play(round, { players });
    const W = "won_by_wolf_side";
    const O = "won_by_opponents";
    expect(result.holes.map((h) => [h.hole, h.wolfUserId, h.status, h.wolfSideNet, h.opponentsNet])).toEqual([
      [1, "a", W, 4, 5],
      [2, "b", "tied", 5, 5],
      [3, "c", O, 4, 3],
      [4, "d", W, 4, 5],
      [5, "a", "tied", 4, 4],
      [6, "b", O, 4, 3],
      [7, "c", "tied", 5, 5],
      [8, "d", W, 4, 5],
      [9, "a", W, 3, 4],
      [10, "b", O, 5, 4],
      [11, "c", W, 2, 3],
      [12, "d", W, 4, 5],
      [13, "a", "tied", 4, 4],
      [14, "b", W, 3, 4],
      [15, "c", O, 5, 4],
      [16, "d", O, 4, 3],
      [17, "c", W, 3, 4],
      [18, "b", W, 4, 5],
    ]);
    expect(hole(result, 17).lastPlace).toEqual(["c"]);
    expect(hole(result, 18).lastPlace).toEqual(["b", "c"]);
    expect(result.points).toEqual({ a: 19, b: 14, c: 12, d: 15 });
    expect(result.deltas).toEqual({ a: 1600, b: -400, c: -1200, d: 0 });
    expect(sum(Object.values(result.deltas))).toBe(0);
    expect(result.complete).toBe(true);
  });

  it("awards on each hole exactly the points that make up the totals", () => {
    const result = play(round, { players });
    for (const id of ORDER) expect(sum(result.holes.map((h) => h.points[id]!))).toBe(result.points[id]);
  });

  it("leaves the 18th unpaid until the tied Wolf is recorded", () => {
    const result = play({ ...round, 18: { gross: [4, 4, 5, 5], wolf: partner("a") } }, { players });
    expect(hole(result, 18)).toMatchObject({ status: "needs_wolf", lastPlace: ["b", "c"] });
    // Standings after 17: a 17, b 12, c 12, d 15, total 56.
    expect(result.points).toEqual({ a: 17, b: 12, c: 12, d: 15 });
    expect(result.deltas).toEqual({ a: 1200, b: -800, c: -800, d: 400 });
    expect(result.complete).toBe(false);
  });
});

describe("scoreWolf: unavailable", () => {
  const input = { teeOrder: ORDER, holes: course18, scores: [], holeEvents: [], pointCents: 100 };

  it.each([
    ["three players", scratch.slice(0, 3), ["a", "b", "c"]],
    ["two players", scratch.slice(0, 2), ["a", "b"]],
    ["five players", [...scratch, player("e")], ["a", "b", "c", "d", "e"]],
    ["no players", [], []],
    ["the same player twice", [player("a"), player("b"), player("c"), player("c")], ORDER],
  ])("is null with %s", (_name, players, teeOrder) => {
    expect(scoreWolf({ ...input, players, teeOrder })).toBeNull();
  });

  it.each([
    ["misses a player", ["a", "b", "c"]],
    ["names a player twice", ["a", "b", "c", "c"]],
    ["names someone else", ["a", "b", "c", "z"]],
  ])("is null when the tee order %s", (_name, teeOrder) => {
    expect(scoreWolf({ ...input, players: scratch, teeOrder })).toBeNull();
  });

  it("is null for a round that is not 18 holes", () => {
    expect(scoreWolf({ ...input, players: scratch, holes: front9 })).toBeNull();
  });
});
