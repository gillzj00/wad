import type { Cents, UserId } from "../shared/types.js";
import type { scoreGreenies } from "./greenies.js";
import type { SkinsResult } from "./skins.js";
import type { scoreWad, WadSegment } from "./wad.js";
import type { WolfResult } from "./wolf.js";

type GreeniesResult = ReturnType<typeof scoreGreenies>;
type WadResult = ReturnType<typeof scoreWad>;

export type LedgerGame = "skins" | "wad" | "greenies" | "wolf";

/**
 * Why a pair owes what it owes, for one game and one direction. Signed toward
 * the pair's net: positive is money `from` owes `to`, negative is money `to`
 * owes `from` in this game, which comes off what `from` owes.
 */
export interface LedgerItem {
  game: LedgerGame;
  /** Skins and greenies: the holes the money came from, ascending. Empty otherwise. */
  holes: number[];
  /** Wad: the nines the money came from. Empty otherwise. */
  segments: WadSegment[];
  /** Wolf: the difference in the pair's points, signed like `amountCents`. Zero otherwise. */
  points: number;
  amountCents: Cents;
}

/** What one player owes another, net across the games, and why. `amountCents` is positive. */
export interface LedgerPair {
  from: UserId;
  to: UserId;
  amountCents: Cents;
  /** In the order skins, wad, greenies, wolf; within a game, the positive item first. */
  items: LedgerItem[];
}

/**
 * Each game's result with its field (the players in it). Null or absent: not
 * played. The results may come from JSON that leaves out null fields (the iOS
 * bridge does), so a missing winner or holder is treated as null.
 */
export interface LedgerInput {
  skins?: { players: UserId[]; result: SkinsResult } | null;
  wad?: { players: UserId[]; result: WadResult } | null;
  greenies?: { players: UserId[]; result: GreeniesResult; amountCents: Cents } | null;
  /** Wolf's field is the result's tee order. */
  wolf?: { result: WolfResult; pointCents: Cents } | null;
}

/** One movement of money between two players, as a game engine makes it. */
interface Flow {
  game: LedgerGame;
  payer: UserId;
  payee: UserId;
  cents: Cents;
  hole?: number;
  segment?: WadSegment;
  points?: number;
}

const GAMES: LedgerGame[] = ["skins", "wad", "greenies", "wolf"];
const byId = (a: UserId, b: UserId) => (a < b ? -1 : a > b ? 1 : 0);

/** The winner collects `cents` from each other player in the field. */
function fromEach(flows: Flow[], field: UserId[], winner: UserId, base: Omit<Flow, "payer" | "payee">): void {
  if (!Number.isInteger(base.cents)) throw new Error(`amount must be integer cents, got ${base.cents}`);
  if (base.cents === 0) return;
  for (const p of field) if (p !== winner) flows.push({ ...base, payer: p, payee: winner });
}

/**
 * The pairwise ledger: for every pair of players with a non-zero net, who owes
 * whom, how much, and from which holes of which game. It expands each game's
 * payments into flows between pairs exactly as the game engines move the
 * money, so every player's pairwise nets sum to their position from `settle`.
 * Pairs are ordered by the debtor's id, then the creditor's.
 */
export function pairwiseLedger(input: LedgerInput): LedgerPair[] {
  const flows: Flow[] = [];

  if (input.skins) {
    const { players, result } = input.skins;
    for (const h of result.holes) {
      if (h.status !== "won" || !h.winnerUserId || typeof h.atStakeCents !== "number") continue;
      fromEach(flows, players, h.winnerUserId, { game: "skins", cents: h.atStakeCents, hole: h.hole });
    }
  }
  if (input.wad) {
    const { players, result } = input.wad;
    for (const w of result.instances) {
      if (!w.complete || !w.holderUserId) continue;
      fromEach(flows, players, w.holderUserId, { game: "wad", cents: w.valueCents, segment: w.segment });
    }
  }
  if (input.greenies) {
    const { players, result, amountCents } = input.greenies;
    for (const h of result.holes) {
      if (h.status !== "awarded" || !h.winnerUserId) continue;
      fromEach(flows, players, h.winnerUserId, { game: "greenies", cents: amountCents, hole: h.hole });
    }
  }
  if (input.wolf) {
    const { result, pointCents } = input.wolf;
    const ids = result.teeOrder;
    for (let i = 0; i < ids.length; i++) {
      for (let j = i + 1; j < ids.length; j++) {
        const a = ids[i]!;
        const b = ids[j]!;
        const diff = (result.points[a] ?? 0) - (result.points[b] ?? 0);
        if (diff === 0 || pointCents === 0) continue;
        const [payer, payee] = diff > 0 ? [b, a] : [a, b];
        const points = Math.abs(diff);
        flows.push({ game: "wolf", payer, payee, cents: pointCents * points, points });
      }
    }
  }

  // Group the flows by unordered pair, the lower id first.
  const pairs = new Map<string, { low: UserId; high: UserId; flows: Flow[] }>();
  for (const f of flows) {
    const [low, high] = byId(f.payer, f.payee) < 0 ? [f.payer, f.payee] : [f.payee, f.payer];
    const key = JSON.stringify([low, high]);
    let pair = pairs.get(key);
    if (!pair) {
      pair = { low, high, flows: [] };
      pairs.set(key, pair);
    }
    pair.flows.push(f);
  }

  const ledger: LedgerPair[] = [];
  for (const { low, high, flows: pairFlows } of pairs.values()) {
    // Positive: the lower id owes the higher.
    const lowOwes = pairFlows.reduce((sum, f) => sum + (f.payer === low ? f.cents : -f.cents), 0);
    if (lowOwes === 0) continue;
    const [from, to] = lowOwes > 0 ? [low, high] : [high, low];

    const items: LedgerItem[] = [];
    for (const game of GAMES) {
      for (const owed of [true, false]) {
        const group = pairFlows.filter((f) => f.game === game && (f.payer === from) === owed);
        if (group.length === 0) continue;
        const sign = owed ? 1 : -1;
        items.push({
          game,
          holes: group.flatMap((f) => (f.hole === undefined ? [] : [f.hole])).sort((a, b) => a - b),
          segments: group.flatMap((f) => (f.segment === undefined ? [] : [f.segment])),
          points: sign * group.reduce((sum, f) => sum + (f.points ?? 0), 0) || 0,
          amountCents: sign * group.reduce((sum, f) => sum + f.cents, 0),
        });
      }
    }
    ledger.push({ from, to, amountCents: Math.abs(lowOwes), items });
  }

  return ledger.sort((a, b) => byId(a.from, b.from) || byId(a.to, b.to));
}
