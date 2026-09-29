import { describe, expect, it } from "vitest";
import { scoreGreenies } from "../../src/engines/greenies.js";
import type { HoleEvents, Score } from "../../src/shared/types.js";
import { course18 } from "./fixtures.js";

// Par 3s in the fixture: holes 3, 6, 11, 16.
const players = ["a", "b", "c"];
const event = (hole: number, greenieWinner: string | null): HoleEvents => ({ hole, wadMakers: [], greenieWinner });
const score = (hole: number, userId: string, gross: number): Score => ({ hole, userId, gross });

const run = (holeEvents: HoleEvents[], scores: Score[]) =>
  scoreGreenies({ players, holes: course18, scores, holeEvents, amountCents: 500 });

describe("scoreGreenies", () => {
  it("winner collects the amount from each other player", () => {
    const { holes, deltas } = run([event(3, "a")], [score(3, "a", 3)]);
    expect(holes.find((h) => h.hole === 3)).toEqual({ hole: 3, winnerUserId: "a", status: "awarded" });
    expect(deltas).toEqual({ a: 1000, b: -500, c: -500 });
  });

  it("counts a birdie or ace as par or better", () => {
    const { deltas } = run([event(3, "a"), event(6, "b")], [score(3, "a", 2), score(6, "b", 1)]);
    expect(deltas).toEqual({ a: 500, b: 500, c: -1000 });
  });

  it("lists every par 3 and pays nothing when no greenie is recorded", () => {
    const { holes, deltas } = run([], []);
    expect(holes.map((h) => [h.hole, h.status])).toEqual([
      [3, "none"],
      [6, "none"],
      [11, "none"],
      [16, "none"],
    ]);
    expect(deltas).toEqual({ a: 0, b: 0, c: 0 });
  });

  it("marks a winner whose score is not in yet as pending and does not pay", () => {
    const { holes, deltas } = run([event(3, "a")], []);
    expect(holes.find((h) => h.hole === 3)!.status).toBe("pending");
    expect(deltas).toEqual({ a: 0, b: 0, c: 0 });
  });

  it("marks a winner who scored worse than par as invalid and does not pay", () => {
    const { holes, deltas } = run([event(3, "a")], [score(3, "a", 4)]);
    expect(holes.find((h) => h.hole === 3)!.status).toBe("invalid");
    expect(deltas).toEqual({ a: 0, b: 0, c: 0 });
  });

  it("marks a greenie on a non-par-3 as invalid", () => {
    const { holes, deltas } = run([event(1, "a")], [score(1, "a", 4)]);
    expect(holes.find((h) => h.hole === 1)).toEqual({ hole: 1, winnerUserId: "a", status: "invalid" });
    expect(deltas).toEqual({ a: 0, b: 0, c: 0 });
  });

  it("marks a winner who is not in the round as invalid", () => {
    const { holes } = run([event(3, "stranger")], [score(3, "stranger", 3)]);
    expect(holes.find((h) => h.hole === 3)!.status).toBe("invalid");
  });

  it("keeps deltas zero-sum across several holes", () => {
    const { deltas } = run(
      [event(3, "a"), event(6, "b"), event(11, "a"), event(16, null)],
      [score(3, "a", 3), score(6, "b", 3), score(11, "a", 3)],
    );
    expect(deltas).toEqual({ a: 1500, b: 0, c: -1500 });
    expect(Object.values(deltas).reduce((x, y) => x + y, 0)).toBe(0);
  });
});
