// Round types for the round lifecycle routes. They mirror docs/api.md; keep
// the two in sync.
import type { scoreGreenies } from "../engines/greenies.js";
import type { SkinsResult } from "../engines/skins.js";
import type { scoreWad } from "../engines/wad.js";
import type { GamesConfig, HoleEvents, Score, UserId } from "./types.js";

export type RoundStatus = "in_progress";

export interface RoundCourse {
  courseId: string;
  name: string;
  teeId: string;
  /** Tee name, e.g. "Blue". */
  tee: string;
}

export interface RoundPlayer {
  userId: UserId;
  displayName: string;
  handicapIndex: number;
  /**
   * The handicap the games use: the override when there is one, else the value
   * computed from the handicap index and the tee. Null when there is neither,
   * which is a tee with no rating and slope and no override.
   */
  courseHandicap: number | null;
  /** The per-round override; null when the course handicap is the computed one. */
  courseHandicapOverride: number | null;
  /** Holes where the player receives ticks; null until every player has a course handicap. */
  ticksByHole: Record<number, number> | null;
  /** A guest has no account; any participant scores for them. */
  guest: boolean;
  joinedAt: string;
}

/**
 * What the engines return for the round's scores and hole events, unchanged.
 * A game that is not enabled is left out.
 */
export interface RoundState {
  /**
   * Null until every player has a course handicap. When `complete` is true and
   * `carryOutCents` is not zero, that carryover is unresolved and is not paid.
   */
  skins?: SkinsResult | null;
  wad?: ReturnType<typeof scoreWad>;
  greenies?: ReturnType<typeof scoreGreenies>;
}

export interface Round {
  roundId: string;
  course: RoundCourse;
  /** Calendar date of play, YYYY-MM-DD. */
  date: string;
  holeCount: 18;
  status: RoundStatus;
  joinCode: string;
  createdBy: UserId;
  createdAt: string;
  games: GamesConfig;
  players: RoundPlayer[];
  scores: Score[];
  holes: HoleEvents[];
  state: RoundState;
}
