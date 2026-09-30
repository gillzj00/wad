# Domain Model — Games & Handicaps

This document is the source of truth for how each game is scored and how money is computed. The rules below were confirmed by the product owner (@gillzj00); see [ADR-0010](adr/0010-game-rules.md). Anything still unresolved is listed under [Open Questions](#open-questions) and must be confirmed before implementing the affected behavior — **do not guess**.

Conventions used here:
- All money is stored and computed as **integer cents**. Display formats to dollars.
- **Stroke index** (a.k.a. hole handicap) ranks hole difficulty 1–18, where 1 is the hardest. It is per-course (and can differ by tee set).
- Wad, Skins and Greenies pay out by **"collect from each"**: the winner collects the amount from **each** other player in the round. Wolf is a points game and pays out by **"pay the difference"**: every pair of players settles the difference in their points. With integer-cent amounts neither produces fractional cents.
- All game results are netted into a **single settlement per round**. A 9-hole round settles after hole 9; an 18-hole round settles after hole 18. Nothing is paid mid-round.

---

## Handicaps and "ticks" (shared by Skins and Wolf)

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

## Game 4: Wolf

A points game for **exactly four players** over an 18-hole round. On every hole one player is the Wolf and plays the hole with a partner against the other two, or alone against the other three. See [ADR-0012](adr/0012-wolf-rules.md).

**Settings (per round):** value per point (default **$1**), and the **tee order**: the four players in a fixed order. The default tee order is the order the players were added to the round; the group can reorder it before play.

**Players:** Wolf is not played with two, three or five players, and there are no three-player rules. While a round with Wolf enabled does not have exactly four players, Wolf is **unavailable**: it has no state and is not part of the settlement. A round is created with one player and the others join afterwards, so this is checked whenever the game is scored, not when the round is created.

**Who is the Wolf:**
- **Holes 1-16:** the Wolf rotates through the tee order. Hole 1 is the first player, hole 2 the second, hole 3 the third, hole 4 the fourth, hole 5 the first again, and so on, so each player is the Wolf four times.
- **Hole 17:** the player in **last place** on Wolf points after hole 16.
- **Hole 18:** the player in last place after hole 17. The standings are worked out again, so it need not be the same player as on 17.
- **Tie for last place:** not decided yet, see [Open Question 4](#open-questions). The engine does not pick. The group records who the Wolf is for that hole; the record is accepted only if that player is one of those tied for last. Until it is recorded the hole **needs a Wolf** and scores no points.

**Choice:** on each hole the Wolf either takes **one partner** (2 v 2) or plays alone as **Lone Wolf** (1 v 3). Blind Wolf (declaring alone before anyone tees off) is not played.

**Recording:** for each hole the group records the Wolf's choice: the partner, or lone. On 17 and 18 with a tie for last place the group also records the Wolf. The app does not check when the choice was made.

**Winning a hole:** net best ball. Each side's score is the **lowest net score** among its players, where net = gross - ticks, with the same relative tick allocation as Skins (see above). The lower side score wins the hole. If the two side scores are equal the hole is **tied**: nobody gets points and nothing carries over to the next hole.

**Points:**

| Outcome | Points |
| --- | --- |
| Wolf and partner win | 2 to the Wolf and 2 to the partner |
| Wolf and partner lose | 3 to each of the two opponents |
| Lone Wolf wins | 4 to the Wolf |
| Lone Wolf loses | 1 to each of the three opponents |

**When a hole is scored:** only when all four players have a gross score on it and the Wolf's choice is recorded (and, on 17 or 18 with a tie for last place, the Wolf is recorded). Otherwise it is **pending** and has no points.
- On holes 1-16 the Wolf comes from the fixed rotation, so a hole can be scored while an earlier hole is still pending.
- On 17 and 18 the Wolf comes from the standings. Hole 17 is pending until every one of holes 1-16 is scored (won or tied), and hole 18 until hole 17 is too. A hole that is pending, needs a Wolf, or is invalid holds back the holes whose Wolf depends on it.

**Invalid records:** a record that breaks the rules is reported as **invalid** and scores no points. It is never corrected silently and never paid. The cases: the partner is the Wolf; the partner is not a player in the round; a recorded Wolf on holes 1-16 who is not the one the rotation gives; a recorded Wolf on 17 or 18 who is not in last place (or not among those tied for it); a partner recorded together with lone. A record can become invalid afterwards, for example when a corrected score changes who was in last place.

**Money:** at the end, **every pair of players settles the difference in their points** at the value per point. For one player that adds up to

```
delta = value per point * (4 * own points - total points of all four)
```

which is whole cents and sums to zero over the four players. Only points from scored holes count. Wolf is **one game over the 18 holes** and is part of the single round settlement. It is played in 18-hole rounds only.

> Example ($1 a point; tee order A, B, C, D): Hole 1, Wolf A takes B and their best ball wins -> A and B get 2 each. Hole 2, Wolf B goes alone and loses -> A, C and D get 1 each. Hole 3, Wolf C takes D and they lose -> A and B get 3 each. Hole 4, Wolf D goes alone and wins -> D gets 4. Points: A 6, B 5, C 1, D 5, 17 in total. A is 1 point up on B, 5 up on C and 1 up on D: A collects $1 + $5 + $1 = **+$7**, which is `4 * 6 - 17`. B: `4 * 5 - 17` = +$3. C: `4 * 1 - 17` = -$13. D: +$3. The four add up to $0.

The engine exposes the tee order, the running points per player, the per-player deltas, whether all 18 holes are scored, and per hole: the Wolf (nullable), the status (won by the Wolf's side, won by the opponents, tied, pending, needs a Wolf, invalid) with the reason when invalid, the recorded choice and partner, the players in last place (17 and 18), the two sides, each side's net best ball, every player's net score, and the points awarded.

---

## Cross-cutting: settlement

At the end of the round the app computes each player's net position across **all** games (Wad + Skins + Greenies + Wolf), then reduces it to pairwise payments (who pays whom, how much) by repeatedly matching the largest creditor with the largest debtor, which needs at most one payment fewer than the number of players owed or owing. Those payments drive the Venmo deep links. All intermediate math stays in integer cents; only pairwise transfers are surfaced to the user.

---

## Open Questions

Resolve these with @gillzj00 before implementing the affected behavior. Update this section and add/adjust an ADR when answered.

1. **Skins — unresolved carryover at the end.** If the final hole is pushed, the carried value has no next hole. Is it simply not paid out, or is there a tiebreak (e.g. a playoff hole, or split among the tied players)? Until answered the engine must not pay it out and should expose the unresolved amount so the UI can show it.
2. **Leaving mid-round.** If a player leaves before the round ends, what happens to their games? (E.g. settle everything up to the last completed hole, or void their participation in unfinished games.)
3. **Handicaps for 9-hole rounds.** GHIN computes a separate 9-hole course handicap (about half the index, using the nine's own rating and par). Should a 9-hole round use that, or half of the 18-hole course handicap, or the full 18-hole difference? The engine allocates whatever handicaps it is given across the holes played, ranked by stroke index, so this only affects how the handicaps are computed before allocation.
4. **Wolf — tie for last place on holes 17 and 18.** The Wolf on 17 and 18 is the player in last place on points. When two or more players are tied for last, who is the Wolf? (E.g. the one earliest or latest in the tee order, the one who was Wolf longest ago, or the group's choice.) Interim behavior, to be confirmed: the engine does not pick. The hole's record may name the Wolf (`wolfUserId`), which is valid only if that player is among those tied for last; a recorded player who is not makes the hole invalid. Until a Wolf is recorded the hole has the status `needs_wolf`, scores no points, and keeps the settlement from being final.
