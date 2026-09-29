import { scoreGreenies } from "../../engines/greenies.js";
import { scoreSkins } from "../../engines/skins.js";
import { scoreWad } from "../../engines/wad.js";
import type { RoundState } from "../../shared/rounds.js";
import type { Player } from "../../shared/types.js";
import type { RoundRecord } from "./roundStore.js";

/** Skins needs every player's course handicap; null while one is missing. */
function skinsPlayers(record: RoundRecord): Player[] | null {
  const players: Player[] = [];
  for (const p of record.players) {
    if (p.courseHandicap === null) return null;
    players.push({ userId: p.userId, displayName: p.displayName, courseHandicap: p.courseHandicap });
  }
  return players;
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
    const withHandicaps = skinsPlayers(record);
    state.skins = withHandicaps ? scoreSkins({ players: withHandicaps, holes: tee.holes, scores, baseCents: games.skins.baseCents }) : null;
  }
  if (games.wad) {
    state.wad = scoreWad({ players, holes: tee.holes, scores, holeEvents, startCents: games.wad.startCents, stepCents: games.wad.stepCents });
  }
  if (games.greenies) {
    state.greenies = scoreGreenies({ players, holes: tee.holes, scores, holeEvents, amountCents: games.greenies.amountCents });
  }
  return state;
}
