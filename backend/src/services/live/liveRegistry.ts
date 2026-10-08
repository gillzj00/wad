import { DeleteCommand, type DynamoDBDocumentClient, GetCommand, QueryCommand, TransactWriteCommand } from "@aws-sdk/lib-dynamodb";

/** Which live room each WebSocket connection is in; see docs/data-model.md (live room items). */
export interface LiveRegistry {
  /** The room the connection is subscribed to, or null when it is in none. */
  roomOf(connectionId: string): Promise<string | null>;
  /** Puts the connection in the room, taking it out of any other room, until `ttl` (epoch seconds). */
  join(connectionId: string, roundCode: string, ttl: number): Promise<void>;
  /** Takes the connection out of the room; a no-op when it is not in it. */
  remove(roundCode: string, connectionId: string): Promise<void>;
  /** The connections in the room. */
  members(roundCode: string): Promise<string[]>;
}

type Item = Record<string, unknown>;

const roomKey = (roundCode: string) => `LIVE#${roundCode}`;
const connectionKey = (connectionId: string) => `CONN#${connectionId}`;

/** Single-table storage: a member item per connection under the room, and a reverse item per connection. */
export class DynamoLiveRegistry implements LiveRegistry {
  constructor(
    private readonly db: DynamoDBDocumentClient,
    private readonly tableName: string,
    private readonly now: () => Date = () => new Date(),
  ) {}

  async roomOf(connectionId: string): Promise<string | null> {
    const res = await this.db.send(
      new GetCommand({ TableName: this.tableName, Key: { PK: connectionKey(connectionId), SK: "LIVE" }, ConsistentRead: true }),
    );
    const item = res.Item;
    return item && typeof item.roundCode === "string" && !this.expired(item) ? item.roundCode : null;
  }

  async join(connectionId: string, roundCode: string, ttl: number): Promise<void> {
    const previous = await this.roomOf(connectionId);
    // One transaction, so the connection is never in a room its reverse item does not name.
    await this.db.send(
      new TransactWriteCommand({
        TransactItems: [
          ...(previous !== null && previous !== roundCode
            ? [{ Delete: { TableName: this.tableName, Key: { PK: roomKey(previous), SK: connectionKey(connectionId) } } }]
            : []),
          {
            Put: {
              TableName: this.tableName,
              Item: { PK: roomKey(roundCode), SK: connectionKey(connectionId), type: "liveMember", roundCode, connectionId, ttl },
            },
          },
          {
            Put: {
              TableName: this.tableName,
              Item: { PK: connectionKey(connectionId), SK: "LIVE", type: "liveConnection", roundCode, connectionId, ttl },
            },
          },
        ],
      }),
    );
  }

  async remove(roundCode: string, connectionId: string): Promise<void> {
    await Promise.all([
      this.db.send(new DeleteCommand({ TableName: this.tableName, Key: { PK: roomKey(roundCode), SK: connectionKey(connectionId) } })),
      // Only while the reverse item names this room: a connection that moved on keeps its new room.
      this.db
        .send(
          new DeleteCommand({
            TableName: this.tableName,
            Key: { PK: connectionKey(connectionId), SK: "LIVE" },
            ConditionExpression: "#code = :code",
            ExpressionAttributeNames: { "#code": "roundCode" },
            ExpressionAttributeValues: { ":code": roundCode },
          }),
        )
        .catch((err: unknown) => {
          if (!(err instanceof Error && err.name === "ConditionalCheckFailedException")) throw err;
        }),
    ]);
  }

  async members(roundCode: string): Promise<string[]> {
    const items: Item[] = [];
    let startKey: Item | undefined;
    do {
      const res = await this.db.send(
        new QueryCommand({
          TableName: this.tableName,
          KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
          ExpressionAttributeValues: { ":pk": roomKey(roundCode), ":sk": "CONN#" },
          ConsistentRead: true,
          ...(startKey ? { ExclusiveStartKey: startKey } : {}),
        }),
      );
      items.push(...((res.Items ?? []) as Item[]));
      startKey = res.LastEvaluatedKey;
    } while (startKey);
    return items.filter((item) => !this.expired(item)).map((item) => (item.SK as string).slice("CONN#".length));
  }

  /** DynamoDB deletes expired items lazily, so the TTL is checked on read as well. */
  private expired(item: Item): boolean {
    return typeof item.ttl === "number" && item.ttl <= Math.floor(this.now().getTime() / 1000);
  }
}
