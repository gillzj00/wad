import type { APIGatewayProxyEventV2, APIGatewayProxyStructuredResultV2 } from "aws-lambda";
import { describe, expect, it } from "vitest";
import { createHandler } from "../../src/handlers/profile.js";
import { createHandler as createRoundsHandler } from "../../src/handlers/rounds.js";
import { createHandler as createSettlementHandler } from "../../src/handlers/settlement.js";
import { ProfileService } from "../../src/services/profile/profileService.js";
import { DynamoProfileStore } from "../../src/services/profile/profileStore.js";
import { RoundService } from "../../src/services/rounds/roundService.js";
import { DynamoRoundStore } from "../../src/services/rounds/roundStore.js";
import { SettlementService } from "../../src/services/rounds/settlementService.js";
import { course, courseItem, fakeDb, type Item, NOW, profileItem, TABLE } from "../services/rounds/fixtures.js";

type Handler = (event: APIGatewayProxyEventV2) => Promise<unknown>;

function event(routeKey: string, options: { sub?: unknown; body?: unknown; rawBody?: string; base64?: boolean; roundId?: string } = {}) {
  const sub = "sub" in options ? options.sub : "u_1";
  const text = options.rawBody ?? (options.body === undefined ? undefined : JSON.stringify(options.body));
  return {
    routeKey,
    requestContext: sub === undefined ? {} : { authorizer: { jwt: { claims: { sub, email: "zach@example.com" }, scopes: [] } } },
    pathParameters: options.roundId ? { roundId: options.roundId } : undefined,
    body: text !== undefined && options.base64 ? Buffer.from(text).toString("base64") : text,
    isBase64Encoded: options.base64 ?? false,
  } as unknown as APIGatewayProxyEventV2;
}

async function call(handler: Handler, e: APIGatewayProxyEventV2) {
  const res = (await handler(e)) as APIGatewayProxyStructuredResultV2;
  return { status: res.statusCode, body: JSON.parse(res.body as string) };
}

function setup(seed: Item[] = []) {
  const fake = fakeDb(seed);
  const handler = createHandler(new ProfileService(new DynamoProfileStore(fake.db, TABLE), () => NOW));
  const get = (sub: unknown = "u_1") => call(handler, event("GET /v1/me", { sub }));
  const put = (body: unknown, sub: unknown = "u_1") => call(handler, event("PUT /v1/me", { sub, body }));
  return { ...fake, handler, get, put };
}

const zach = { userId: "u_1", displayName: "Zach", handicapIndex: 13.1, venmoHandle: "zach-g", complete: true };

describe("GET /v1/me", () => {
  it("returns the caller's profile", async () => {
    const { get } = setup([{ ...profileItem("u_1", "Zach", 13.1), venmoHandle: "zach-g" }, profileItem("u_2", "Sam", 7)]);
    expect(await get()).toEqual({ status: 200, body: { profile: zach } });
    expect(await get("u_2")).toEqual({
      status: 200,
      body: { profile: { userId: "u_2", displayName: "Sam", handicapIndex: 7, venmoHandle: null, complete: true } },
    });
  });

  it("returns an empty, incomplete profile for a user who has not saved one", async () => {
    const { get, items } = setup();
    expect(await get()).toEqual({
      status: 200,
      body: { profile: { userId: "u_1", displayName: null, handicapIndex: null, venmoHandle: null, complete: false } },
    });
    expect(items.size).toBe(0);
  });

  it("is incomplete without a display name or a handicap index", async () => {
    const { get } = setup([
      { PK: "USER#u_1", SK: "PROFILE", displayName: "Zach", venmoHandle: "zach-g" },
      { PK: "USER#u_2", SK: "PROFILE", handicapIndex: 7 },
    ]);
    expect((await get()).body.profile).toEqual({ ...zach, handicapIndex: null, complete: false });
    expect((await get("u_2")).body.profile.complete).toBe(false);
  });
});

describe("PUT /v1/me", () => {
  it("saves the profile and returns it", async () => {
    const { get, put, items } = setup();
    const res = await put({ displayName: " Zach ", handicapIndex: 13.1, venmoHandle: "@zach-g" });
    expect(res).toEqual({ status: 200, body: { profile: zach } });
    expect(await get()).toEqual(res);
    expect(items.get("USER#u_1|PROFILE")).toEqual({
      PK: "USER#u_1",
      SK: "PROFILE",
      type: "user",
      userId: "u_1",
      displayName: "Zach",
      handicapIndex: 13.1,
      venmoHandle: "zach-g",
      updatedAt: NOW.toISOString(),
    });
  });

  it("stores nothing from the token but the sub", async () => {
    const { put, items } = setup();
    await put({ displayName: "Zach" });
    expect(JSON.stringify([...items.values()])).not.toContain("zach@example.com");
    expect(Object.keys(items.get("USER#u_1|PROFILE")!).sort()).toEqual(["PK", "SK", "displayName", "type", "updatedAt", "userId"]);
  });

  it("decodes a base64 body", async () => {
    const { handler } = setup();
    const res = await call(handler, event("PUT /v1/me", { body: { displayName: "Zach" }, base64: true }));
    expect(res.body.profile.displayName).toBe("Zach");
  });

  it("changes only the fields sent", async () => {
    const { put } = setup();
    await put({ displayName: "Zach", handicapIndex: 13.1, venmoHandle: "zach-g" });
    expect((await put({ handicapIndex: 12.8 })).body.profile).toEqual({ ...zach, handicapIndex: 12.8 });
    expect((await put({ venmoHandle: "zach_g2" })).body.profile).toEqual({ ...zach, handicapIndex: 12.8, venmoHandle: "zach_g2" });
    expect((await put({ displayName: "Zach G" })).body.profile).toEqual({
      ...zach,
      displayName: "Zach G",
      handicapIndex: 12.8,
      venmoHandle: "zach_g2",
    });
  });

  it("builds a profile one field at a time", async () => {
    const { put } = setup();
    expect((await put({ venmoHandle: "zach-g" })).body.profile).toEqual({ ...zach, displayName: null, handicapIndex: null, complete: false });
    expect((await put({ handicapIndex: 13.1 })).body.profile).toEqual({ ...zach, displayName: null, complete: false });
    expect((await put({ displayName: "Zach" })).body.profile).toEqual(zach);
  });

  it("clears the handicap index and the Venmo handle with null", async () => {
    const { get, put } = setup();
    await put({ displayName: "Zach", handicapIndex: 13.1, venmoHandle: "zach-g" });
    expect((await put({ venmoHandle: null })).body.profile).toEqual({ ...zach, venmoHandle: null });
    expect((await put({ handicapIndex: null })).body.profile).toEqual({ ...zach, handicapIndex: null, venmoHandle: null, complete: false });
    expect((await get()).body.profile).toEqual({ ...zach, handicapIndex: null, venmoHandle: null, complete: false });
  });

  it("does not clear the display name", async () => {
    const { get, put } = setup();
    await put({ displayName: "Zach", handicapIndex: 13.1, venmoHandle: "zach-g" });
    for (const displayName of [null, "", "  "]) {
      const res = await put({ displayName });
      expect(res.status).toBe(400);
      expect(res.body.error.code).toBe("invalid_display_name");
    }
    expect((await get()).body.profile).toEqual(zach);
  });

  it.each([
    [{ displayName: "x".repeat(41) }, "invalid_display_name"],
    [{ displayName: 42 }, "invalid_display_name"],
    [{ handicapIndex: 54.1 }, "invalid_handicap_index"],
    [{ handicapIndex: -10.1 }, "invalid_handicap_index"],
    [{ handicapIndex: 13.15 }, "invalid_handicap_index"],
    [{ handicapIndex: "13.1" }, "invalid_handicap_index"],
    [{ venmoHandle: "abcd" }, "invalid_venmo_handle"],
    [{ venmoHandle: "a".repeat(31) }, "invalid_venmo_handle"],
    [{ venmoHandle: "zach g" }, "invalid_venmo_handle"],
    [{ venmoHandle: "" }, "invalid_venmo_handle"],
    [{}, "invalid_body"],
    [[], "invalid_body"],
    ["Zach", "invalid_body"],
    [{ displayName: "Zach", handicapIndex: 99 }, "invalid_handicap_index"],
  ])("rejects %j with 400 %s and writes nothing", async (body, code) => {
    const { put, items } = setup();
    const res = await put(body);
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe(code);
    expect(typeof res.body.error.message).toBe("string");
    expect(items.size).toBe(0);
  });

  it("returns 400 for a missing or malformed body", async () => {
    const { handler, items } = setup();
    for (const rawBody of [undefined, "", "{not json"]) {
      const res = await call(handler, event("PUT /v1/me", rawBody === undefined ? {} : { rawBody }));
      expect(res.status).toBe(400);
      expect(res.body.error.code).toBe("invalid_json");
    }
    expect(items.size).toBe(0);
  });
});

describe("profile handler: the caller", () => {
  it.each(["GET /v1/me", "PUT /v1/me"])("returns 401 without a caller: %s", async (routeKey) => {
    const { handler, items, sent } = setup([profileItem("u_1", "Zach", 13.1)]);
    for (const sub of [undefined, "", 42, null]) {
      const res = await call(handler, event(routeKey, { sub, body: { displayName: "Eve" } }));
      expect(res.status).toBe(401);
      expect(res.body.error.code).toBe("unauthorized");
    }
    expect(sent).toEqual([]);
    expect(items.get("USER#u_1|PROFILE")).toEqual(profileItem("u_1", "Zach", 13.1));
  });

  it("does not take a user id from headers, query or path", async () => {
    const { handler, sent } = setup([profileItem("u_1", "Zach", 13.1)]);
    for (const routeKey of ["GET /v1/me", "PUT /v1/me"]) {
      const e = event(routeKey, { sub: undefined, body: { displayName: "Eve", userId: "u_1", sub: "u_1" } });
      e.headers = { "x-user-id": "u_1", authorization: "Bearer u_1" };
      e.queryStringParameters = { userId: "u_1", sub: "u_1" };
      e.pathParameters = { userId: "u_1" };
      expect((await call(handler, e)).status).toBe(401);
    }
    expect(sent).toEqual([]);
  });

  it("reads and writes the caller's profile whatever other ids the request carries", async () => {
    const sam = profileItem("u_2", "Sam", 7);
    const { handler, items } = setup([profileItem("u_1", "Zach", 13.1), sam]);
    const carry = (e: APIGatewayProxyEventV2) => {
      e.headers = { "x-user-id": "u_2" };
      e.queryStringParameters = { userId: "u_2", sub: "u_2" };
      e.pathParameters = { userId: "u_2" };
      return e;
    };
    const body = { displayName: "Zach G", userId: "u_2", sub: "u_2", PK: "USER#u_2", SK: "PROFILE", type: "admin", complete: true };
    const put = await call(handler, carry(event("PUT /v1/me", { body })));
    expect(put.body.profile).toEqual({ userId: "u_1", displayName: "Zach G", handicapIndex: 13.1, venmoHandle: null, complete: true });
    const got = await call(handler, carry(event("GET /v1/me")));
    expect(got.body.profile).toEqual(put.body.profile);
    expect(items.get("USER#u_2|PROFILE")).toEqual(sam);
    expect(items.get("USER#u_1|PROFILE")).toMatchObject({ PK: "USER#u_1", SK: "PROFILE", type: "user", userId: "u_1", displayName: "Zach G" });
    expect(items.get("USER#u_1|PROFILE")).not.toHaveProperty("sub");
    expect(items.get("USER#u_1|PROFILE")).not.toHaveProperty("complete");
  });

  it("returns 404 for an unknown route", async () => {
    const { handler } = setup();
    for (const routeKey of ["DELETE /v1/me", "GET /v1/users/{userId}", "PUT /v1/users/{userId}"]) {
      const res = await call(handler, event(routeKey));
      expect(res.status).toBe(404);
      expect(res.body.error.code).toBe("route_not_found");
    }
  });

  it("does not swallow unexpected errors", async () => {
    const service = {
      getProfile: async () => {
        throw new Error("boom");
      },
    } as unknown as ProfileService;
    await expect(createHandler(service)(event("GET /v1/me"))).rejects.toThrow("boom");
  });
});

describe("a saved profile and rounds", () => {
  const roundBody = { courseId: course.courseId, teeId: "male-blue", date: "2026-10-03", holes: 18, games: { skins: { baseCents: 500 } } };

  function app() {
    const base = setup([courseItem]);
    const store = new DynamoRoundStore(base.db, TABLE, () => NOW);
    let minutes = 0;
    const rounds = createRoundsHandler(
      new RoundService(store, { now: () => new Date(NOW.getTime() + minutes++ * 60_000), newId: () => "id1", newJoinCode: () => "ABCD2F" }),
    );
    const settlement = createSettlementHandler(new SettlementService(store));
    return { ...base, rounds, settlement };
  }

  it("lets a user create a round once the profile is saved", async () => {
    const { put, rounds } = app();
    const create = () => call(rounds, event("POST /v1/rounds", { body: roundBody }));

    const before = await create();
    expect(before.status).toBe(409);
    expect(before.body.error.code).toBe("profile_incomplete");

    // A display name alone is not enough.
    expect((await put({ displayName: "Zach" })).body.profile.complete).toBe(false);
    expect((await create()).body.error.code).toBe("profile_incomplete");

    expect((await put({ handicapIndex: 13.1 })).body.profile.complete).toBe(true);
    const after = await create();
    expect(after.status).toBe(201);
    expect(after.body.round.players).toHaveLength(1);
    expect(after.body.round.players[0]).toMatchObject({ userId: "u_1", displayName: "Zach", handicapIndex: 13.1, guest: false });
    expect(after.body.round.players[0].courseHandicap).toEqual(expect.any(Number));
  });

  it("lets a user join a round once the profile is saved", async () => {
    const { put, rounds } = app();
    await put({ displayName: "Zach", handicapIndex: 13.1 });
    expect((await call(rounds, event("POST /v1/rounds", { body: roundBody }))).status).toBe(201);

    const join = () => call(rounds, event("POST /v1/rounds/join", { sub: "u_2", body: { joinCode: "ABCD2F" } }));
    expect((await join()).body.error.code).toBe("profile_incomplete");
    await put({ displayName: "Sam", handicapIndex: -1.2 }, "u_2");
    const joined = await join();
    expect(joined.status).toBe(200);
    expect(joined.body.round.players.map((p: { displayName: string }) => p.displayName)).toEqual(["Zach", "Sam"]);
    expect(joined.body.round.players[1].handicapIndex).toBe(-1.2);
  });

  it("stops a user from creating a round after the handicap index is cleared", async () => {
    const { put, rounds } = app();
    await put({ displayName: "Zach", handicapIndex: 13.1 });
    await put({ handicapIndex: null });
    const res = await call(rounds, event("POST /v1/rounds", { body: roundBody }));
    expect(res.body.error.code).toBe("profile_incomplete");
  });

  it("gives the settlement the payee's Venmo handle", async () => {
    const { put, rounds, settlement } = app();
    await put({ displayName: "Zach", handicapIndex: 10, venmoHandle: "@zach-g" });
    await put({ displayName: "Sam", handicapIndex: 10 }, "u_2");
    const created = await call(rounds, event("POST /v1/rounds", { body: roundBody }));
    const roundId = created.body.round.roundId as string;
    await call(rounds, event("POST /v1/rounds/join", { sub: "u_2", body: { joinCode: "ABCD2F" } }));
    // Zach wins the first hole.
    for (const [sub, gross] of [["u_1", 3], ["u_2", 5]] as const) {
      const res = await call(rounds, event("PUT /v1/rounds/{roundId}/scores", { sub, roundId, body: { hole: 1, gross } }));
      expect(res.status).toBe(200);
    }
    const res = await call(settlement, event("GET /v1/rounds/{roundId}/settlement", { roundId }));
    expect(res.status).toBe(200);
    expect(res.body.settlement.transfers).toHaveLength(1);
    expect(res.body.settlement.transfers[0]).toMatchObject({ from: "u_2", to: "u_1", amountCents: 500, toVenmoHandle: "zach-g" });
  });
});
