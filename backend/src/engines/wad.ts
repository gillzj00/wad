import type { Cents, Deltas, HoleEvents, HoleInfo, Score, UserId } from "../shared/types.js";
import { collectFromEach, zeroDeltas } from "./money.js";

export type WadSegment = "front" | "back";

export interface WadMake {
  hole: number;
  userId: UserId;
  /** Wad value after this make. */
  valueCents: Cents;
}

export interface WadInstanceResult {
  segment: WadSegment;
  holderUserId: UserId | null;
  /** Current value: what the holder has, or what the first make would take. */
  valueCents: Cents;
  makes: WadMake[];
  /** Every player has a score on the segment's last hole; the holder has been paid. */
  complete: boolean;
}

export interface IgnoredMake {
  hole: number;
  userId: UserId;
  reason: "not-a-player" | "duplicate";
}

export interface WadInput {
  players: UserId[];
  /** The holes being played. Holes 1-9 are the front instance, 10-18 the back. */
  holes: HoleInfo[];
  scores: Score[];
  holeEvents: HoleEvents[];
  startCents: Cents;
  stepCents: Cents;
}

export function scoreWad(input: WadInput): { instances: WadInstanceResult[]; deltas: Deltas; ignored: IgnoredMake[] } {
  const { players, holes, scores, holeEvents, startCents, stepCents } = input;
  const deltas = zeroDeltas(players);
  const ignored: IgnoredMake[] = [];
  const makersByHole = new Map(holeEvents.map((e) => [e.hole, e.wadMakers]));
  const scored = new Set(scores.map((s) => `${s.hole}:${s.userId}`));

  const segments: [WadSegment, HoleInfo[]][] = [
    ["front", holes.filter((h) => h.hole <= 9)],
    ["back", holes.filter((h) => h.hole > 9)],
  ];

  const instances: WadInstanceResult[] = [];
  for (const [segment, segHoles] of segments) {
    if (segHoles.length === 0) continue;
    const ordered = [...segHoles].sort((a, b) => a.hole - b.hole);

    let holder: UserId | null = null;
    let value = startCents;
    const makes: WadMake[] = [];
    for (const h of ordered) {
      const seen = new Set<UserId>();
      for (const userId of makersByHole.get(h.hole) ?? []) {
        if (!players.includes(userId)) {
          ignored.push({ hole: h.hole, userId, reason: "not-a-player" });
          continue;
        }
        if (seen.has(userId)) {
          ignored.push({ hole: h.hole, userId, reason: "duplicate" });
          continue;
        }
        seen.add(userId);
        if (holder !== null) value += stepCents;
        holder = userId;
        makes.push({ hole: h.hole, userId, valueCents: value });
      }
    }

    const lastHole = ordered[ordered.length - 1]!.hole;
    const complete = players.every((p) => scored.has(`${lastHole}:${p}`));
    if (complete && holder !== null) collectFromEach(deltas, players, holder, value);
    instances.push({ segment, holderUserId: holder, valueCents: value, makes, complete });
  }

  return { instances, deltas, ignored };
}
