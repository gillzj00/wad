import { scoreGreenies } from "../../engines/greenies.js";
import { scoreSkins } from "../../engines/skins.js";
import { scoreWad } from "../../engines/wad.js";
import { scoreWolf, type WolfResult } from "../../engines/wolf.js";
import type { RoundState } from "../../shared/rounds.js";
import type { HoleEvents, Player } from "../../shared/types.js";
import { effectiveCourseHandicap, effectiveTeeOrder, type RoundRecord } from "./roundStore.js";

/** Skins and Wolf need every player's course handicap; null while one is missing. */
export function playersWithHandicaps(record: RoundRecord): Player[] | null {
  const players: Player[] = [];
  for (const p of record.players) {
    const courseHandicap = effectiveCourseHandicap(p);
    if (courseHandicap === null) return null;
    players.push({ userId: p.userId, displayName: p.displayName, courseHandicap });
  }
  return players;
}

/**
 * Wolf for the round with the given hole events. Null while a player has no
 * course handicap, and from the engine unless there are exactly four players.
 */
export function wolfState(record: RoundRecord, holeEvents: HoleEvents[]): WolfResult | null {
  const { games, tee } = record.meta;
  const players = playersWithHandicaps(record);
  if (!games.wolf || !players) return null;
  return scoreWolf({
    players,
    teeOrder: effectiveTeeOrder(record),
    holes: tee.holes,
    scores: record.scores,
    holeEvents,
    pointCents: games.wolf.pointCents,
  });
}

/**
 * Runs the engines over the stored scores and hole events. Nothing here knows
 * a game rule: it only hands the round to the engines and returns what they say.
 */
export function computeState(record: RoundRecord): RoundState {
  const { games, tee } = record.meta;
  const { scores, holes: holeEvents } = record;
  const players = record.players.map((p) => p.userId);
  const state: RoundState = {};

  if (games.skins) {
    const withHandicaps = playersWithHandicaps(record);
    // Rounds created before the setting existed have no `carryover`: they carry over.
    state.skins = withHandicaps
      ? scoreSkins({ players: withHandicaps, holes: tee.holes, scores, baseCents: games.skins.baseCents, carryover: games.skins.carryover ?? true })
      : null;
  }
  if (games.wad) {
    state.wad = scoreWad({ players, holes: tee.holes, scores, holeEvents, startCents: games.wad.startCents, stepCents: games.wad.stepCents });
  }
  if (games.greenies) {
    state.greenies = scoreGreenies({ players, holes: tee.holes, scores, holeEvents, amountCents: games.greenies.amountCents });
  }
  if (games.wolf) state.wolf = wolfState(record, holeEvents);
  return state;
}
