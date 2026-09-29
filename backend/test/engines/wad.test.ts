import { describe, expect, it } from "vitest";
import { scoreWad } from "../../src/engines/wad.js";
import type { HoleEvents, HoleInfo, Score } from "../../src/shared/types.js";
import { course18, front9 } from "./fixtures.js";

const players = ["a", "b", "c", "d"];
const makers = (hole: number, ...wadMakers: string[]): HoleEvents => ({ hole, wadMakers, greenieWinner: null });
const allScored = (holes: HoleInfo[]): Score[] =>
  holes.flatMap((h) => players.map((userId) => ({ hole: h.hole, userId, gross: h.par })));

const run = (holes: HoleInfo[], holeEvents: HoleEvents[], scores = allScored(holes)) =>
  scoreWad({ players, holes, scores, holeEvents, startCents: 700, stepCents: 200 });

describe("scoreWad", () => {
  it("first make takes it at the start value, each later make adds the step (domain example)", () => {
    const { instances, deltas } = run(front9, [makers(2, "a"), makers(5, "b", "c"), makers(7, "c")]);
    const front = instances[0]!;
    expect(front.makes).toEqual([
      { hole: 2, userId: "a", valueCents: 700 },
      { hole: 5, userId: "b", valueCents: 900 },
      { hole: 5, userId: "c", valueCents: 1100 },
      { hole: 7, userId: "c", valueCents: 1300 },
    ]);
    expect(front).toMatchObject({ segment: "front", holderUserId: "c", valueCents: 1300, complete: true });
    // c collects $13 from each of the other three.
    expect(deltas).toEqual({ a: -1300, b: -1300, c: 3900, d: -1300 });
  });

  it("runs the front and back as separate instances, each starting fresh", () => {
    const { instances, deltas } = run(course18, [makers(3, "a"), makers(4, "b"), makers(12, "d")]);
    expect(instances.map((i) => [i.segment, i.holderUserId, i.valueCents])).toEqual([
      ["front", "b", 900],
      ["back", "d", 700],
    ]);
    expect(deltas).toEqual({ a: -900 - 700, b: 2700 - 700, c: -900 - 700, d: -900 + 2100 });
  });

  it("pays nothing for a nine where nobody made one", () => {
    const { instances, deltas } = run(front9, []);
    expect(instances[0]).toMatchObject({ holderUserId: null, valueCents: 700, makes: [], complete: true });
    expect(deltas).toEqual({ a: 0, b: 0, c: 0, d: 0 });
  });

  it("does not pay until every player has a score on the last hole of the nine", () => {
    const scores = allScored(front9).filter((s) => !(s.hole === 9 && s.userId === "d"));
    const { instances, deltas } = run(front9, [makers(1, "a")], scores);
    expect(instances[0]).toMatchObject({ holderUserId: "a", complete: false });
    expect(deltas).toEqual({ a: 0, b: 0, c: 0, d: 0 });
  });

  it("handles a back-nine-only round as a single instance", () => {
    const back9 = course18.slice(9);
    const { instances } = run(back9, [makers(10, "a")]);
    expect(instances).toHaveLength(1);
    expect(instances[0]).toMatchObject({ segment: "back", holderUserId: "a", valueCents: 700 });
  });

  it("uses the configured start and step", () => {
    const { instances } = scoreWad({
      players,
      holes: front9,
      scores: allScored(front9),
      holeEvents: [makers(1, "a"), makers(2, "b")],
      startCents: 1000,
      stepCents: 500,
    });
    expect(instances[0]!.valueCents).toBe(1500);
  });

  it("ignores makes by non-players and duplicate makes on a hole", () => {
    const { instances, ignored } = run(front9, [makers(1, "a", "stranger", "a")]);
    expect(instances[0]!.makes).toEqual([{ hole: 1, userId: "a", valueCents: 700 }]);
    expect(ignored).toEqual([
      { hole: 1, userId: "stranger", reason: "not-a-player" },
      { hole: 1, userId: "a", reason: "duplicate" },
    ]);
  });
});
