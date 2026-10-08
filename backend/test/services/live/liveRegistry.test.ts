import { describe, expect, it } from "vitest";
import { DynamoLiveRegistry } from "../../../src/services/live/liveRegistry.js";
import { fakeDb, type Item, TABLE } from "../rounds/fixtures.js";
import { NOW } from "./fixtures.js";

const EPOCH = Math.floor(NOW.getTime() / 1000);
const TTL = EPOCH + 6 * 3600;

function setup(seed: Item[] = []) {
  const fake = fakeDb(seed);
  return { ...fake, registry: new DynamoLiveRegistry(fake.db, TABLE, () => NOW) };
}

const member = (roundCode: string, connectionId: string, ttl = TTL): Item => ({
  PK: `LIVE#${roundCode}`,
  SK: `CONN#${connectionId}`,
  type: "liveMember",
  roundCode,
  connectionId,
  ttl,
});
const reverse = (connectionId: string, roundCode: string, ttl = TTL): Item => ({
  PK: `CONN#${connectionId}`,
  SK: "LIVE",
  type: "liveConnection",
  roundCode,
  connectionId,
  ttl,
});

const room = (roundCode: string, ...connectionIds: string[]): Item[] =>
  connectionIds.flatMap((id) => [member(roundCode, id), reverse(id, roundCode)]);

describe("DynamoLiveRegistry", () => {
  it("joins a room by writing the member and reverse items in one transaction", async () => {
    const { registry, items, sent } = setup();
    await registry.join("c1", "ABC123", TTL);
    expect(items.get("LIVE#ABC123|CONN#c1")).toEqual(member("ABC123", "c1"));
    expect(items.get("CONN#c1|LIVE")).toEqual(reverse("c1", "ABC123"));
    expect(sent.map((s) => s.name)).toEqual(["GetCommand", "TransactWriteCommand"]);
    expect(sent[1]!.input).toEqual({
      TransactItems: [{ Put: { TableName: TABLE, Item: member("ABC123", "c1") } }, { Put: { TableName: TABLE, Item: reverse("c1", "ABC123") } }],
    });
  });

  it("finds a connection's room and lists a room's members, with consistent reads", async () => {
    const { registry, sent } = setup([...room("ABC123", "c1", "c2"), ...room("XYZ789", "c3")]);
    expect(await registry.roomOf("c1")).toBe("ABC123");
    expect(await registry.roomOf("c3")).toBe("XYZ789");
    expect(await registry.roomOf("c9")).toBeNull();
    expect(await registry.members("ABC123")).toEqual(["c1", "c2"]);
    expect(await registry.members("XYZ789")).toEqual(["c3"]);
    expect(await registry.members("NOPE00")).toEqual([]);
    expect(sent.every((s) => s.input.ConsistentRead === true)).toBe(true);
    expect(sent.at(-1)).toEqual({
      name: "QueryCommand",
      input: {
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: { ":pk": "LIVE#NOPE00", ":sk": "CONN#" },
        ConsistentRead: true,
      },
    });
  });

  it("moves a connection to another room, deleting the old membership in the same transaction", async () => {
    const { registry, items, sent } = setup(room("ABC123", "c1", "c2"));
    await registry.join("c1", "XYZ789", TTL + 10);
    expect(items.has("LIVE#ABC123|CONN#c1")).toBe(false);
    expect(items.get("LIVE#ABC123|CONN#c2")).toEqual(member("ABC123", "c2"));
    expect(items.get("LIVE#XYZ789|CONN#c1")).toEqual(member("XYZ789", "c1", TTL + 10));
    expect(items.get("CONN#c1|LIVE")).toEqual(reverse("c1", "XYZ789", TTL + 10));
    expect((sent[1]!.input.TransactItems as Item[])[0]).toEqual({ Delete: { TableName: TABLE, Key: { PK: "LIVE#ABC123", SK: "CONN#c1" } } });
  });

  it("renews the ttl when a connection subscribes to its room again, without a delete", async () => {
    const { registry, items, sent } = setup(room("ABC123", "c1"));
    await registry.join("c1", "ABC123", TTL + 100);
    expect(items.get("LIVE#ABC123|CONN#c1")).toEqual(member("ABC123", "c1", TTL + 100));
    expect(items.get("CONN#c1|LIVE")).toEqual(reverse("c1", "ABC123", TTL + 100));
    expect(sent[1]!.input.TransactItems).toHaveLength(2);
  });

  it("removes a connection from its room", async () => {
    const { registry, items, sent } = setup(room("ABC123", "c1", "c2"));
    await registry.remove("ABC123", "c1");
    expect([...items.keys()]).toEqual(["LIVE#ABC123|CONN#c2", "CONN#c2|LIVE"]);
    expect(sent).toEqual([
      { name: "DeleteCommand", input: { TableName: TABLE, Key: { PK: "LIVE#ABC123", SK: "CONN#c1" } } },
      {
        name: "DeleteCommand",
        input: {
          TableName: TABLE,
          Key: { PK: "CONN#c1", SK: "LIVE" },
          ConditionExpression: "#code = :code",
          ExpressionAttributeNames: { "#code": "roundCode" },
          ExpressionAttributeValues: { ":code": "ABC123" },
        },
      },
    ]);
  });

  it("removing a connection that is not in the room changes nothing, not even the room it is in", async () => {
    const { registry, items } = setup(room("ABC123", "c1"));
    await registry.remove("ABC123", "c9");
    await registry.remove("XYZ789", "c1");
    expect([...items.keys()]).toEqual(["LIVE#ABC123|CONN#c1", "CONN#c1|LIVE"]);
    expect(await registry.roomOf("c1")).toBe("ABC123");
  });

  it("ignores expired items, which DynamoDB deletes lazily", async () => {
    const { registry } = setup([
      member("ABC123", "c1", EPOCH),
      reverse("c1", "ABC123", EPOCH),
      member("ABC123", "c2", EPOCH + 1),
      reverse("c2", "ABC123", EPOCH + 1),
    ]);
    expect(await registry.members("ABC123")).toEqual(["c2"]);
    expect(await registry.roomOf("c1")).toBeNull();
    expect(await registry.roomOf("c2")).toBe("ABC123");
  });
});
