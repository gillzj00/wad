import type { Cents, Deltas, HoleEvents, HoleInfo, Score, UserId } from "../shared/types.js";
import { collectFromEach, zeroDeltas } from "./money.js";

/**
 * - none: no greenie recorded on this par 3
 * - awarded: valid winner; paid out
 * - pending: winner recorded but their score is not in yet; not paid yet
 * - invalid: winner is not a player, the hole is not a par 3, or the winner
 *   scored worse than par (e.g. the score was corrected afterwards); not paid
 */
export type GreenieStatus = "none" | "awarded" | "pending" | "invalid";

export interface GreenieHoleResult {
  hole: number;
  winnerUserId: UserId | null;
  status: GreenieStatus;
}

export interface GreeniesInput {
  players: UserId[];
  holes: HoleInfo[];
  scores: Score[];
  holeEvents: HoleEvents[];
  amountCents: Cents;
}

export function scoreGreenies(input: GreeniesInput): { holes: GreenieHoleResult[]; deltas: Deltas } {
  const { players, holes, scores, holeEvents, amountCents } = input;
  const deltas = zeroDeltas(players);
  const winnerByHole = new Map(holeEvents.map((e) => [e.hole, e.greenieWinner]));
  const gross = new Map(scores.map((s) => [`${s.hole}:${s.userId}`, s.gross]));

  const results: GreenieHoleResult[] = [];
  for (const h of [...holes].sort((a, b) => a.hole - b.hole)) {
    const winner = winnerByHole.get(h.hole) ?? null;
    if (h.par !== 3) {
      if (winner !== null) results.push({ hole: h.hole, winnerUserId: winner, status: "invalid" });
      continue;
    }
    if (winner === null) {
      results.push({ hole: h.hole, winnerUserId: null, status: "none" });
      continue;
    }
    const winnerGross = gross.get(`${h.hole}:${winner}`);
    let status: GreenieStatus;
    if (!players.includes(winner)) status = "invalid";
    else if (winnerGross === undefined) status = "pending";
    else if (winnerGross > h.par) status = "invalid";
    else status = "awarded";

    if (status === "awarded") collectFromEach(deltas, players, winner, amountCents);
    results.push({ hole: h.hole, winnerUserId: winner, status });
  }
  return { holes: results, deltas };
}
