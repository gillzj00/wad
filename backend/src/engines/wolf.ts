import type { Cents, Deltas, HoleEvents, HoleInfo, Player, Score, UserId, WolfChoice } from "../shared/types.js";
import { allocateTicks, netScore } from "./handicap.js";

export const WOLF_PLAYERS = 4;
export const WOLF_HOLES = 18;
/** The tee order rotation covers holes 1 to 16; on 17 and 18 the Wolf is the player in last place. */
export const WOLF_ROTATION_HOLES = 16;

export const WOLF_POINTS = {
  /** To the Wolf and to the partner when their side wins. */
  partnerWin: 2,
  /** To each of the two opponents when the Wolf and partner lose. */
  partnerLoss: 3,
  /** To the Wolf when the Lone Wolf wins. */
  loneWin: 4,
  /** To each of the three opponents when the Lone Wolf loses. */
  loneLoss: 1,
} as const;

/**
 * - won_by_wolf_side / won_by_opponents: the lower net best ball; points awarded
 * - tied: equal net best balls; no points, nothing carries over
 * - pending: a score or the Wolf's choice is missing, or (holes 17 and 18) an
 *   earlier hole is not scored yet so the standings that name the Wolf are not known
 * - needs_wolf: hole 17 or 18 with a tie for last place and no Wolf recorded;
 *   the engine does not pick (Open Question 4 in docs/domain-model.md)
 * - invalid: the hole's record breaks a rule (see WolfInvalidReason); no points
 */
export type WolfHoleStatus = "won_by_wolf_side" | "won_by_opponents" | "tied" | "pending" | "needs_wolf" | "invalid";

/**
 * - partner_and_lone: a partner is recorded together with the lone choice
 * - partner_missing: the partner choice is recorded without a partner
 * - partner_not_a_player / wolf_not_a_player: the id is not one of the four players
 * - partner_is_wolf: the partner is the Wolf
 * - wolf_contradicts_rotation: holes 1 to 16, the recorded Wolf is not the one the tee order gives
 * - wolf_not_in_last_place: holes 17 and 18, the recorded Wolf is not in last place, or not among those tied for it
 */
export type WolfInvalidReason =
  | "partner_and_lone"
  | "partner_missing"
  | "partner_not_a_player"
  | "wolf_not_a_player"
  | "partner_is_wolf"
  | "wolf_contradicts_rotation"
  | "wolf_not_in_last_place";

export interface WolfHoleResult {
  hole: number;
  /** Null while the Wolf is not known: a pending hole 17 or 18, needs_wolf, or a record that names no valid Wolf. */
  wolfUserId: UserId | null;
  status: WolfHoleStatus;
  /** Set only when status is invalid. */
  invalidReason: WolfInvalidReason | null;
  /** The choice as recorded; null when none is. */
  choice: WolfChoice | null;
  /** The partner as recorded; null when none is. */
  partnerUserId: UserId | null;
  /** Holes 17 and 18 once the standings are known: the players in last place. Otherwise null. */
  lastPlace: UserId[] | null;
  /** The Wolf, and the partner if there is one. Null unless the hole is scored. */
  wolfSide: UserId[] | null;
  /** Everyone else, in tee order. Null unless the hole is scored. */
  opponents: UserId[] | null;
  /** Lowest net score on each side. Null unless the hole is scored. */
  wolfSideNet: number | null;
  opponentsNet: number | null;
  /** Net scores for the hole, present once all four players have a score. */
  net: Record<UserId, number> | null;
  /** Points awarded on this hole; all zero unless the hole was won. */
  points: Record<UserId, number>;
}

export interface WolfResult {
  /** The tee order the rotation used. */
  teeOrder: UserId[];
  holes: WolfHoleResult[];
  /** Running points per player, from scored holes only. */
  points: Record<UserId, number>;
  /** pointCents * (4 * own points - total points): every pair settles the difference in their points. */
  deltas: Deltas;
  /** True when all 18 holes are won or tied. */
  complete: boolean;
}

export interface WolfInput {
  /** Exactly four. */
  players: Player[];
  /** The four players' ids in the order they tee off. */
  teeOrder: UserId[];
  /** Holes 1 to 18. */
  holes: HoleInfo[];
  scores: Score[];
  holeEvents: HoleEvents[];
  pointCents: Cents;
}

function isPermutation(order: UserId[], ids: UserId[]): boolean {
  return order.length === ids.length && new Set(order).size === order.length && order.every((id) => ids.includes(id));
}

function zeroPoints(ids: UserId[]): Record<UserId, number> {
  return Object.fromEntries(ids.map((id) => [id, 0]));
}

/**
 * Scores Wolf (docs/domain-model.md, Game 4). Returns null when Wolf cannot be
 * played with this input: not exactly four distinct players, a tee order that
 * is not those four players, or holes other than 1 to 18.
 */
export function scoreWolf(input: WolfInput): WolfResult | null {
  const { players, teeOrder, holes, scores, holeEvents, pointCents } = input;
  if (!Number.isInteger(pointCents) || pointCents < 0) throw new Error(`pointCents must be non-negative integer cents, got ${pointCents}`);

  const ids = players.map((p) => p.userId);
  if (ids.length !== WOLF_PLAYERS || new Set(ids).size !== WOLF_PLAYERS) return null;
  if (!isPermutation(teeOrder, ids)) return null;
  const ordered = [...holes].sort((a, b) => a.hole - b.hole);
  if (ordered.length !== WOLF_HOLES || ordered.some((h, i) => h.hole !== i + 1)) return null;

  const ticks = allocateTicks(players, holes);
  const gross = new Map(scores.map((s) => [`${s.hole}:${s.userId}`, s.gross]));
  const eventByHole = new Map(holeEvents.map((e) => [e.hole, e.wolf]));
  const total = zeroPoints(teeOrder);

  const results: WolfHoleResult[] = [];
  /** Every hole so far is won or tied, so the standings after it are known. */
  let standingsKnown = true;

  for (const h of ordered) {
    const event = eventByHole.get(h.hole) ?? null;
    const choice = event?.choice ?? null;
    const partner = event?.partnerUserId ?? null;
    const recordedWolf = event?.wolfUserId ?? null;

    const grossByPlayer = teeOrder.map((id) => gross.get(`${h.hole}:${id}`));
    const net = grossByPlayer.every((g) => g !== undefined)
      ? Object.fromEntries(teeOrder.map((id, i) => [id, netScore(grossByPlayer[i]!, ticks[id]![h.hole]!)]))
      : null;

    const result: WolfHoleResult = {
      hole: h.hole,
      wolfUserId: null,
      status: "pending",
      invalidReason: null,
      choice,
      partnerUserId: partner,
      lastPlace: null,
      wolfSide: null,
      opponents: null,
      wolfSideNet: null,
      opponentsNet: null,
      net,
      points: zeroPoints(teeOrder),
    };
    results.push(result);
    const standingsBefore: boolean = standingsKnown;
    // Set again below only when this hole is won or tied.
    standingsKnown = false;
    const invalid = (reason: WolfInvalidReason) => {
      result.status = "invalid";
      result.invalidReason = reason;
    };

    // What is wrong with the record whoever the Wolf is.
    if (choice === "lone" && partner !== null) {
      invalid("partner_and_lone");
      continue;
    }
    if (choice === "partner" && partner === null) {
      invalid("partner_missing");
      continue;
    }
    if (partner !== null && !ids.includes(partner)) {
      invalid("partner_not_a_player");
      continue;
    }
    if (recordedWolf !== null && !ids.includes(recordedWolf)) {
      invalid("wolf_not_a_player");
      continue;
    }

    // Who the Wolf is.
    if (h.hole <= WOLF_ROTATION_HOLES) {
      const rotation = teeOrder[(h.hole - 1) % WOLF_PLAYERS]!;
      if (recordedWolf !== null && recordedWolf !== rotation) {
        invalid("wolf_contradicts_rotation");
        continue;
      }
      result.wolfUserId = rotation;
    } else {
      // Pending: the standings that name the Wolf are not known yet.
      if (!standingsBefore) continue;
      const fewest = Math.min(...teeOrder.map((id) => total[id]!));
      const last = teeOrder.filter((id) => total[id] === fewest);
      result.lastPlace = last;
      if (recordedWolf !== null && !last.includes(recordedWolf)) {
        invalid("wolf_not_in_last_place");
        continue;
      }
      if (last.length > 1 && recordedWolf === null) {
        result.status = "needs_wolf";
        continue;
      }
      result.wolfUserId = recordedWolf ?? last[0]!;
    }
    const wolf = result.wolfUserId;

    if (partner === wolf) {
      invalid("partner_is_wolf");
      continue;
    }
    // Pending: the choice or a score is missing.
    if (choice === null || net === null) continue;

    const wolfSide = partner === null ? [wolf] : [wolf, partner];
    const opponents = teeOrder.filter((id) => !wolfSide.includes(id));
    const best = (side: UserId[]) => Math.min(...side.map((id) => net[id]!));
    const wolfSideNet = best(wolfSide);
    const opponentsNet = best(opponents);
    result.wolfSide = wolfSide;
    result.opponents = opponents;
    result.wolfSideNet = wolfSideNet;
    result.opponentsNet = opponentsNet;
    standingsKnown = standingsBefore;

    if (wolfSideNet === opponentsNet) {
      result.status = "tied";
      continue;
    }
    const wolfSideWon = wolfSideNet < opponentsNet;
    result.status = wolfSideWon ? "won_by_wolf_side" : "won_by_opponents";
    const winners = wolfSideWon ? wolfSide : opponents;
    let each: number;
    if (choice === "lone") each = wolfSideWon ? WOLF_POINTS.loneWin : WOLF_POINTS.loneLoss;
    else each = wolfSideWon ? WOLF_POINTS.partnerWin : WOLF_POINTS.partnerLoss;
    for (const id of winners) {
      result.points[id] = each;
      total[id] = total[id]! + each;
    }
  }

  const allPoints = teeOrder.reduce((sum, id) => sum + total[id]!, 0);
  const deltas: Deltas = Object.fromEntries(
    teeOrder.map((id) => {
      const cents = pointCents * (WOLF_PLAYERS * total[id]! - allPoints);
      return [id, cents === 0 ? 0 : cents]; // never -0
    }),
  );
  return { teeOrder: [...teeOrder], holes: results, points: total, deltas, complete: standingsKnown };
}
