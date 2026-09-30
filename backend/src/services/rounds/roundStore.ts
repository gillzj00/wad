import {
  DeleteCommand,
  type DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  QueryCommand,
  TransactWriteCommand,
  UpdateCommand,
} from "@aws-sdk/lib-dynamodb";
import type { RoundStatus } from "../../shared/rounds.js";
import type { Cents, Course, GamesConfig, HoleEvents, HoleInfo, Score, UserId, WolfEvent } from "../../shared/types.js";

/** The tee as it was when the round was created, so later course edits do not change a round. */
export interface TeeSnapshot {
  teeId: string;
  name: string;
  courseRating: number | null;
  slope: number | null;
  par: number;
  holes: HoleInfo[];
}

export interface RoundMeta {
  roundId: string;
  courseId: string;
  courseName: string;
  tee: TeeSnapshot;
  date: string;
  holeCount: 18;
  status: RoundStatus;
  joinCode: string;
  createdBy: UserId;
  createdAt: string;
  games: GamesConfig;
  playerCount: number;
  /** The tee order as it was last set; absent until then. See `effectiveTeeOrder`. */
  teeOrder?: UserId[];
}

export interface PlayerRecord {
  userId: UserId;
  displayName: string;
  handicapIndex: number;
  /** Computed from the handicap index and the tee; null on a tee with no rating and slope. */
  courseHandicap: number | null;
  /** The group's per-round override; null when there is none. */
  courseHandicapOverride: number | null;
  guest: boolean;
  joinedAt: string;
}

export interface RoundRecord {
  meta: RoundMeta;
  players: PlayerRecord[];
  scores: Score[];
  holes: HoleEvents[];
}

export interface UserProfile {
  displayName: string | null;
  handicapIndex: number | null;
}

/**
 * A record that a transfer was paid. It carries the whole transfer, so it can
 * only ever be matched to a transfer with the same payer, payee and amount.
 */
export interface PaidMarker {
  transferId: string;
  from: UserId;
  to: UserId;
  amountCents: Cents;
  paidAt: string;
  paidBy: UserId;
}

export type MarkPaidResult = "marked" | "already_marked";
export type CreateRoundResult = "created" | "join_code_taken";
export type AddPlayerResult = "added" | "already_member" | "round_full";
export type SetOverrideResult = "updated" | "player_not_found";

/** The handicap the games use: the override when there is one, else the computed course handicap. */
export function effectiveCourseHandicap(player: Pick<PlayerRecord, "courseHandicap" | "courseHandicapOverride">): number | null {
  return player.courseHandicapOverride ?? player.courseHandicap;
}

/**
 * The order the players tee off in: the order that was set, then anyone who
 * joined after it was set, in the order they joined. With no order set that
 * is the order the players were added.
 */
export function effectiveTeeOrder(record: Pick<RoundRecord, "players"> & { meta: Pick<RoundMeta, "teeOrder"> }): UserId[] {
  const ids = record.players.map((p) => p.userId);
  const set = (record.meta.teeOrder ?? []).filter((id, i, all) => ids.includes(id) && all.indexOf(id) === i);
  return [...set, ...ids.filter((id) => !set.includes(id))];
}

export interface RoundStore {
  getCourse(courseId: string): Promise<Course | null>;
  getProfile(userId: UserId): Promise<UserProfile | null>;
  /** Writes the join code, the round and its creator together, or nothing if the code is in use. */
  createRound(meta: RoundMeta, creator: PlayerRecord, joinCodeTtl: number): Promise<CreateRoundResult>;
  resolveJoinCode(code: string): Promise<string | null>;
  getRound(roundId: string): Promise<RoundRecord | null>;
  /** Adds the player only while the round has fewer than `maxPlayers`. */
  addPlayer(round: RoundRef, player: PlayerRecord, maxPlayers: number): Promise<AddPlayerResult>;
  /** Replaces one player's score on one hole. Last writer wins. */
  putScore(roundId: string, score: Score, change: Change): Promise<void>;
  /** Removes one player's score on one hole; a no-op when there is none. */
  deleteScore(roundId: string, hole: number, userId: UserId): Promise<void>;
  /** Sets only the given fields of the hole's events, leaving the other as it is. Last writer wins per field. */
  setHoleEvents(roundId: string, hole: number, fields: HoleEventFields, change: Change): Promise<void>;
  /** Sets or clears (null) the player's override, leaving the computed course handicap as it is. Last writer wins. */
  setCourseHandicapOverride(roundId: string, userId: UserId, override: number | null, change: Change): Promise<SetOverrideResult>;
  /** Replaces the round's tee order. Last writer wins. */
  setTeeOrder(roundId: string, teeOrder: UserId[], change: Change): Promise<void>;
  /** Null for a user without a profile or without a Venmo handle. */
  getVenmoHandle(userId: UserId): Promise<string | null>;
  listPaidMarkers(roundId: string): Promise<PaidMarker[]>;
  /** Writes the marker only if the transfer has none; the first marker is kept. */
  markTransferPaid(roundId: string, marker: PaidMarker): Promise<MarkPaidResult>;
  /** Removes the marker; a no-op when there is none. */
  unmarkTransferPaid(roundId: string, transferId: string): Promise<void>;
}

/** Who made a write and when. */
export interface Change {
  by: UserId;
  at: string;
}

/** A null `wolf` clears what was recorded for Wolf on the hole. */
export type HoleEventFields = Partial<Pick<HoleEvents, "wadMakers" | "greenieWinner">> & { wolf?: WolfEvent | null };

export type RoundRef = Pick<RoundMeta, "roundId" | "createdAt">;

type Item = Record<string, unknown>;

const NOT_EXISTS = "attribute_not_exists(PK)";
const EXISTS = "attribute_exists(PK)";
const PAID_PREFIX = "SETTLEMENT#PAID#";

/** Which items of a cancelled transaction failed their condition; null for any other error. */
function failedConditions(err: unknown): boolean[] | null {
  if (!(err instanceof Error) || err.name !== "TransactionCanceledException") return null;
  const reasons = (err as { CancellationReasons?: { Code?: string }[] }).CancellationReasons;
  if (!reasons) return null;
  const failed = reasons.map((r) => r.Code === "ConditionalCheckFailed");
  // A cancellation for any other reason (throttling, conflict) is not a condition result.
  const others = reasons.some((r) => r.Code !== undefined && r.Code !== "None" && r.Code !== "ConditionalCheckFailed");
  return others || !failed.includes(true) ? null : failed;
}

/** Single-table storage; see docs/data-model.md for the item layout. */
export class DynamoRoundStore implements RoundStore {
  constructor(
    private readonly db: DynamoDBDocumentClient,
    private readonly tableName: string,
    private readonly now: () => Date = () => new Date(),
  ) {}

  async getCourse(courseId: string): Promise<Course | null> {
    const item = await this.get(`COURSE#${courseId}`, "PROFILE");
    return (item?.course as Course | undefined) ?? null;
  }

  async getProfile(userId: UserId): Promise<UserProfile | null> {
    const item = await this.get(`USER#${userId}`, "PROFILE");
    if (!item) return null;
    return {
      displayName: typeof item.displayName === "string" ? item.displayName : null,
      handicapIndex: typeof item.handicapIndex === "number" ? item.handicapIndex : null,
    };
  }

  async createRound(meta: RoundMeta, creator: PlayerRecord, joinCodeTtl: number): Promise<CreateRoundResult> {
    try {
      await this.db.send(
        new TransactWriteCommand({
          TransactItems: [
            {
              Put: {
                TableName: this.tableName,
                Item: { PK: `JOINCODE#${meta.joinCode}`, SK: "ROUND", type: "joinCode", roundId: meta.roundId, ttl: joinCodeTtl },
                ConditionExpression: NOT_EXISTS,
              },
            },
            {
              Put: {
                TableName: this.tableName,
                Item: { PK: `ROUND#${meta.roundId}`, SK: "META", type: "round", ...this.historyKeys(meta, meta.createdBy), ...meta },
                ConditionExpression: NOT_EXISTS,
              },
            },
            { Put: { TableName: this.tableName, Item: this.playerItem(meta, creator), ConditionExpression: NOT_EXISTS } },
          ],
        }),
      );
      return "created";
    } catch (err) {
      const failed = failedConditions(err);
      if (failed?.[0] && !failed[1] && !failed[2]) return "join_code_taken";
      throw err;
    }
  }

  async resolveJoinCode(code: string): Promise<string | null> {
    const item = await this.get(`JOINCODE#${code}`, "ROUND");
    // DynamoDB deletes expired items lazily, so check the TTL on read as well.
    if (!item || (item.ttl as number) <= Math.floor(this.now().getTime() / 1000)) return null;
    return item.roundId as string;
  }

  async getRound(roundId: string): Promise<RoundRecord | null> {
    const items: Item[] = [];
    let startKey: Item | undefined;
    do {
      const res = await this.db.send(
        new QueryCommand({
          TableName: this.tableName,
          KeyConditionExpression: "PK = :pk",
          ExpressionAttributeValues: { ":pk": `ROUND#${roundId}` },
          ConsistentRead: true,
          ...(startKey ? { ExclusiveStartKey: startKey } : {}),
        }),
      );
      items.push(...((res.Items ?? []) as Item[]));
      startKey = res.LastEvaluatedKey;
    } while (startKey);

    const metaItem = items.find((i) => i.SK === "META");
    if (!metaItem) return null;
    const kind = (prefix: string) => items.filter((i) => (i.SK as string).startsWith(prefix));
    return {
      meta: toMeta(metaItem),
      players: kind("PLAYER#")
        .map(toPlayer)
        .sort((a, b) => a.joinedAt.localeCompare(b.joinedAt)),
      scores: kind("SCORE#").map((i) => ({ userId: i.userId as string, hole: i.hole as number, gross: i.gross as number })),
      holes: kind("HOLE#").map(toHoleEvents),
    };
  }

  async addPlayer(round: RoundRef, player: PlayerRecord, maxPlayers: number): Promise<AddPlayerResult> {
    try {
      await this.db.send(
        new TransactWriteCommand({
          TransactItems: [
            {
              Update: {
                TableName: this.tableName,
                Key: { PK: `ROUND#${round.roundId}`, SK: "META" },
                UpdateExpression: "SET playerCount = playerCount + :one",
                ConditionExpression: "attribute_exists(PK) AND playerCount < :max",
                ExpressionAttributeValues: { ":one": 1, ":max": maxPlayers },
              },
            },
            { Put: { TableName: this.tableName, Item: this.playerItem(round, player), ConditionExpression: NOT_EXISTS } },
          ],
        }),
      );
      return "added";
    } catch (err) {
      const failed = failedConditions(err);
      if (failed?.[1]) return "already_member";
      if (failed?.[0]) return "round_full";
      throw err;
    }
  }

  async putScore(roundId: string, score: Score, change: Change): Promise<void> {
    await this.db.send(
      new PutCommand({
        TableName: this.tableName,
        Item: {
          PK: `ROUND#${roundId}`,
          SK: scoreSortKey(score.hole, score.userId),
          type: "score",
          userId: score.userId,
          hole: score.hole,
          gross: score.gross,
          updatedAt: change.at,
          updatedBy: change.by,
        },
      }),
    );
  }

  async deleteScore(roundId: string, hole: number, userId: UserId): Promise<void> {
    await this.db.send(new DeleteCommand({ TableName: this.tableName, Key: { PK: `ROUND#${roundId}`, SK: scoreSortKey(hole, userId) } }));
  }

  async setHoleEvents(roundId: string, hole: number, fields: HoleEventFields, change: Change): Promise<void> {
    const values: Item = { type: "holeEvents", hole, updatedAt: change.at, updatedBy: change.by };
    if (fields.wadMakers !== undefined) values.wadMakers = fields.wadMakers;
    if (fields.greenieWinner !== undefined) values.greenieWinner = fields.greenieWinner;
    if (fields.wolf !== undefined) values.wolf = fields.wolf;
    const names = Object.keys(values);
    // An update, not a put: a device setting the greenie must not erase the wad makers another device just set.
    await this.db.send(
      new UpdateCommand({
        TableName: this.tableName,
        Key: { PK: `ROUND#${roundId}`, SK: `HOLE#${twoDigits(hole)}` },
        UpdateExpression: `SET ${names.map((_, i) => `#f${i} = :v${i}`).join(", ")}`,
        ExpressionAttributeNames: Object.fromEntries(names.map((name, i) => [`#f${i}`, name])),
        ExpressionAttributeValues: Object.fromEntries(names.map((name, i) => [`:v${i}`, values[name]])),
      }),
    );
  }

  async setCourseHandicapOverride(roundId: string, userId: UserId, override: number | null, change: Change): Promise<SetOverrideResult> {
    try {
      await this.db.send(
        new UpdateCommand({
          TableName: this.tableName,
          Key: { PK: `ROUND#${roundId}`, SK: `PLAYER#${userId}` },
          UpdateExpression: "SET #override = :override, #at = :at, #by = :by",
          // An update creates a missing item, so without this a write for an unknown player would add a broken one.
          ConditionExpression: EXISTS,
          ExpressionAttributeNames: { "#override": "courseHandicapOverride", "#at": "courseHandicapOverrideAt", "#by": "courseHandicapOverrideBy" },
          ExpressionAttributeValues: { ":override": override, ":at": change.at, ":by": change.by },
        }),
      );
      return "updated";
    } catch (err) {
      if (err instanceof Error && err.name === "ConditionalCheckFailedException") return "player_not_found";
      throw err;
    }
  }

  async setTeeOrder(roundId: string, teeOrder: UserId[], change: Change): Promise<void> {
    await this.db.send(
      new UpdateCommand({
        TableName: this.tableName,
        Key: { PK: `ROUND#${roundId}`, SK: "META" },
        UpdateExpression: "SET #order = :order, #at = :at, #by = :by",
        // An update creates a missing item, so without this a write for an unknown round would add a broken one.
        ConditionExpression: EXISTS,
        ExpressionAttributeNames: { "#order": "teeOrder", "#at": "teeOrderAt", "#by": "teeOrderBy" },
        ExpressionAttributeValues: { ":order": teeOrder, ":at": change.at, ":by": change.by },
      }),
    );
  }

  async getVenmoHandle(userId: UserId): Promise<string | null> {
    const item = await this.get(`USER#${userId}`, "PROFILE");
    const handle = typeof item?.venmoHandle === "string" ? item.venmoHandle.trim() : "";
    return handle === "" ? null : handle;
  }

  async listPaidMarkers(roundId: string): Promise<PaidMarker[]> {
    const items: Item[] = [];
    let startKey: Item | undefined;
    do {
      const res = await this.db.send(
        new QueryCommand({
          TableName: this.tableName,
          KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
          ExpressionAttributeValues: { ":pk": `ROUND#${roundId}`, ":sk": PAID_PREFIX },
          ConsistentRead: true,
          ...(startKey ? { ExclusiveStartKey: startKey } : {}),
        }),
      );
      items.push(...((res.Items ?? []) as Item[]));
      startKey = res.LastEvaluatedKey;
    } while (startKey);
    return items.map((i) => ({
      transferId: i.transferId as string,
      from: i.from as string,
      to: i.to as string,
      amountCents: i.amountCents as number,
      paidAt: i.paidAt as string,
      paidBy: i.paidBy as string,
    }));
  }

  async markTransferPaid(roundId: string, marker: PaidMarker): Promise<MarkPaidResult> {
    try {
      await this.db.send(
        new PutCommand({
          TableName: this.tableName,
          Item: { PK: `ROUND#${roundId}`, SK: `${PAID_PREFIX}${marker.transferId}`, type: "transferPaid", ...marker },
          ConditionExpression: NOT_EXISTS,
        }),
      );
      return "marked";
    } catch (err) {
      if (err instanceof Error && err.name === "ConditionalCheckFailedException") return "already_marked";
      throw err;
    }
  }

  async unmarkTransferPaid(roundId: string, transferId: string): Promise<void> {
    await this.db.send(new DeleteCommand({ TableName: this.tableName, Key: { PK: `ROUND#${roundId}`, SK: `${PAID_PREFIX}${transferId}` } }));
  }

  private async get(pk: string, sk: string): Promise<Item | undefined> {
    const res = await this.db.send(new GetCommand({ TableName: this.tableName, Key: { PK: pk, SK: sk }, ConsistentRead: true }));
    return res.Item;
  }

  /** GSI1 keys for a user's round history (docs/data-model.md). */
  private historyKeys(meta: RoundRef, userId: UserId): Item {
    const startEpoch = Math.floor(new Date(meta.createdAt).getTime() / 1000);
    return { GSI1PK: `USER#${userId}`, GSI1SK: `ROUND#${startEpoch}#${meta.roundId}` };
  }

  private playerItem(meta: RoundRef, player: PlayerRecord): Item {
    return {
      PK: `ROUND#${meta.roundId}`,
      SK: `PLAYER#${player.userId}`,
      type: "roundPlayer",
      // Guests have no account, so they have no history to index.
      ...(player.guest ? {} : this.historyKeys(meta, player.userId)),
      ...player,
    };
  }
}

const twoDigits = (hole: number) => String(hole).padStart(2, "0");

const scoreSortKey = (hole: number, userId: UserId) => `SCORE#${twoDigits(hole)}#${userId}`;

function toHoleEvents(item: Item): HoleEvents {
  const wolf = item.wolf as WolfEvent | null | undefined;
  return {
    hole: item.hole as number,
    wadMakers: (item.wadMakers as string[] | undefined) ?? [],
    greenieWinner: (item.greenieWinner as string | null | undefined) ?? null,
    ...(wolf ? { wolf } : {}),
  };
}

function toMeta(item: Item): RoundMeta {
  return {
    roundId: item.roundId as string,
    courseId: item.courseId as string,
    courseName: item.courseName as string,
    tee: item.tee as TeeSnapshot,
    date: item.date as string,
    holeCount: 18,
    status: item.status as RoundStatus,
    joinCode: item.joinCode as string,
    createdBy: item.createdBy as string,
    createdAt: item.createdAt as string,
    games: item.games as GamesConfig,
    playerCount: item.playerCount as number,
    ...(Array.isArray(item.teeOrder) ? { teeOrder: item.teeOrder as UserId[] } : {}),
  };
}

function toPlayer(item: Item): PlayerRecord {
  return {
    userId: item.userId as string,
    displayName: item.displayName as string,
    handicapIndex: item.handicapIndex as number,
    courseHandicap: (item.courseHandicap as number | null | undefined) ?? null,
    courseHandicapOverride: (item.courseHandicapOverride as number | null | undefined) ?? null,
    guest: item.guest === true,
    joinedAt: item.joinedAt as string,
  };
}
