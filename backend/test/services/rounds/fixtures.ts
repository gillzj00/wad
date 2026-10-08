import type { DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";
import type { Course, Tee } from "../../../src/shared/types.js";

export const TABLE = "wad-test";
export const NOW = new Date("2026-09-29T12:00:00Z");

const pars = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 5, 3, 4, 4];
const strokeIndexes = [7, 11, 17, 3, 1, 15, 9, 5, 13, 8, 18, 2, 10, 6, 12, 16, 4, 14];

function tee(teeId: string, name: string, overrides: Partial<Tee> = {}): Tee {
  return {
    teeId,
    name,
    gender: "male",
    courseRating: 72.1,
    slope: 131,
    par: 72,
    totalYards: 6600,
    holes: pars.map((par, i) => ({ hole: i + 1, par, strokeIndex: strokeIndexes[i]!, yardage: 360 + i })),
    strokeIndexValid: true,
    ...overrides,
  };
}

/** A made-up course. */
export const course: Course = {
  courseId: "gca-7k2m9qb4",
  clubName: "Maple Hollow Golf Club",
  courseName: "North",
  location: { address: null, city: "Springfield", state: "IL", country: "United States", latitude: null, longitude: null },
  source: "golfcourseapi",
  scorecardUrl: null,
  fetchedAt: "2026-09-28T00:00:00.000Z",
  tees: [
    tee("male-blue", "Blue"),
    tee("male-unrated", "Unrated", { courseRating: null, slope: null }),
    tee("male-junior", "Junior", {
      strokeIndexValid: false,
      holes: pars.map((par, i) => ({ hole: i + 1, par, strokeIndex: null, yardage: 220 })),
    }),
    tee("male-short", "Short", { holes: pars.slice(0, 9).map((par, i) => ({ hole: i + 1, par, strokeIndex: i + 1, yardage: 300 })) }),
  ],
};

export type Item = Record<string, unknown>;

interface Command {
  constructor: { name: string };
  input: Item;
}

interface TransactItem {
  Put?: { Item: Item; ConditionExpression?: string };
  Update?: { Key: Item; UpdateExpression: string; ConditionExpression: string; ExpressionAttributeValues: Record<string, number> };
  Delete?: { Key: Item; ConditionExpression?: string };
}

export function transactionCancelled(codes: string[]): Error {
  return Object.assign(new Error("Transaction cancelled"), {
    name: "TransactionCanceledException",
    CancellationReasons: codes.map((Code) => ({ Code })),
  });
}

const keyOf = (item: Item) => `${item.PK}|${item.SK}`;

/**
 * Minimal stand-in for the document client: stores items by PK/SK and applies
 * the conditions the round store uses, all or nothing per transaction.
 */
export function fakeDb(seed: Item[] = []) {
  const items = new Map<string, Item>(seed.map((i) => [keyOf(i), i]));
  const sent: { name: string; input: Item }[] = [];
  /** Errors thrown by the next transactions instead of running them. */
  const failures: Error[] = [];

  function transact(actions: TransactItem[]) {
    const codes = actions.map(({ Put, Update, Delete }) => {
      if (Put) {
        if (Put.ConditionExpression === undefined) return "None";
        if (Put.ConditionExpression !== "attribute_not_exists(PK)") throw new Error(`fake db: unsupported condition ${Put.ConditionExpression}`);
        return items.has(keyOf(Put.Item)) ? "ConditionalCheckFailed" : "None";
      }
      if (Delete) {
        if (Delete.ConditionExpression !== undefined) throw new Error("fake db: unsupported delete condition");
        return "None";
      }
      if (!Update) throw new Error("fake db: unsupported transaction item");
      if (
        Update.ConditionExpression !== "attribute_exists(PK) AND playerCount < :max" ||
        Update.UpdateExpression !== "SET playerCount = playerCount + :one"
      ) {
        throw new Error("fake db: unsupported update");
      }
      const existing = items.get(keyOf(Update.Key));
      const max = Update.ExpressionAttributeValues[":max"]!;
      return existing && (existing.playerCount as number) < max ? "None" : "ConditionalCheckFailed";
    });
    if (codes.some((c) => c !== "None")) throw transactionCancelled(codes);
    for (const { Put, Update, Delete } of actions) {
      if (Put) items.set(keyOf(Put.Item), Put.Item);
      if (Delete) items.delete(keyOf(Delete.Key));
      if (Update) {
        const existing = items.get(keyOf(Update.Key))!;
        items.set(keyOf(Update.Key), {
          ...existing,
          playerCount: (existing.playerCount as number) + Update.ExpressionAttributeValues[":one"]!,
        });
      }
    }
  }

  const db = {
    async send(cmd: Command) {
      const name = cmd.constructor.name;
      sent.push({ name, input: cmd.input });
      switch (name) {
        case "GetCommand":
          return { Item: items.get(keyOf(cmd.input.Key as Item)) };
        case "QueryCommand": {
          const values = cmd.input.ExpressionAttributeValues as Item;
          const condition = cmd.input.KeyConditionExpression;
          if (condition !== "PK = :pk" && condition !== "PK = :pk AND begins_with(SK, :sk)") throw new Error(`fake db: unsupported query ${condition}`);
          const prefix = condition === "PK = :pk" ? "" : (values[":sk"] as string);
          const found = [...items.values()].filter((i) => i.PK === values[":pk"] && (i.SK as string).startsWith(prefix));
          return { Items: found.sort((a, b) => (a.SK as string).localeCompare(b.SK as string)) };
        }
        case "PutCommand": {
          const item = cmd.input.Item as Item;
          const condition = cmd.input.ConditionExpression;
          if (condition !== undefined && condition !== "attribute_not_exists(PK)") throw new Error("fake db: unsupported put condition");
          if (condition !== undefined && items.has(keyOf(item))) {
            throw Object.assign(new Error("The conditional request failed"), { name: "ConditionalCheckFailedException" });
          }
          items.set(keyOf(item), item);
          return {};
        }
        case "DeleteCommand": {
          const key = cmd.input.Key as Item;
          const condition = cmd.input.ConditionExpression as string | undefined;
          if (condition !== undefined) {
            // Only "<attribute> = :value" (the attribute may be a #name): the item must exist with that value.
            const match = /^(#?\w+) = (:\w+)$/.exec(condition);
            if (!match) throw new Error(`fake db: unsupported delete condition ${condition}`);
            const names = (cmd.input.ExpressionAttributeNames ?? {}) as Record<string, string>;
            const attribute = match[1]!.startsWith("#") ? names[match[1]!] : match[1]!;
            const existing = items.get(keyOf(key));
            if (!existing || attribute === undefined || existing[attribute] !== (cmd.input.ExpressionAttributeValues as Item)[match[2]!]) {
              throw Object.assign(new Error("The conditional request failed"), { name: "ConditionalCheckFailedException" });
            }
          }
          items.delete(keyOf(key));
          return {};
        }
        case "UpdateCommand": {
          // Only "SET #name = :value, ...": named fields are replaced, the rest are kept.
          // The one condition supported is that the item exists.
          const condition = cmd.input.ConditionExpression;
          if (condition !== undefined && condition !== "attribute_exists(PK)") throw new Error("fake db: unsupported update condition");
          const expression = cmd.input.UpdateExpression as string;
          if (!expression.startsWith("SET ")) throw new Error(`fake db: unsupported update ${expression}`);
          const names = cmd.input.ExpressionAttributeNames as Record<string, string>;
          const values = cmd.input.ExpressionAttributeValues as Item;
          const key = cmd.input.Key as Item;
          if (condition !== undefined && !items.has(keyOf(key))) {
            throw Object.assign(new Error("The conditional request failed"), { name: "ConditionalCheckFailedException" });
          }
          const item: Item = { ...(items.get(keyOf(key)) ?? key) };
          for (const assignment of expression.slice(4).split(", ")) {
            const match = /^(#\w+) = (:\w+)$/.exec(assignment);
            if (!match || !(match[1]! in names) || !(match[2]! in values)) throw new Error(`fake db: unsupported assignment ${assignment}`);
            item[names[match[1]!]!] = values[match[2]!];
          }
          items.set(keyOf(key), item);
          return cmd.input.ReturnValues === "ALL_NEW" ? { Attributes: { ...item } } : {};
        }
        case "TransactWriteCommand": {
          const failure = failures.shift();
          if (failure) throw failure;
          transact(cmd.input.TransactItems as TransactItem[]);
          return {};
        }
        default:
          throw new Error(`fake db: unsupported command ${name}`);
      }
    },
  } as unknown as DynamoDBDocumentClient;

  return { db, items, sent, failures };
}

export const courseItem: Item = { PK: `COURSE#${course.courseId}`, SK: "PROFILE", type: "course", course };

export function profileItem(userId: string, displayName: string, handicapIndex: number): Item {
  return { PK: `USER#${userId}`, SK: "PROFILE", type: "user", userId, displayName, handicapIndex };
}
