import type { Cents, Deltas, UserId } from "../shared/types.js";

export function zeroDeltas(players: UserId[]): Deltas {
  return Object.fromEntries(players.map((p) => [p, 0]));
}

/** The winner collects `amount` from each other player. Mutates `deltas`. */
export function collectFromEach(deltas: Deltas, players: UserId[], winner: UserId, amount: Cents): void {
  if (!Number.isInteger(amount)) throw new Error(`amount must be integer cents, got ${amount}`);
  for (const p of players) {
    if (p === winner) continue;
    deltas[p] = (deltas[p] ?? 0) - amount;
    deltas[winner] = (deltas[winner] ?? 0) + amount;
  }
}

export function addDeltas(...all: Deltas[]): Deltas {
  const sum: Deltas = {};
  for (const d of all) {
    for (const [p, v] of Object.entries(d)) sum[p] = (sum[p] ?? 0) + v;
  }
  return sum;
}
