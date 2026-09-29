import { describe, expect, it } from "vitest";
import { RoundError } from "../../../src/services/rounds/errors.js";
import { RoundService } from "../../../src/services/rounds/roundService.js";
import { DynamoRoundStore } from "../../../src/services/rounds/roundStore.js";
import type { Round } from "../../../src/shared/rounds.js";
import { course, courseItem, fakeDb, NOW, profileItem, TABLE } from "./fixtures.js";

// Everyone has the same handicap, so nobody gets ticks and net equals gross.
const profiles = ["u_1", "u_2", "u_3", "u_4", "u_5"].map((id) => profileItem(id, id, 10));

const ROUND = "r_id1";
const GAMES = { skins: { baseCents: 500 }, wad: { startCents: 700, stepCents: 200 }, greenies: { amountCents: 500 } };
const WRITES = ["PutCommand", "DeleteCommand", "UpdateCommand", "TransactWriteCommand"];

/** A round created by u_1 with the given other members, then the write log cleared. */
async function setup(options: { members?: string[]; games?: object; teeId?: string } = {}) {
  const fake = fakeDb([courseItem, ...profiles]);
  let ids = 0;
  let minutes = 0;
  const service = new RoundService(new DynamoRoundStore(fake.db, TABLE, () => NOW), {
    now: () => new Date(NOW.getTime() + minutes++ * 60_000),
    newId: () => `id${++ids}`,
    newJoinCode: () => "ABCD2F",
  });
  const body = { courseId: course.courseId, teeId: options.teeId ?? "male-blue", date: "2026-10-03", holes: 18, games: options.games ?? GAMES };
  await service.createRound("u_1", body);
  for (const member of options.members ?? ["u_2", "u_3", "u_4"]) await service.joinRound(member, { joinCode: "ABCD2F" });
  fake.sent.length = 0;
  const writes = () => fake.sent.filter((s) => WRITES.includes(s.name));
  /** Each player sets their own score on the hole; `gross` is in player order. */
  const scoreHole = async (hole: number, gross: number[]) => {
    const players = ["u_1", ...(options.members ?? ["u_2", "u_3", "u_4"])];
    let round: Round | undefined;
    for (const [i, g] of gross.entries()) round = await service.putScore(players[i]!, ROUND, { hole, gross: g });
    return round!;
  };
  return { ...fake, service, writes, scoreHole };
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

describe("RoundService.putScore", () => {
  it("stores the caller's own score and returns the round", async () => {
    const { service, items, writes } = await setup();
    const round = await service.putScore("u_2", ROUND, { hole: 4, gross: 5 });
    expect(round.scores).toEqual([{ userId: "u_2", hole: 4, gross: 5 }]);
    expect(items.get(`ROUND#${ROUND}|SCORE#04#u_2`)).toMatchObject({ type: "score", userId: "u_2", hole: 4, gross: 5, updatedBy: "u_2" });
    expect(writes().map((w) => w.name)).toEqual(["PutCommand"]);
    expect(writes()[0]!.input.ConditionExpression).toBeUndefined();
    expect(await service.getRound("u_1", ROUND)).toEqual(round);
  });

  it("accepts the caller's own id as userId", async () => {
    const { service } = await setup();
    const round = await service.putScore("u_2", ROUND, { hole: 18, gross: 1, userId: "u_2" });
    expect(round.scores).toEqual([{ userId: "u_2", hole: 18, gross: 1 }]);
  });

  it("lets any player score for a guest", async () => {
    const { service, items } = await setup({ members: ["u_2"] });
    const { player } = await service.addGuest("u_1", ROUND, { displayName: "Pat", handicapIndex: 10 });
    const round = await service.putScore("u_2", ROUND, { hole: 1, gross: 6, userId: player.userId });
    expect(round.scores).toEqual([{ userId: player.userId, hole: 1, gross: 6 }]);
    expect(items.get(`ROUND#${ROUND}|SCORE#01#${player.userId}`)).toMatchObject({ gross: 6, updatedBy: "u_2" });
  });

  it("does not let a player set another member's score", async () => {
    const { service, writes } = await setup();
    await service.putScore("u_2", ROUND, { hole: 1, gross: 4 });
    const before = writes().length;
    expect(await failure(service.putScore("u_1", ROUND, { hole: 1, gross: 9, userId: "u_2" }))).toEqual({ kind: "forbidden", code: "not_score_owner" });
    expect(await failure(service.putScore("u_1", ROUND, { hole: 1, gross: null, userId: "u_2" }))).toEqual({ kind: "forbidden", code: "not_score_owner" });
    expect(writes()).toHaveLength(before);
    expect((await service.getRound("u_1", ROUND)).scores).toEqual([{ userId: "u_2", hole: 1, gross: 4 }]);
  });

  it("is for players of the round only", async () => {
    const { service, writes } = await setup();
    expect(await failure(service.putScore("u_5", ROUND, { hole: 1, gross: 4 }))).toEqual({ kind: "forbidden", code: "not_a_participant" });
    expect(await failure(service.putScore("u_5", ROUND, { hole: 1, gross: 4, userId: "u_1" }))).toEqual({ kind: "forbidden", code: "not_a_participant" });
    expect(await failure(service.putScore("u_1", "r_missing", { hole: 1, gross: 4 }))).toEqual({ kind: "not_found", code: "round_not_found" });
    expect(writes()).toEqual([]);
  });

  it.each([
    ["hole 0", { hole: 0, gross: 4 }, "invalid_hole"],
    ["hole 19", { hole: 19, gross: 4 }, "invalid_hole"],
    ["a fractional hole", { hole: 1.5, gross: 4 }, "invalid_hole"],
    ["a string hole", { hole: "4", gross: 4 }, "invalid_hole"],
    ["no hole", { gross: 4 }, "invalid_hole"],
    ["a gross of 0", { hole: 1, gross: 0 }, "invalid_gross"],
    ["a negative gross", { hole: 1, gross: -1 }, "invalid_gross"],
    ["a gross over the bound", { hole: 1, gross: 21 }, "invalid_gross"],
    ["a fractional gross", { hole: 1, gross: 4.5 }, "invalid_gross"],
    ["a string gross", { hole: 1, gross: "4" }, "invalid_gross"],
    ["a gross that is not a number", { hole: 1, gross: Number.NaN }, "invalid_gross"],
    ["no gross", { hole: 1 }, "invalid_body"],
    ["a userId that is not a string", { hole: 1, gross: 4, userId: 7 }, "invalid_body"],
    ["an empty userId", { hole: 1, gross: 4, userId: "" }, "invalid_body"],
    ["a list as the body", [{ hole: 1, gross: 4 }], "invalid_body"],
    ["a null body", null, "invalid_body"],
    ["a player who is not in the round", { hole: 1, gross: 4, userId: "u_5" }, "unknown_player"],
  ])("rejects %s", async (_name, body, code) => {
    const { service, writes } = await setup();
    expect(await failure(service.putScore("u_1", ROUND, body))).toEqual({ kind: "validation", code });
    expect(writes()).toEqual([]);
  });

  it("accepts the highest and lowest gross", async () => {
    const { service } = await setup();
    await service.putScore("u_1", ROUND, { hole: 1, gross: 1 });
    const round = await service.putScore("u_1", ROUND, { hole: 2, gross: 20 });
    expect(round.scores.map((s) => s.gross)).toEqual([1, 20]);
  });

  it("gives the same round when the same score is written again", async () => {
    const { service, items } = await setup();
    const first = await service.putScore("u_1", ROUND, { hole: 4, gross: 5 });
    const count = items.size;
    const second = await service.putScore("u_1", ROUND, { hole: 4, gross: 5 });
    expect(second).toEqual(first);
    expect(items.size).toBe(count);
  });

  it("replaces a score with the latest write", async () => {
    const { service } = await setup();
    await service.putScore("u_1", ROUND, { hole: 4, gross: 5 });
    const round = await service.putScore("u_1", ROUND, { hole: 4, gross: 6 });
    expect(round.scores).toEqual([{ userId: "u_1", hole: 4, gross: 6 }]);
  });

  it("clears a score with a null gross, and clearing again changes nothing", async () => {
    const { service, items, writes } = await setup();
    const empty = await service.getRound("u_1", ROUND);
    await service.putScore("u_1", ROUND, { hole: 4, gross: 5 });
    await service.putScore("u_2", ROUND, { hole: 4, gross: 4 });
    const cleared = await service.putScore("u_1", ROUND, { hole: 4, gross: null });
    expect(cleared.scores).toEqual([{ userId: "u_2", hole: 4, gross: 4 }]);
    expect(items.has(`ROUND#${ROUND}|SCORE#04#u_1`)).toBe(false);
    expect(await service.putScore("u_1", ROUND, { hole: 4, gross: null })).toEqual(cleared);
    expect(writes().map((w) => w.name)).toEqual(["PutCommand", "PutCommand", "DeleteCommand", "DeleteCommand"]);
    expect(await service.putScore("u_2", ROUND, { hole: 4, gross: null })).toEqual(empty);
  });

  it("keeps every player's score when they all write the same hole at once", async () => {
    const { service } = await setup();
    const gross: Record<string, number> = { u_1: 4, u_2: 5, u_3: 3, u_4: 6 };
    await Promise.all(Object.entries(gross).map(([userId, g]) => service.putScore(userId, ROUND, { hole: 1, gross: g })));
    const round = await service.getRound("u_1", ROUND);
    expect(Object.fromEntries(round.scores.map((s) => [s.userId, s.gross]))).toEqual(gross);
    expect(round.state.skins!.holes[0]).toMatchObject({ hole: 1, status: "won", winnerUserId: "u_3", atStakeCents: 500 });
  });
});

describe("RoundService.putHoleEvents", () => {
  it("stores the hole's wad makers in order and its greenie winner", async () => {
    const { service, items, writes } = await setup();
    const round = await service.putHoleEvents("u_4", ROUND, "3", { wadMakers: ["u_2", "u_1"], greenieWinner: "u_3" });
    expect(round.holes).toEqual([{ hole: 3, wadMakers: ["u_2", "u_1"], greenieWinner: "u_3" }]);
    expect(items.get(`ROUND#${ROUND}|HOLE#03`)).toMatchObject({ type: "holeEvents", hole: 3, wadMakers: ["u_2", "u_1"], greenieWinner: "u_3", updatedBy: "u_4" });
    expect(writes().map((w) => w.name)).toEqual(["UpdateCommand"]);
    expect(await service.getRound("u_1", ROUND)).toEqual(round);
  });

  it("accepts a guest as a wad maker and as the greenie winner", async () => {
    const { service } = await setup({ members: ["u_2"] });
    const { player } = await service.addGuest("u_1", ROUND, { displayName: "Pat", handicapIndex: 10 });
    const round = await service.putHoleEvents("u_2", ROUND, "06", { wadMakers: [player.userId], greenieWinner: player.userId });
    expect(round.holes).toEqual([{ hole: 6, wadMakers: [player.userId], greenieWinner: player.userId }]);
  });

  it("changes only the field that was sent", async () => {
    const { service } = await setup();
    await service.putHoleEvents("u_1", ROUND, "3", { wadMakers: ["u_2"], greenieWinner: "u_3" });
    expect((await service.putHoleEvents("u_2", ROUND, "3", { greenieWinner: null })).holes).toEqual([{ hole: 3, wadMakers: ["u_2"], greenieWinner: null }]);
    expect((await service.putHoleEvents("u_2", ROUND, "3", { wadMakers: [] })).holes).toEqual([{ hole: 3, wadMakers: [], greenieWinner: null }]);
  });

  it("keeps both fields when two devices set one each at once", async () => {
    const { service } = await setup();
    await Promise.all([
      service.putHoleEvents("u_1", ROUND, "3", { wadMakers: ["u_1", "u_4"] }),
      service.putHoleEvents("u_2", ROUND, "3", { greenieWinner: "u_2" }),
    ]);
    expect((await service.getRound("u_1", ROUND)).holes).toEqual([{ hole: 3, wadMakers: ["u_1", "u_4"], greenieWinner: "u_2" }]);
  });

  it("gives the same round when the same events are written again", async () => {
    const { service, items } = await setup();
    const first = await service.putHoleEvents("u_1", ROUND, "5", { wadMakers: ["u_2", "u_3"], greenieWinner: null });
    const count = items.size;
    expect(await service.putHoleEvents("u_3", ROUND, "5", { wadMakers: ["u_2", "u_3"], greenieWinner: null })).toEqual(first);
    expect(items.size).toBe(count);
  });

  it("clears a greenie on any hole", async () => {
    const { service } = await setup();
    expect((await service.putHoleEvents("u_1", ROUND, "1", { greenieWinner: null })).holes).toEqual([{ hole: 1, wadMakers: [], greenieWinner: null }]);
  });

  it("is for players of the round only", async () => {
    const { service, writes } = await setup();
    expect(await failure(service.putHoleEvents("u_5", ROUND, "3", { wadMakers: [] }))).toEqual({ kind: "forbidden", code: "not_a_participant" });
    expect(await failure(service.putHoleEvents("u_1", "r_missing", "3", { wadMakers: [] }))).toEqual({ kind: "not_found", code: "round_not_found" });
    expect(writes()).toEqual([]);
  });

  it.each([
    ["hole 0", "0", { wadMakers: [] }, "invalid_hole"],
    ["hole 19", "19", { wadMakers: [] }, "invalid_hole"],
    ["a hole that is not a number", "three", { wadMakers: [] }, "invalid_hole"],
    ["a fractional hole", "3.5", { wadMakers: [] }, "invalid_hole"],
    ["no hole", undefined, { wadMakers: [] }, "invalid_hole"],
    ["neither field", "3", {}, "invalid_body"],
    ["wad makers that are not a list", "3", { wadMakers: "u_1" }, "invalid_body"],
    ["a wad maker that is not a string", "3", { wadMakers: [1] }, "invalid_body"],
    ["more wad makers than players", "3", { wadMakers: ["u_1", "u_2", "u_3", "u_4", "u_5"] }, "invalid_body"],
    ["a greenie winner that is not a string", "3", { greenieWinner: 3 }, "invalid_body"],
    ["a list as the body", "3", [], "invalid_body"],
    ["a wad maker listed twice", "3", { wadMakers: ["u_1", "u_2", "u_1"] }, "duplicate_wad_maker"],
    ["a wad maker who is not in the round", "3", { wadMakers: ["u_1", "u_5"] }, "unknown_player"],
    ["a greenie winner who is not in the round", "3", { greenieWinner: "u_5" }, "unknown_player"],
    ["a greenie on a par 4", "1", { greenieWinner: "u_1" }, "not_a_par_three"],
    ["a greenie on a par 5", "2", { wadMakers: ["u_1"], greenieWinner: "u_1" }, "not_a_par_three"],
  ])("rejects %s", async (_name, hole, body, code) => {
    const { service, writes } = await setup();
    expect(await failure(service.putHoleEvents("u_1", ROUND, hole, body))).toEqual({ kind: "validation", code });
    expect(writes()).toEqual([]);
  });

  it("rejects a greenie winner whose score on the hole is over par", async () => {
    const { service, writes } = await setup();
    await service.putScore("u_1", ROUND, { hole: 3, gross: 4 });
    await service.putScore("u_2", ROUND, { hole: 3, gross: 3 });
    const before = writes().length;
    expect(await failure(service.putHoleEvents("u_2", ROUND, "3", { greenieWinner: "u_1" }))).toEqual({ kind: "validation", code: "greenie_winner_over_par" });
    expect(writes()).toHaveLength(before);
    const round = await service.putHoleEvents("u_1", ROUND, "3", { greenieWinner: "u_2" });
    expect(round.state.greenies!.holes[0]).toEqual({ hole: 3, winnerUserId: "u_2", status: "awarded" });
  });
});

describe("game state", () => {
  it("has no winners or money before anything is scored", async () => {
    const { service } = await setup();
    const { state } = await service.getRound("u_1", ROUND);
    const zero = { u_1: 0, u_2: 0, u_3: 0, u_4: 0 };
    expect(state.skins).toMatchObject({ complete: false, carryOutCents: 0, deltas: zero });
    expect(state.skins!.holes).toHaveLength(18);
    expect(state.skins!.holes[0]).toEqual({ hole: 1, status: "pending", carriedInCents: 0, atStakeCents: 500, winnerUserId: null, net: null });
    expect(state.wad).toEqual({
      instances: [
        { segment: "front", holderUserId: null, valueCents: 700, makes: [], complete: false },
        { segment: "back", holderUserId: null, valueCents: 700, makes: [], complete: false },
      ],
      deltas: zero,
      ignored: [],
    });
    expect(state.greenies).toEqual({
      holes: [3, 6, 11, 16].map((hole) => ({ hole, winnerUserId: null, status: "none" })),
      deltas: zero,
    });
  });

  it("leaves out the games that are not enabled", async () => {
    const { service } = await setup({ games: { wad: {} } });
    expect(Object.keys((await service.getRound("u_1", ROUND)).state)).toEqual(["wad"]);
    const none = await setup({ games: {} });
    expect((await none.service.putScore("u_1", ROUND, { hole: 1, gross: 4 })).state).toEqual({});
  });

  it("has no skins state until every player has a course handicap", async () => {
    const { service } = await setup({ teeId: "male-unrated" });
    const { state } = await service.putScore("u_1", ROUND, { hole: 1, gross: 4 });
    expect(state.skins).toBeNull();
    expect(state.wad!.instances).toHaveLength(2);
    expect(state.greenies!.holes).toHaveLength(4);
  });

  it("uses net scores for skins", async () => {
    const fake = fakeDb([courseItem, profileItem("u_1", "Zach", 15.4), profileItem("u_2", "Sam", 7)]);
    const service = new RoundService(new DynamoRoundStore(fake.db, TABLE, () => NOW), { newId: () => "id1", newJoinCode: () => "ABCD2F" });
    const created = await service.createRound("u_1", { courseId: course.courseId, teeId: "male-blue", date: "2026-10-03", holes: 18, games: { skins: {} } });
    await service.joinRound("u_2", { joinCode: "ABCD2F" });
    // Hole 5 is stroke index 1, so the higher handicap gets a tick there.
    expect(created.players[0]!.courseHandicap).toBeGreaterThan(0);
    for (let hole = 1; hole <= 4; hole++) {
      await service.putScore("u_1", ROUND, { hole, gross: 4 });
      await service.putScore("u_2", ROUND, { hole, gross: 4 });
    }
    await service.putScore("u_1", ROUND, { hole: 5, gross: 5 });
    const round = await service.putScore("u_2", ROUND, { hole: 5, gross: 5 });
    expect(round.players.find((p) => p.userId === "u_1")!.ticksByHole).toMatchObject({ 5: 1 });
    expect(round.state.skins!.holes[4]).toMatchObject({ hole: 5, status: "won", winnerUserId: "u_1", net: { u_1: 4, u_2: 5 } });
  });

  it("follows the wad example: $7, $9, $11, then $13", async () => {
    const { service, scoreHole } = await setup();
    await service.putHoleEvents("u_1", ROUND, "2", { wadMakers: ["u_1"] });
    await service.putHoleEvents("u_2", ROUND, "5", { wadMakers: ["u_2", "u_3"] });
    const round = await service.putHoleEvents("u_3", ROUND, "7", { wadMakers: ["u_3"] });
    expect(round.state.wad).toEqual({
      instances: [
        {
          segment: "front",
          holderUserId: "u_3",
          valueCents: 1300,
          makes: [
            { hole: 2, userId: "u_1", valueCents: 700 },
            { hole: 5, userId: "u_2", valueCents: 900 },
            { hole: 5, userId: "u_3", valueCents: 1100 },
            { hole: 7, userId: "u_3", valueCents: 1300 },
          ],
          complete: false,
        },
        { segment: "back", holderUserId: null, valueCents: 700, makes: [], complete: false },
      ],
      deltas: { u_1: 0, u_2: 0, u_3: 0, u_4: 0 },
      ignored: [],
    });

    // The holder is paid once everyone has a score on the ninth.
    const afterNine = await scoreHole(9, [4, 4, 5, 4]);
    expect(afterNine.state.wad!.instances[0]).toMatchObject({ holderUserId: "u_3", valueCents: 1300, complete: true });
    expect(afterNine.state.wad!.deltas).toEqual({ u_1: -1300, u_2: -1300, u_3: 3900, u_4: -1300 });
  });

  it("follows the skins example: two pushes, then a $15 win", async () => {
    const { scoreHole } = await setup();
    await scoreHole(1, [4, 4, 5, 5]);
    await scoreHole(2, [5, 6, 5, 6]);
    const round = await scoreHole(3, [2, 3, 3, 4]);
    const skins = round.state.skins!;
    expect(skins.holes.slice(0, 4)).toEqual([
      { hole: 1, status: "pushed", carriedInCents: 0, atStakeCents: 500, winnerUserId: null, net: { u_1: 4, u_2: 4, u_3: 5, u_4: 5 } },
      { hole: 2, status: "pushed", carriedInCents: 500, atStakeCents: 1000, winnerUserId: null, net: { u_1: 5, u_2: 6, u_3: 5, u_4: 6 } },
      { hole: 3, status: "won", carriedInCents: 1000, atStakeCents: 1500, winnerUserId: "u_1", net: { u_1: 2, u_2: 3, u_3: 3, u_4: 4 } },
      { hole: 4, status: "pending", carriedInCents: 0, atStakeCents: 500, winnerUserId: null, net: null },
    ]);
    expect(skins.deltas).toEqual({ u_1: 4500, u_2: -1500, u_3: -1500, u_4: -1500 });
    expect(skins).toMatchObject({ complete: false, carryOutCents: 0 });
  });

  it("waits for a hole's missing score before settling the holes after it", async () => {
    const { service, scoreHole } = await setup();
    await scoreHole(1, [4, 4, 5]);
    const round = await scoreHole(2, [3, 4, 4, 4]);
    expect(round.state.skins!.holes.slice(0, 2).map((h) => h.status)).toEqual(["pending", "pending"]);
    expect(round.state.skins!.deltas).toEqual({ u_1: 0, u_2: 0, u_3: 0, u_4: 0 });
    const late = await service.putScore("u_4", ROUND, { hole: 1, gross: 5 });
    expect(late.state.skins!.holes.slice(0, 2).map((h) => h.status)).toEqual(["pushed", "won"]);
    expect(late.state.skins!.deltas).toEqual({ u_1: 3000, u_2: -1000, u_3: -1000, u_4: -1000 });
  });

  it("shows a carryover left after a pushed 18th and does not pay it", async () => {
    const { service, scoreHole } = await setup();
    for (let hole = 1; hole <= 16; hole++) await scoreHole(hole, [3, 4, 4, 4]);
    await scoreHole(17, [4, 4, 5, 5]);
    const round = await scoreHole(18, [4, 5, 4, 5]);
    const skins = round.state.skins!;
    expect(skins.complete).toBe(true);
    expect(skins.carryOutCents).toBe(1000);
    expect(skins.holes[16]).toMatchObject({ hole: 17, status: "pushed", atStakeCents: 500, winnerUserId: null });
    expect(skins.holes[17]).toMatchObject({ hole: 18, status: "pushed", carriedInCents: 500, atStakeCents: 1000, winnerUserId: null });
    // Sixteen skins at $5 from each of three players, and nothing for the carryover.
    expect(skins.deltas).toEqual({ u_1: 16 * 1500, u_2: -16 * 500, u_3: -16 * 500, u_4: -16 * 500 });
    expect(await service.recompute("u_2", ROUND)).toEqual(round.state);
  });

  it("holds a greenie until the winner's score is in, and drops it if the score ends over par", async () => {
    const { service } = await setup();
    const zero = { u_1: 0, u_2: 0, u_3: 0, u_4: 0 };
    const pending = await service.putHoleEvents("u_1", ROUND, "3", { greenieWinner: "u_2" });
    expect(pending.state.greenies!.holes[0]).toEqual({ hole: 3, winnerUserId: "u_2", status: "pending" });
    expect(pending.state.greenies!.deltas).toEqual(zero);

    const awarded = await service.putScore("u_2", ROUND, { hole: 3, gross: 3 });
    expect(awarded.state.greenies!.holes[0]).toEqual({ hole: 3, winnerUserId: "u_2", status: "awarded" });
    expect(awarded.state.greenies!.deltas).toEqual({ u_1: -500, u_2: 1500, u_3: -500, u_4: -500 });

    // A corrected score is stored as sent; the greenie stays recorded but is not paid.
    const invalid = await service.putScore("u_2", ROUND, { hole: 3, gross: 4 });
    expect(invalid.holes).toEqual([{ hole: 3, wadMakers: [], greenieWinner: "u_2" }]);
    expect(invalid.state.greenies!.holes[0]).toEqual({ hole: 3, winnerUserId: "u_2", status: "invalid" });
    expect(invalid.state.greenies!.deltas).toEqual(zero);
  });
});

describe("RoundService.recompute", () => {
  it("returns the state of the stored scores and hole events without writing", async () => {
    const { service, scoreHole, writes } = await setup();
    await scoreHole(1, [4, 5, 5, 5]);
    await service.putHoleEvents("u_1", ROUND, "1", { wadMakers: ["u_4"] });
    const round = await service.getRound("u_1", ROUND);
    const before = writes().length;
    const state = await service.recompute("u_3", ROUND);
    expect(state).toEqual(round.state);
    expect(state.skins!.deltas).toEqual({ u_1: 1500, u_2: -500, u_3: -500, u_4: -500 });
    expect(state.wad!.instances[0]).toMatchObject({ holderUserId: "u_4", valueCents: 700 });
    expect(await service.recompute("u_3", ROUND)).toEqual(state);
    expect(writes()).toHaveLength(before);
  });

  it("is for players of the round only", async () => {
    const { service } = await setup();
    expect(await failure(service.recompute("u_5", ROUND))).toEqual({ kind: "forbidden", code: "not_a_participant" });
    expect(await failure(service.recompute("u_1", "r_missing"))).toEqual({ kind: "not_found", code: "round_not_found" });
  });
});
