import type { HoleInfo, UserId } from "../shared/types.js";

export interface TeeRating {
  slope: number;
  courseRating: number;
  par: number;
}

/**
 * WHS course handicap for a tee: round(index * slope / 113 + (rating - par)).
 */
export function courseHandicap(handicapIndex: number, tee: TeeRating): number {
  return Math.round(handicapIndex * (tee.slope / 113) + (tee.courseRating - tee.par));
}

/** Ticks received on each hole, keyed by hole number. */
export type TicksByHole = Record<number, number>;

/**
 * Allocates handicap strokes ("ticks") relative to the lowest handicap in the
 * group. Each player's ticks go to the played holes in stroke-index order
 * (hardest first), wrapping around when a player has more ticks than holes.
 */
export function allocateTicks(
  players: { userId: UserId; courseHandicap: number }[],
  holes: HoleInfo[],
): Record<UserId, TicksByHole> {
  if (holes.length === 0) throw new Error("no holes to allocate ticks over");
  const strokeIndexes = new Set(holes.map((h) => h.strokeIndex));
  if (strokeIndexes.size !== holes.length) throw new Error("stroke indexes must be unique");

  const ranked = [...holes].sort((a, b) => a.strokeIndex - b.strokeIndex);
  const scratch = Math.min(...players.map((p) => p.courseHandicap));

  const result: Record<UserId, TicksByHole> = {};
  for (const player of players) {
    const ticks = player.courseHandicap - scratch;
    const perHole = Math.floor(ticks / ranked.length);
    const extra = ticks % ranked.length;
    const byHole: TicksByHole = {};
    ranked.forEach((h, rank) => {
      byHole[h.hole] = perHole + (rank < extra ? 1 : 0);
    });
    result[player.userId] = byHole;
  }
  return result;
}

export function netScore(gross: number, ticks: number): number {
  return gross - ticks;
}
