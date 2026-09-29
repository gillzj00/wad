import type { Cents, Deltas, HoleInfo, Player, Score, UserId } from "../shared/types.js";
import { allocateTicks, netScore } from "./handicap.js";
import { collectFromEach, zeroDeltas } from "./money.js";

/**
 * - won: a sole lowest net score; the winner collects atStake from each other player
 * - pushed: tie for lowest net; atStake carries to the next hole
 * - pending: this hole, or an earlier one, is missing a score
 */
export type SkinStatus = "won" | "pushed" | "pending";

export interface SkinHoleResult {
  hole: number;
  status: SkinStatus;
  /** Value carried in from pushed holes. Null when an earlier hole is pending. */
  carriedInCents: Cents | null;
  /** carriedIn + base. Null when an earlier hole is pending. */
  atStakeCents: Cents | null;
  winnerUserId: UserId | null;
  /** Net scores for the hole, present once every player has a score. */
  net: Record<UserId, number> | null;
}

export interface SkinsResult {
  holes: SkinHoleResult[];
  deltas: Deltas;
  /** True when every hole has every player's score. */
  complete: boolean;
  /**
   * Value carried out of the last resolved hole (0 unless it was pushed). When
   * `complete` is true and this is non-zero, the final carryover is unresolved:
   * it is not paid out (see Open Question 1 in docs/domain-model.md).
   */
  carryOutCents: Cents;
}

export interface SkinsInput {
  players: Player[];
  /** The holes being played. */
  holes: HoleInfo[];
  scores: Score[];
  baseCents: Cents;
}

export function scoreSkins(input: SkinsInput): SkinsResult {
  const { players, holes, scores, baseCents } = input;
  const ids = players.map((p) => p.userId);
  const ticks = allocateTicks(players, holes);
  const gross = new Map(scores.map((s) => [`${s.hole}:${s.userId}`, s.gross]));
  const deltas = zeroDeltas(ids);

  const results: SkinHoleResult[] = [];
  let carry: Cents = 0;
  let blocked = false;

  for (const h of [...holes].sort((a, b) => a.hole - b.hole)) {
    const atStake = carry + baseCents;
    const grossByPlayer = ids.map((id) => gross.get(`${h.hole}:${id}`));
    const net = grossByPlayer.every((g) => g !== undefined)
      ? Object.fromEntries(ids.map((id, i) => [id, netScore(grossByPlayer[i]!, ticks[id]![h.hole]!)]))
      : null;

    if (blocked || net === null) {
      results.push({
        hole: h.hole,
        status: "pending",
        carriedInCents: blocked ? null : carry,
        atStakeCents: blocked ? null : atStake,
        winnerUserId: null,
        net,
      });
      blocked = true;
      continue;
    }

    const best = Math.min(...Object.values(net));
    const leaders = ids.filter((id) => net[id] === best);
    if (leaders.length === 1) {
      const winner = leaders[0]!;
      collectFromEach(deltas, ids, winner, atStake);
      results.push({ hole: h.hole, status: "won", carriedInCents: carry, atStakeCents: atStake, winnerUserId: winner, net });
      carry = 0;
    } else {
      results.push({ hole: h.hole, status: "pushed", carriedInCents: carry, atStakeCents: atStake, winnerUserId: null, net });
      carry = atStake;
    }
  }

  return { holes: results, deltas, complete: !blocked, carryOutCents: carry };
}
