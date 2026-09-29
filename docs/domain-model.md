# Domain Model — Games & Handicaps

This document is the source of truth for how each game is scored and how money is computed. The rules below were confirmed by the product owner (@gillzj00); see [ADR-0010](adr/0010-game-rules.md). Anything still unresolved is listed under [Open Questions](#open-questions) and must be confirmed before implementing the affected behavior — **do not guess**.

Conventions used here:
- All money is stored and computed as **integer cents**. Display formats to dollars.
- **Stroke index** (a.k.a. hole handicap) ranks hole difficulty 1–18, where 1 is the hardest. It is per-course (and can differ by tee set).
- Every game that pays out uses **"collect from each"**: the winner collects the amount from **each** other player in the round. With integer-cent amounts this never produces fractional cents.
- All game results are netted into a **single settlement per round**. A 9-hole round settles after hole 9; an 18-hole round settles after hole 18. Nothing is paid mid-round.

---

## Handicaps and "ticks" (shared by Skins)

Players of different ability are equalized by giving weaker players extra strokes ("ticks") on the hardest holes.

**Course Handicap** (World Handicap System) is the default, computed from each player's Handicap Index and the selected tee:

```
Course Handicap = round( HandicapIndex * (Slope / 113) + (CourseRating - Par) )
```

The group can override any player's handicap for a round (e.g. an agreed playing handicap). The override replaces the computed course handicap for that round only.

**Allocating ticks (relative method):**
1. Find the lowest course handicap in the group; call it the group scratch.
2. Each player's ticks = `their course handicap − group scratch` (so the best player gets 0).
3. Allocate a player's ticks to holes in stroke-index order: 1 tick each to the holes with stroke index 1, 2, 3, … up to the number of ticks.
4. If a player has more than 18 ticks, wrap around: every hole gets 1, then the hardest holes get a 2nd, etc.

A player's **net score** on a hole = `gross strokes − ticks received on that hole`.

> Example: Zach is a 15 course handicap, friend is 7. Group scratch = 7. Zach gets `15 − 7 = 8` ticks, placed on the holes whose stroke index is 1–8 (the 8 hardest). On those holes Zach's net = gross − 1. The friend gets net = gross everywhere.

---

## Game 1: Wad (putting game)

A carrying-value putting game, played as independent instances over holes 1–9 and holes 10–18 (a 9-hole round has one instance).

**Settings (per round):** start value (default **$7**) and step (default **$2**).

**Qualifying make:** a player's **first putt on the green** is holed from **at least a flagstick's length** away. Each player has only one first putt per green, so a player can qualify at most once per hole. The group judges the distance on the course; the app does not measure it.

**Recording:** for each hole, the group records the **ordered list** of players who made a qualifying putt (usually empty, sometimes one, occasionally more). Order matters: it is the order the putts were made.

**Holding and value:** process qualifying makes in order across the nine:
- If nobody holds the Wad yet in this instance, the maker becomes the holder at the **start value**.
- Otherwise, the value increases by the **step** and the maker becomes the holder. This applies to **every** subsequent make, including the current holder making another one.

> Example (defaults): Hole 2, A makes one -> A holds at $7. Hole 5, B then C both make one, in that order -> B holds at $9, then C holds at $11. Hole 7, C makes another -> C holds at $13.

**End of instance:** after the last hole of the instance (9 or 18), the holder **collects the current value from each other player**. If nobody holds it, nothing is owed. The next instance starts fresh (no holder, start value).

State the engine exposes, per instance: current holder (nullable), current value, and the ordered history of makes (hole, maker, resulting value).

---

## Game 2: Skins (net, with carryovers)

Hole-by-hole net competition for a base amount per skin (default **$5**).

**Winning a skin:** on each hole, compute every player's net score (gross − ticks). The player with the **sole lowest net score wins the skin** and **collects the hole's value from each other player**.

**Push / carryover:** if two or more players tie for the lowest net score, nobody wins and no money changes hands on that hole. The hole's value carries forward: the next hole is worth the carried value **plus** the base value. Carrying continues until a hole is won outright.

> Example (base $5, 4 players): Hole 1: two net pars, two net bogeys -> push, hole 2 is worth $10. Hole 2 pushes -> hole 3 is worth $15. A wins hole 3 outright -> A collects $15 from each of the other three (+$45). Hole 4 is worth $5 again.

Skins is **one game over the whole round**: carryovers continue through the turn (a push on 9 carries to 10). What happens to a carryover still unresolved after the final hole is an [Open Question](#open-questions).

The engine exposes, per hole: base value, carried-in value, total at stake, winner (nullable if pushed), and the resulting per-player deltas.

---

## Game 3: Greenies (par-3 game)

Played only on par-3 holes, for a fixed amount (default **$5**).

**Eligibility:** a player is eligible on a par 3 if their **tee shot finishes on the green** and they then score **par or better** (par, birdie, or ace).

**Winner:** at most **one greenie per hole**. If more than one player is eligible, the greenie goes to the eligible player whose **tee shot finished closest to the pin**. If nobody is eligible, there is no greenie on that hole.

**Recording:** for each par 3 the group records the greenie winner (or none). The app should only offer players who scored par or better on the hole, and reject a winner who did not.

**Settlement:** the winner **collects the greenie amount from each other player**.

> Example (amount $5, 3 players): A and B both hit the green and make par; A's tee shot was closer. A wins the greenie and collects $5 from B and $5 from C (+$10).

---

## Cross-cutting: settlement

At the end of the round the app computes each player's net position across **all** games (Wad + Skins + Greenies), then reduces it to pairwise payments (who pays whom, how much) by repeatedly matching the largest creditor with the largest debtor, which needs at most one payment fewer than the number of players owed or owing. Those payments drive the Venmo deep links. All intermediate math stays in integer cents; only pairwise transfers are surfaced to the user.

---

## Open Questions

Resolve these with @gillzj00 before implementing the affected behavior. Update this section and add/adjust an ADR when answered.

1. **Skins — unresolved carryover at the end.** If the final hole is pushed, the carried value has no next hole. Is it simply not paid out, or is there a tiebreak (e.g. a playoff hole, or split among the tied players)? Until answered the engine must not pay it out and should expose the unresolved amount so the UI can show it.
2. **Leaving mid-round.** If a player leaves before the round ends, what happens to their games? (E.g. settle everything up to the last completed hole, or void their participation in unfinished games.)
3. **Handicaps for 9-hole rounds.** GHIN computes a separate 9-hole course handicap (about half the index, using the nine's own rating and par). Should a 9-hole round use that, or half of the 18-hole course handicap, or the full 18-hole difference? The engine allocates whatever handicaps it is given across the holes played, ranked by stroke index, so this only affects how the handicaps are computed before allocation.
