import { type DynamoDBDocumentClient, GetCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import type { UserId } from "../../shared/types.js";
import type { ProfileUpdate } from "./validation.js";

/** The stored fields of a profile; a field never set, or cleared, is null. */
export interface StoredProfile {
  displayName: string | null;
  handicapIndex: number | null;
  venmoHandle: string | null;
}

export interface ProfileStore {
  /** Null for a user who has never saved a profile. */
  get(userId: UserId): Promise<StoredProfile | null>;
  /** Sets only the given fields, leaving the others as they are, and returns the profile after the write. */
  update(userId: UserId, fields: ProfileUpdate, at: string): Promise<StoredProfile>;
}

type Item = Record<string, unknown>;

function toProfile(item: Item): StoredProfile {
  return {
    displayName: typeof item.displayName === "string" ? item.displayName : null,
    handicapIndex: typeof item.handicapIndex === "number" ? item.handicapIndex : null,
    venmoHandle: typeof item.venmoHandle === "string" ? item.venmoHandle : null,
  };
}

/** The user profile item of the single table; see docs/data-model.md. */
export class DynamoProfileStore implements ProfileStore {
  constructor(
    private readonly db: DynamoDBDocumentClient,
    private readonly tableName: string,
  ) {}

  async get(userId: UserId): Promise<StoredProfile | null> {
    const res = await this.db.send(new GetCommand({ TableName: this.tableName, Key: this.key(userId), ConsistentRead: true }));
    return res.Item ? toProfile(res.Item) : null;
  }

  async update(userId: UserId, fields: ProfileUpdate, at: string): Promise<StoredProfile> {
    const values: Item = { type: "user", userId, updatedAt: at };
    if (fields.displayName !== undefined) values.displayName = fields.displayName;
    if (fields.handicapIndex !== undefined) values.handicapIndex = fields.handicapIndex;
    if (fields.venmoHandle !== undefined) values.venmoHandle = fields.venmoHandle;
    const names = Object.keys(values);
    // An update, not a put: a device setting the Venmo handle must not erase the handicap another device just set.
    const res = await this.db.send(
      new UpdateCommand({
        TableName: this.tableName,
        Key: this.key(userId),
        UpdateExpression: `SET ${names.map((_, i) => `#f${i} = :v${i}`).join(", ")}`,
        ExpressionAttributeNames: Object.fromEntries(names.map((name, i) => [`#f${i}`, name])),
        ExpressionAttributeValues: Object.fromEntries(names.map((name, i) => [`:v${i}`, values[name]])),
        ReturnValues: "ALL_NEW",
      }),
    );
    return toProfile(res.Attributes ?? {});
  }

  private key(userId: UserId): Item {
    return { PK: `USER#${userId}`, SK: "PROFILE" };
  }
}
