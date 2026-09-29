import { describe, expect, it } from "vitest";
import { RoundError } from "../../../src/services/rounds/errors.js";
import { RoundService } from "../../../src/services/rounds/roundService.js";
import { DynamoRoundStore } from "../../../src/services/rounds/roundStore.js";
import { SettlementService, transferId } from "../../../src/services/rounds/settlementService.js";
import type { Settlement } from "../../../src/shared/settlement.js";
import { course, courseItem, fakeDb, type Item, NOW, profileItem, TABLE } from "./fixtures.js";

const ROUND = "r_id1";
const GAMES = { skins: { baseCents: 500 }, wad: { startCents: 700, stepCents: 200 }, greenies: { amountCents: 500 } };
const WRITES = ["PutCommand", "DeleteCommand", "UpdateCommand", "TransactWriteCommand"];
const PAID_AT = "2026-10-03T20:00:00.000Z";

// On the Blue tee (rating 72.1, slope 131, par 72) the course handicap is
// round(index * 131 / 113 + 0.1): index 10 -> round(11.69) = 12 and
// index 12 -> round(14.01) = 14. The lowest is 12, so u_1, u_2 and u_3 get no
// ticks and u_4 gets 14 - 12 = 2, on stroke indexes 1 and 2: holes 5 and 12.
const profiles: Item[] = [
  { ...profileItem("u_1", "Ann", 10), venmoHandle: "ann-golf" },
  { ...profileItem("u_2", "Bo", 10), venmoHandle: " bo-golf " },
  profileItem("u_3", "Cy", 10),
  { ...profileItem("u_4", "Di", 12), venmoHandle: "di-golf" },
  profileItem("u_5", "Eve", 10),
];

// Gross scores for u_1, u_2, u_3, u_4. Pars: 4 5 3 4 4 3 5 4 4 / 4 3 5 4 4 5 3 4 4.
//
// Skins, base 500, the winner collects the hole's value from each of the 3 others:
//   hole  scores    result                              u_1    u_2    u_3    u_4
//    1    4 5 5 5   u_1 wins 500                      +1500   -500   -500   -500
//    2    5 5 6 6   push, 500 carries
//    3    3 3 4 4   push, 1000 carries
//    4    5 4 5 5   u_2 wins 1500                     -1500  +4500  -1500  -1500
//    5    4 5 5 5   u_4 nets 4 with a tick: push, 500 carries
//    6    4 4 3 4   u_3 wins 1000                     -1000  -1000  +3000  -1000
//    7    5 5 5 5   push, 500 carries
//    8    4 4 4 4   push, 1000 carries
//    9    4 4 4 5   push, 1500 carries through the turn
//   10    5 5 5 4   u_4 wins 2000                     -2000  -2000  -2000  +6000
//   11    3 4 4 4   u_1 wins 500                      +1500   -500   -500   -500
//   12    5 6 6 6   u_4 nets 5 with a tick: push, 500 carries
//   13    4 4 5 5   push, 1000 carries
//   14    4 5 4 3   u_4 wins 1500                     -1500  -1500  -1500  +4500
//   15    5 5 5 5   push, 500 carries
//   16    3 3 3 4   push, 1000 carries
//   17    4 3 4 4   u_2 wins 1500                     -1500  +4500  -1500  -1500
//   18    4 4 5 5   push: 500 is left unresolved and is not paid
//                                              skins  -4500  +3500  -4500  +5500
const SCORES: number[][] = [
  [4, 5, 5, 5],
  [5, 5, 6, 6],
  [3, 3, 4, 4],
  [5, 4, 5, 5],
  [4, 5, 5, 5],
  [4, 4, 3, 4],
  [5, 5, 5, 5],
  [4, 4, 4, 4],
  [4, 4, 4, 5],
  [5, 5, 5, 4],
  [3, 4, 4, 4],
  [5, 6, 6, 6],
  [4, 4, 5, 5],
  [4, 5, 4, 3],
  [5, 5, 5, 5],
  [3, 3, 3, 4],
  [4, 3, 4, 4],
  [4, 4, 5, 5],
];

// Wad, start 700, step 200, the holder collects from each of the 3 others:
//   front: hole 2 u_2 (700); hole 7 u_3 (900) then u_1 (1100). u_1 holds 1100.
//   back: hole 12 u_4 (700); hole 15 u_4 again (900); hole 18 u_2 (1100). u_2 holds 1100.
//                                                     u_1    u_2    u_3    u_4
//   front                                            +3300  -1100  -1100  -1100
//   back                                             -1100  +3300  -1100  -1100
//                                                wad +2200  +2200  -2200  -2200
const WAD_MAKERS: Record<number, string[]> = { 2: ["u_2"], 7: ["u_3", "u_1"], 12: ["u_4"], 15: ["u_4"], 18: ["u_2"] };

// Greenies, 500 from each of the 3 others, on the par 3s (3, 6, 11, 16):
//                                                     u_1    u_2    u_3    u_4
//   hole 3 u_1 (3)                                   +1500   -500   -500   -500
//   hole 6 u_3 (3)                                    -500   -500  +1500   -500
//   hole 11 u_1 (3)                                  +1500   -500   -500   -500
//   hole 16 u_2 (3)                                   -500  +1500   -500   -500
//                                           greenies +2000      0      0  -2000
const GREENIES: Record<number, string> = { 3: "u_1", 6: "u_3", 11: "u_1", 16: "u_2" };

// Positions: u_1 -4500 + 2200 + 2000 = -300; u_2 3500 + 2200 + 0 = 5700;
// u_3 -4500 - 2200 + 0 = -6700; u_4 5500 - 2200 - 2000 = 1300. Sum 0.
//
// Transfers, largest creditor against largest debtor:
//   u_2 (5700) and u_3 (6700): u_3 pays u_2 5700, u_3 still owes 1000
//   u_4 (1300) and u_3 (1000): u_3 pays u_4 1000, u_4 is still owed 300
//   u_4 (300) and u_1 (300):   u_1 pays u_4 300
const POSITIONS = { u_1: -300, u_2: 5700, u_3: -6700, u_4: 1300 };
const TRANSFERS = [
  { from: "u_3", to: "u_2", amountCents: 5700, toVenmoHandle: "bo-golf" },
  { from: "u_3", to: "u_4", amountCents: 1000, toVenmoHandle: "di-golf" },
  { from: "u_1", to: "u_4", amountCents: 300, toVenmoHandle: "di-golf" },
];

async function setup(options: { members?: string[]; games?: object; teeId?: string } = {}) {
  const fake = fakeDb([courseItem, ...profiles]);
  const store = new DynamoRoundStore(fake.db, TABLE, () => NOW);
  let ids = 0;
  let minutes = 0;
  const rounds = new RoundService(store, {
    now: () => new Date(NOW.getTime() + minutes++ * 60_000),
    newId: () => `id${++ids}`,
    newJoinCode: () => "ABCD2F",
  });
  const settlement = new SettlementService(store, { now: () => new Date(PAID_AT) });
  const members = options.members ?? ["u_2", "u_3", "u_4"];
  const players = ["u_1", ...members];
  const body = { courseId: course.courseId, teeId: options.teeId ?? "male-blue", date: "2026-10-03", holes: 18, games: options.games ?? GAMES };
  await rounds.createRound("u_1", body);
  for (const member of members) await rounds.joinRound(member, { joinCode: "ABCD2F" });

  /** Scores holes 1 to `through`, then records the wad makers and greenies of those holes. */
  const play = async (through = 18) => {
    for (let hole = 1; hole <= through; hole++) {
      for (const [i, userId] of players.entries()) await rounds.putScore(userId, ROUND, { hole, gross: SCORES[hole - 1]![i]! });
      const wadMakers = WAD_MAKERS[hole];
      if (wadMakers) await rounds.putHoleEvents("u_1", ROUND, String(hole), { wadMakers });
      const greenieWinner = GREENIES[hole];
      if (greenieWinner) await rounds.putHoleEvents("u_1", ROUND, String(hole), { greenieWinner });
    }
    fake.sent.length = 0;
  };
  const writes = () => fake.sent.filter((s) => WRITES.includes(s.name));
  const paidItems = () => [...fake.items.values()].filter((i) => (i.SK as string).startsWith("SETTLEMENT#PAID#"));
  return { ...fake, rounds, settlement, play, writes, paidItems };
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

const find = (s: Settlement, from: string, to: string) => {
  const transfer = s.transfers.find((t) => t.from === from && t.to === to);
  if (!transfer) throw new Error(`no transfer from ${from} to ${to}`);
  return transfer;
};

const sum = (values: number[]) => values.reduce((a, b) => a + b, 0);

/** What each player ends up with if every transfer is paid. */
function replay(s: Settlement): Record<string, number> {
  const result: Record<string, number> = Object.fromEntries(Object.keys(s.positions).map((id) => [id, 0]));
  for (const t of s.transfers) {
    result[t.from]! -= t.amountCents;
    result[t.to]! += t.amountCents;
  }
  return result;
}

describe("SettlementService.getSettlement", () => {
  it("settles a full round across the three games", async () => {
    const { settlement, play, writes } = await setup();
    await play();
    const s = await settlement.getSettlement("u_1", ROUND);

    expect(s.roundId).toBe(ROUND);
    expect(s.status).toBe("final");
    expect(s.incompleteHoles).toEqual([]);
    expect(s.issues).toEqual([]);
    expect(s.games).toEqual({
      skins: { u_1: -4500, u_2: 3500, u_3: -4500, u_4: 5500 },
      wad: { u_1: 2200, u_2: 2200, u_3: -2200, u_4: -2200 },
      greenies: { u_1: 2000, u_2: 0, u_3: 0, u_4: -2000 },
    });
    expect(s.positions).toEqual(POSITIONS);
    expect(s.transfers).toEqual(
      TRANSFERS.map((t) => ({ ...t, transferId: transferId(ROUND, t), paid: false, paidAt: null, paidBy: null })),
    );
    expect(s.stalePayments).toEqual([]);
    expect(writes()).toEqual([]);
  });

  it("has positions that sum to zero and transfers that reproduce them", async () => {
    const { settlement, play } = await setup();
    await play();
    const s = await settlement.getSettlement("u_2", ROUND);
    expect(sum(Object.values(s.positions))).toBe(0);
    expect(replay(s)).toEqual(s.positions);
    for (const t of s.transfers) {
      expect(Number.isInteger(t.amountCents)).toBe(true);
      expect(t.amountCents).toBeGreaterThan(0);
    }
    expect(new Set(s.transfers.map((t) => t.transferId)).size).toBe(s.transfers.length);
  });

  it("exposes the carryover of a pushed 18th hole and pays it to nobody", async () => {
    const { settlement, play } = await setup();
    await play();
    const s = await settlement.getSettlement("u_1", ROUND);
    expect(s.skinsCarryover).toEqual({ amountCents: 500, unresolved: true });
    expect(s.status).toBe("final");
    // The skins deltas are exactly the seven skins that were won; the 500 left on 18 is in none of them.
    expect(sum(Object.values(s.games.skins!))).toBe(0);
    expect(sum(Object.values(s.games.skins!).filter((v) => v > 0))).toBe(3500 + 5500);
    expect(sum(Object.values(s.positions))).toBe(0);
    expect(sum(s.transfers.map((t) => t.amountCents))).toBe(5700 + 1300);
  });

  it("has no unresolved carryover when the last hole is won", async () => {
    const { rounds, settlement, play } = await setup();
    await play();
    await rounds.putScore("u_1", ROUND, { hole: 18, gross: 3 });
    const s = await settlement.getSettlement("u_1", ROUND);
    expect(s.skinsCarryover).toEqual({ amountCents: 0, unresolved: false });
    // u_1 wins the 500 on 18 from each: +1500, the others -500.
    expect(s.positions).toEqual({ u_1: 1200, u_2: 5200, u_3: -7200, u_4: 800 });
  });

  it("is provisional while holes are missing scores", async () => {
    const { rounds, settlement, play } = await setup();
    await play(4);
    await rounds.putScore("u_1", ROUND, { hole: 5, gross: 4 });
    const s = await settlement.getSettlement("u_1", ROUND);
    expect(s.status).toBe("provisional");
    expect(s.incompleteHoles).toEqual([5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]);
    expect(s.issues).toEqual([]);
    // Skins after hole 4: u_1 +1500 -1500, u_2 -500 +4500, u_3 and u_4 -500 -1500.
    // The wad is not paid before hole 9. Greenie on hole 3: u_1 +1500, the others -500.
    expect(s.games).toEqual({
      skins: { u_1: 0, u_2: 4000, u_3: -2000, u_4: -2000 },
      wad: { u_1: 0, u_2: 0, u_3: 0, u_4: 0 },
      greenies: { u_1: 1500, u_2: -500, u_3: -500, u_4: -500 },
    });
    expect(s.positions).toEqual({ u_1: 1500, u_2: 3500, u_3: -2500, u_4: -2500 });
    expect(replay(s)).toEqual(s.positions);
    // A carryover in a round still being played is not an unresolved one.
    expect(s.skinsCarryover).toEqual({ amountCents: 0, unresolved: false });
  });

  it("is provisional with no transfers before any score", async () => {
    const { settlement } = await setup();
    const s = await settlement.getSettlement("u_1", ROUND);
    expect(s.status).toBe("provisional");
    expect(s.incompleteHoles).toHaveLength(18);
    expect(s.positions).toEqual({ u_1: 0, u_2: 0, u_3: 0, u_4: 0 });
    expect(s.transfers).toEqual([]);
  });

  it("reports skins as an issue when players have no course handicap", async () => {
    const { settlement, play } = await setup({ teeId: "male-unrated" });
    await play();
    const s = await settlement.getSettlement("u_1", ROUND);
    expect(s.status).toBe("provisional");
    expect(s.incompleteHoles).toEqual([]);
    expect(s.issues).toEqual([expect.objectContaining({ code: "skins_unavailable", hole: null, userId: null })]);
    expect(s.games.skins).toBeNull();
    expect(s.skinsCarryover).toBeNull();
    // Wad and greenies only: u_1 2200 + 2000, u_2 2200, u_3 -2200, u_4 -2200 - 2000.
    expect(s.positions).toEqual({ u_1: 4200, u_2: 2200, u_3: -2200, u_4: -4200 });
    expect(replay(s)).toEqual(s.positions);
  });

  it("reports an invalid greenie and does not pay it", async () => {
    const { rounds, settlement, play } = await setup();
    await play();
    // u_2 won the greenie on 16 with a 3; the score is corrected to a bogey.
    await rounds.putScore("u_2", ROUND, { hole: 16, gross: 4 });
    const s = await settlement.getSettlement("u_1", ROUND);
    expect(s.status).toBe("provisional");
    expect(s.issues).toEqual([expect.objectContaining({ code: "greenie_invalid", hole: 16, userId: "u_2" })]);
    // Only holes 3, 6 and 11 pay: u_1 +1500 -500 +1500, u_3 -500 +1500 -500, u_2 and u_4 -500 three times.
    expect(s.games.greenies).toEqual({ u_1: 2500, u_2: -1500, u_3: 500, u_4: -1500 });
    expect(sum(Object.values(s.positions))).toBe(0);
  });

  it("reports a greenie that waits for the winner's score", async () => {
    const { rounds, settlement } = await setup({ games: { greenies: { amountCents: 500 } } });
    await rounds.putHoleEvents("u_1", ROUND, "3", { greenieWinner: "u_2" });
    const s = await settlement.getSettlement("u_1", ROUND);
    expect(s.issues).toEqual([expect.objectContaining({ code: "greenie_pending", hole: 3, userId: "u_2" })]);
    expect(s.positions).toEqual({ u_1: 0, u_2: 0, u_3: 0, u_4: 0 });
    expect(s.games).toEqual({ greenies: { u_1: 0, u_2: 0, u_3: 0, u_4: 0 } });
    expect(s.skinsCarryover).toBeNull();
  });

  it("settles a round with no games to nothing", async () => {
    const { settlement, play } = await setup({ games: {} });
    await play();
    const s = await settlement.getSettlement("u_1", ROUND);
    expect(s).toMatchObject({ status: "final", games: {}, positions: { u_1: 0, u_2: 0, u_3: 0, u_4: 0 }, transfers: [], skinsCarryover: null });
  });

  it("is for players of the round only", async () => {
    const { settlement, play } = await setup();
    await play();
    expect(await failure(settlement.getSettlement("u_5", ROUND))).toEqual({ kind: "forbidden", code: "not_a_participant" });
    expect(await failure(settlement.getSettlement("u_1", "r_other"))).toEqual({ kind: "not_found", code: "round_not_found" });
    expect(await failure(settlement.getSettlement("u_1", ""))).toEqual({ kind: "not_found", code: "round_not_found" });
  });
});

describe("SettlementService.markPaid", () => {
  it("lets the payer mark the transfer paid", async () => {
    const { settlement, play, writes, items } = await setup();
    await play();
    const id = transferId(ROUND, TRANSFERS[1]!);
    const s = await settlement.markPaid("u_3", ROUND, id);

    expect(find(s, "u_3", "u_4")).toMatchObject({ transferId: id, amountCents: 1000, paid: true, paidAt: PAID_AT, paidBy: "u_3" });
    expect(find(s, "u_3", "u_2").paid).toBe(false);
    expect(find(s, "u_1", "u_4").paid).toBe(false);
    expect(s.positions).toEqual(POSITIONS);
    expect(s.stalePayments).toEqual([]);

    expect(writes().map((w) => w.name)).toEqual(["PutCommand"]);
    expect(writes()[0]!.input.ConditionExpression).toBe("attribute_not_exists(PK)");
    expect(items.get(`ROUND#${ROUND}|SETTLEMENT#PAID#${id}`)).toEqual({
      PK: `ROUND#${ROUND}`,
      SK: `SETTLEMENT#PAID#${id}`,
      type: "transferPaid",
      transferId: id,
      from: "u_3",
      to: "u_4",
      amountCents: 1000,
      paidAt: PAID_AT,
      paidBy: "u_3",
    });
    expect(await settlement.getSettlement("u_1", ROUND)).toEqual(s);
  });

  it("lets the payee mark the transfer paid", async () => {
    const { settlement, play } = await setup();
    await play();
    const s = await settlement.markPaid("u_4", ROUND, transferId(ROUND, TRANSFERS[1]!));
    expect(find(s, "u_3", "u_4")).toMatchObject({ paid: true, paidBy: "u_4" });
  });

  it("is idempotent and keeps the first marker", async () => {
    const { settlement, play, paidItems } = await setup();
    await play();
    const id = transferId(ROUND, TRANSFERS[1]!);
    const first = await settlement.markPaid("u_3", ROUND, id);
    const again = await settlement.markPaid("u_4", ROUND, id);
    expect(again).toEqual(first);
    expect(find(again, "u_3", "u_4")).toMatchObject({ paid: true, paidBy: "u_3" });
    expect(paidItems()).toHaveLength(1);
  });

  it("refuses a player who is not a party of the transfer", async () => {
    const { settlement, play, writes } = await setup();
    await play();
    const id = transferId(ROUND, TRANSFERS[1]!);
    for (const other of ["u_1", "u_2"]) {
      expect(await failure(settlement.markPaid(other, ROUND, id))).toEqual({ kind: "forbidden", code: "not_transfer_party" });
    }
    expect(writes()).toEqual([]);
    expect(find(await settlement.getSettlement("u_1", ROUND), "u_3", "u_4").paid).toBe(false);
  });

  it("refuses someone who is not in the round", async () => {
    const { settlement, play, writes } = await setup();
    await play();
    const id = transferId(ROUND, TRANSFERS[1]!);
    expect(await failure(settlement.markPaid("u_5", ROUND, id))).toEqual({ kind: "forbidden", code: "not_a_participant" });
    expect(await failure(settlement.markPaid("u_3", "r_other", id))).toEqual({ kind: "not_found", code: "round_not_found" });
    expect(writes()).toEqual([]);
  });

  it("refuses a transfer the settlement does not have", async () => {
    const { settlement, play, writes } = await setup();
    await play();
    const ids = ["", "t_unknown", transferId(ROUND, { from: "u_3", to: "u_4", amountCents: 1001 }), transferId("r_other", TRANSFERS[1]!)];
    for (const id of ids) {
      expect(await failure(settlement.markPaid("u_3", ROUND, id))).toEqual({ kind: "not_found", code: "transfer_not_found" });
    }
    expect(writes()).toEqual([]);
  });

  it("refuses while the round is incomplete", async () => {
    const { settlement, play, writes } = await setup();
    await play(17);
    const s = await settlement.getSettlement("u_1", ROUND);
    expect(s.incompleteHoles).toEqual([18]);
    expect(s.transfers.length).toBeGreaterThan(0);
    for (const t of s.transfers) {
      expect(await failure(settlement.markPaid(t.from, ROUND, t.transferId))).toEqual({ kind: "conflict", code: "round_incomplete" });
    }
    expect(writes()).toEqual([]);
  });

  it("refuses while the settlement has issues", async () => {
    const { settlement, play, writes } = await setup({ teeId: "male-unrated" });
    await play();
    const s = await settlement.getSettlement("u_1", ROUND);
    const t = s.transfers[0]!;
    expect(await failure(settlement.markPaid(t.from, ROUND, t.transferId))).toEqual({ kind: "conflict", code: "settlement_has_issues" });
    expect(writes()).toEqual([]);
  });

  it("does not carry a paid marker over to a transfer changed by a score correction", async () => {
    const { rounds, settlement, play, paidItems } = await setup();
    await play();
    const id = transferId(ROUND, TRANSFERS[1]!);
    await settlement.markPaid("u_3", ROUND, id);

    // u_1 corrects hole 18 from 4 to 3 and wins its 500 from each: u_1 +1500, the others -500.
    // Positions: u_1 1200, u_2 5200, u_3 -7200, u_4 800.
    // Transfers: u_3 pays u_2 5200, then u_1 1200, then u_4 800.
    await rounds.putScore("u_1", ROUND, { hole: 18, gross: 3 });
    const corrected = await settlement.getSettlement("u_4", ROUND);
    expect(corrected.status).toBe("final");
    expect(corrected.transfers.map(({ from, to, amountCents, paid, paidAt, paidBy }) => ({ from, to, amountCents, paid, paidAt, paidBy }))).toEqual([
      { from: "u_3", to: "u_2", amountCents: 5200, paid: false, paidAt: null, paidBy: null },
      { from: "u_3", to: "u_1", amountCents: 1200, paid: false, paidAt: null, paidBy: null },
      { from: "u_3", to: "u_4", amountCents: 800, paid: false, paidAt: null, paidBy: null },
    ]);
    expect(corrected.transfers.map((t) => t.transferId)).not.toContain(id);
    expect(corrected.stalePayments).toEqual([{ transferId: id, from: "u_3", to: "u_4", amountCents: 1000, paidAt: PAID_AT, paidBy: "u_3" }]);

    // The old id no longer names a transfer, so it cannot be marked again.
    expect(await failure(settlement.markPaid("u_3", ROUND, id))).toEqual({ kind: "not_found", code: "transfer_not_found" });

    // The changed transfer is marked on its own id.
    const remarked = await settlement.markPaid("u_4", ROUND, find(corrected, "u_3", "u_4").transferId);
    expect(find(remarked, "u_3", "u_4")).toMatchObject({ amountCents: 800, paid: true, paidBy: "u_4" });
    expect(remarked.stalePayments).toHaveLength(1);
    expect(paidItems()).toHaveLength(2);
  });

  it("does not trust a marker whose stored transfer differs from the one it is filed under", async () => {
    const { settlement, play, items } = await setup();
    await play();
    const id = transferId(ROUND, TRANSFERS[1]!);
    const marker = { transferId: id, from: "u_3", to: "u_4", amountCents: 900, paidAt: PAID_AT, paidBy: "u_3" };
    items.set(`ROUND#${ROUND}|SETTLEMENT#PAID#${id}`, { PK: `ROUND#${ROUND}`, SK: `SETTLEMENT#PAID#${id}`, type: "transferPaid", ...marker });
    const s = await settlement.getSettlement("u_1", ROUND);
    expect(s.transfers.every((t) => !t.paid)).toBe(true);
    expect(s.stalePayments).toEqual([marker]);
  });

  it("lets any player mark a transfer with a guest", async () => {
    const { rounds, settlement } = await setup({ members: ["u_2"], games: { greenies: { amountCents: 500 } } });
    const { player: guest } = await rounds.addGuest("u_1", ROUND, { displayName: "Pat", handicapIndex: 10 });
    const players = ["u_1", "u_2", guest.userId];
    for (let hole = 1; hole <= 18; hole++) {
      for (const userId of players) await rounds.putScore("u_1" === userId || userId === guest.userId ? "u_1" : userId, ROUND, { hole, gross: 3, userId });
    }
    // The guest wins the greenie on 3 and collects 500 from each of the two others.
    await rounds.putHoleEvents("u_2", ROUND, "3", { greenieWinner: guest.userId });
    const s = await settlement.getSettlement("u_1", ROUND);
    expect(s.positions).toEqual({ u_1: -500, u_2: -500, [guest.userId]: 1000 });
    expect(s.transfers.map((t) => t.toVenmoHandle)).toEqual([null, null]);

    const marked = await settlement.markPaid("u_2", ROUND, find(s, "u_1", guest.userId).transferId);
    expect(find(marked, "u_1", guest.userId)).toMatchObject({ paid: true, paidBy: "u_2" });
    expect(find(marked, "u_2", guest.userId).paid).toBe(false);
  });
});

describe("SettlementService.markUnpaid", () => {
  it("lets a party mark the transfer unpaid, and is idempotent", async () => {
    const { settlement, play, paidItems, writes } = await setup();
    await play();
    const id = transferId(ROUND, TRANSFERS[1]!);
    await settlement.markPaid("u_3", ROUND, id);

    expect(await failure(settlement.markUnpaid("u_1", ROUND, id))).toEqual({ kind: "forbidden", code: "not_transfer_party" });
    expect(await failure(settlement.markUnpaid("u_5", ROUND, id))).toEqual({ kind: "forbidden", code: "not_a_participant" });
    expect(paidItems()).toHaveLength(1);

    const s = await settlement.markUnpaid("u_4", ROUND, id);
    expect(find(s, "u_3", "u_4")).toMatchObject({ paid: false, paidAt: null, paidBy: null });
    expect(paidItems()).toEqual([]);
    expect(await settlement.markUnpaid("u_3", ROUND, id)).toEqual(s);
    expect(writes().map((w) => w.name)).toEqual(["PutCommand", "DeleteCommand", "DeleteCommand"]);
    expect(await failure(settlement.markUnpaid("u_3", ROUND, "t_unknown"))).toEqual({ kind: "not_found", code: "transfer_not_found" });
  });

  it("removes a stale marker", async () => {
    const { rounds, settlement, play, paidItems } = await setup();
    await play();
    const id = transferId(ROUND, TRANSFERS[1]!);
    await settlement.markPaid("u_3", ROUND, id);
    await rounds.putScore("u_1", ROUND, { hole: 18, gross: 3 });

    expect(await failure(settlement.markUnpaid("u_2", ROUND, id))).toEqual({ kind: "forbidden", code: "not_transfer_party" });
    const s = await settlement.markUnpaid("u_3", ROUND, id);
    expect(s.stalePayments).toEqual([]);
    expect(paidItems()).toEqual([]);
  });

  it("works while the round is incomplete", async () => {
    // Skins and greenies only. Positions: u_1 -4500 + 2000 = -2500, u_2 3500, u_3 -4500, u_4 5500 - 2000 = 3500.
    // Transfers: u_3 pays u_2 3500 (u_2 before u_4 by id), u_1 pays u_4 2500, u_3 pays u_4 1000.
    const { rounds, settlement, play } = await setup({ games: { skins: GAMES.skins, greenies: GAMES.greenies } });
    await play();
    const id = transferId(ROUND, { from: "u_1", to: "u_4", amountCents: 2500 });
    await settlement.markPaid("u_1", ROUND, id);
    // Hole 18 was pushed and paid nothing, so clearing a score on it changes no position.
    await rounds.putScore("u_3", ROUND, { hole: 18, gross: null });
    const open = await settlement.getSettlement("u_1", ROUND);
    expect(open.status).toBe("provisional");
    expect(open.incompleteHoles).toEqual([18]);
    expect(find(open, "u_1", "u_4")).toMatchObject({ amountCents: 2500, paid: true });
    const s = await settlement.markUnpaid("u_4", ROUND, id);
    expect(find(s, "u_1", "u_4").paid).toBe(false);
  });
});
