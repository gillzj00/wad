# Domain Model — Games & Handicaps

This document is the source of truth for how each game is scored and how money is computed. The payout math must be exact, so anything ambiguous is listed under [Open Questions](#open-questions) and must be confirmed with the product owner (@gillzj00) before implementation — **do not guess**.

Conventions used here:
- All money is stored and computed as **integer cents**. Display formats to dollars.
- **Stroke index** (a.k.a. hole handicap) ranks hole difficulty 1–18, where 1 is the hardest. It is per-course (and can differ by tee set).
- A round has 18 holes; games that "reset every 9" treat holes 1–9 (front) and 10–18 (back) as independent instances.

---

## Handicaps and "ticks" (shared by Skins)

Players of different ability are equalized by giving weaker players extra strokes ("ticks") on the hardest holes.

**Course Handicap** (World Handicap System):

```
Course Handicap = round( HandicapIndex * (Slope / 113) + (CourseRating - Par) )
```

For v1 we let players either use the computed course handicap for the selected tee or override with a manually agreed playing handicap (see [Open Questions](#open-questions) on which is the default).

**Allocating ticks (relative method):**
1. Find the lowest course handicap in the group; call it the group scratch.
2. Each player's ticks = `their course handicap − group scratch` (so the best player gets 0).
3. Allocate a player's ticks to holes in stroke-index order: 1 tick each to the holes with stroke index 1, 2, 3, … up to the number of ticks.
4. If a player has more than 18 ticks, wrap around: every hole gets 1, then the hardest holes get a 2nd, etc.

A player's **net score** on a hole = `gross strokes − ticks received on that hole`.

> Example: Zach is a 15 course handicap, friend is 7. Group scratch = 7. Zach gets `15 − 7 = 8` ticks, placed on the holes whose stroke index is 1–8 (the 8 hardest). On those holes Zach's net = gross − 1. The friend gets net = gross everywhere.

---

## Game 1: Wad (putting game)

A carrying-pot putting game that resets every 9 holes.

**Earning / holding the Wad:** On a green, a player "makes the Wad" if their **first putt on that green** is holed **from at least a flagstick's length away**. Doing so makes them the current holder.

**Value:**
- The Wad starts at **$7** for each 9-hole instance.
- Each time the Wad **transfers** to a different holder, its value increases by **$2** (so 1st transfer -> $9, 2nd -> $11, …).
- If no one qualifies on a green, the Wad stays put and the value does not change.

**Reset:** At the start of the back nine (hole 10), the Wad resets to $7 with no holder.

**Settlement:** Determined per 9-hole instance based on who holds the Wad when the instance ends. Exact direction of payment is an [Open Question](#open-questions).

State the engine must track, per 9-hole instance: current holder (nullable), current value, and the history of transfers (hole, from, to, resulting value).

### Wad open items
See [Open Questions](#open-questions): end-of-nine payout direction and recipients; definition of "flagstick length" (proposed default: a configurable constant, ~7 ft / 84 in); whether the current holder re-making it increases the value.

---

## Game 2: Skins (net, with carryovers)

Hole-by-hole net competition for a fixed amount per skin (default **$5**).

**Winning a skin:** On each hole, compute every player's net score (gross − ticks). The player with the **sole lowest net score wins the skin** for that hole.

**Push / carryover:** If two or more players tie for the lowest net score, no one wins; the hole "pushes" and its value carries to the next hole, which is then worth the carried amount **plus** the base skin value. Carrying continues until a hole is won outright.

> Example (base $5): Hole 1 ties -> hole 2 is worth $10. Hole 2 ties -> hole 3 is worth $15. Someone wins hole 3 outright -> they win $15; hole 4 resets to $5.

**Settlement model** (per-hole pot vs. loser-pays) is an [Open Question](#open-questions). The engine should expose, per hole: base value, carried-in value, total at stake, winner (nullable if pushed), and the resulting per-player deltas once the settlement model is confirmed.

Does Skins reset every 9 or run across all 18? Assume **all 18 with carryovers not crossing the 9 boundary reset** — confirm in [Open Questions](#open-questions).

---

## Game 3: Greenies (par-3 game)

Played only on par-3 holes, for a fixed amount (default **$5**).

**Earning a greenie:** A player earns a greenie on a par-3 if their **tee shot finishes on the green** (green in regulation off the tee) **and** they then score **par or better** on the hole. Hitting the green but making bogey or worse does not earn it. (Confirm the exact "on the green" and "par or better" definitions in [Open Questions](#open-questions).)

**Settlement (round-robin wash):** On each par-3, every player who did **not** earn a greenie pays the greenie amount to **each** player who **did**. Players who both earned greenies wash against each other; if everyone earns one (or no one does), the hole is a wash.

> Example (amount $5, 3 players): A and B earn greenies, C does not. C pays $5 to A and $5 to B (−$10 for C, +$5 each for A and B). A vs. B washes.

This game's rules are fully determined; the only confirmations needed are the two definitional points above.

---

## Cross-cutting: settlement

At the end of the round the app computes each player's net position across **all** games (Wad + Skins + Greenies), then reduces it to the minimum set of pairwise payments (who pays whom, how much). Those payments drive the Venmo deep links. All intermediate math stays in integer cents; only pairwise transfers are surfaced to the user.

---

## Open Questions

Resolve these with @gillzj00 before implementing the affected engine. Update this section and add/adjust an ADR when answered.

1. **Wad — end-of-nine payout.** When a 9-hole instance ends, does the holder **collect** the current value from each other player, does the holder **pay** it, or is it a single pot? Who are the counterparties (every other player, or only those who ever held it)?
2. **Wad — "flagstick length."** Use a fixed configurable distance (proposed default ~7 ft) that the scorer confirms, or capture an actual measured distance? A binary "was it a flagstick or longer?" toggle at scoring time is the proposed MVP.
3. **Wad — holder re-makes it.** If the current holder makes another qualifying putt, does the value still go up $2, or only on a change of holder? (Proposed: only on transfer.)
4. **Skins — settlement model.** Each player antes the skin value into a per-hole pot and the winner takes the pot, OR each losing player pays the skin value directly to the winner? These produce different totals for groups larger than two.
5. **Skins — 9-hole boundary.** Do carryovers reset at the turn (hole 10) or run continuously through 18?
6. **Greenies — definitions.** Confirm "on the green" = tee shot comes to rest on the green (GIR off the tee), and that **par or better** (not strictly par) earns it.
7. **Handicap default.** Default to the WHS-computed course handicap for the selected tee, or to a manually agreed playing handicap? Allow per-round override either way.
8. **Money edge cases.** Rounding rule for any odd cents (proposed: all amounts are whole dollars, so no fractional cents arise); behavior when a player leaves mid-round.
