import { describe, expect, it } from "vitest";
import { RoundError } from "../../../src/services/rounds/errors.js";
import { RoundService } from "../../../src/services/rounds/roundService.js";
import { DynamoRoundStore } from "../../../src/services/rounds/roundStore.js";
import { SettlementService, transferId } from "../../../src/services/rounds/settlementService.js";
import type { Round } from "../../../src/shared/rounds.js";
import { course, courseItem, fakeDb, NOW, profileItem, TABLE } from "./fixtures.js";

// Everyone has index 10. On the Blue tee (rating 72.1, slope 131, par 72) the
// computed course handicap is round(10 * 131 / 113 + 0.1) = round(11.69) = 12.
// The Unrated tee has no rating and slope, so nothing is computed there.
const profiles = ["u_1", "u_2", "u_3", "u_4", "u_5"].map((id) => profileItem(id, id, 10));

const ROUND = "r_id1";
const UNRATED = "male-unrated";
const WRITES = ["PutCommand", "DeleteCommand", "UpdateCommand", "TransactWriteCommand"];
const PAID_AT = "2026-10-03T20:00:00.000Z";

// Stroke indexes of holes 1 to 18 are 7 11 17 3 1 15 9 5 13 / 8 18 2 10 6 12 16 4 14,
// so the 8 hardest holes (stroke index 1 to 8) are 5, 12, 4, 17, 8, 14, 1 and 10.
const EIGHT_HARDEST = { 1: 1, 4: 1, 5: 1, 8: 1, 10: 1, 12: 1, 14: 1, 17: 1 };

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
  const settlement = new SettlementService(store, { now: () => new Date(PAID_AT) });
  const members = options.members ?? ["u_2"];
  const games = options.games ?? { skins: { baseCents: 500 } };
  await service.createRound("u_1", { courseId: course.courseId, teeId: options.teeId ?? "male-blue", date: "2026-10-03", holes: 18, games });
  for (const member of members) await service.joinRound(member, { joinCode: "ABCD2F" });
  fake.sent.length = 0;
  const writes = () => fake.sent.filter((s) => WRITES.includes(s.name));
  const playerItem = (userId: string) => fake.items.get(`ROUND#${ROUND}|PLAYER#${userId}`);
  return { ...fake, service, settlement, writes, playerItem };
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

const player = (round: Round, userId: string) => {
  const found = round.players.find((p) => p.userId === userId);
  if (!found) throw new Error(`no player ${userId}`);
  return found;
};

const handicaps = (round: Round) => round.players.map((p) => [p.userId, p.courseHandicap, p.courseHandicapOverride]);

describe("RoundService.putHandicapOverride", () => {
  it("replaces the computed course handicap for the round and keeps the computed value stored", async () => {
    const { service, writes, playerItem } = await setup();
    const before = playerItem("u_1")!;
    const round = await service.putHandicapOverride("u_1", ROUND, "u_1", { courseHandicap: 15 });

    expect(handicaps(round)).toEqual([
      ["u_1", 15, 15],
      ["u_2", 12, null],
    ]);
    expect(writes().map((w) => w.name)).toEqual(["UpdateCommand"]);
    expect(writes()[0]!.input.ConditionExpression).toBe("attribute_exists(PK)");
    expect(playerItem("u_1")).toEqual({
      ...before,
      courseHandicap: 12,
      courseHandicapOverride: 15,
      courseHandicapOverrideAt: expect.any(String),
      courseHandicapOverrideBy: "u_1",
    });
    expect(await service.getRound("u_2", ROUND)).toEqual(round);
  });

  it("lets any player set the override of any other player", async () => {
    const { service, playerItem } = await setup({ members: ["u_2", "u_3"] });
    const round = await service.putHandicapOverride("u_3", ROUND, "u_1", { courseHandicap: 9 });
    expect(handicaps(round)).toEqual([
      ["u_1", 9, 9],
      ["u_2", 12, null],
      ["u_3", 12, null],
    ]);
    expect(playerItem("u_1")).toMatchObject({ courseHandicapOverrideBy: "u_3" });
  });

  it("lets any player set a guest's override", async () => {
    const { service } = await setup();
    const { player: guest } = await service.addGuest("u_1", ROUND, { displayName: "Pat", handicapIndex: 20 });
    expect(guest).toMatchObject({ courseHandicap: 23, courseHandicapOverride: null });
    const round = await service.putHandicapOverride("u_2", ROUND, guest.userId, { courseHandicap: 18 });
    expect(player(round, guest.userId)).toMatchObject({ handicapIndex: 20, courseHandicap: 18, courseHandicapOverride: 18, guest: true });
  });

  it("clears the override with null and falls back to the computed course handicap", async () => {
    const { service, playerItem } = await setup();
    const original = await service.getRound("u_1", ROUND);
    await service.putHandicapOverride("u_1", ROUND, "u_2", { courseHandicap: 3 });
    const cleared = await service.putHandicapOverride("u_2", ROUND, "u_2", { courseHandicap: null });
    expect(cleared).toEqual(original);
    expect(player(cleared, "u_2")).toMatchObject({ courseHandicap: 12, courseHandicapOverride: null });
    expect(playerItem("u_2")).toMatchObject({ courseHandicap: 12, courseHandicapOverride: null });
  });

  it("falls back to no course handicap when the override is cleared on an unrated tee", async () => {
    const { service } = await setup({ teeId: UNRATED });
    const set = await service.putHandicapOverride("u_1", ROUND, "u_1", { courseHandicap: 15 });
    expect(player(set, "u_1")).toMatchObject({ courseHandicap: 15, courseHandicapOverride: 15 });
    const cleared = await service.putHandicapOverride("u_1", ROUND, "u_1", { courseHandicap: null });
    expect(player(cleared, "u_1")).toMatchObject({ courseHandicap: null, courseHandicapOverride: null, ticksByHole: null });
  });

  it("is idempotent: writing the same override or clearing twice changes nothing", async () => {
    const { service, writes } = await setup();
    const first = await service.putHandicapOverride("u_1", ROUND, "u_2", { courseHandicap: 20 });
    const again = await service.putHandicapOverride("u_2", ROUND, "u_2", { courseHandicap: 20 });
    expect(again).toEqual(first);

    const cleared = await service.putHandicapOverride("u_1", ROUND, "u_2", { courseHandicap: null });
    expect(await service.putHandicapOverride("u_1", ROUND, "u_2", { courseHandicap: null })).toEqual(cleared);
    // Clearing a player who never had an override is a no-op as well.
    expect(await service.putHandicapOverride("u_1", ROUND, "u_1", { courseHandicap: null })).toEqual(cleared);
    expect(writes().map((w) => w.name)).toEqual(Array(5).fill("UpdateCommand"));
  });

  it("keeps the last write", async () => {
    const { service } = await setup();
    await service.putHandicapOverride("u_1", ROUND, "u_2", { courseHandicap: 20 });
    const round = await service.putHandicapOverride("u_2", ROUND, "u_2", { courseHandicap: 8 });
    expect(player(round, "u_2")).toMatchObject({ courseHandicap: 8, courseHandicapOverride: 8 });
  });

  it.each([-10, -3, 0, 54])("accepts %i", async (courseHandicap) => {
    const { service } = await setup();
    const round = await service.putHandicapOverride("u_1", ROUND, "u_1", { courseHandicap });
    expect(player(round, "u_1")).toMatchObject({ courseHandicap, courseHandicapOverride: courseHandicap });
  });

  it("stores negative zero as zero", async () => {
    const { service, playerItem } = await setup();
    await service.putHandicapOverride("u_1", ROUND, "u_1", { courseHandicap: -0 });
    expect(Object.is(playerItem("u_1")!.courseHandicapOverride, 0)).toBe(true);
  });

  it.each([
    ["a body that is not an object", [], "invalid_body"],
    ["a null body", null, "invalid_body"],
    ["a missing courseHandicap", {}, "invalid_body"],
    ["a fraction", { courseHandicap: 7.5 }, "invalid_course_handicap"],
    ["a string", { courseHandicap: "7" }, "invalid_course_handicap"],
    ["a boolean", { courseHandicap: true }, "invalid_course_handicap"],
    ["a value below the range", { courseHandicap: -11 }, "invalid_course_handicap"],
    ["a value above the range", { courseHandicap: 55 }, "invalid_course_handicap"],
    ["a value that is not a number", { courseHandicap: Number.NaN }, "invalid_course_handicap"],
    ["infinity", { courseHandicap: Number.POSITIVE_INFINITY }, "invalid_course_handicap"],
  ])("rejects %s", async (_name, body, code) => {
    const { service, sent } = await setup();
    expect(await failure(service.putHandicapOverride("u_1", ROUND, "u_1", body))).toEqual({ kind: "validation", code });
    expect(sent).toEqual([]);
  });

  it("is for players of the round only", async () => {
    const { service, writes } = await setup();
    const body = { courseHandicap: 15 };
    expect(await failure(service.putHandicapOverride("u_5", ROUND, "u_1", body))).toEqual({ kind: "forbidden", code: "not_a_participant" });
    // Not even for their own handicap.
    expect(await failure(service.putHandicapOverride("u_5", ROUND, "u_5", body))).toEqual({ kind: "forbidden", code: "not_a_participant" });
    expect(await failure(service.putHandicapOverride("u_1", "r_other", "u_1", body))).toEqual({ kind: "not_found", code: "round_not_found" });
    expect(await failure(service.putHandicapOverride("u_1", "", "u_1", body))).toEqual({ kind: "not_found", code: "round_not_found" });
    expect(writes()).toEqual([]);
  });

  it("rejects a player who is not in the round and creates no item for them", async () => {
    const { service, writes, items } = await setup();
    for (const userId of ["u_5", "guest_unknown", "", undefined]) {
      expect(await failure(service.putHandicapOverride("u_1", ROUND, userId, { courseHandicap: 15 }))).toEqual({
        kind: "validation",
        code: "unknown_player",
      });
    }
    expect(writes()).toEqual([]);
    expect(items.has(`ROUND#${ROUND}|PLAYER#u_5`)).toBe(false);
  });

  it("rejects a player whose item is gone by the time of the write", async () => {
    const fake = fakeDb([courseItem, ...profiles]);
    const inner = new DynamoRoundStore(fake.db, TABLE, () => NOW);
    const store = Object.assign(Object.create(inner) as DynamoRoundStore, {
      setCourseHandicapOverride: async () => "player_not_found" as const,
    });
    const service = new RoundService(store, { newId: () => "id1", newJoinCode: () => "ABCD2F" });
    await service.createRound("u_1", { courseId: course.courseId, teeId: "male-blue", date: "2026-10-03", holes: 18, games: {} });
    expect(await failure(service.putHandicapOverride("u_1", ROUND, "u_1", { courseHandicap: 15 }))).toEqual({
      kind: "validation",
      code: "unknown_player",
    });
  });
});

describe("the effective course handicap", () => {
  it("allocates ticks from overrides on an unrated tee: 15 against 7 gives 8 ticks on the 8 hardest holes", async () => {
    const { service } = await setup({ teeId: UNRATED });
    const one = await service.putHandicapOverride("u_1", ROUND, "u_1", { courseHandicap: 15 });
    // Ticks are relative to the lowest handicap, so they wait for every player.
    expect(one.players.map((p) => p.ticksByHole)).toEqual([null, null]);

    const round = await service.putHandicapOverride("u_1", ROUND, "u_2", { courseHandicap: 7 });
    expect(handicaps(round)).toEqual([
      ["u_1", 15, 15],
      ["u_2", 7, 7],
    ]);
    expect(player(round, "u_1").ticksByHole).toEqual(EIGHT_HARDEST);
    expect(player(round, "u_2").ticksByHole).toEqual({});
  });

  it("allocates ticks from the override instead of the computed value on a rated tee", async () => {
    const { service } = await setup();
    const before = await service.getRound("u_1", ROUND);
    expect(before.players.map((p) => p.ticksByHole)).toEqual([{}, {}]);

    // u_1 plays off 20 against the computed 12 of u_2: 8 ticks.
    const round = await service.putHandicapOverride("u_2", ROUND, "u_1", { courseHandicap: 20 });
    expect(player(round, "u_1").ticksByHole).toEqual(EIGHT_HARDEST);
    expect(player(round, "u_2").ticksByHole).toEqual({});

    const cleared = await service.putHandicapOverride("u_2", ROUND, "u_1", { courseHandicap: null });
    expect(cleared.players.map((p) => p.ticksByHole)).toEqual([{}, {}]);
  });

  it("makes skins available once the last player has an override", async () => {
    const { service } = await setup({ teeId: UNRATED, members: ["u_2", "u_3"] });
    expect((await service.getRound("u_1", ROUND)).state.skins).toBeNull();
    expect((await service.putHandicapOverride("u_1", ROUND, "u_1", { courseHandicap: 15 })).state.skins).toBeNull();
    expect((await service.putHandicapOverride("u_1", ROUND, "u_2", { courseHandicap: 7 })).state.skins).toBeNull();
    expect(await service.recompute("u_1", ROUND)).toEqual({ skins: null });

    const round = await service.putHandicapOverride("u_1", ROUND, "u_3", { courseHandicap: 7 });
    expect(round.state.skins).toMatchObject({ complete: false, carryOutCents: 0, deltas: { u_1: 0, u_2: 0, u_3: 0 } });
    expect(round.state.skins!.holes).toHaveLength(18);
    expect(await service.recompute("u_2", ROUND)).toEqual(round.state);

    // Clearing one takes skins away again.
    expect((await service.putHandicapOverride("u_3", ROUND, "u_2", { courseHandicap: null })).state.skins).toBeNull();
  });

  it("uses the ticks in the skins net scores", async () => {
    const { service } = await setup({ teeId: UNRATED });
    await service.putHandicapOverride("u_1", ROUND, "u_1", { courseHandicap: 15 });
    await service.putHandicapOverride("u_1", ROUND, "u_2", { courseHandicap: 7 });
    // Hole 1 has stroke index 7: u_1 gets a tick and wins with a net 4 against a 5.
    await service.putScore("u_1", ROUND, { hole: 1, gross: 5 });
    const round = await service.putScore("u_2", ROUND, { hole: 1, gross: 5 });
    expect(round.state.skins!.holes[0]).toMatchObject({ hole: 1, status: "won", winnerUserId: "u_1", net: { u_1: 4, u_2: 5 } });
    expect(round.state.skins!.deltas).toEqual({ u_1: 500, u_2: -500 });
  });
});

describe("settlement with handicap overrides", () => {
  // Both players score 4 on every hole, except that u_1 scores 5 on hole 5.
  async function played() {
    const s = await setup({ teeId: UNRATED });
    for (let hole = 1; hole <= 18; hole++) {
      await s.service.putScore("u_1", ROUND, { hole, gross: hole === 5 ? 5 : 4 });
      await s.service.putScore("u_2", ROUND, { hole, gross: 4 });
    }
    return s;
  }

  it("drops the skins_unavailable issue and becomes final once every player has an override", async () => {
    const { service, settlement } = await played();
    const without = await settlement.getSettlement("u_1", ROUND);
    expect(without).toMatchObject({ status: "provisional", incompleteHoles: [], games: { skins: null }, skinsCarryover: null, transfers: [] });
    expect(without.issues.map((i) => i.code)).toEqual(["skins_unavailable"]);

    await service.putHandicapOverride("u_1", ROUND, "u_1", { courseHandicap: 7 });
    expect((await settlement.getSettlement("u_1", ROUND)).issues.map((i) => i.code)).toEqual(["skins_unavailable"]);

    // Equal handicaps, no ticks. Holes 1 to 4 push and carry 2000, so hole 5 is
    // worth 2500 and u_2 wins it. Holes 6 to 18 push: 13 * 500 is left unresolved.
    await service.putHandicapOverride("u_1", ROUND, "u_2", { courseHandicap: 7 });
    const s = await settlement.getSettlement("u_2", ROUND);
    expect(s.status).toBe("final");
    expect(s.issues).toEqual([]);
    expect(s.games).toEqual({ skins: { u_1: -2500, u_2: 2500 } });
    expect(s.positions).toEqual({ u_1: -2500, u_2: 2500 });
    expect(s.transfers).toEqual([
      {
        transferId: transferId(ROUND, { from: "u_1", to: "u_2", amountCents: 2500 }),
        from: "u_1",
        to: "u_2",
        amountCents: 2500,
        toVenmoHandle: null,
        paid: false,
        paidAt: null,
        paidBy: null,
      },
    ]);
    expect(s.skinsCarryover).toEqual({ amountCents: 6500, unresolved: true });

    const marked = await settlement.markPaid("u_1", ROUND, s.transfers[0]!.transferId);
    expect(marked.transfers[0]).toMatchObject({ paid: true, paidBy: "u_1" });
  });

  it("changes the skins results when a handicap is overridden after the scores, and leaves a paid marker stale", async () => {
    const { service, settlement, items } = await played();
    await service.putHandicapOverride("u_1", ROUND, "u_1", { courseHandicap: 7 });
    await service.putHandicapOverride("u_1", ROUND, "u_2", { courseHandicap: 7 });
    const id = transferId(ROUND, { from: "u_1", to: "u_2", amountCents: 2500 });
    await settlement.markPaid("u_2", ROUND, id);

    // u_1 now plays off 15 against 7: a tick on holes 1, 4, 5, 8, 10, 12, 14 and 17.
    //   hole  value  result
    //    1     500   u_1 nets 3 and wins
    //    4    1500   u_1 wins, after 2 and 3 pushed
    //    5     500   u_1 nets 4 against 4: push
    //    8    2000   u_1 wins, after 5, 6 and 7 pushed
    //   10    1000   u_1 wins, after 9 pushed
    //   12    1000   u_1 wins, after 11 pushed
    //   14    1000   u_1 wins, after 13 pushed
    //   17    1500   u_1 wins, after 15 and 16 pushed
    //   18     500   push, left unresolved
    // u_1 collects 500 + 1500 + 2000 + 1000 + 1000 + 1000 + 1500 = 8500.
    const round = await service.putHandicapOverride("u_2", ROUND, "u_1", { courseHandicap: 15 });
    expect(round.state.skins!.deltas).toEqual({ u_1: 8500, u_2: -8500 });
    expect(round.state.skins!.holes.filter((h) => h.status === "won").map((h) => [h.hole, h.winnerUserId, h.atStakeCents])).toEqual([
      [1, "u_1", 500],
      [4, "u_1", 1500],
      [8, "u_1", 2000],
      [10, "u_1", 1000],
      [12, "u_1", 1000],
      [14, "u_1", 1000],
      [17, "u_1", 1500],
    ]);
    expect(round.scores).toHaveLength(36);

    const s = await settlement.getSettlement("u_1", ROUND);
    expect(s.status).toBe("final");
    expect(s.positions).toEqual({ u_1: 8500, u_2: -8500 });
    expect(s.skinsCarryover).toEqual({ amountCents: 500, unresolved: true });
    expect(s.transfers.map(({ from, to, amountCents, paid, paidAt, paidBy }) => ({ from, to, amountCents, paid, paidAt, paidBy }))).toEqual([
      { from: "u_2", to: "u_1", amountCents: 8500, paid: false, paidAt: null, paidBy: null },
    ]);
    expect(s.transfers.map((t) => t.transferId)).not.toContain(id);
    expect(s.stalePayments).toEqual([{ transferId: id, from: "u_1", to: "u_2", amountCents: 2500, paidAt: PAID_AT, paidBy: "u_2" }]);
    expect(items.has(`ROUND#${ROUND}|SETTLEMENT#PAID#${id}`)).toBe(true);
    expect(await failure(settlement.markPaid("u_2", ROUND, id))).toEqual({ kind: "not_found", code: "transfer_not_found" });

    // Putting the handicap back gives the paid transfer back, still paid.
    await service.putHandicapOverride("u_1", ROUND, "u_1", { courseHandicap: 7 });
    const restored = await settlement.getSettlement("u_1", ROUND);
    expect(restored.transfers).toEqual([expect.objectContaining({ transferId: id, amountCents: 2500, paid: true, paidBy: "u_2" })]);
    expect(restored.stalePayments).toEqual([]);
  });

  it("reports skins as unavailable again when an override is cleared on an unrated tee", async () => {
    const { service, settlement } = await played();
    await service.putHandicapOverride("u_1", ROUND, "u_1", { courseHandicap: 7 });
    await service.putHandicapOverride("u_1", ROUND, "u_2", { courseHandicap: 7 });
    await service.putHandicapOverride("u_1", ROUND, "u_2", { courseHandicap: null });
    const s = await settlement.getSettlement("u_1", ROUND);
    expect(s.status).toBe("provisional");
    expect(s.issues.map((i) => i.code)).toEqual(["skins_unavailable"]);
    expect(s.positions).toEqual({ u_1: 0, u_2: 0 });
  });

  it("does not change wad or greenies", async () => {
    const games = { wad: { startCents: 700, stepCents: 200 }, greenies: { amountCents: 500 } };
    const { service, settlement } = await setup({ games });
    for (let hole = 1; hole <= 18; hole++) {
      for (const userId of ["u_1", "u_2"]) await service.putScore(userId, ROUND, { hole, gross: 3 });
    }
    await service.putHoleEvents("u_1", ROUND, "2", { wadMakers: ["u_1"] });
    await service.putHoleEvents("u_1", ROUND, "3", { greenieWinner: "u_2" });
    const before = await settlement.getSettlement("u_1", ROUND);
    await service.putHandicapOverride("u_1", ROUND, "u_1", { courseHandicap: 30 });
    expect(await settlement.getSettlement("u_1", ROUND)).toEqual(before);
    expect(before.positions).toEqual({ u_1: 200, u_2: -200 });
  });
});
