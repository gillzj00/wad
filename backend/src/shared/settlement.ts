// Settlement types for the settlement routes. They mirror docs/api.md; keep
// the two in sync.
import type { Cents, Deltas, UserId } from "./types.js";

/** Final only when every hole has every player's score and there are no issues. */
export type SettlementStatus = "provisional" | "final";

export type SettlementIssueCode =
  | "skins_unavailable"
  | "greenie_pending"
  | "greenie_invalid"
  | "wad_make_ignored"
  | "wolf_unavailable"
  | "wolf_pending"
  | "wolf_needs_wolf"
  | "wolf_invalid";

/** Something in the round that keeps the settlement from being final. */
export interface SettlementIssue {
  code: SettlementIssueCode;
  hole: number | null;
  userId: UserId | null;
  message: string;
}

export interface SettlementTransfer {
  /** Derived from the round, payer, payee and amount, so it changes when any of them does. */
  transferId: string;
  from: UserId;
  to: UserId;
  amountCents: Cents;
  /** The payee's Venmo handle from their profile; null when they have none or are a guest. */
  toVenmoHandle: string | null;
  paid: boolean;
  paidAt: string | null;
  paidBy: UserId | null;
}

/** A paid marker whose transfer is no longer part of the settlement. */
export interface StalePayment {
  transferId: string;
  from: UserId;
  to: UserId;
  amountCents: Cents;
  paidAt: string;
  paidBy: UserId;
}

export interface SkinsCarryover {
  /** The value carried out of the last resolved hole. Never part of a position or transfer. */
  amountCents: Cents;
  /** True when the last hole was pushed: the carryover has no next hole and is not paid. */
  unresolved: boolean;
}

export interface Settlement {
  roundId: string;
  status: SettlementStatus;
  /** Holes where at least one player has no score. */
  incompleteHoles: number[];
  issues: SettlementIssue[];
  /** Each enabled game's deltas as the engine returned them; skins and wolf are null while unavailable. */
  games: { skins?: Deltas | null; wad?: Deltas; greenies?: Deltas; wolf?: Deltas | null };
  positions: Deltas;
  transfers: SettlementTransfer[];
  /** Null when skins is not enabled or is unavailable. */
  skinsCarryover: SkinsCarryover | null;
  stalePayments: StalePayment[];
}
