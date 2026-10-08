import { describe, expect, it } from "vitest";
import { RoundError } from "../../../src/services/rounds/errors.js";
import { RoundService } from "../../../src/services/rounds/roundService.js";
import { DynamoRoundStore } from "../../../src/services/rounds/roundStore.js";
import { SettlementService, transferId } from "../../../src/services/rounds/settlementService.js";
import type { WolfEvent } from "../../../src/shared/types.js";
import { course, courseItem, fakeDb, NOW, profileItem, TABLE } from "./fixtures.js";

const ROUND = "r_id1";
const WOLF = { wolf: { pointCents: 100 } };
const WRITES = ["PutCommand", "DeleteCommand", "UpdateCommand", "TransactWriteCommand"];
const LONE = { choice: "lone" };
const partner = (partnerUserId: string) => ({ choice: "partner", partnerUserId });

// On the Blue tee (rating 72.1, slope 131, par 72) the course handicap is
// round(index * 131 / 113 + 0.1): index 10 -> 12 and index 12 -> 14. The lowest
// is 12, so u_1, u_2 and u_3 get no ticks and u_4 gets 2: holes 5 and 12.
const profiles = [
  profileItem("u_1", "Ann", 10),
  profileItem("u_2", "Bo", 10),
  profileItem("u_3", "Cy", 10),
  profileItem("u_4", "Di", 12),
  profileItem("u_5", "Eve", 10),
];

// The full round of test/engines/wolf.test.ts, with u_1 to u_4 for a to d.
// Gross scores for u_1, u_2, u_3, u_4 and what is recorded for Wolf.
//
//  hole Wolf  choice      gross     Wolf side v opponents (net)   points              u_1 u_2 u_3 u_4
//   1   u_1   with u_2    4 5 5 5   4 v 5                         u_1, u_2 +2           2   2   0   0
//   2   u_2   alone       5 5 6 6   5 v 5                         tied                  2   2   0   0
//   3   u_3   with u_4    3 3 4 4   4 v 3                         u_1, u_2 +3           5   5   0   0
//   4   u_4   alone       5 5 5 4   4 v 5                         u_4 +4                5   5   0   4
//   5   u_1   with u_3    4 5 5 5   4 v 4 (u_4 nets 4)            tied                  5   5   0   4
//   6   u_2   alone       4 4 3 4   4 v 3                         u_1, u_3, u_4 +1      6   5   1   5
//   7   u_3   with u_1    5 5 5 5   5 v 5                         tied                  6   5   1   5
//   8   u_4   with u_3    5 5 4 5   4 v 5                         u_3, u_4 +2           6   5   3   7
//   9   u_1   alone       3 4 4 4   3 v 4                         u_1 +4               10   5   3   7
//  10   u_2   with u_3    5 5 5 4   5 v 4                         u_1, u_4 +3          13   5   3  10
//  11   u_3   alone       3 4 2 4   2 v 3                         u_3 +4               13   5   7  10
//  12   u_4   with u_2    5 6 5 5   4 v 5 (u_4 nets 4)            u_2, u_4 +2          13   7   7  12
//  13   u_1   with u_4    4 4 5 5   4 v 4                         tied                 13   7   7  12
//  14   u_2   alone       4 3 4 4   3 v 4                         u_2 +4               13  11   7  12
//  15   u_3   with u_2    5 5 6 4   5 v 4                         u_1, u_4 +3          16  11   7  15
//  16   u_4   alone       3 3 3 4   4 v 3                         u_1, u_2, u_3 +1     17  12   8  15
//  17   u_3 (last, 8)     alone     4 5 3 4: 3 v 4                u_3 +4               17  12  12  15
//  18   u_2 and u_3 are tied for last; u_2 is recorded as the Wolf, with u_1
//                                   4 4 5 5: 4 v 5                u_1, u_2 +2          19  14  12  15
//
// Total 60 points at 100 cents: u_1 100 * (76 - 60) = 1600, u_2 100 * (56 - 60) = -400,
// u_3 100 * (48 - 60) = -1200, u_4 100 * (60 - 60) = 0.
const HOLES: [number[], WolfEvent][] = [
  [[4, 5, 5, 5], partner("u_2")],
  [[5, 5, 6, 6], LONE],
  [[3, 3, 4, 4], partner("u_4")],
  [[5, 5, 5, 4], LONE],
  [[4, 5, 5, 5], partner("u_3")],
  [[4, 4, 3, 4], LONE],
  [[5, 5, 5, 5], partner("u_1")],
  [[5, 5, 4, 5], partner("u_3")],
  [[3, 4, 4, 4], LONE],
  [[5, 5, 5, 4], partner("u_3")],
  [[3, 4, 2, 4], LONE],
  [[5, 6, 5, 5], partner("u_2")],
  [[4, 4, 5, 5], partner("u_4")],
  [[4, 3, 4, 4], LONE],
  [[5, 5, 6, 4], partner("u_2")],
  [[3, 3, 3, 4], LONE],
  [[4, 5, 3, 4], LONE],
  [[4, 4, 5, 5], { choice: "partner", partnerUserId: "u_1", wolfUserId: "u_2" }],
] as [number[], WolfEvent][];
const WOLF_DELTAS = { u_1: 1600, u_2: -400, u_3: -1200, u_4: 0 };

/** A round created by u_1 with the given other members, then the write log cleared. */
async function setup(options: { members?: string[]; games?: object; teeId?: string } = {}) {
  const fake = fakeDb([courseItem, ...profiles]);
  const store = new DynamoRoundStore(fake.db, TABLE, () => NOW);
  let ids = 0;
  let minutes = 0;
  const service = new RoundService(store, {
    now: () => new Date(NOW.getTime() + minutes++ * 60_000),
    newId: () => `id${++ids}`,
    newJoinCode: () => "ABCD2F",
  });
  const settlement = new SettlementService(store, { now: () => NOW });
  const members = options.members ?? ["u_2", "u_3", "u_4"];
  const players = ["u_1", ...members];
  const body = { courseId: course.courseId, teeId: options.teeId ?? "male-blue", date: "2026-10-03", holes: 18, games: options.games ?? WOLF };
  await service.createRound("u_1", body);
  for (const member of members) await service.joinRound(member, { joinCode: "ABCD2F" });
  fake.sent.length = 0;

  const scoreHole = async (hole: number, gross: number[]) => {
    for (const [i, g] of gross.entries()) await service.putScore(players[i]!, ROUND, { hole, gross: g });
  };
  /** Plays holes `from` to `through` of HOLES; a hole in `wolf` records that instead, or nothing for null. */
  const play = async (through = 18, wolf: Record<number, object | null> = {}, from = 1) => {
    for (let hole = from; hole <= through; hole++) {
      const [gross, recorded] = HOLES[hole - 1]!;
      await scoreHole(hole, gross);
      const event = hole in wolf ? wolf[hole] : recorded;
      if (event) await service.putHoleEvents("u_1", ROUND, String(hole), { wolf: event });
    }
    fake.sent.length = 0;
  };
  const writes = () => fake.sent.filter((s) => WRITES.includes(s.name));
  return { ...fake, service, settlement, scoreHole, play, writes };
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

describe("creating a round with wolf", () => {
  it("defaults to 100 cents a point and takes the amount given", async () => {
    expect((await setup({ games: { wolf: {} } })).items.get(`ROUND#${ROUND}|META`)).toMatchObject({ games: { wolf: { pointCents: 100 } } });
    const { service } = await setup({ games: { wolf: { pointCents: 25 }, skins: {} } });
    expect((await service.getRound("u_1", ROUND)).games).toEqual({ wolf: { pointCents: 25 }, skins: { baseCents: 500, carryover: true } });
    expect((await (await setup({ games: { wolf: { pointCents: 0 } } })).service.getRound("u_1", ROUND)).games).toEqual({ wolf: { pointCents: 0 } });
  });

  it.each([
    ["a fraction of a cent", { pointCents: 12.5 }, "invalid_amount"],
    ["a negative amount", { pointCents: -100 }, "invalid_amount"],
    ["a string amount", { pointCents: "100" }, "invalid_amount"],
    ["a null amount", { pointCents: null }, "invalid_amount"],
    ["settings that are not an object", true, "invalid_body"],
  ])("rejects %s", async (_name, wolf, code) => {
    expect(await failure(setup({ games: { wolf } }))).toEqual({ kind: "validation", code });
  });

  it("is created with one player, so wolf is unavailable until there are four", async () => {
    const { service } = await setup({ members: [] });
    expect((await service.getRound("u_1", ROUND)).state).toEqual({ wolf: null });
    await service.joinRound("u_2", { joinCode: "ABCD2F" });
    await service.joinRound("u_3", { joinCode: "ABCD2F" });
    expect((await service.getRound("u_1", ROUND)).state.wolf).toBeNull();
    const round = await service.joinRound("u_4", { joinCode: "ABCD2F" });
    expect(round.state.wolf).toMatchObject({ teeOrder: ["u_1", "u_2", "u_3", "u_4"], complete: false, deltas: { u_1: 0, u_2: 0, u_3: 0, u_4: 0 } });
    expect(round.state.wolf!.holes).toHaveLength(18);
    expect(round.state.wolf!.holes[0]).toMatchObject({ hole: 1, wolfUserId: "u_1", status: "pending" });
  });

  it("counts a guest as one of the four", async () => {
    const { service } = await setup({ members: ["u_2", "u_3"] });
    const { round, player } = await service.addGuest("u_1", ROUND, { displayName: "Pat", handicapIndex: 10 });
    expect(round.state.wolf!.teeOrder).toEqual(["u_1", "u_2", "u_3", player.userId]);
  });

  it("is unavailable while a player has no course handicap", async () => {
    const { service } = await setup({ teeId: "male-unrated" });
    expect((await service.getRound("u_1", ROUND)).state.wolf).toBeNull();
    for (const id of ["u_1", "u_2", "u_3"]) await service.putHandicapOverride("u_1", ROUND, id, { courseHandicap: 10 });
    expect((await service.getRound("u_1", ROUND)).state.wolf).toBeNull();
    const round = await service.putHandicapOverride("u_1", ROUND, "u_4", { courseHandicap: 12 });
    expect(round.state.wolf).not.toBeNull();
  });

  it("leaves wolf out of the state when it is not one of the games", async () => {
    const { service } = await setup({ games: { skins: {} } });
    expect(Object.keys((await service.getRound("u_1", ROUND)).state)).toEqual(["skins"]);
  });
});

describe("RoundService.putTeeOrder", () => {
  it("is the order the players were added until it is set", async () => {
    const { service } = await setup({ members: ["u_3", "u_2", "u_4"] });
    expect((await service.getRound("u_1", ROUND)).teeOrder).toEqual(["u_1", "u_3", "u_2", "u_4"]);
  });

  it("sets the order, which the wolf rotation follows", async () => {
    const { service, items, writes } = await setup();
    const round = await service.putTeeOrder("u_3", ROUND, { teeOrder: ["u_4", "u_2", "u_1", "u_3"] });
    expect(round.teeOrder).toEqual(["u_4", "u_2", "u_1", "u_3"]);
    expect(round.players.map((p) => p.userId)).toEqual(["u_1", "u_2", "u_3", "u_4"]);
    expect(round.state.wolf!.teeOrder).toEqual(["u_4", "u_2", "u_1", "u_3"]);
    expect(round.state.wolf!.holes.slice(0, 5).map((h) => h.wolfUserId)).toEqual(["u_4", "u_2", "u_1", "u_3", "u_4"]);
    expect(items.get(`ROUND#${ROUND}|META`)).toMatchObject({ teeOrder: ["u_4", "u_2", "u_1", "u_3"], teeOrderBy: "u_3", playerCount: 4, joinCode: "ABCD2F" });
    expect(writes().map((w) => w.name)).toEqual(["UpdateCommand"]);
    expect(writes()[0]!.input.ConditionExpression).toBe("attribute_exists(PK)");
    expect(await service.getRound("u_1", ROUND)).toEqual(round);
  });

  it("keeps the last write, and the same order again changes nothing", async () => {
    const { service } = await setup();
    await service.putTeeOrder("u_1", ROUND, { teeOrder: ["u_4", "u_2", "u_1", "u_3"] });
    const round = await service.putTeeOrder("u_2", ROUND, { teeOrder: ["u_2", "u_1", "u_4", "u_3"] });
    expect(round.teeOrder).toEqual(["u_2", "u_1", "u_4", "u_3"]);
    expect((await service.putTeeOrder("u_2", ROUND, { teeOrder: ["u_2", "u_1", "u_4", "u_3"] })).teeOrder).toEqual(round.teeOrder);
  });

  it("works in a round without wolf", async () => {
    const { service } = await setup({ games: { skins: {} }, members: ["u_2"] });
    expect((await service.putTeeOrder("u_1", ROUND, { teeOrder: ["u_2", "u_1"] })).teeOrder).toEqual(["u_2", "u_1"]);
  });

  it("puts a player who joins after the order was set at the end", async () => {
    const { service } = await setup({ members: ["u_2", "u_3"] });
    await service.putTeeOrder("u_1", ROUND, { teeOrder: ["u_3", "u_1", "u_2"] });
    const round = await service.joinRound("u_4", { joinCode: "ABCD2F" });
    expect(round.teeOrder).toEqual(["u_3", "u_1", "u_2", "u_4"]);
    expect(round.state.wolf!.teeOrder).toEqual(["u_3", "u_1", "u_2", "u_4"]);
  });

  it("is for players of the round only", async () => {
    const { service, writes } = await setup();
    const teeOrder = ["u_4", "u_2", "u_1", "u_3"];
    expect(await failure(service.putTeeOrder("u_5", ROUND, { teeOrder }))).toEqual({ kind: "forbidden", code: "not_a_participant" });
    expect(await failure(service.putTeeOrder("u_1", "r_missing", { teeOrder }))).toEqual({ kind: "not_found", code: "round_not_found" });
    expect(writes()).toEqual([]);
  });

  it.each([
    ["no tee order", {}, "invalid_body"],
    ["a tee order that is not a list", { teeOrder: "u_1" }, "invalid_body"],
    ["an id that is not a string", { teeOrder: ["u_1", "u_2", "u_3", 4] }, "invalid_body"],
    ["more ids than a round has players", { teeOrder: ["u_1", "u_2", "u_3", "u_4", "u_5"] }, "invalid_body"],
    ["a list as the body", [["u_1", "u_2", "u_3", "u_4"]], "invalid_body"],
    ["someone who is not in the round", { teeOrder: ["u_1", "u_2", "u_3", "u_5"] }, "unknown_player"],
    ["a missing player", { teeOrder: ["u_1", "u_2", "u_3"] }, "invalid_tee_order"],
    ["a player listed twice", { teeOrder: ["u_1", "u_2", "u_3", "u_3"] }, "invalid_tee_order"],
    ["an empty order", { teeOrder: [] }, "invalid_tee_order"],
  ])("rejects %s", async (_name, body, code) => {
    const { service, writes } = await setup();
    expect(await failure(service.putTeeOrder("u_1", ROUND, body))).toEqual({ kind: "validation", code });
    expect(writes()).toEqual([]);
    expect((await service.getRound("u_1", ROUND)).teeOrder).toEqual(["u_1", "u_2", "u_3", "u_4"]);
  });

  it("cannot be changed once the round has a score", async () => {
    const { service, writes } = await setup();
    await service.putScore("u_2", ROUND, { hole: 1, gross: 4 });
    const before = writes().length;
    expect(await failure(service.putTeeOrder("u_1", ROUND, { teeOrder: ["u_4", "u_2", "u_1", "u_3"] }))).toEqual({ kind: "conflict", code: "tee_order_locked" });
    expect(writes()).toHaveLength(before);
    // Clearing the score opens it again.
    await service.putScore("u_2", ROUND, { hole: 1, gross: null });
    expect((await service.putTeeOrder("u_1", ROUND, { teeOrder: ["u_4", "u_2", "u_1", "u_3"] })).teeOrder).toEqual(["u_4", "u_2", "u_1", "u_3"]);
  });

  it("cannot be changed once the round has a wolf record", async () => {
    const { service } = await setup();
    await service.putHoleEvents("u_1", ROUND, "1", { wolf: LONE });
    expect(await failure(service.putTeeOrder("u_1", ROUND, { teeOrder: ["u_4", "u_2", "u_1", "u_3"] }))).toEqual({ kind: "conflict", code: "tee_order_locked" });
    await service.putHoleEvents("u_1", ROUND, "1", { wolf: null });
    expect((await service.putTeeOrder("u_1", ROUND, { teeOrder: ["u_4", "u_2", "u_1", "u_3"] })).teeOrder).toEqual(["u_4", "u_2", "u_1", "u_3"]);
  });
});

describe("RoundService.putHoleEvents with wolf", () => {
  it("stores the wolf's choice and returns it with the hole", async () => {
    const { service, items, writes } = await setup();
    const round = await service.putHoleEvents("u_3", ROUND, "1", { wolf: partner("u_2") });
    const wolf = { choice: "partner", partnerUserId: "u_2", wolfUserId: null };
    expect(round.holes).toEqual([{ hole: 1, wadMakers: [], greenieWinner: null, wolf }]);
    expect(items.get(`ROUND#${ROUND}|HOLE#01`)).toMatchObject({ type: "holeEvents", hole: 1, wolf, updatedBy: "u_3" });
    expect(writes().map((w) => w.name)).toEqual(["UpdateCommand"]);
    expect(await service.getRound("u_1", ROUND)).toEqual(round);
  });

  it("scores the hole through the engine once the scores and the choice are in", async () => {
    const { service, scoreHole } = await setup();
    await scoreHole(1, [4, 5, 5, 5]);
    expect((await service.getRound("u_1", ROUND)).state.wolf!.holes[0]).toMatchObject({ status: "pending", net: { u_1: 4, u_2: 5, u_3: 5, u_4: 5 } });
    const round = await service.putHoleEvents("u_1", ROUND, "1", { wolf: partner("u_2") });
    expect(round.state.wolf!.holes[0]).toMatchObject({
      wolfUserId: "u_1",
      status: "won_by_wolf_side",
      wolfSide: ["u_1", "u_2"],
      opponents: ["u_3", "u_4"],
      wolfSideNet: 4,
      opponentsNet: 5,
      points: { u_1: 2, u_2: 2, u_3: 0, u_4: 0 },
    });
    // 2 points each of 4 in total: 100 * (8 - 4) and 100 * (0 - 4).
    expect(round.state.wolf!.deltas).toEqual({ u_1: 400, u_2: 400, u_3: -400, u_4: -400 });
    expect((await service.recompute("u_2", ROUND)).wolf).toEqual(round.state.wolf);
  });

  it("replaces the record as a whole and clears it with null", async () => {
    const { service } = await setup();
    await service.putHoleEvents("u_1", ROUND, "1", { wolf: partner("u_2") });
    const lone = await service.putHoleEvents("u_2", ROUND, "1", { wolf: LONE });
    expect(lone.holes[0]!.wolf).toEqual({ choice: "lone", partnerUserId: null, wolfUserId: null });
    const cleared = await service.putHoleEvents("u_2", ROUND, "1", { wolf: null });
    expect(cleared.holes).toEqual([{ hole: 1, wadMakers: [], greenieWinner: null }]);
    expect(cleared.state.wolf!.holes[0]).toMatchObject({ status: "pending", choice: null });
  });

  it("leaves the hole's other events as they are", async () => {
    const { service } = await setup({ games: { ...WOLF, wad: {}, greenies: {} } });
    await service.putHoleEvents("u_1", ROUND, "3", { wadMakers: ["u_2"], greenieWinner: "u_4" });
    const round = await service.putHoleEvents("u_2", ROUND, "3", { wolf: LONE });
    expect(round.holes).toEqual([{ hole: 3, wadMakers: ["u_2"], greenieWinner: "u_4", wolf: { choice: "lone", partnerUserId: null, wolfUserId: null } }]);
    const after = await service.putHoleEvents("u_2", ROUND, "3", { wadMakers: [] });
    expect(after.holes[0]).toMatchObject({ wadMakers: [], greenieWinner: "u_4", wolf: { choice: "lone" } });
  });

  it("accepts a recorded wolf that agrees with the rotation, and a guest as the partner", async () => {
    const { service } = await setup({ members: ["u_2", "u_3"] });
    const { player } = await service.addGuest("u_1", ROUND, { displayName: "Pat", handicapIndex: 10 });
    const round = await service.putHoleEvents("u_1", ROUND, "2", { wolf: { choice: "partner", partnerUserId: player.userId, wolfUserId: "u_2" } });
    expect(round.state.wolf!.holes[1]).toMatchObject({ wolfUserId: "u_2", partnerUserId: player.userId, status: "pending", invalidReason: null });
  });

  it.each([
    ["a wolf that is not an object", "1", { wolf: "lone" }, "invalid_body"],
    ["a wolf that is a list", "1", { wolf: [] }, "invalid_body"],
    ["an empty wolf", "1", { wolf: {} }, "invalid_body"],
    ["a wolf of nulls", "1", { wolf: { choice: null, partnerUserId: null, wolfUserId: null } }, "invalid_body"],
    ["a choice that is not partner or lone", "1", { wolf: { choice: "blind" } }, "invalid_body"],
    ["a partner that is not a string", "1", { wolf: { choice: "partner", partnerUserId: 2 } }, "invalid_body"],
    ["a wolf id that is not a string", "17", { wolf: { choice: "lone", wolfUserId: 2 } }, "invalid_body"],
    ["hole 19", "19", { wolf: LONE }, "invalid_hole"],
    ["a partner who is not in the round", "1", { wolf: partner("u_5") }, "unknown_player"],
    ["a wolf who is not in the round", "17", { wolf: { choice: "lone", wolfUserId: "u_5" } }, "unknown_player"],
    ["the wolf as their own partner", "1", { wolf: partner("u_1") }, "wolf_partner_is_wolf"],
    ["the wolf as their own partner on a later turn", "7", { wolf: partner("u_3") }, "wolf_partner_is_wolf"],
    ["a partner together with lone", "1", { wolf: { choice: "lone", partnerUserId: "u_2" } }, "wolf_partner_and_lone"],
    ["the partner choice without a partner", "1", { wolf: { choice: "partner" } }, "wolf_partner_missing"],
    ["a partner without a choice", "1", { wolf: { partnerUserId: "u_1" } }, "wolf_partner_is_wolf"],
    ["a wolf on hole 2 who is not the one in the rotation", "2", { wolf: { choice: "lone", wolfUserId: "u_1" } }, "wolf_wolf_contradicts_rotation"],
  ])("rejects %s", async (_name, hole, body, code) => {
    const { service, writes } = await setup();
    expect(await failure(service.putHoleEvents("u_1", ROUND, hole, body))).toEqual({ kind: "validation", code });
    expect(writes()).toEqual([]);
  });

  it("rejects a wolf on 17 who is not in last place, and one on 18 who is not among those tied", async () => {
    const { service, play, writes } = await setup();
    // After 16: u_1 17, u_2 12, u_3 8, u_4 15. u_3 is last.
    await play(16);
    expect(await failure(service.putHoleEvents("u_1", ROUND, "17", { wolf: { choice: "lone", wolfUserId: "u_2" } }))).toEqual({
      kind: "validation",
      code: "wolf_wolf_not_in_last_place",
    });
    // After 17: u_1 17, u_2 12, u_3 12, u_4 15. u_2 and u_3 are tied for last.
    await play(17, {}, 17);
    expect(await failure(service.putHoleEvents("u_1", ROUND, "18", { wolf: { choice: "lone", wolfUserId: "u_4" } }))).toEqual({
      kind: "validation",
      code: "wolf_wolf_not_in_last_place",
    });
    expect(writes()).toEqual([]);
    const round = await service.putHoleEvents("u_1", ROUND, "18", { wolf: { choice: "lone", wolfUserId: "u_3" } });
    expect(round.state.wolf!.holes[17]).toMatchObject({ wolfUserId: "u_3", lastPlace: ["u_2", "u_3"], status: "pending" });
  });

  it("rejects a wolf record in a round without wolf", async () => {
    const { service, writes } = await setup({ games: { skins: {} } });
    expect(await failure(service.putHoleEvents("u_1", ROUND, "1", { wolf: LONE }))).toEqual({ kind: "validation", code: "wolf_not_enabled" });
    expect(writes()).toEqual([]);
  });

  it("rejects a wolf record while wolf is unavailable", async () => {
    const three = await setup({ members: ["u_2", "u_3"] });
    expect(await failure(three.service.putHoleEvents("u_1", ROUND, "1", { wolf: LONE }))).toEqual({ kind: "conflict", code: "wolf_unavailable" });
    expect(three.writes()).toEqual([]);
    const unrated = await setup({ teeId: "male-unrated" });
    expect(await failure(unrated.service.putHoleEvents("u_1", ROUND, "1", { wolf: LONE }))).toEqual({ kind: "conflict", code: "wolf_unavailable" });
  });

  it("is for players of the round only", async () => {
    const { service, writes } = await setup();
    expect(await failure(service.putHoleEvents("u_5", ROUND, "1", { wolf: LONE }))).toEqual({ kind: "forbidden", code: "not_a_participant" });
    expect(writes()).toEqual([]);
  });
});

describe("settlement with wolf", () => {
  it("settles a full round of wolf", async () => {
    const { settlement, service, play, writes } = await setup();
    await play();
    const round = await service.getRound("u_1", ROUND);
    expect(round.state.wolf).toMatchObject({ complete: true, points: { u_1: 19, u_2: 14, u_3: 12, u_4: 15 }, deltas: WOLF_DELTAS });

    const s = await settlement.getSettlement("u_1", ROUND);
    expect(s.status).toBe("final");
    expect(s.incompleteHoles).toEqual([]);
    expect(s.issues).toEqual([]);
    expect(s.games).toEqual({ wolf: WOLF_DELTAS });
    expect(s.positions).toEqual(WOLF_DELTAS);
    // u_1 is owed 1600: the largest debtor u_3 pays 1200, then u_2 pays 400. u_4 is even.
    const transfers = [
      { from: "u_3", to: "u_1", amountCents: 1200 },
      { from: "u_2", to: "u_1", amountCents: 400 },
    ];
    expect(s.transfers).toEqual(transfers.map((t) => ({ ...t, transferId: transferId(ROUND, t), toVenmoHandle: null, paid: false, paidAt: null, paidBy: null })));
    expect(s.skinsCarryover).toBeNull();
    expect(writes()).toEqual([]);
  });

  it("adds wolf to the other games in one settlement", async () => {
    const { settlement, play } = await setup({ games: { ...WOLF, skins: { baseCents: 500 }, wad: {}, greenies: {} } });
    await play();
    const s = await settlement.getSettlement("u_1", ROUND);
    expect(s.status).toBe("final");
    expect(s.games.wolf).toEqual(WOLF_DELTAS);
    const zero = { u_1: 0, u_2: 0, u_3: 0, u_4: 0 };
    expect(s.games.wad).toEqual(zero);
    expect(s.games.greenies).toEqual(zero);
    for (const id of ["u_1", "u_2", "u_3", "u_4"] as const) expect(s.positions[id]).toBe(s.games.skins![id]! + WOLF_DELTAS[id]);
    expect(Object.values(s.positions).reduce((a, b) => a + b, 0)).toBe(0);
  });

  it("uses the point value of the round", async () => {
    const { settlement, play } = await setup({ games: { wolf: { pointCents: 25 } } });
    await play();
    expect((await settlement.getSettlement("u_1", ROUND)).games.wolf).toEqual({ u_1: 400, u_2: -100, u_3: -300, u_4: 0 });
  });

  it("reports wolf as unavailable without four players and leaves it out of the positions", async () => {
    const { settlement, service } = await setup({ members: ["u_2", "u_3"] });
    for (let hole = 1; hole <= 18; hole++) for (const id of ["u_1", "u_2", "u_3"]) await service.putScore(id, ROUND, { hole, gross: 4 });
    const s = await settlement.getSettlement("u_1", ROUND);
    expect(s.status).toBe("provisional");
    expect(s.incompleteHoles).toEqual([]);
    expect(s.issues).toEqual([{ code: "wolf_unavailable", hole: null, userId: null, message: expect.stringContaining("four players") }]);
    expect(s.games).toEqual({ wolf: null });
    expect(s.positions).toEqual({ u_1: 0, u_2: 0, u_3: 0 });
    expect(s.transfers).toEqual([]);
  });

  it("is not final while a tie for last place leaves a hole without its wolf", async () => {
    const { settlement, play } = await setup();
    // Hole 18 has its choice and no recorded wolf; u_2 and u_3 are tied for last.
    await play(18, { 18: partner("u_1") });
    const s = await settlement.getSettlement("u_1", ROUND);
    expect(s.status).toBe("provisional");
    expect(s.incompleteHoles).toEqual([]);
    expect(s.issues).toEqual([{ code: "wolf_needs_wolf", hole: 18, userId: null, message: expect.stringContaining("hole 18") }]);
    // Hole 18 pays nothing. After 17: 17, 12, 12, 15 of 56 points.
    expect(s.games.wolf).toEqual({ u_1: 1200, u_2: -800, u_3: -800, u_4: 400 });
    const transfer = s.transfers[0]!;
    expect(await failure(settlement.markPaid(transfer.to, ROUND, transfer.transferId))).toEqual({ kind: "conflict", code: "settlement_has_issues" });
  });

  it("is not final while a hole waits for the wolf's choice, which also holds back 17 and 18", async () => {
    const { settlement, play } = await setup();
    await play(18, { 9: null });
    const s = await settlement.getSettlement("u_1", ROUND);
    expect(s.status).toBe("provisional");
    expect(s.incompleteHoles).toEqual([]);
    expect(s.issues.map((i) => [i.code, i.hole, i.userId])).toEqual([
      ["wolf_pending", 9, "u_1"],
      ["wolf_pending", 17, null],
      ["wolf_pending", 18, null],
    ]);
    // Without holes 9, 17 and 18: u_1 17 - 4 = 13, u_2 12, u_3 8, u_4 15, 48 points in total.
    expect(s.games.wolf).toEqual({ u_1: 400, u_2: 0, u_3: -1600, u_4: 1200 });
  });

  it("lists a hole that is missing a score as incomplete, not as a wolf issue", async () => {
    const { settlement, service, play } = await setup();
    await play();
    await service.putScore("u_4", ROUND, { hole: 12, gross: null });
    const s = await settlement.getSettlement("u_1", ROUND);
    expect(s.status).toBe("provisional");
    expect(s.incompleteHoles).toEqual([12]);
    // 17 and 18 have their scores and wait for hole 12.
    expect(s.issues.map((i) => [i.code, i.hole])).toEqual([
      ["wolf_pending", 17],
      ["wolf_pending", 18],
    ]);
  });

  it("reports a wolf record that a later score made invalid, and does not pay the hole", async () => {
    const { settlement, service, play } = await setup();
    // u_3 is recorded as the wolf on 17, which is right while u_3 is last after 16.
    await play(18, { 17: { choice: "lone", wolfUserId: "u_3" } });
    expect((await settlement.getSettlement("u_1", ROUND)).status).toBe("final");

    // Hole 14 is corrected: u_2 made 5, not 3, so u_2 alone loses 5 to 4. u_2 loses the 4 points
    // and u_1, u_3 and u_4 get 1 each. After 16: u_1 18, u_2 8, u_3 9, u_4 16. u_2 is last now.
    await service.putScore("u_2", ROUND, { hole: 14, gross: 5 });
    const round = await service.getRound("u_1", ROUND);
    expect(round.state.wolf!.holes[16]).toMatchObject({
      status: "invalid",
      invalidReason: "wolf_not_in_last_place",
      wolfUserId: null,
      lastPlace: ["u_2"],
      points: { u_1: 0, u_2: 0, u_3: 0, u_4: 0 },
    });
    expect(round.state.wolf!.points).toEqual({ u_1: 18, u_2: 8, u_3: 9, u_4: 16 });

    const s = await settlement.getSettlement("u_1", ROUND);
    expect(s.status).toBe("provisional");
    expect(s.incompleteHoles).toEqual([]);
    expect(s.issues.map((i) => [i.code, i.hole])).toEqual([
      ["wolf_invalid", 17],
      ["wolf_pending", 18],
    ]);
    expect(s.issues[0]!.message).toContain("wolf_not_in_last_place");
    // Holes 17 and 18 pay nothing. 51 points: 100 * (72 - 51), 100 * (32 - 51), 100 * (36 - 51), 100 * (64 - 51).
    expect(s.games.wolf).toEqual({ u_1: 2100, u_2: -1900, u_3: -1500, u_4: 1300 });
  });
});
