// Round types for the round lifecycle routes. They mirror docs/api.md; keep
// the two in sync.
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
  /** Null when the tee has no rating and slope; set it with the per-round override. */
  courseHandicap: number | null;
  /** Holes where the player receives ticks; null until every player has a course handicap. */
  ticksByHole: Record<number, number> | null;
  /** A guest has no account; any participant scores for them. */
  guest: boolean;
  joinedAt: string;
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
}
