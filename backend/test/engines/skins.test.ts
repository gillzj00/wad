import { describe, expect, it } from "vitest";
import { scoreSkins } from "../../src/engines/skins.js";
import type { HoleInfo, Player, Score } from "../../src/shared/types.js";
import { course18 } from "./fixtures.js";

const player = (userId: string, courseHandicap = 0): Player => ({ userId, displayName: userId, courseHandicap });

/** Everyone makes gross par on every hole, then apply overrides as [hole, userId, gross]. */
function scoresFor(players: Player[], holes: HoleInfo[], overrides: [number, string, number][] = []): Score[] {
  const map = new Map<string, Score>();
  for (const h of holes) for (const p of players) map.set(`${h.hole}:${p.userId}`, { hole: h.hole, userId: p.userId, gross: h.par });
  for (const [hole, userId, gross] of overrides) map.set(`${hole}:${userId}`, { hole, userId, gross });
  return [...map.values()];
}

describe("scoreSkins", () => {
  const four = [player("a"), player("b"), player("c"), player("d")];
  const firstFour = course18.slice(0, 4);

  it("pushes on a tie for low net and carries the value forward (domain example)", () => {
    const scores = scoresFor(four, firstFour, [
      // Hole 1: a, b net par; c, d net bogey -> push.
      [1, "c", 5],
      [1, "d", 5],
      // Hole 2: all par -> push. Hole 3: a birdies -> wins $15.
      [3, "a", 2],
      // Hole 4: b birdies -> wins $5.
      [4, "b", 3],
    ]);
    const { holes, deltas, complete, carryOutCents } = scoreSkins({ players: four, holes: firstFour, scores, baseCents: 500 });

    expect(holes.map((h) => [h.hole, h.status, h.atStakeCents, h.winnerUserId])).toEqual([
      [1, "pushed", 500, null],
      [2, "pushed", 1000, null],
      [3, "won", 1500, "a"],
      [4, "won", 500, "b"],
    ]);
    // a: +1500 * 3 - 500; b: +500 * 3 - 1500; c, d: -1500 - 500.
    expect(deltas).toEqual({ a: 4000, b: 0, c: -2000, d: -2000 });
    expect(complete).toBe(true);
    expect(carryOutCents).toBe(0);
  });

  it("applies handicap ticks to net scores (15 vs 7, everyone shoots gross par)", () => {
    const players = [player("zach", 15), player("friend", 7)];
    const { holes, deltas, complete, carryOutCents } = scoreSkins({
      players,
      holes: course18,
      scores: scoresFor(players, course18),
      baseCents: 500,
    });

    // Zach's ticks are on holes 1, 4, 5, 8, 10, 12, 14, 17; he wins each outright
    // and collects whatever carried in from the pushed holes before it.
    const won = holes.filter((h) => h.status === "won").map((h) => [h.hole, h.atStakeCents]);
    expect(won).toEqual([
      [1, 500],
      [4, 1500],
      [5, 500],
      [8, 1500],
      [10, 1000],
      [12, 1000],
      [14, 1000],
      [17, 1500],
    ]);
    expect(holes.find((h) => h.hole === 5)!.net).toEqual({ zach: 3, friend: 4 });
    expect(deltas).toEqual({ zach: 8500, friend: -8500 });
    expect(complete).toBe(true);
    // Hole 18 pushes with nothing after it: reported, not paid.
    expect(carryOutCents).toBe(500);
  });

  it("carries a push on hole 9 through the turn to hole 10", () => {
    const players = [player("zach", 15), player("friend", 7)];
    const { holes } = scoreSkins({ players, holes: course18, scores: scoresFor(players, course18), baseCents: 500 });
    expect(holes.find((h) => h.hole === 9)!.status).toBe("pushed");
    expect(holes.find((h) => h.hole === 10)).toMatchObject({ carriedInCents: 500, atStakeCents: 1000, winnerUserId: "zach" });
  });

  it("marks a hole missing a score, and every hole after it, as pending", () => {
    const scores = scoresFor(four, firstFour, [[1, "a", 3]]).filter((s) => !(s.hole === 2 && s.userId === "d"));
    const { holes, deltas, complete } = scoreSkins({ players: four, holes: firstFour, scores, baseCents: 500 });

    expect(holes[0]).toMatchObject({ hole: 1, status: "won", winnerUserId: "a" });
    expect(holes[1]).toMatchObject({ hole: 2, status: "pending", carriedInCents: 0, atStakeCents: 500, net: null });
    expect(holes[2]).toMatchObject({ hole: 3, status: "pending", carriedInCents: null, atStakeCents: null });
    expect(holes[2]!.net).not.toBeNull();
    expect(deltas).toEqual({ a: 1500, b: -500, c: -500, d: -500 });
    expect(complete).toBe(false);
  });

  it("keeps deltas zero-sum", () => {
    const scores = scoresFor(four, course18, [
      [2, "a", 4],
      [7, "b", 4],
      [11, "c", 2],
      [15, "d", 4],
    ]);
    const { deltas } = scoreSkins({ players: four, holes: course18, scores, baseCents: 500 });
    expect(Object.values(deltas).reduce((x, y) => x + y, 0)).toBe(0);
  });

  describe("without carryover", () => {
    it("pays nothing for a push, and the next hole is worth the base again", () => {
      // Holes 1 and 2 push; a wins hole 3 for the base only; b wins hole 4.
      const scores = scoresFor(four, firstFour, [
        [1, "c", 5],
        [1, "d", 5],
        [3, "a", 2],
        [4, "b", 3],
      ]);
      const { holes, deltas, complete, carryOutCents } = scoreSkins({ players: four, holes: firstFour, scores, baseCents: 500, carryover: false });

      expect(holes.map((h) => [h.hole, h.status, h.carriedInCents, h.atStakeCents, h.winnerUserId])).toEqual([
        [1, "pushed", 0, 500, null],
        [2, "pushed", 0, 500, null],
        [3, "won", 0, 500, "a"],
        [4, "won", 0, 500, "b"],
      ]);
      expect(deltas).toEqual({ a: 1000, b: 1000, c: -1000, d: -1000 });
      expect(complete).toBe(true);
      expect(carryOutCents).toBe(0);
    });

    it("leaves nothing unresolved when the round ends on a push", () => {
      // Everyone shoots gross par with no ticks: every hole pushes.
      const { holes, deltas, complete, carryOutCents } = scoreSkins({
        players: four,
        holes: course18,
        scores: scoresFor(four, course18),
        baseCents: 500,
        carryover: false,
      });

      expect(holes.every((h) => h.status === "pushed" && h.carriedInCents === 0 && h.atStakeCents === 500)).toBe(true);
      expect(deltas).toEqual({ a: 0, b: 0, c: 0, d: 0 });
      expect(complete).toBe(true);
      expect(carryOutCents).toBe(0);
    });

    it("still marks a hole missing a score, and every hole after it, as pending", () => {
      const scores = scoresFor(four, firstFour, [[1, "c", 5], [1, "d", 5]]).filter((s) => !(s.hole === 2 && s.userId === "d"));
      const { holes, complete, carryOutCents } = scoreSkins({ players: four, holes: firstFour, scores, baseCents: 500, carryover: false });

      expect(holes[0]).toMatchObject({ hole: 1, status: "pushed", carriedInCents: 0, atStakeCents: 500 });
      expect(holes[1]).toMatchObject({ hole: 2, status: "pending", carriedInCents: 0, atStakeCents: 500, net: null });
      expect(holes[2]).toMatchObject({ hole: 3, status: "pending", carriedInCents: null, atStakeCents: null });
      expect(complete).toBe(false);
      expect(carryOutCents).toBe(0);
    });
  });

  it("carries over by default, the same as carryover: true", () => {
    const scores = scoresFor(four, firstFour, [
      [1, "c", 5],
      [1, "d", 5],
      [3, "a", 2],
    ]);
    const input = { players: four, holes: firstFour, scores, baseCents: 500 };
    const byDefault = scoreSkins(input);
    expect(byDefault).toEqual(scoreSkins({ ...input, carryover: true }));
    expect(byDefault.holes[2]).toMatchObject({ status: "won", carriedInCents: 1000, atStakeCents: 1500, winnerUserId: "a" });
    expect(byDefault.deltas).toEqual({ a: 4500, b: -1500, c: -1500, d: -1500 });
  });
});
