import { describe, expect, it } from "vitest";
import { RoundError } from "../../../src/services/rounds/errors.js";
import { JOIN_CODE_ATTEMPTS, JOIN_CODE_TTL_SECONDS, RoundService } from "../../../src/services/rounds/roundService.js";
import { DynamoRoundStore, type PlayerRecord, type RoundRef } from "../../../src/services/rounds/roundStore.js";
import { course, courseItem, fakeDb, type Item, NOW, profileItem, TABLE } from "./fixtures.js";

const NOW_S = NOW.getTime() / 1000;

const profiles = [
  profileItem("u_1", "Zach", 15.4),
  profileItem("u_2", "Sam", 7),
  profileItem("u_3", "Ana", 0),
  profileItem("u_4", "Lee", 22.3),
  profileItem("u_5", "Kim", 12),
];

const body = (extra: Record<string, unknown> = {}) => ({
  courseId: course.courseId,
  teeId: "male-blue",
  date: "2026-10-03",
  holes: 18,
  games: { skins: { baseCents: 500 }, wad: { startCents: 700, stepCents: 200 }, greenies: { amountCents: 500 } },
  ...extra,
});

function setup(options: { codes?: string[]; seed?: Item[]; store?: (db: ReturnType<typeof fakeDb>["db"]) => DynamoRoundStore } = {}) {
  const fake = fakeDb(options.seed ?? [courseItem, ...profiles]);
  const codes = [...(options.codes ?? ["ABCD2F", "GHJK34", "MNPQ56"])];
  let ids = 0;
  let minutes = 0;
  // Each call is a minute later, so players sort in the order they joined.
  const now = () => new Date(NOW.getTime() + minutes++ * 60_000);
  const store = options.store?.(fake.db) ?? new DynamoRoundStore(fake.db, TABLE, () => NOW);
  const service = new RoundService(store, {
    now,
    newId: () => `id${++ids}`,
    newJoinCode: () => {
      const code = codes.shift();
      if (!code) throw new Error("test ran out of join codes");
      return code;
    },
  });
  return { ...fake, service };
}

async function failure(promise: Promise<unknown>): Promise<Pick<RoundError, "kind" | "code">> {
  try {
    await promise;
  } catch (err) {
    if (err instanceof RoundError) return { kind: err.kind, code: err.code };
    throw err;
  }
  throw new Error("expected the call to fail");
}

describe("RoundService.createRound", () => {
  it("creates an 18-hole round with the creator as its first player", async () => {
    const { service, items } = setup();
    const round = await service.createRound("u_1", body());
    expect(round).toEqual({
      roundId: "r_id1",
      course: { courseId: course.courseId, name: "North", teeId: "male-blue", tee: "Blue" },
      date: "2026-10-03",
      holeCount: 18,
      status: "in_progress",
      joinCode: "ABCD2F",
      createdBy: "u_1",
      createdAt: NOW.toISOString(),
      games: { skins: { baseCents: 500 }, wad: { startCents: 700, stepCents: 200 }, greenies: { amountCents: 500 } },
      players: [
        {
          userId: "u_1",
          displayName: "Zach",
          handicapIndex: 15.4,
          courseHandicap: 18,
          courseHandicapOverride: null,
          ticksByHole: {},
          guest: false,
          joinedAt: NOW.toISOString(),
        },
      ],
      teeOrder: ["u_1"],
      scores: [],
      holes: [],
      state: round.state,
    });
    expect(Object.keys(round.state).sort()).toEqual(["greenies", "skins", "wad"]);
    expect(items.get("JOINCODE#ABCD2F|ROUND")).toMatchObject({ roundId: "r_id1", ttl: NOW_S + JOIN_CODE_TTL_SECONDS });
    expect(items.get("ROUND#r_id1|META")).toMatchObject({ playerCount: 1, tee: { teeId: "male-blue", courseRating: 72.1, slope: 131, par: 72 } });
    expect((items.get("ROUND#r_id1|META")!.tee as { holes: unknown[] }).holes).toHaveLength(18);
    expect(await service.getRound("u_1", "r_id1")).toEqual(round);
  });

  it("enables only the games that are included and fills in the default amounts", async () => {
    const { service } = setup();
    expect((await service.createRound("u_1", body({ games: { wad: {}, greenies: { amountCents: 0 } } }))).games).toEqual({
      wad: { startCents: 700, stepCents: 200 },
      greenies: { amountCents: 0 },
    });
    expect((await service.createRound("u_1", body({ games: { skins: {}, wad: { stepCents: 100 }, greenies: {} } }))).games).toEqual({
      skins: { baseCents: 500 },
      wad: { startCents: 700, stepCents: 100 },
      greenies: { amountCents: 500 },
    });
    expect((await service.createRound("u_1", body({ games: {} }))).games).toEqual({});
  });

  it.each([
    ["a fraction of a cent", { skins: { baseCents: 5.5 } }],
    ["a negative amount", { wad: { startCents: -700, stepCents: 200 } }],
    ["a negative step", { wad: { startCents: 700, stepCents: -1 } }],
    ["a string amount", { greenies: { amountCents: "500" } }],
    ["a null amount", { greenies: { amountCents: null } }],
    ["an amount that is not a number", { skins: { baseCents: Number.NaN } }],
    ["an amount too large to be exact", { skins: { baseCents: 2 ** 53 } }],
  ])("rejects %s", async (_name, games) => {
    const { service, sent } = setup();
    expect(await failure(service.createRound("u_1", body({ games })))).toEqual({ kind: "validation", code: "invalid_amount" });
    expect(sent).toEqual([]);
  });

  it.each([
    ["a body that is not an object", [], "invalid_body"],
    ["a missing course", body({ courseId: undefined }), "invalid_body"],
    ["a blank tee", body({ teeId: " " }), "invalid_body"],
    ["a missing date", body({ date: undefined }), "invalid_body"],
    ["a date in another format", body({ date: "10/03/2026" }), "invalid_date"],
    ["a date that does not exist", body({ date: "2026-02-30" }), "invalid_date"],
    ["missing holes", body({ holes: undefined }), "invalid_holes"],
    ["an unknown hole count", body({ holes: 12 }), "invalid_holes"],
    ["holes as a string", body({ holes: "18" }), "invalid_holes"],
    ["missing games", body({ games: undefined }), "invalid_body"],
    ["games as a list", body({ games: [] }), "invalid_body"],
    ["a game that is not an object", body({ games: { skins: true } }), "invalid_body"],
    ["an unknown game", body({ games: { nassau: { baseCents: 500 } } }), "unknown_game"],
  ])("rejects %s", async (_name, input, code) => {
    const { service, sent } = setup();
    expect(await failure(service.createRound("u_1", input))).toEqual({ kind: "validation", code });
    expect(sent).toEqual([]);
  });

  it("rejects 9-hole rounds until their handicap rule is decided", async () => {
    const { service, sent } = setup();
    expect(await failure(service.createRound("u_1", body({ holes: 9 })))).toEqual({ kind: "validation", code: "nine_hole_rounds_unsupported" });
    expect(sent).toEqual([]);
  });

  it("rejects an unknown course or tee", async () => {
    const { service } = setup();
    expect(await failure(service.createRound("u_1", body({ courseId: "gca-missing1" })))).toEqual({ kind: "not_found", code: "course_not_found" });
    expect(await failure(service.createRound("u_1", body({ teeId: "male-gold" })))).toEqual({ kind: "not_found", code: "tee_not_found" });
  });

  it("rejects a tee without 18 valid stroke indexes", async () => {
    const { service } = setup();
    expect(await failure(service.createRound("u_1", body({ teeId: "male-junior" })))).toEqual({ kind: "validation", code: "tee_not_usable" });
    expect(await failure(service.createRound("u_1", body({ teeId: "male-short" })))).toEqual({ kind: "validation", code: "tee_not_usable" });
  });

  it("leaves the course handicap unset on a tee without rating and slope", async () => {
    const { service } = setup();
    const round = await service.createRound("u_1", body({ teeId: "male-unrated" }));
    expect(round.players[0]).toMatchObject({ handicapIndex: 15.4, courseHandicap: null, ticksByHole: null });
  });

  it.each([
    ["no profile", []],
    ["no display name", [{ PK: "USER#u_1", SK: "PROFILE", handicapIndex: 15.4 }]],
    ["a blank display name", [profileItem("u_1", "  ", 15.4)]],
    ["no handicap index", [{ PK: "USER#u_1", SK: "PROFILE", displayName: "Zach" }]],
    ["a handicap index out of range", [profileItem("u_1", "Zach", 60)]],
  ])("needs a complete profile: %s", async (_name, seed) => {
    const { service, items } = setup({ seed: [courseItem, ...seed] });
    expect(await failure(service.createRound("u_1", body()))).toEqual({ kind: "conflict", code: "profile_incomplete" });
    expect([...items.keys()].filter((k) => k.startsWith("ROUND#") || k.startsWith("JOINCODE#"))).toEqual([]);
  });

  it("retries with a new join code when the first is taken", async () => {
    const { service, items, sent } = setup({ codes: ["ABCD2F", "ABCD2F", "GHJK34"] });
    await service.createRound("u_1", body());
    const second = await service.createRound("u_2", body());
    expect(second.joinCode).toBe("GHJK34");
    expect(sent.filter((s) => s.name === "TransactWriteCommand")).toHaveLength(3);
    expect(items.get("JOINCODE#ABCD2F|ROUND")?.roundId).toBe("r_id1");
    expect(items.get("JOINCODE#GHJK34|ROUND")?.roundId).toBe(second.roundId);
    expect(items.get(`ROUND#${second.roundId}|META`)?.joinCode).toBe("GHJK34");
    expect((await service.joinRound("u_3", { joinCode: "GHJK34" })).roundId).toBe(second.roundId);
  });

  it("gives up after a bounded number of collisions", async () => {
    const { service, items, sent } = setup({ codes: ["ABCD2F", ...Array<string>(JOIN_CODE_ATTEMPTS).fill("ABCD2F")] });
    await service.createRound("u_1", body());
    await expect(service.createRound("u_2", body())).rejects.toThrow("no free join code");
    expect(sent.filter((s) => s.name === "TransactWriteCommand")).toHaveLength(1 + JOIN_CODE_ATTEMPTS);
    expect([...items.keys()].filter((k) => k.endsWith("|META"))).toEqual(["ROUND#r_id1|META"]);
  });
});

describe("RoundService.getRound", () => {
  it("is limited to the round's players", async () => {
    const { service } = setup();
    const round = await service.createRound("u_1", body());
    expect(await failure(service.getRound("u_2", round.roundId))).toEqual({ kind: "forbidden", code: "not_a_participant" });
    expect(await failure(service.getRound("u_1", "r_missing"))).toEqual({ kind: "not_found", code: "round_not_found" });
    expect(await failure(service.getRound("u_1", ""))).toEqual({ kind: "not_found", code: "round_not_found" });
  });

  it("returns stored scores and hole events", async () => {
    const { service, items } = setup();
    const { roundId } = await service.createRound("u_1", body());
    items.set(`ROUND#${roundId}|SCORE#04#u_1`, { PK: `ROUND#${roundId}`, SK: "SCORE#04#u_1", userId: "u_1", hole: 4, gross: 5 });
    items.set(`ROUND#${roundId}|HOLE#04`, { PK: `ROUND#${roundId}`, SK: "HOLE#04", hole: 4, wadMakers: ["u_1"], greenieWinner: null });
    const round = await service.getRound("u_1", roundId);
    expect(round.scores).toEqual([{ userId: "u_1", hole: 4, gross: 5 }]);
    expect(round.holes).toEqual([{ hole: 4, wadMakers: ["u_1"], greenieWinner: null }]);
  });
});

describe("RoundService.joinRound", () => {
  it("adds the caller and allocates ticks relative to the lowest handicap", async () => {
    const { service, items } = setup();
    const { roundId } = await service.createRound("u_1", body());
    const round = await service.joinRound("u_2", { joinCode: "abcd-2f" });
    expect(round.roundId).toBe(roundId);
    expect(round.players.map((p) => [p.userId, p.displayName, p.courseHandicap, p.guest])).toEqual([
      ["u_1", "Zach", 18, false],
      ["u_2", "Sam", 8, false],
    ]);
    // 10 ticks: one on each of the holes with stroke index 1-10.
    expect(round.players[0]!.ticksByHole).toEqual({ 1: 1, 4: 1, 5: 1, 7: 1, 8: 1, 10: 1, 12: 1, 13: 1, 14: 1, 17: 1 });
    expect(round.players[1]!.ticksByHole).toEqual({});
    expect(items.get(`ROUND#${roundId}|META`)?.playerCount).toBe(2);
    expect(await service.getRound("u_2", roundId)).toEqual(round);
  });

  it("is idempotent for a player already in the round", async () => {
    const { service, items, sent } = setup();
    const { roundId } = await service.createRound("u_1", body());
    const first = await service.joinRound("u_2", { joinCode: "ABCD2F" });
    const writes = sent.filter((s) => s.name === "TransactWriteCommand").length;

    expect(await service.joinRound("u_2", { joinCode: "ABCD2F" })).toEqual(first);
    expect(await service.joinRound("u_1", { joinCode: "ABCD2F" })).toEqual(first);
    expect(sent.filter((s) => s.name === "TransactWriteCommand")).toHaveLength(writes);
    expect(items.get(`ROUND#${roundId}|META`)?.playerCount).toBe(2);
    expect([...items.keys()].filter((k) => k.includes("|PLAYER#"))).toHaveLength(2);
  });

  it("lets a player who is already in a full round join again", async () => {
    const { service } = setup();
    await service.createRound("u_1", body());
    for (const id of ["u_2", "u_3", "u_4"]) await service.joinRound(id, { joinCode: "ABCD2F" });
    expect((await service.joinRound("u_4", { joinCode: "ABCD2F" })).players).toHaveLength(4);
  });

  it("treats a concurrent join by the same player as joined", async () => {
    // The same user joins from two devices: the other request wins between this one's read and write.
    class Racing extends DynamoRoundStore {
      override async addPlayer(round: RoundRef, player: PlayerRecord, max: number) {
        await super.addPlayer(round, player, max);
        return super.addPlayer(round, player, max);
      }
    }
    const { service, items } = setup({ store: (db) => new Racing(db, TABLE, () => NOW) });
    const { roundId } = await service.createRound("u_1", body());
    const round = await service.joinRound("u_2", { joinCode: "ABCD2F" });
    expect(round.players.map((p) => p.userId)).toEqual(["u_1", "u_2"]);
    expect(items.get(`ROUND#${roundId}|META`)?.playerCount).toBe(2);
  });

  it("refuses a fifth player", async () => {
    const { service, items } = setup();
    const { roundId } = await service.createRound("u_1", body());
    for (const id of ["u_2", "u_3", "u_4"]) await service.joinRound(id, { joinCode: "ABCD2F" });
    expect(await failure(service.joinRound("u_5", { joinCode: "ABCD2F" }))).toEqual({ kind: "conflict", code: "round_full" });
    expect(items.get(`ROUND#${roundId}|META`)?.playerCount).toBe(4);
    expect(items.has(`ROUND#${roundId}|PLAYER#u_5`)).toBe(false);
  });

  it("cannot exceed four players when two joins race for the last place", async () => {
    // Both requests read a round with three players; the other one writes first.
    class Racing extends DynamoRoundStore {
      override async addPlayer(round: RoundRef, player: PlayerRecord, max: number) {
        if (player.userId === "u_5") await super.addPlayer(round, { ...player, userId: "u_4", displayName: "Lee" }, max);
        return super.addPlayer(round, player, max);
      }
    }
    const { service, items } = setup({ store: (db) => new Racing(db, TABLE, () => NOW) });
    const { roundId } = await service.createRound("u_1", body());
    for (const id of ["u_2", "u_3"]) await service.joinRound(id, { joinCode: "ABCD2F" });

    expect(await failure(service.joinRound("u_5", { joinCode: "ABCD2F" }))).toEqual({ kind: "conflict", code: "round_full" });
    expect(items.get(`ROUND#${roundId}|META`)?.playerCount).toBe(4);
    expect([...items.keys()].filter((k) => k.includes("|PLAYER#")).sort()).toEqual(
      ["u_1", "u_2", "u_3", "u_4"].map((id) => `ROUND#${roundId}|PLAYER#${id}`),
    );
  });

  it("returns not found for an unknown, malformed or expired code", async () => {
    const { service, items } = setup();
    await service.createRound("u_1", body());
    const notFound = { kind: "not_found", code: "join_code_not_found" };
    expect(await failure(service.joinRound("u_2", { joinCode: "ZZZZZZ" }))).toEqual(notFound);
    expect(await failure(service.joinRound("u_2", { joinCode: "ABC" }))).toEqual(notFound);
    expect(await failure(service.joinRound("u_2", { joinCode: "ABCD0F" }))).toEqual(notFound);
    items.set("JOINCODE#ABCD2F|ROUND", { ...items.get("JOINCODE#ABCD2F|ROUND")!, ttl: NOW_S });
    expect(await failure(service.joinRound("u_2", { joinCode: "ABCD2F" }))).toEqual(notFound);
  });

  it.each([
    ["no code", {}],
    ["a blank code", { joinCode: "  " }],
    ["a code that is not a string", { joinCode: 123456 }],
    ["a body that is not an object", "ABCD2F"],
  ])("rejects %s", async (_name, input) => {
    const { service } = setup();
    expect(await failure(service.joinRound("u_2", input))).toEqual({ kind: "validation", code: "invalid_body" });
  });

  it("needs a complete profile", async () => {
    const { service } = setup({ seed: [courseItem, profiles[0]!] });
    await service.createRound("u_1", body());
    expect(await failure(service.joinRound("u_2", { joinCode: "ABCD2F" }))).toEqual({ kind: "conflict", code: "profile_incomplete" });
  });
});

describe("RoundService.addGuest", () => {
  it("adds a guest with a course handicap from their index", async () => {
    const { service, items } = setup();
    const { roundId } = await service.createRound("u_1", body());
    const { round, player } = await service.addGuest("u_1", roundId, { displayName: " Pat ", handicapIndex: -1.2 });
    expect(player).toMatchObject({ userId: "guest_id2", displayName: "Pat", handicapIndex: -1.2, courseHandicap: -1, guest: true, ticksByHole: {} });
    expect(round.players.map((p) => p.userId)).toEqual(["u_1", "guest_id2"]);
    expect(Object.keys(round.players[0]!.ticksByHole!)).toHaveLength(18);
    expect(round.players[0]!.ticksByHole![5]).toBe(2);
    expect(items.get(`ROUND#${roundId}|META`)?.playerCount).toBe(2);
  });

  it("counts guests toward the four players", async () => {
    const { service } = setup();
    const { roundId } = await service.createRound("u_1", body());
    for (const name of ["Pat", "Jo", "Max"]) await service.addGuest("u_1", roundId, { displayName: name, handicapIndex: 10 });
    expect(await failure(service.addGuest("u_1", roundId, { displayName: "Extra", handicapIndex: 10 }))).toEqual({ kind: "conflict", code: "round_full" });
    expect(await failure(service.joinRound("u_2", { joinCode: "ABCD2F" }))).toEqual({ kind: "conflict", code: "round_full" });
  });

  it("is limited to the round's players", async () => {
    const { service } = setup();
    const { roundId } = await service.createRound("u_1", body());
    const guest = { displayName: "Pat", handicapIndex: 10 };
    expect(await failure(service.addGuest("u_2", roundId, guest))).toEqual({ kind: "forbidden", code: "not_a_participant" });
    expect(await failure(service.addGuest("u_1", "r_missing", guest))).toEqual({ kind: "not_found", code: "round_not_found" });
  });

  it.each([
    ["no name", { handicapIndex: 10 }, "invalid_body"],
    ["a blank name", { displayName: " ", handicapIndex: 10 }, "invalid_body"],
    ["a name that is too long", { displayName: "x".repeat(41), handicapIndex: 10 }, "invalid_display_name"],
    ["no handicap index", { displayName: "Pat" }, "invalid_handicap_index"],
    ["a handicap index as a string", { displayName: "Pat", handicapIndex: "10" }, "invalid_handicap_index"],
    ["a handicap index above 54", { displayName: "Pat", handicapIndex: 54.1 }, "invalid_handicap_index"],
    ["a handicap index below -10", { displayName: "Pat", handicapIndex: -10.1 }, "invalid_handicap_index"],
  ])("rejects %s", async (_name, input, code) => {
    const { service } = setup();
    const { roundId } = await service.createRound("u_1", body());
    expect(await failure(service.addGuest("u_1", roundId, input))).toEqual({ kind: "validation", code });
  });
});
