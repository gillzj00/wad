// Generated from backend/src/engines by `npm run build:ios-engines`. Do not edit.
"use strict";
var WadEngines = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // src/engines/index.ts
  var index_exports = {};
  __export(index_exports, {
    allocateTicks: () => allocateTicks,
    courseHandicap: () => courseHandicap,
    netScore: () => netScore,
    scoreGreenies: () => scoreGreenies,
    scoreSkins: () => scoreSkins,
    scoreWad: () => scoreWad,
    scoreWolf: () => scoreWolf,
    settle: () => settle
  });

  // src/engines/handicap.ts
  function courseHandicap(handicapIndex, tee) {
    return Math.round(handicapIndex * (tee.slope / 113) + (tee.courseRating - tee.par));
  }
  function allocateTicks(players, holes) {
    if (holes.length === 0) throw new Error("no holes to allocate ticks over");
    const strokeIndexes = new Set(holes.map((h) => h.strokeIndex));
    if (strokeIndexes.size !== holes.length) throw new Error("stroke indexes must be unique");
    const ranked = [...holes].sort((a, b) => a.strokeIndex - b.strokeIndex);
    const scratch = Math.min(...players.map((p) => p.courseHandicap));
    const result = {};
    for (const player of players) {
      const ticks = player.courseHandicap - scratch;
      const perHole = Math.floor(ticks / ranked.length);
      const extra = ticks % ranked.length;
      const byHole = {};
      ranked.forEach((h, rank) => {
        byHole[h.hole] = perHole + (rank < extra ? 1 : 0);
      });
      result[player.userId] = byHole;
    }
    return result;
  }
  function netScore(gross, ticks) {
    return gross - ticks;
  }

  // src/engines/money.ts
  function zeroDeltas(players) {
    return Object.fromEntries(players.map((p) => [p, 0]));
  }
  function collectFromEach(deltas, players, winner, amount) {
    if (!Number.isInteger(amount)) throw new Error(`amount must be integer cents, got ${amount}`);
    for (const p of players) {
      if (p === winner) continue;
      deltas[p] = (deltas[p] ?? 0) - amount;
      deltas[winner] = (deltas[winner] ?? 0) + amount;
    }
  }
  function addDeltas(...all) {
    const sum = {};
    for (const d of all) {
      for (const [p, v] of Object.entries(d)) sum[p] = (sum[p] ?? 0) + v;
    }
    return sum;
  }

  // src/engines/greenies.ts
  function scoreGreenies(input) {
    const { players, holes, scores, holeEvents, amountCents } = input;
    const deltas = zeroDeltas(players);
    const winnerByHole = new Map(holeEvents.map((e) => [e.hole, e.greenieWinner]));
    const gross = new Map(scores.map((s) => [`${s.hole}:${s.userId}`, s.gross]));
    const results = [];
    for (const h of [...holes].sort((a, b) => a.hole - b.hole)) {
      const winner = winnerByHole.get(h.hole) ?? null;
      if (h.par !== 3) {
        if (winner !== null) results.push({ hole: h.hole, winnerUserId: winner, status: "invalid" });
        continue;
      }
      if (winner === null) {
        results.push({ hole: h.hole, winnerUserId: null, status: "none" });
        continue;
      }
      const winnerGross = gross.get(`${h.hole}:${winner}`);
      let status;
      if (!players.includes(winner)) status = "invalid";
      else if (winnerGross === void 0) status = "pending";
      else if (winnerGross > h.par) status = "invalid";
      else status = "awarded";
      if (status === "awarded") collectFromEach(deltas, players, winner, amountCents);
      results.push({ hole: h.hole, winnerUserId: winner, status });
    }
    return { holes: results, deltas };
  }

  // src/engines/skins.ts
  function scoreSkins(input) {
    const { players, holes, scores, baseCents, carryover = true } = input;
    const ids = players.map((p) => p.userId);
    const ticks = allocateTicks(players, holes);
    const gross = new Map(scores.map((s) => [`${s.hole}:${s.userId}`, s.gross]));
    const deltas = zeroDeltas(ids);
    const results = [];
    let carry = 0;
    let blocked = false;
    for (const h of [...holes].sort((a, b) => a.hole - b.hole)) {
      const atStake = carry + baseCents;
      const grossByPlayer = ids.map((id) => gross.get(`${h.hole}:${id}`));
      const net = grossByPlayer.every((g) => g !== void 0) ? Object.fromEntries(ids.map((id, i) => [id, netScore(grossByPlayer[i], ticks[id][h.hole])])) : null;
      if (blocked || net === null) {
        results.push({
          hole: h.hole,
          status: "pending",
          carriedInCents: blocked ? null : carry,
          atStakeCents: blocked ? null : atStake,
          winnerUserId: null,
          net
        });
        blocked = true;
        continue;
      }
      const best = Math.min(...Object.values(net));
      const leaders = ids.filter((id) => net[id] === best);
      if (leaders.length === 1) {
        const winner = leaders[0];
        collectFromEach(deltas, ids, winner, atStake);
        results.push({ hole: h.hole, status: "won", carriedInCents: carry, atStakeCents: atStake, winnerUserId: winner, net });
        carry = 0;
      } else {
        results.push({ hole: h.hole, status: "pushed", carriedInCents: carry, atStakeCents: atStake, winnerUserId: null, net });
        carry = carryover ? atStake : 0;
      }
    }
    return { holes: results, deltas, complete: !blocked, carryOutCents: carry };
  }

  // src/engines/wad.ts
  function scoreWad(input) {
    const { players, holes, scores, holeEvents, startCents, stepCents } = input;
    const deltas = zeroDeltas(players);
    const ignored = [];
    const makersByHole = new Map(holeEvents.map((e) => [e.hole, e.wadMakers]));
    const scored = new Set(scores.map((s) => `${s.hole}:${s.userId}`));
    const segments = [
      ["front", holes.filter((h) => h.hole <= 9)],
      ["back", holes.filter((h) => h.hole > 9)]
    ];
    const instances = [];
    for (const [segment, segHoles] of segments) {
      if (segHoles.length === 0) continue;
      const ordered = [...segHoles].sort((a, b) => a.hole - b.hole);
      let holder = null;
      let value = startCents;
      const makes = [];
      for (const h of ordered) {
        const seen = /* @__PURE__ */ new Set();
        for (const userId of makersByHole.get(h.hole) ?? []) {
          if (!players.includes(userId)) {
            ignored.push({ hole: h.hole, userId, reason: "not-a-player" });
            continue;
          }
          if (seen.has(userId)) {
            ignored.push({ hole: h.hole, userId, reason: "duplicate" });
            continue;
          }
          seen.add(userId);
          if (holder !== null) value += stepCents;
          holder = userId;
          makes.push({ hole: h.hole, userId, valueCents: value });
        }
      }
      const lastHole = ordered[ordered.length - 1].hole;
      const complete = players.every((p) => scored.has(`${lastHole}:${p}`));
      if (complete && holder !== null) collectFromEach(deltas, players, holder, value);
      instances.push({ segment, holderUserId: holder, valueCents: value, makes, complete });
    }
    return { instances, deltas, ignored };
  }

  // src/engines/settlement.ts
  function settle(...gameDeltas) {
    const positions = addDeltas(...gameDeltas);
    const total = Object.values(positions).reduce((a, b) => a + b, 0);
    if (total !== 0) throw new Error(`deltas must sum to zero, got ${total}`);
    const byAmountThenId = (a, b) => b[1] - a[1] || a[0].localeCompare(b[0]);
    const creditors = Object.entries(positions).filter(([, v]) => v > 0);
    const debtors = Object.entries(positions).filter(([, v]) => v < 0).map(([id, v]) => [id, -v]);
    const transfers = [];
    while (creditors.length > 0 && debtors.length > 0) {
      creditors.sort(byAmountThenId);
      debtors.sort(byAmountThenId);
      const creditor = creditors[0];
      const debtor = debtors[0];
      const amount = Math.min(creditor[1], debtor[1]);
      transfers.push({ from: debtor[0], to: creditor[0], amountCents: amount });
      creditor[1] -= amount;
      debtor[1] -= amount;
      if (creditor[1] === 0) creditors.shift();
      if (debtor[1] === 0) debtors.shift();
    }
    return { positions, transfers };
  }

  // src/engines/wolf.ts
  var WOLF_PLAYERS = 4;
  var WOLF_HOLES = 18;
  var WOLF_ROTATION_HOLES = 16;
  var WOLF_POINTS = {
    /** To the Wolf and to the partner when their side wins. */
    partnerWin: 2,
    /** To each of the two opponents when the Wolf and partner lose. */
    partnerLoss: 3,
    /** To the Wolf when the Lone Wolf wins. */
    loneWin: 4,
    /** To each of the three opponents when the Lone Wolf loses. */
    loneLoss: 1
  };
  function isPermutation(order, ids) {
    return order.length === ids.length && new Set(order).size === order.length && order.every((id) => ids.includes(id));
  }
  function zeroPoints(ids) {
    return Object.fromEntries(ids.map((id) => [id, 0]));
  }
  function scoreWolf(input) {
    const { players, teeOrder, holes, scores, holeEvents, pointCents } = input;
    if (!Number.isInteger(pointCents) || pointCents < 0) throw new Error(`pointCents must be non-negative integer cents, got ${pointCents}`);
    const ids = players.map((p) => p.userId);
    if (ids.length !== WOLF_PLAYERS || new Set(ids).size !== WOLF_PLAYERS) return null;
    if (!isPermutation(teeOrder, ids)) return null;
    const ordered = [...holes].sort((a, b) => a.hole - b.hole);
    if (ordered.length !== WOLF_HOLES || ordered.some((h, i) => h.hole !== i + 1)) return null;
    const ticks = allocateTicks(players, holes);
    const gross = new Map(scores.map((s) => [`${s.hole}:${s.userId}`, s.gross]));
    const eventByHole = new Map(holeEvents.map((e) => [e.hole, e.wolf]));
    const total = zeroPoints(teeOrder);
    const results = [];
    let standingsKnown = true;
    for (const h of ordered) {
      const event = eventByHole.get(h.hole) ?? null;
      const choice = event?.choice ?? null;
      const partner = event?.partnerUserId ?? null;
      const recordedWolf = event?.wolfUserId ?? null;
      const grossByPlayer = teeOrder.map((id) => gross.get(`${h.hole}:${id}`));
      const net = grossByPlayer.every((g) => g !== void 0) ? Object.fromEntries(teeOrder.map((id, i) => [id, netScore(grossByPlayer[i], ticks[id][h.hole])])) : null;
      const result = {
        hole: h.hole,
        wolfUserId: null,
        status: "pending",
        invalidReason: null,
        choice,
        partnerUserId: partner,
        lastPlace: null,
        wolfSide: null,
        opponents: null,
        wolfSideNet: null,
        opponentsNet: null,
        net,
        points: zeroPoints(teeOrder)
      };
      results.push(result);
      const standingsBefore = standingsKnown;
      standingsKnown = false;
      const invalid = (reason) => {
        result.status = "invalid";
        result.invalidReason = reason;
      };
      if (choice === "lone" && partner !== null) {
        invalid("partner_and_lone");
        continue;
      }
      if (choice === "partner" && partner === null) {
        invalid("partner_missing");
        continue;
      }
      if (partner !== null && !ids.includes(partner)) {
        invalid("partner_not_a_player");
        continue;
      }
      if (recordedWolf !== null && !ids.includes(recordedWolf)) {
        invalid("wolf_not_a_player");
        continue;
      }
      if (h.hole <= WOLF_ROTATION_HOLES) {
        const rotation = teeOrder[(h.hole - 1) % WOLF_PLAYERS];
        if (recordedWolf !== null && recordedWolf !== rotation) {
          invalid("wolf_contradicts_rotation");
          continue;
        }
        result.wolfUserId = rotation;
      } else {
        if (!standingsBefore) continue;
        const fewest = Math.min(...teeOrder.map((id) => total[id]));
        const last = teeOrder.filter((id) => total[id] === fewest);
        result.lastPlace = last;
        if (recordedWolf !== null && !last.includes(recordedWolf)) {
          invalid("wolf_not_in_last_place");
          continue;
        }
        if (last.length > 1 && recordedWolf === null) {
          result.status = "needs_wolf";
          continue;
        }
        result.wolfUserId = recordedWolf ?? last[0];
      }
      const wolf = result.wolfUserId;
      if (partner === wolf) {
        invalid("partner_is_wolf");
        continue;
      }
      if (choice === null || net === null) continue;
      const wolfSide = partner === null ? [wolf] : [wolf, partner];
      const opponents = teeOrder.filter((id) => !wolfSide.includes(id));
      const best = (side) => Math.min(...side.map((id) => net[id]));
      const wolfSideNet = best(wolfSide);
      const opponentsNet = best(opponents);
      result.wolfSide = wolfSide;
      result.opponents = opponents;
      result.wolfSideNet = wolfSideNet;
      result.opponentsNet = opponentsNet;
      standingsKnown = standingsBefore;
      if (wolfSideNet === opponentsNet) {
        result.status = "tied";
        continue;
      }
      const wolfSideWon = wolfSideNet < opponentsNet;
      result.status = wolfSideWon ? "won_by_wolf_side" : "won_by_opponents";
      const winners = wolfSideWon ? wolfSide : opponents;
      let each;
      if (choice === "lone") each = wolfSideWon ? WOLF_POINTS.loneWin : WOLF_POINTS.loneLoss;
      else each = wolfSideWon ? WOLF_POINTS.partnerWin : WOLF_POINTS.partnerLoss;
      for (const id of winners) {
        result.points[id] = each;
        total[id] = total[id] + each;
      }
    }
    const allPoints = teeOrder.reduce((sum, id) => sum + total[id], 0);
    const deltas = Object.fromEntries(
      teeOrder.map((id) => {
        const cents = pointCents * (WOLF_PLAYERS * total[id] - allPoints);
        return [id, cents === 0 ? 0 : cents];
      })
    );
    return { teeOrder: [...teeOrder], holes: results, points: total, deltas, complete: standingsKnown };
  }
  return __toCommonJS(index_exports);
})();
