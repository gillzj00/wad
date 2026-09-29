import type { Cents, Deltas, UserId } from "../shared/types.js";
import { addDeltas } from "./money.js";

export interface Transfer {
  from: UserId;
  to: UserId;
  amountCents: Cents;
}

/**
 * Nets the per-game deltas into one position per player and reduces them to
 * pairwise transfers by repeatedly matching the largest creditor with the
 * largest debtor. That yields at most (players with a non-zero position - 1)
 * transfers. Ties are broken by user id so the result is deterministic.
 */
export function settle(...gameDeltas: Deltas[]): { positions: Deltas; transfers: Transfer[] } {
  const positions = addDeltas(...gameDeltas);
  const total = Object.values(positions).reduce((a, b) => a + b, 0);
  if (total !== 0) throw new Error(`deltas must sum to zero, got ${total}`);

  const byAmountThenId = (a: [UserId, Cents], b: [UserId, Cents]) => b[1] - a[1] || a[0].localeCompare(b[0]);
  const creditors = Object.entries(positions).filter(([, v]) => v > 0);
  const debtors = Object.entries(positions)
    .filter(([, v]) => v < 0)
    .map(([id, v]): [UserId, Cents] => [id, -v]);

  const transfers: Transfer[] = [];
  while (creditors.length > 0 && debtors.length > 0) {
    creditors.sort(byAmountThenId);
    debtors.sort(byAmountThenId);
    const creditor = creditors[0]!;
    const debtor = debtors[0]!;
    const amount = Math.min(creditor[1], debtor[1]);
    transfers.push({ from: debtor[0], to: creditor[0], amountCents: amount });
    creditor[1] -= amount;
    debtor[1] -= amount;
    if (creditor[1] === 0) creditors.shift();
    if (debtor[1] === 0) debtors.shift();
  }
  return { positions, transfers };
}
