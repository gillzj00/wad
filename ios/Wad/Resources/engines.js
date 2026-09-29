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
    const { players, holes, scores, baseCents } = input;
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
        carry = atStake;
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
  return __toCommonJS(index_exports);
})();
