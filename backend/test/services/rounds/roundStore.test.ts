import { describe, expect, it } from "vitest";
import { DynamoRoundStore, type PlayerRecord, type RoundMeta } from "../../../src/services/rounds/roundStore.js";
import { course, courseItem, fakeDb, type Item, NOW, profileItem, TABLE, transactionCancelled } from "./fixtures.js";

const NOW_S = NOW.getTime() / 1000;

const meta: RoundMeta = {
  roundId: "r_1",
  courseId: course.courseId,
  courseName: "North",
  tee: { teeId: "male-blue", name: "Blue", courseRating: 72.1, slope: 131, par: 72, holes: [{ hole: 1, par: 4, strokeIndex: 7 }] },
  date: "2026-10-03",
  holeCount: 18,
  status: "in_progress",
  joinCode: "ABCD2F",
  createdBy: "u_1",
  createdAt: NOW.toISOString(),
  games: { skins: { baseCents: 500 } },
  playerCount: 1,
};

const player = (userId: string, extra: Partial<PlayerRecord> = {}): PlayerRecord => ({
  userId,
  displayName: userId,
  handicapIndex: 10,
  courseHandicap: 12,
  courseHandicapOverride: null,
  guest: false,
  joinedAt: NOW.toISOString(),
  ...extra,
});

function setup(seed: Item[] = []) {
  const fake = fakeDb(seed);
  return { ...fake, store: new DynamoRoundStore(fake.db, TABLE, () => NOW) };
}

async function created(seed: Item[] = []) {
  const s = setup(seed);
  expect(await s.store.createRound(meta, player("u_1"), NOW_S + 60)).toBe("created");
  return s;
}

describe("DynamoRoundStore", () => {
  it("reads the cached course and the user profile", async () => {
    const { store } = setup([courseItem, profileItem("u_1", "Zach", 15.4), { PK: "USER#u_2", SK: "PROFILE" }]);
    expect(await store.getCourse(course.courseId)).toEqual(course);
    expect(await store.getCourse("gca-missing1")).toBeNull();
    expect(await store.getProfile("u_1")).toEqual({ displayName: "Zach", handicapIndex: 15.4 });
    expect(await store.getProfile("u_2")).toEqual({ displayName: null, handicapIndex: null });
    expect(await store.getProfile("u_3")).toBeNull();
  });

  it("creates the join code, the round and its creator in one conditional transaction", async () => {
    const { items, sent } = await created();
    expect(sent.map((s) => s.name)).toEqual(["TransactWriteCommand"]);
    const actions = sent[0]!.input.TransactItems as { Put: { TableName: string; ConditionExpression: string } }[];
    expect(actions.map((a) => a.Put.TableName)).toEqual([TABLE, TABLE, TABLE]);
    expect(actions.map((a) => a.Put.ConditionExpression)).toEqual(Array(3).fill("attribute_not_exists(PK)"));

    expect(items.get("JOINCODE#ABCD2F|ROUND")).toEqual({ PK: "JOINCODE#ABCD2F", SK: "ROUND", type: "joinCode", roundId: "r_1", ttl: NOW_S + 60 });
    expect(items.get("ROUND#r_1|META")).toEqual({
      PK: "ROUND#r_1",
      SK: "META",
      type: "round",
      GSI1PK: "USER#u_1",
      GSI1SK: `ROUND#${NOW_S}#r_1`,
      ...meta,
    });
    expect(items.get("ROUND#r_1|PLAYER#u_1")).toEqual({
      PK: "ROUND#r_1",
      SK: "PLAYER#u_1",
      type: "roundPlayer",
      GSI1PK: "USER#u_1",
      GSI1SK: `ROUND#${NOW_S}#r_1`,
      ...player("u_1"),
    });
  });

  it("writes nothing when the join code is already in use", async () => {
    const { store, items } = await created();
    const other = { ...meta, roundId: "r_2", createdBy: "u_9" };
    expect(await store.createRound(other, player("u_9"), NOW_S + 60)).toBe("join_code_taken");
    expect(items.has("ROUND#r_2|META")).toBe(false);
    expect(items.has("ROUND#r_2|PLAYER#u_9")).toBe(false);
    expect(items.get("JOINCODE#ABCD2F|ROUND")?.roundId).toBe("r_1");
  });

  it("rethrows a create failure that is not a join code collision", async () => {
    const { store, failures } = setup();
    failures.push(transactionCancelled(["None", "ConditionalCheckFailed", "None"]));
    await expect(store.createRound(meta, player("u_1"), NOW_S + 60)).rejects.toThrow("Transaction cancelled");
    failures.push(transactionCancelled(["TransactionConflict", "None", "None"]));
    await expect(store.createRound(meta, player("u_1"), NOW_S + 60)).rejects.toThrow("Transaction cancelled");
    failures.push(new Error("network"));
    await expect(store.createRound(meta, player("u_1"), NOW_S + 60)).rejects.toThrow("network");
  });

  it("resolves a join code until its TTL passes", async () => {
    const fake = fakeDb();
    let now = NOW;
    const store = new DynamoRoundStore(fake.db, TABLE, () => now);
    await store.createRound(meta, player("u_1"), NOW_S + 60);
    expect(await store.resolveJoinCode("ABCD2F")).toBe("r_1");
    expect(await store.resolveJoinCode("ZZZZZZ")).toBeNull();
    now = new Date(NOW.getTime() + 60_000);
    expect(await store.resolveJoinCode("ABCD2F")).toBeNull();
  });

  it("adds a player and counts them on the round", async () => {
    const { store, items, sent } = await created();
    expect(await store.addPlayer(meta, player("u_2"), 4)).toBe("added");
    expect(items.get("ROUND#r_1|META")?.playerCount).toBe(2);
    expect(items.get("ROUND#r_1|PLAYER#u_2")).toMatchObject({ type: "roundPlayer", GSI1PK: "USER#u_2", GSI1SK: `ROUND#${NOW_S}#r_1`, userId: "u_2" });
    expect(sent[1]!.input.TransactItems).toEqual([
      {
        Update: {
          TableName: TABLE,
          Key: { PK: "ROUND#r_1", SK: "META" },
          UpdateExpression: "SET playerCount = playerCount + :one",
          ConditionExpression: "attribute_exists(PK) AND playerCount < :max",
          ExpressionAttributeValues: { ":one": 1, ":max": 4 },
        },
      },
      { Put: { TableName: TABLE, Item: items.get("ROUND#r_1|PLAYER#u_2"), ConditionExpression: "attribute_not_exists(PK)" } },
    ]);
  });

  it("does not index a guest in the user history", async () => {
    const { store, items } = await created();
    await store.addPlayer(meta, player("guest_1", { guest: true }), 4);
    const item = items.get("ROUND#r_1|PLAYER#guest_1")!;
    expect(item.guest).toBe(true);
    expect(item).not.toHaveProperty("GSI1PK");
    expect(item).not.toHaveProperty("GSI1SK");
  });

  it("reports a player who is already in the round without counting them twice", async () => {
    const { store, items } = await created();
    await store.addPlayer(meta, player("u_2"), 4);
    expect(await store.addPlayer(meta, player("u_2", { displayName: "changed" }), 4)).toBe("already_member");
    expect(items.get("ROUND#r_1|META")?.playerCount).toBe(2);
    expect(items.get("ROUND#r_1|PLAYER#u_2")?.displayName).toBe("u_2");
  });

  it("refuses a player once the round is full", async () => {
    const { store, items } = await created();
    for (const id of ["u_2", "u_3", "u_4"]) expect(await store.addPlayer(meta, player(id), 4)).toBe("added");
    expect(await store.addPlayer(meta, player("u_5"), 4)).toBe("round_full");
    expect(items.get("ROUND#r_1|META")?.playerCount).toBe(4);
    expect(items.has("ROUND#r_1|PLAYER#u_5")).toBe(false);
  });

  it("maps the condition failures of a lost race and rethrows anything else", async () => {
    const { store, failures } = await created();
    failures.push(transactionCancelled(["ConditionalCheckFailed", "None"]));
    expect(await store.addPlayer(meta, player("u_2"), 4)).toBe("round_full");
    failures.push(transactionCancelled(["None", "ConditionalCheckFailed"]));
    expect(await store.addPlayer(meta, player("u_2"), 4)).toBe("already_member");
    failures.push(transactionCancelled(["ConditionalCheckFailed", "ConditionalCheckFailed"]));
    expect(await store.addPlayer(meta, player("u_2"), 4)).toBe("already_member");
    failures.push(transactionCancelled(["TransactionConflict", "None"]));
    await expect(store.addPlayer(meta, player("u_2"), 4)).rejects.toThrow("Transaction cancelled");
    failures.push(new Error("network"));
    await expect(store.addPlayer(meta, player("u_2"), 4)).rejects.toThrow("network");
  });

  it("reads a whole round with one partition query", async () => {
    const { store, items, sent } = await created();
    await store.addPlayer(meta, player("u_2", { joinedAt: "2026-09-29T12:05:00.000Z", courseHandicap: null }), 4);
    items.set("ROUND#r_1|SCORE#04#u_1", { PK: "ROUND#r_1", SK: "SCORE#04#u_1", type: "score", userId: "u_1", hole: 4, gross: 5 });
    items.set("ROUND#r_1|HOLE#04", { PK: "ROUND#r_1", SK: "HOLE#04", type: "hole", hole: 4, wadMakers: ["u_2"], greenieWinner: null });
    items.set("ROUND#r_1|CONN#abc", { PK: "ROUND#r_1", SK: "CONN#abc", type: "connection" });

    expect(await store.getRound("r_1")).toEqual({
      meta: { ...meta, playerCount: 2 },
      players: [player("u_1"), player("u_2", { joinedAt: "2026-09-29T12:05:00.000Z", courseHandicap: null })],
      scores: [{ userId: "u_1", hole: 4, gross: 5 }],
      holes: [{ hole: 4, wadMakers: ["u_2"], greenieWinner: null }],
    });
    expect(sent.at(-1)).toEqual({
      name: "QueryCommand",
      input: { TableName: TABLE, KeyConditionExpression: "PK = :pk", ExpressionAttributeValues: { ":pk": "ROUND#r_1" }, ConsistentRead: true },
    });
    expect(await store.getRound("r_missing")).toBeNull();
  });

  it("sets and clears a player's handicap override without touching the rest of the item", async () => {
    const { store, items, sent } = await created();
    const before = items.get("ROUND#r_1|PLAYER#u_1")!;
    const change = { by: "u_2", at: "2026-09-29T12:10:00.000Z" };

    expect(await store.setCourseHandicapOverride("r_1", "u_1", 15, change)).toBe("updated");
    expect(sent.at(-1)).toEqual({
      name: "UpdateCommand",
      input: {
        TableName: TABLE,
        Key: { PK: "ROUND#r_1", SK: "PLAYER#u_1" },
        UpdateExpression: "SET #override = :override, #at = :at, #by = :by",
        ConditionExpression: "attribute_exists(PK)",
        ExpressionAttributeNames: { "#override": "courseHandicapOverride", "#at": "courseHandicapOverrideAt", "#by": "courseHandicapOverrideBy" },
        ExpressionAttributeValues: { ":override": 15, ":at": change.at, ":by": "u_2" },
      },
    });
    expect(items.get("ROUND#r_1|PLAYER#u_1")).toEqual({
      ...before,
      courseHandicap: 12,
      courseHandicapOverride: 15,
      courseHandicapOverrideAt: change.at,
      courseHandicapOverrideBy: "u_2",
    });
    expect((await store.getRound("r_1"))!.players).toEqual([player("u_1", { courseHandicapOverride: 15 })]);

    expect(await store.setCourseHandicapOverride("r_1", "u_1", null, { by: "u_1", at: "2026-09-29T12:20:00.000Z" })).toBe("updated");
    expect(items.get("ROUND#r_1|PLAYER#u_1")).toMatchObject({ courseHandicap: 12, courseHandicapOverride: null, courseHandicapOverrideBy: "u_1" });
    expect((await store.getRound("r_1"))!.players).toEqual([player("u_1")]);
  });

  it("does not create a player item when setting an override for someone who is not in the round", async () => {
    const { store, items } = await created();
    const change = { by: "u_1", at: NOW.toISOString() };
    expect(await store.setCourseHandicapOverride("r_1", "u_9", 15, change)).toBe("player_not_found");
    expect(await store.setCourseHandicapOverride("r_missing", "u_1", 15, change)).toBe("player_not_found");
    expect(items.has("ROUND#r_1|PLAYER#u_9")).toBe(false);
    expect(items.has("ROUND#r_missing|PLAYER#u_1")).toBe(false);
  });

  it("rethrows a failed override write that is not a condition failure", async () => {
    const db = {
      send: async () => {
        throw Object.assign(new Error("throttled"), { name: "ProvisionedThroughputExceededException" });
      },
    } as never;
    const store = new DynamoRoundStore(db, TABLE, () => NOW);
    await expect(store.setCourseHandicapOverride("r_1", "u_1", 15, { by: "u_1", at: NOW.toISOString() })).rejects.toThrow("throttled");
  });

  it("reads a player item written before overrides existed", async () => {
    const { store, items } = await created();
    const old = { ...items.get("ROUND#r_1|PLAYER#u_1")! };
    delete old.courseHandicapOverride;
    items.set("ROUND#r_1|PLAYER#u_1", old);
    expect((await store.getRound("r_1"))!.players).toEqual([player("u_1")]);
  });

  it("reads the Venmo handle from the profile", async () => {
    const { store } = setup([
      { ...profileItem("u_1", "Zach", 15.4), venmoHandle: " zach-g " },
      { ...profileItem("u_2", "Bo", 10), venmoHandle: "  " },
      { ...profileItem("u_3", "Cy", 10), venmoHandle: 42 },
      profileItem("u_4", "Di", 10),
    ]);
    expect(await store.getVenmoHandle("u_1")).toBe("zach-g");
    expect(await store.getVenmoHandle("u_2")).toBeNull();
    expect(await store.getVenmoHandle("u_3")).toBeNull();
    expect(await store.getVenmoHandle("u_4")).toBeNull();
    expect(await store.getVenmoHandle("u_5")).toBeNull();
  });

  it("writes a paid marker once and keeps the first", async () => {
    const { store, items, sent } = await created();
    const marker = { transferId: "t_abc", from: "u_2", to: "u_1", amountCents: 1500, paidAt: "2026-10-03T20:00:00.000Z", paidBy: "u_2" };
    expect(await store.markTransferPaid("r_1", marker)).toBe("marked");
    expect(sent.at(-1)).toEqual({
      name: "PutCommand",
      input: {
        TableName: TABLE,
        Item: { PK: "ROUND#r_1", SK: "SETTLEMENT#PAID#t_abc", type: "transferPaid", ...marker },
        ConditionExpression: "attribute_not_exists(PK)",
      },
    });
    expect(await store.markTransferPaid("r_1", { ...marker, paidAt: "2026-10-04T08:00:00.000Z", paidBy: "u_1" })).toBe("already_marked");
    expect(items.get("ROUND#r_1|SETTLEMENT#PAID#t_abc")).toMatchObject({ paidAt: "2026-10-03T20:00:00.000Z", paidBy: "u_2" });
  });

  it("rethrows a failed marker write that is not a condition failure", async () => {
    const db = {
      send: async () => {
        throw Object.assign(new Error("throttled"), { name: "ProvisionedThroughputExceededException" });
      },
    } as never;
    const store = new DynamoRoundStore(db, TABLE, () => NOW);
    const marker = { transferId: "t_abc", from: "u_2", to: "u_1", amountCents: 1500, paidAt: NOW.toISOString(), paidBy: "u_2" };
    await expect(store.markTransferPaid("r_1", marker)).rejects.toThrow("throttled");
  });

  it("lists the paid markers of one round and leaves them out of the round", async () => {
    const { store, sent } = await created();
    const a = { transferId: "t_abc", from: "u_2", to: "u_1", amountCents: 1500, paidAt: "2026-10-03T20:00:00.000Z", paidBy: "u_2" };
    const b = { transferId: "t_def", from: "u_3", to: "u_1", amountCents: 700, paidAt: "2026-10-03T20:05:00.000Z", paidBy: "u_1" };
    await store.markTransferPaid("r_1", a);
    await store.markTransferPaid("r_1", b);
    await store.markTransferPaid("r_2", { ...a, transferId: "t_other" });

    expect(await store.listPaidMarkers("r_1")).toEqual([a, b]);
    expect(sent.at(-1)).toEqual({
      name: "QueryCommand",
      input: {
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: { ":pk": "ROUND#r_1", ":sk": "SETTLEMENT#PAID#" },
        ConsistentRead: true,
      },
    });
    expect(await store.listPaidMarkers("r_missing")).toEqual([]);
    expect(await store.getRound("r_1")).toMatchObject({ scores: [], holes: [] });
  });

  it("removes a paid marker, and removing a missing one is a no-op", async () => {
    const { store, items, sent } = await created();
    const marker = { transferId: "t_abc", from: "u_2", to: "u_1", amountCents: 1500, paidAt: NOW.toISOString(), paidBy: "u_2" };
    await store.markTransferPaid("r_1", marker);
    await store.unmarkTransferPaid("r_1", "t_abc");
    expect(items.has("ROUND#r_1|SETTLEMENT#PAID#t_abc")).toBe(false);
    expect(sent.at(-1)).toEqual({ name: "DeleteCommand", input: { TableName: TABLE, Key: { PK: "ROUND#r_1", SK: "SETTLEMENT#PAID#t_abc" } } });
    await store.unmarkTransferPaid("r_1", "t_abc");
    expect(await store.listPaidMarkers("r_1")).toEqual([]);
  });
});
