import { randomUUID } from "node:crypto";
import { scoreGreenies } from "../../engines/greenies.js";
import { allocateTicks, courseHandicap } from "../../engines/handicap.js";
import type { Round, RoundPlayer, RoundState } from "../../shared/rounds.js";
import type { HoleInfo, Tee, UserId } from "../../shared/types.js";
import { RoundError } from "./errors.js";
import { computeState } from "./gameState.js";
import { generateJoinCode, normalizeJoinCode } from "./joinCode.js";
import type { PlayerRecord, RoundRecord, RoundStore, TeeSnapshot } from "./roundStore.js";
import { isHandicapIndex, parseCreateRound, parseGuest, parseHoleEvents, parseHoleParam, parseJoinCode, parseScore } from "./validation.js";

export const MAX_PLAYERS = 4;
export const HOLE_COUNT = 18;
export const JOIN_CODE_ATTEMPTS = 5;
/** A join code works for two days after the round is created. */
export const JOIN_CODE_TTL_SECONDS = 48 * 60 * 60;

export interface RoundServiceDeps {
  now?: () => Date;
  newId?: () => string;
  newJoinCode?: () => string;
}

export class RoundService {
  private readonly now: () => Date;
  private readonly newId: () => string;
  private readonly newJoinCode: () => string;

  constructor(
    private readonly store: RoundStore,
    deps: RoundServiceDeps = {},
  ) {
    this.now = deps.now ?? (() => new Date());
    this.newId = deps.newId ?? randomUUID;
    this.newJoinCode = deps.newJoinCode ?? (() => generateJoinCode());
  }

  async createRound(userId: UserId, body: unknown): Promise<Round> {
    const input = parseCreateRound(body);
    const course = await this.store.getCourse(input.courseId);
    if (!course) throw new RoundError("not_found", "course_not_found", "no course with that id");
    const tee = course.tees.find((t) => t.teeId === input.teeId);
    if (!tee) throw new RoundError("not_found", "tee_not_found", "the course has no tee with that id");
    const snapshot = snapshotTee(tee);

    const now = this.now();
    const creator = await this.memberRecord(userId, snapshot, now);
    const meta = {
      roundId: `r_${this.newId()}`,
      courseId: course.courseId,
      courseName: course.courseName || course.clubName,
      tee: snapshot,
      date: input.date,
      holeCount: 18 as const,
      status: "in_progress" as const,
      createdBy: userId,
      createdAt: now.toISOString(),
      games: input.games,
      playerCount: 1,
    };
    const ttl = Math.floor(now.getTime() / 1000) + JOIN_CODE_TTL_SECONDS;

    for (let attempt = 0; attempt < JOIN_CODE_ATTEMPTS; attempt++) {
      const record = { ...meta, joinCode: this.newJoinCode() };
      if ((await this.store.createRound(record, creator, ttl)) === "created") {
        return toRound({ meta: record, players: [creator], scores: [], holes: [] });
      }
    }
    throw new Error(`no free join code after ${JOIN_CODE_ATTEMPTS} attempts`);
  }

  async getRound(userId: UserId, roundId: string): Promise<Round> {
    return toRound(await this.roundForMember(userId, roundId));
  }

  /** Idempotent: a player already in the round gets the round back unchanged. */
  async joinRound(userId: UserId, body: unknown): Promise<Round> {
    const code = normalizeJoinCode(parseJoinCode(body));
    const roundId = code ? await this.store.resolveJoinCode(code) : null;
    const record = roundId ? await this.store.getRound(roundId) : null;
    if (!record) throw new RoundError("not_found", "join_code_not_found", "no round with that join code");
    if (record.players.some((p) => p.userId === userId)) return toRound(record);

    const player = await this.memberRecord(userId, record.meta.tee, this.now());
    const result = await this.store.addPlayer(record.meta, player, MAX_PLAYERS);
    if (result === "round_full") throw roundFull();
    return toRound(await this.reload(record.meta.roundId));
  }

  async addGuest(userId: UserId, roundId: string, body: unknown): Promise<{ round: Round; player: RoundPlayer }> {
    const input = parseGuest(body);
    const record = await this.roundForMember(userId, roundId);
    const guest: PlayerRecord = {
      userId: `guest_${this.newId()}`,
      displayName: input.displayName,
      handicapIndex: input.handicapIndex,
      courseHandicap: handicapFor(input.handicapIndex, record.meta.tee),
      guest: true,
      joinedAt: this.now().toISOString(),
    };
    const result = await this.store.addPlayer(record.meta, guest, MAX_PLAYERS);
    if (result !== "added") throw roundFull();
    const round = toRound(await this.reload(roundId));
    const player = round.players.find((p) => p.userId === guest.userId);
    if (!player) throw new Error(`guest ${guest.userId} missing from round ${roundId} after being added`);
    return { round, player };
  }

  /**
   * Sets or clears one player's gross score on a hole. A player writes their
   * own scores; anyone in the round writes a guest's.
   */
  async putScore(userId: UserId, roundId: string, body: unknown): Promise<Round> {
    const input = parseScore(body);
    const record = await this.roundForMember(userId, roundId);
    const target = playerIn(record, input.userId ?? userId);
    if (target.userId !== userId && !target.guest) {
      throw new RoundError("forbidden", "not_score_owner", "only the player can set their own score");
    }
    if (input.gross === null) await this.store.deleteScore(roundId, input.hole, target.userId);
    else {
      const score = { userId: target.userId, hole: input.hole, gross: input.gross };
      await this.store.putScore(roundId, score, { by: userId, at: this.now().toISOString() });
    }
    return toRound(await this.reload(roundId));
  }

  /** Sets the hole's wad makers, its greenie winner or both. Anyone in the round may. */
  async putHoleEvents(userId: UserId, roundId: string, holeParam: string | undefined, body: unknown): Promise<Round> {
    const hole = parseHoleParam(holeParam);
    const input = parseHoleEvents(body);
    const record = await this.roundForMember(userId, roundId);
    for (const maker of input.wadMakers ?? []) playerIn(record, maker);
    if (typeof input.greenieWinner === "string") checkGreenieWinner(record, hole, input.greenieWinner);
    await this.store.setHoleEvents(roundId, hole, input, { by: userId, at: this.now().toISOString() });
    return toRound(await this.reload(roundId));
  }

  /** State is never stored, so this is the same computation as reading the round. */
  async recompute(userId: UserId, roundId: string): Promise<RoundState> {
    return computeState(await this.roundForMember(userId, roundId));
  }

  private roundForMember(userId: UserId, roundId: string): Promise<RoundRecord> {
    return loadRoundForMember(this.store, userId, roundId);
  }

  private async reload(roundId: string): Promise<RoundRecord> {
    const record = await this.store.getRound(roundId);
    if (!record) throw new Error(`round ${roundId} disappeared`);
    return record;
  }

  /** The caller as a round player, from their profile. */
  private async memberRecord(userId: UserId, tee: TeeSnapshot, now: Date): Promise<PlayerRecord> {
    const profile = await this.store.getProfile(userId);
    const displayName = profile?.displayName?.trim();
    const handicapIndex = profile?.handicapIndex;
    if (!displayName || !isHandicapIndex(handicapIndex)) {
      throw new RoundError("conflict", "profile_incomplete", "set your display name and handicap index before playing a round");
    }
    return {
      userId,
      displayName,
      handicapIndex,
      courseHandicap: handicapFor(handicapIndex, tee),
      guest: false,
      joinedAt: now.toISOString(),
    };
  }
}

/** The round, for one of its players only. */
export async function loadRoundForMember(store: RoundStore, userId: UserId, roundId: string): Promise<RoundRecord> {
  const record = roundId ? await store.getRound(roundId) : null;
  if (!record) throw new RoundError("not_found", "round_not_found", "no round with that id");
  if (!record.players.some((p) => p.userId === userId)) {
    throw new RoundError("forbidden", "not_a_participant", "you are not a player in this round");
  }
  return record;
}

function playerIn(record: RoundRecord, userId: UserId): PlayerRecord {
  const player = record.players.find((p) => p.userId === userId);
  if (!player) throw new RoundError("validation", "unknown_player", `${userId} is not a player in this round`);
  return player;
}

/**
 * Checks what can be checked when the winner is recorded. A winner whose score
 * is not in yet is accepted, since scores and hole events arrive in any order;
 * the greenies engine decides whether the greenie is paid.
 */
function checkGreenieWinner(record: RoundRecord, hole: number, winner: UserId): void {
  playerIn(record, winner);
  const par = record.meta.tee.holes.find((h) => h.hole === hole)?.par;
  if (par !== 3) throw new RoundError("validation", "not_a_par_three", `hole ${hole} is not a par 3, so it has no greenie`);
  const result = scoreGreenies({
    players: record.players.map((p) => p.userId),
    holes: record.meta.tee.holes,
    scores: record.scores,
    holeEvents: [{ hole, wadMakers: [], greenieWinner: winner }],
    amountCents: 0,
  }).holes.find((h) => h.hole === hole);
  if (result?.status === "invalid") {
    throw new RoundError("validation", "greenie_winner_over_par", "the greenie winner must score par or better on the hole");
  }
}

function roundFull(): RoundError {
  return new RoundError("conflict", "round_full", `a round has at most ${MAX_PLAYERS} players`);
}

function snapshotTee(tee: Tee): TeeSnapshot {
  const holes: HoleInfo[] = [];
  for (const h of tee.holes) if (h.strokeIndex !== null) holes.push({ hole: h.hole, par: h.par, strokeIndex: h.strokeIndex });
  if (!tee.strokeIndexValid || tee.holes.length !== HOLE_COUNT || holes.length !== HOLE_COUNT) {
    throw new RoundError("validation", "tee_not_usable", `the tee needs ${HOLE_COUNT} holes, each with a unique stroke index`);
  }
  return { teeId: tee.teeId, name: tee.name, courseRating: tee.courseRating, slope: tee.slope, par: tee.par, holes };
}

function handicapFor(handicapIndex: number, tee: TeeSnapshot): number | null {
  if (tee.courseRating === null || tee.slope === null) return null;
  const value = courseHandicap(handicapIndex, { slope: tee.slope, courseRating: tee.courseRating, par: tee.par });
  return value === 0 ? 0 : value; // never -0
}

/** Only the holes where the player gets ticks, as in docs/api.md. */
function ticksFor(record: RoundRecord): Record<UserId, Record<number, number>> | null {
  const players: { userId: UserId; courseHandicap: number }[] = [];
  for (const p of record.players) {
    if (p.courseHandicap === null) return null;
    players.push({ userId: p.userId, courseHandicap: p.courseHandicap });
  }
  if (players.length === 0) return null;
  const all = allocateTicks(players, record.meta.tee.holes);
  const result: Record<UserId, Record<number, number>> = {};
  for (const [userId, byHole] of Object.entries(all)) {
    result[userId] = Object.fromEntries(Object.entries(byHole).filter(([, ticks]) => ticks > 0));
  }
  return result;
}

function toRound(record: RoundRecord): Round {
  const { meta } = record;
  const ticks = ticksFor(record);
  return {
    roundId: meta.roundId,
    course: { courseId: meta.courseId, name: meta.courseName, teeId: meta.tee.teeId, tee: meta.tee.name },
    date: meta.date,
    holeCount: meta.holeCount,
    status: meta.status,
    joinCode: meta.joinCode,
    createdBy: meta.createdBy,
    createdAt: meta.createdAt,
    games: meta.games,
    players: record.players.map((p) => ({ ...p, ticksByHole: ticks?.[p.userId] ?? null })),
    scores: record.scores,
    holes: record.holes,
    state: computeState(record),
  };
}
