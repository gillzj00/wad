import { createHash } from "node:crypto";
import { zeroDeltas } from "../../engines/money.js";
import { settle } from "../../engines/settlement.js";
import type { Settlement, SettlementIssue, SettlementTransfer } from "../../shared/settlement.js";
import type { Cents, Deltas, UserId } from "../../shared/types.js";
import { RoundError } from "./errors.js";
import { computeState } from "./gameState.js";
import { loadRoundForMember } from "./roundService.js";
import type { PaidMarker, RoundRecord, RoundStore } from "./roundStore.js";

export interface SettlementServiceDeps {
  now?: () => Date;
}

interface Party {
  from: UserId;
  to: UserId;
  amountCents: Cents;
}

/**
 * The id is a digest of the transfer itself. Transfers are derived on every
 * read, so a paid marker is tied to the payer, payee and amount it was made
 * for: when a correction changes any of them the transfer gets another id.
 */
export function transferId(roundId: string, transfer: Party): string {
  const digest = createHash("sha256").update(JSON.stringify([roundId, transfer.from, transfer.to, transfer.amountCents])).digest("hex");
  return `t_${digest.slice(0, 24)}`;
}

const sameTransfer = (a: Party, b: Party) => a.from === b.from && a.to === b.to && a.amountCents === b.amountCents;

export class SettlementService {
  private readonly now: () => Date;

  constructor(
    private readonly store: RoundStore,
    deps: SettlementServiceDeps = {},
  ) {
    this.now = deps.now ?? (() => new Date());
  }

  async getSettlement(userId: UserId, roundId: string): Promise<Settlement> {
    return this.build(await loadRoundForMember(this.store, userId, roundId));
  }

  /** Idempotent: marking a paid transfer again keeps the first marker. */
  async markPaid(userId: UserId, roundId: string, id: string): Promise<Settlement> {
    const record = await loadRoundForMember(this.store, userId, roundId);
    const settlement = await this.build(record);
    const transfer = settlement.transfers.find((t) => t.transferId === id);
    if (!transfer) throw transferNotFound();
    requireParty(record, userId, transfer);
    if (settlement.incompleteHoles.length > 0) {
      throw new RoundError("conflict", "round_incomplete", "transfers can be marked paid once every hole is scored");
    }
    if (settlement.issues.length > 0) {
      throw new RoundError("conflict", "settlement_has_issues", "transfers can be marked paid once the settlement has no issues");
    }
    await this.store.markTransferPaid(roundId, {
      transferId: id,
      from: transfer.from,
      to: transfer.to,
      amountCents: transfer.amountCents,
      paidAt: this.now().toISOString(),
      paidBy: userId,
    });
    return this.build(record);
  }

  /** Idempotent. Also removes a stale marker, so a payment recorded before a correction can be withdrawn. */
  async markUnpaid(userId: UserId, roundId: string, id: string): Promise<Settlement> {
    const record = await loadRoundForMember(this.store, userId, roundId);
    const settlement = await this.build(record);
    const target = settlement.transfers.find((t) => t.transferId === id) ?? settlement.stalePayments.find((p) => p.transferId === id);
    if (!target) throw transferNotFound();
    requireParty(record, userId, target);
    await this.store.unmarkTransferPaid(roundId, id);
    return this.build(record);
  }

  /**
   * Positions and transfers are what the settle engine returns for the game
   * deltas the game engines returned; nothing here computes money.
   */
  private async build(record: RoundRecord): Promise<Settlement> {
    const { roundId } = record.meta;
    const ids = record.players.map((p) => p.userId);
    const state = computeState(record);

    const games: Settlement["games"] = {};
    const deltas: Deltas[] = [];
    const issues: SettlementIssue[] = [];

    if (state.skins !== undefined) {
      games.skins = state.skins?.deltas ?? null;
      if (state.skins) deltas.push(state.skins.deltas);
      else {
        issues.push({
          code: "skins_unavailable",
          hole: null,
          userId: null,
          message: "skins cannot be scored until every player has a course handicap, so it is not part of this settlement",
        });
      }
    }
    if (state.wad) {
      games.wad = state.wad.deltas;
      deltas.push(state.wad.deltas);
      for (const make of state.wad.ignored) {
        issues.push({ code: "wad_make_ignored", hole: make.hole, userId: make.userId, message: `a wad make on hole ${make.hole} was ignored` });
      }
    }
    if (state.greenies) {
      games.greenies = state.greenies.deltas;
      deltas.push(state.greenies.deltas);
      for (const h of state.greenies.holes) {
        if (h.status === "pending") {
          issues.push({ code: "greenie_pending", hole: h.hole, userId: h.winnerUserId, message: `the greenie on hole ${h.hole} waits for the winner's score` });
        } else if (h.status === "invalid") {
          issues.push({ code: "greenie_invalid", hole: h.hole, userId: h.winnerUserId, message: `the greenie on hole ${h.hole} is not valid and is not paid` });
        }
      }
    }

    const scored = new Set(record.scores.map((s) => `${s.hole}:${s.userId}`));
    const incompleteHoles = record.meta.tee.holes
      .map((h) => h.hole)
      .filter((hole) => ids.some((id) => !scored.has(`${hole}:${id}`)))
      .sort((a, b) => a - b);

    // The zero deltas only make every player appear in the positions.
    const { positions, transfers: derived } = settle(zeroDeltas(ids), ...deltas);

    const markers = await this.store.listPaidMarkers(roundId);
    const used = new Set<PaidMarker>();
    const transfers: SettlementTransfer[] = [];
    for (const t of derived) {
      const id = transferId(roundId, t);
      const marker = markers.find((m) => m.transferId === id && sameTransfer(m, t));
      if (marker) used.add(marker);
      transfers.push({
        transferId: id,
        from: t.from,
        to: t.to,
        amountCents: t.amountCents,
        toVenmoHandle: await this.venmoHandle(record, t.to),
        paid: marker !== undefined,
        paidAt: marker?.paidAt ?? null,
        paidBy: marker?.paidBy ?? null,
      });
    }

    return {
      roundId,
      status: incompleteHoles.length === 0 && issues.length === 0 ? "final" : "provisional",
      incompleteHoles,
      issues,
      games,
      positions,
      transfers,
      skinsCarryover: state.skins ? { amountCents: state.skins.carryOutCents, unresolved: state.skins.complete && state.skins.carryOutCents !== 0 } : null,
      stalePayments: markers.filter((m) => !used.has(m)),
    };
  }

  private async venmoHandle(record: RoundRecord, userId: UserId): Promise<string | null> {
    const player = record.players.find((p) => p.userId === userId);
    return !player || player.guest ? null : this.store.getVenmoHandle(userId);
  }
}

/** The payer or the payee. A guest has no account, so any player acts for a guest's transfer. */
function requireParty(record: RoundRecord, userId: UserId, transfer: Party): void {
  const parties = [transfer.from, transfer.to];
  const guest = record.players.some((p) => p.guest && parties.includes(p.userId));
  if (!parties.includes(userId) && !guest) {
    throw new RoundError("forbidden", "not_transfer_party", "only the payer or the payee can mark this transfer");
  }
}

function transferNotFound(): RoundError {
  return new RoundError("not_found", "transfer_not_found", "the settlement has no transfer with that id");
}
