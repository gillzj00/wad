import { describe, expect, it } from "vitest";
import { DynamoProfileStore } from "../../../src/services/profile/profileStore.js";
import { DynamoRoundStore } from "../../../src/services/rounds/roundStore.js";
import { fakeDb, type Item, NOW, profileItem, TABLE } from "../rounds/fixtures.js";

const AT = NOW.toISOString();
const LATER = "2026-09-29T13:00:00.000Z";

function setup(seed: Item[] = []) {
  const fake = fakeDb(seed);
  return { ...fake, store: new DynamoProfileStore(fake.db, TABLE) };
}

describe("DynamoProfileStore", () => {
  it("reads a profile with a consistent read of the user's own item", async () => {
    const { store, sent } = setup([{ ...profileItem("u_1", "Zach", 15.4), venmoHandle: "zach-g" }]);
    expect(await store.get("u_1")).toEqual({ displayName: "Zach", handicapIndex: 15.4, venmoHandle: "zach-g" });
    expect(sent).toEqual([{ name: "GetCommand", input: { TableName: TABLE, Key: { PK: "USER#u_1", SK: "PROFILE" }, ConsistentRead: true } }]);
  });

  it("returns null when the user has no profile", async () => {
    const { store } = setup([profileItem("u_1", "Zach", 15.4)]);
    expect(await store.get("u_2")).toBeNull();
  });

  it("reads missing, cleared or mistyped attributes as null", async () => {
    const { store } = setup([
      { PK: "USER#u_1", SK: "PROFILE" },
      { PK: "USER#u_2", SK: "PROFILE", displayName: 42, handicapIndex: "7", venmoHandle: null },
    ]);
    const empty = { displayName: null, handicapIndex: null, venmoHandle: null };
    expect(await store.get("u_1")).toEqual(empty);
    expect(await store.get("u_2")).toEqual(empty);
  });

  it("creates the item with the attributes the round store reads", async () => {
    const { store, items } = setup();
    const saved = await store.update("u_1", { displayName: "Zach", handicapIndex: 13.1, venmoHandle: "zach-g" }, AT);
    expect(saved).toEqual({ displayName: "Zach", handicapIndex: 13.1, venmoHandle: "zach-g" });
    expect(items.get("USER#u_1|PROFILE")).toEqual({
      PK: "USER#u_1",
      SK: "PROFILE",
      type: "user",
      userId: "u_1",
      displayName: "Zach",
      handicapIndex: 13.1,
      venmoHandle: "zach-g",
      updatedAt: AT,
    });
  });

  it("is read by the round store", async () => {
    const { store, db } = setup();
    await store.update("u_1", { displayName: "Zach", handicapIndex: 13.1, venmoHandle: "zach-g" }, AT);
    const rounds = new DynamoRoundStore(db, TABLE, () => NOW);
    expect(await rounds.getProfile("u_1")).toEqual({ displayName: "Zach", handicapIndex: 13.1 });
    expect(await rounds.getVenmoHandle("u_1")).toBe("zach-g");
  });

  it("writes with an update that names only the fields sent", async () => {
    const { store, sent } = setup();
    await store.update("u_1", { venmoHandle: "zach-g" }, AT);
    expect(sent).toEqual([
      {
        name: "UpdateCommand",
        input: {
          TableName: TABLE,
          Key: { PK: "USER#u_1", SK: "PROFILE" },
          UpdateExpression: "SET #f0 = :v0, #f1 = :v1, #f2 = :v2, #f3 = :v3",
          ExpressionAttributeNames: { "#f0": "type", "#f1": "userId", "#f2": "updatedAt", "#f3": "venmoHandle" },
          ExpressionAttributeValues: { ":v0": "user", ":v1": "u_1", ":v2": AT, ":v3": "zach-g" },
          ReturnValues: "ALL_NEW",
        },
      },
    ]);
  });

  it("keeps the fields that were not sent", async () => {
    const { store, items } = setup();
    await store.update("u_1", { displayName: "Zach", handicapIndex: 13.1 }, AT);
    // Another device sets the Venmo handle, then the first changes the handicap.
    expect(await store.update("u_1", { venmoHandle: "zach-g" }, LATER)).toEqual({ displayName: "Zach", handicapIndex: 13.1, venmoHandle: "zach-g" });
    expect(await store.update("u_1", { handicapIndex: 12.8 }, LATER)).toEqual({ displayName: "Zach", handicapIndex: 12.8, venmoHandle: "zach-g" });
    expect(items.get("USER#u_1|PROFILE")).toMatchObject({ displayName: "Zach", handicapIndex: 12.8, venmoHandle: "zach-g", updatedAt: LATER });
  });

  it("keeps attributes it does not own", async () => {
    const { store, items } = setup([{ ...profileItem("u_1", "Zach", 15.4), somethingElse: "kept" }]);
    await store.update("u_1", { displayName: "Zach G" }, AT);
    expect(items.get("USER#u_1|PROFILE")).toMatchObject({ displayName: "Zach G", handicapIndex: 15.4, somethingElse: "kept" });
  });

  it("clears a field by writing null", async () => {
    const { store, items } = setup();
    await store.update("u_1", { displayName: "Zach", handicapIndex: 13.1, venmoHandle: "zach-g" }, AT);
    expect(await store.update("u_1", { handicapIndex: null, venmoHandle: null }, LATER)).toEqual({
      displayName: "Zach",
      handicapIndex: null,
      venmoHandle: null,
    });
    expect(items.get("USER#u_1|PROFILE")).toMatchObject({ displayName: "Zach", handicapIndex: null, venmoHandle: null });
    const rounds = new DynamoRoundStore(fakeDb([items.get("USER#u_1|PROFILE")!]).db, TABLE);
    expect(await rounds.getProfile("u_1")).toEqual({ displayName: "Zach", handicapIndex: null });
    expect(await rounds.getVenmoHandle("u_1")).toBeNull();
  });

  it("writes only the caller's item", async () => {
    const other = profileItem("u_2", "Sam", 7);
    const { store, items } = setup([other]);
    await store.update("u_1", { displayName: "Zach" }, AT);
    expect(items.get("USER#u_2|PROFILE")).toEqual(other);
    expect([...items.keys()].sort()).toEqual(["USER#u_1|PROFILE", "USER#u_2|PROFILE"]);
  });
});
