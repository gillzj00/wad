import { describe, expect, it } from "vitest";
import { scoreGreenies } from "../../src/engines/greenies.js";
import { pairwiseLedger, type LedgerInput, type LedgerPair } from "../../src/engines/ledger.js";
import { settle } from "../../src/engines/settlement.js";
import { scoreSkins } from "../../src/engines/skins.js";
import { scoreWad } from "../../src/engines/wad.js";
import type { WolfResult } from "../../src/engines/wolf.js";
import type { Deltas, HoleEvents, HoleInfo, Player, Score } from "../../src/shared/types.js";
import { front9 } from "./fixtures.js";

// Front nine pars: 4 5 3 4 4 3 5 4 4. Par 3s: holes 3 and 6.

const player = (userId: string): Player => ({ userId, displayName: userId, courseHandicap: 0 });

/** Everyone makes par on every hole of `holes` unless `gross` says otherwise (hole -> player -> gross; null is no score). */
function scoresFor(ids: string[], holes: HoleInfo[], gross: Record<number, Record<string, number | null>> = {}): Score[] {
  const scores: Score[] = [];
  for (const h of holes) {
    for (const id of ids) {
      const g = gross[h.hole]?.[id];
      if (g === null) continue;
      scores.push({ hole: h.hole, userId: id, gross: g ?? h.par });
    }
  }
  return scores;
}

function skins(ids: string[], scores: Score[], baseCents = 500, holes = front9) {
  const players = ids.map(player);
  return { players: ids, result: scoreSkins({ players, holes, scores, baseCents }) };
}

function greenies(ids: string[], scores: Score[], holeEvents: HoleEvents[], amountCents = 500) {
  return { players: ids, amountCents, result: scoreGreenies({ players: ids, holes: front9, scores, holeEvents, amountCents }) };
}

function wad(ids: string[], scores: Score[], holeEvents: HoleEvents[]) {
  return { players: ids, result: scoreWad({ players: ids, holes: front9, scores, holeEvents, startCents: 100, stepCents: 100 }) };
}

function wolf(points: Record<string, number>, pointCents = 100): { result: WolfResult; pointCents: number } {
  const teeOrder = Object.keys(points);
  const total = Object.values(points).reduce((a, b) => a + b, 0);
  const deltas = Object.fromEntries(teeOrder.map((id) => [id, pointCents * (4 * points[id]! - total)]));
  return { result: { teeOrder, holes: [], points, deltas, complete: true }, pointCents };
}

const ev = (hole: number, e: Partial<HoleEvents>): HoleEvents => ({ hole, wadMakers: [], greenieWinner: null, ...e });

/** Each player's net across their pairs: positive is owed to them. */
function netByPlayer(ledger: LedgerPair[]): Deltas {
  const net: Deltas = {};
  for (const p of ledger) {
    net[p.from] = (net[p.from] ?? 0) - p.amountCents;
    net[p.to] = (net[p.to] ?? 0) + p.amountCents;
  }
  return net;
}

function expectMatchesSettle(input: LedgerInput, ledger: LedgerPair[]) {
  const deltas = [input.skins, input.wad, input.greenies, input.wolf].flatMap((g) => (g ? [g.result.deltas] : []));
  const { positions } = settle(...deltas);
  const net = netByPlayer(ledger);
  for (const [id, cents] of Object.entries(positions)) expect(net[id] ?? 0, id).toBe(cents);
  for (const p of ledger) {
    expect(p.amountCents).toBeGreaterThan(0);
    expect(p.items.reduce((s, i) => s + i.amountCents, 0)).toBe(p.amountCents);
  }
}

describe("pairwiseLedger", () => {
  it("pays a won skin to the winner from each other player in Skins", () => {
    const ids = ["a", "b", "c"];
    const input = { skins: skins(ids, scoresFor(ids, front9, { 1: { a: 3 } })) };
    expect(pairwiseLedger(input)).toEqual([
      { from: "b", to: "a", amountCents: 500, items: [{ game: "skins", holes: [1], segments: [], points: 0, amountCents: 500 }] },
      { from: "c", to: "a", amountCents: 500, items: [{ game: "skins", holes: [1], segments: [], points: 0, amountCents: 500 }] },
    ]);
  });

  it("nets a pair across games with the debtor's winnings as negative items", () => {
    const ids = ["a", "b"];
    // a wins skins 1 (500) and 6 (2500 with the carry from 2 to 5) and the greenie on 3; b wins skin 9 (1500).
    const scores = scoresFor(ids, front9, { 1: { a: 3 }, 6: { a: 2 }, 9: { b: 3 } });
    const input = { skins: skins(ids, scores), greenies: greenies(ids, scores, [ev(3, { greenieWinner: "a" })]) };
    const ledger = pairwiseLedger(input);
    expect(ledger).toEqual([
      {
        from: "b",
        to: "a",
        amountCents: 2000,
        items: [
          { game: "skins", holes: [1, 6], segments: [], points: 0, amountCents: 3000 },
          { game: "skins", holes: [9], segments: [], points: 0, amountCents: -1500 },
          { game: "greenies", holes: [3], segments: [], points: 0, amountCents: 500 },
        ],
      },
    ]);
    expectMatchesSettle(input, ledger);
  });

  it("carries pushed skins into the hole that is won and pays nothing for the push", () => {
    const ids = ["a", "b"];
    // Hole 1 pushed (both par); a wins hole 2 worth 1000.
    const input = { skins: skins(ids, scoresFor(ids, front9, { 2: { a: 4 } })) };
    expect(pairwiseLedger(input)).toEqual([
      { from: "b", to: "a", amountCents: 1000, items: [{ game: "skins", holes: [2], segments: [], points: 0, amountCents: 1000 }] },
    ]);
  });

  it("leaves a player out of a game out of that game's items", () => {
    const all = ["a", "b", "c", "d"];
    const scores = scoresFor(all, front9, { 1: { d: 2, a: 3 }, 3: { d: 2 } });
    // d is out of Skins and Greenies: d's lower score on 1 is ignored and d's greenie is invalid.
    const skinsField = ["a", "b", "c"];
    const input = {
      skins: skins(skinsField, scores.filter((s) => s.userId !== "d")),
      greenies: greenies(skinsField, scores.filter((s) => s.userId !== "d"), [ev(3, { greenieWinner: "d" })]),
    };
    const ledger = pairwiseLedger(input);
    expect(ledger.every((p) => p.from !== "d" && p.to !== "d")).toBe(true);
    expect(ledger.map((p) => [p.from, p.to])).toEqual([
      ["b", "a"],
      ["c", "a"],
    ]);
    expectMatchesSettle(input, ledger);
  });

  it("ignores pending and invalid greenies", () => {
    const ids = ["a", "b"];
    // Hole 3: a's score is missing (pending). Hole 6: b made bogey (invalid).
    const scores = scoresFor(ids, front9, { 3: { a: null }, 6: { b: 4 } });
    const input = { greenies: greenies(ids, scores, [ev(3, { greenieWinner: "a" }), ev(6, { greenieWinner: "b" })]) };
    expect(input.greenies.result.holes.map((h) => h.status)).toEqual(["pending", "invalid"]);
    expect(pairwiseLedger(input)).toEqual([]);
  });

  it("pays a complete Wad and ignores one that is not complete", () => {
    const ids = ["a", "b", "c"];
    const holeEvents = [ev(2, { wadMakers: ["a"] }), ev(5, { wadMakers: ["b"] })];
    const incomplete = wad(ids, scoresFor(ids, front9, { 9: { c: null } }), holeEvents);
    expect(pairwiseLedger({ wad: incomplete })).toEqual([]);

    const input = { wad: wad(ids, scoresFor(ids, front9), holeEvents) };
    const ledger = pairwiseLedger(input);
    const item = { game: "wad", holes: [], segments: ["front"], points: 0, amountCents: 200 };
    expect(ledger).toEqual([
      { from: "a", to: "b", amountCents: 200, items: [item] },
      { from: "c", to: "b", amountCents: 200, items: [item] },
    ]);
    expectMatchesSettle(input, ledger);
  });

  it("treats a winner or holder left out of the JSON as none", () => {
    const ids = ["a", "b", "c"];
    const fromJSON = JSON.parse(JSON.stringify(wad(ids, scoresFor(ids, front9), []), (_, v: unknown) => (v === null ? undefined : v)));
    expect(fromJSON.result.instances[0].holderUserId).toBeUndefined();
    expect(pairwiseLedger({ wad: fromJSON })).toEqual([]);
  });

  it("settles Wolf per pair by the difference in points and reproduces the deltas", () => {
    const input = { wolf: wolf({ a: 6, b: 2, c: 2, d: 0 }, 100) };
    const ledger = pairwiseLedger(input);
    expect(ledger).toEqual([
      { from: "b", to: "a", amountCents: 400, items: [{ game: "wolf", holes: [], segments: [], points: 4, amountCents: 400 }] },
      { from: "c", to: "a", amountCents: 400, items: [{ game: "wolf", holes: [], segments: [], points: 4, amountCents: 400 }] },
      { from: "d", to: "a", amountCents: 600, items: [{ game: "wolf", holes: [], segments: [], points: 6, amountCents: 600 }] },
      { from: "d", to: "b", amountCents: 200, items: [{ game: "wolf", holes: [], segments: [], points: 2, amountCents: 200 }] },
      { from: "d", to: "c", amountCents: 200, items: [{ game: "wolf", holes: [], segments: [], points: 2, amountCents: 200 }] },
    ]);
    expect(netByPlayer(ledger)).toEqual(input.wolf.result.deltas);
  });

  it("drops a pair that is square after netting", () => {
    const ids = ["a", "b"];
    // a wins skin 1, b wins skin 2: both worth 500.
    const input = { skins: skins(ids, scoresFor(ids, front9, { 1: { a: 3 }, 2: { b: 4 } })) };
    expect(pairwiseLedger(input)).toEqual([]);
  });

  it("is empty when everyone is square or nothing is played", () => {
    const ids = ["a", "b", "c"];
    const scores = scoresFor(ids, front9);
    expect(pairwiseLedger({ skins: skins(ids, scores), greenies: greenies(ids, scores, []), wad: wad(ids, scores, []) })).toEqual([]);
    expect(pairwiseLedger({})).toEqual([]);
    expect(pairwiseLedger({ skins: null, wad: null, greenies: null, wolf: null })).toEqual([]);
  });

  it("sums to every player's settled position across all four games, in a deterministic order", () => {
    const all = ["d", "c", "b", "a"];
    const scores = scoresFor(all, front9, { 1: { a: 3 }, 3: { b: 2 }, 4: { c: 3 }, 6: { d: 3, a: 2 }, 8: { c: 3 } });
    const skinsField = ["a", "b", "c"];
    const input: LedgerInput = {
      skins: skins(skinsField, scores.filter((s) => s.userId !== "d")),
      wad: wad(["b", "c", "d"], scores.filter((s) => s.userId !== "a"), [ev(2, { wadMakers: ["c"] }), ev(7, { wadMakers: ["d", "b"] })]),
      greenies: greenies(all, scores, [ev(3, { greenieWinner: "b" }), ev(6, { greenieWinner: "a" })]),
      wolf: wolf({ c: 3, a: 7, d: 2, b: 0 }, 50),
    };
    const ledger = pairwiseLedger(input);
    expectMatchesSettle(input, ledger);
    const order = ledger.map((p) => `${p.from}${p.to}`);
    expect(order).toEqual([...order].sort());
    for (const p of ledger) {
      const games = p.items.map((i) => i.game);
      const rank = { skins: 0, wad: 1, greenies: 2, wolf: 3 };
      expect(games.map((g) => rank[g])).toEqual(games.map((g) => rank[g]).sort());
    }
    // Wad is played by b, c, d only: a appears in no Wad item.
    expect(ledger.filter((p) => p.from === "a" || p.to === "a").flatMap((p) => p.items).some((i) => i.game === "wad")).toBe(false);
  });
});
