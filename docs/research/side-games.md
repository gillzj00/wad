# Side-game research: candidates beyond Wad, Skins and Greenies

Status: research only. Nothing here is a decided rule. No game described below may be implemented until the product owner (@gillzj00) has answered its rule questions and the answers are recorded in `docs/domain-model.md` and an ADR.

## How to read this document

- **Rules vary by group.** Every game below is folk practice, not a governed format (the exceptions are Stableford and match play, which are in the Rules of Golf). Where sources describe different versions, the versions are listed as variants and none is presented as the correct one.
- **Verification levels.** Sources in section 5 are split into pages that were opened and read, and pages known only through search-result summaries. Anything that rests only on the second group, or on no source at all, is marked **(unverified)**. Where opened sources contradict each other it is marked **(sources disagree)**.
- **Worked examples** are illustrations of one variant with made-up stakes. They are arithmetic checks, not proposed defaults.
- **Popularity** is a judgment. No survey or usage data was found. The basis is how consistently a game appears across the golf publications and game lists consulted, and is stated per game.
- **Effort** is a rough size for engine + data model + API + on-course UI: S (reuses existing inputs and payout shape), M (new hole-level input or new payout shape), L (new mid-hole or per-hole decisions, teams, or several of the above).

### What the engines receive today

From `backend/src/engines` and `docs/data-model.md`:

- Gross strokes per player per hole.
- Per hole, group facts: `wadMakers` (ordered list of players) and `greenieWinner` (one player or none).
- Each player's course handicap (or per-round override), turned into ticks relative to the lowest handicap in the group.
- Par and stroke index per hole.
- Per-game amounts in integer cents.

Payouts all use `collectFromEach`, each engine returns per-player deltas that sum to zero, and `settle` nets all games into one set of transfers. Game state is derived on every read and never stored, and hole-level facts are last-writer-wins per field.

### Two payout shapes that recur below

1. **Collect from each.** One winner collects a fixed amount from every other player. This is the existing convention and is always whole cents.
2. **Pay the point difference.** Players accumulate points; at the end every pair settles the difference in their points at an agreed value per point. For `n` players this gives each player `value * (n * own points - total points)`. It sums to zero and is whole cents whenever points are whole numbers. It is equivalent to "each point collects its value from each other player", so it is compatible with the existing convention, but it is a new calculation.

Team games in a foursome (2 v 2) are normally settled so that each player on the losing side pays the stake and each player on the winning side receives it. That also sums to zero in whole cents.

---

## 1. Summary table

| Game | Players | Individual or team | Gross or net | Recorded per hole beyond gross scores | Payout style | Popularity (basis) | Effort |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Nassau | 2-4 (match play needs 2 sides) | Either | Either, usually net | Nothing; manual presses need a press event | Three fixed bets (front, back, 18), plus presses | Very high (described as the classic bet in nearly every source) | M |
| Match play, individual | 2 (3-4 as pairwise matches) | Individual | Either | Nothing | Fixed bet per match | High (a form of play in the Rules of Golf; basis of Nassau) | S-M |
| Wolf | 4 (3 and 5 variants) | Changes every hole | Usually net | Wolf's choice: partner, lone or blind | Points, pay the difference | Very high (in almost every list consulted) | L |
| Bingo Bango Bongo | 3-4 (2 possible) | Individual | Neither (scores are irrelevant) | Three winners: first on, closest, first in | Points, pay the difference | High | M |
| Sixes / Round Robin / Hollywood | Exactly 4 | Teams, rotating every 6 holes | Usually net | Nothing (pairing order at setup) | Fixed bet per six-hole match | Medium-high | M |
| Vegas | Exactly 4 | Fixed teams of 2 | Usually gross **(unverified)** | Nothing | Per point, team difference | Medium-high | M |
| Stableford / points | 2-4 | Individual | Net (gross possible) | Nothing | Points, pay the difference, or fixed bet | High (in the Rules of Golf; strong in the UK) | S |
| Chicago / quota | 2-4 | Individual | Handicap sets the quota | Nothing | Points over quota | Medium | S |
| Snake | 2-4 | Individual | n/a | Who three-putted, in order | Holder pays each other player | High as an add-on | S |
| Junk / Dots / Trash | 2-4 | Individual (team variants exist) | Group choice | One flag per achievement per player | Per dot, collect from each | High as an add-on | M-L (depends on item list) |
| Closest to the pin / long drive | 2-4 | Individual | n/a | One winner on designated holes | Collect from each | High (also a junk item) | S |
| Hammer | 2, or 4 as 2 v 2 | Either | Either | Hammers thrown, accepted or declined | Per hole, doubled per accepted hammer | Medium | L |
| Banker | 3-4 | Individual v banker | Either | Each player's stake; presses | Pairwise v banker, variable stakes | Medium | L |
| Rabbit | 2-4 | Individual | Either, net in two sources | Nothing | Holder collects per nine | Medium | S |
| Nines (5-3-1) | 3 (4-player variant) | Individual | Either | Nothing | Points, pay the difference | Medium-high for threesomes | S |
| Aces and Deuces | Exactly 4 in the source read | Individual | Either | Nothing | Low collects from each; high pays each | Low-medium | S |
| Defender | 3-4 | 1 v rest, rotating | Either | Nothing (rotation is fixed) | Points, pay the difference | Low-medium | S-M |
| Scotch / Umbrella | Exactly 4 | Fixed teams of 2 | Usually net, birdie gross | Closest in regulation; presses | Per point, team difference | Low-medium, regional **(unverified)** | L |
| Split Sixes | 3 | Individual | Either | Nothing | Points, pay the difference | Low-medium | S |

---

## 2. Games

Each section uses the same headings: play, variants, example, new data, fit, rule questions.

### 2.1 Nassau (with presses)

**Play.** Three separate bets of the same size: the front nine, the back nine, and the full 18. A "$5 Nassau" is $15 at risk. Each bet is won by the side with the better result over those holes, most often at match play (holes won), sometimes at stroke play (total strokes).

**Variants.**
- Match play or stroke play; with or without handicap strokes.
- Match play needs two sides (1 v 1 or 2 v 2 best ball). Stroke play allows more players or teams.
- **Press:** the trailing side opens a new bet, usually the same size as the one being lost, over the remaining holes of that bet. A front-nine bet cannot be pressed during the back nine.
- When a press is allowed: any time the side is behind, or only when 2 down. One source says the opponent may decline but usually accepts.
- **Automatic press:** a press opens by rule when a side goes 2 down.
- **Tied bet:** usually a push with no money; some groups carry the bet into the next segment **(unverified: search summaries and one opened source)**.
- "Adjust": some groups re-balance strokes after the front nine.

**Example.** A and B, 1 v 1, net match play, $5 Nassau. A wins the front 2 up, the back is tied, so A wins the 18 by 2. Front: B pays $5. Back: push. 18: B pays $5. B owes A $10. With a press: B was 2 down after 6 and pressed for $5 over holes 7-9, then won that press 1 up. The press pays B $5, so B owes A $5 in total.

**New data.** None for the base game or for automatic presses, which are a pure function of the scores. Manual presses need an event: which bet, who pressed, starting on which hole, and whether it was accepted if declining is allowed.

**Fit.** Amounts are fixed whole-cent bets, so integer cents hold. One settlement per round holds. "Collect from each" does not apply directly: a match has two sides, not a winner and the rest. With 3 or 4 individual players the format has to be chosen first (see questions).

**Rule questions.**
1. Match play or stroke play? Net or gross?
2. With 3 or 4 players: pairwise matches between every pair, 2 v 2 best ball, or stroke play with the single best score collecting from each?
3. In net play, are strokes the existing group-relative ticks, or the difference between the two players in each match?
4. Tied bet: push, carry over, or something else? In stroke play with several players, what if two tie for best?
5. Presses: none, automatic, or manual? Trigger (2 down, or any deficit)? Size? Can a press be declined? Can a press be pressed? Any limit per nine? Does the 18-hole bet press?
6. 9-hole rounds: a single bet, or not offered?

### 2.2 Match play, individual

**Play.** Two players. Each hole is won by the lower score, or tied. The match is won by the player who is more holes up than there are holes left. With handicaps, strokes are given by hole using the stroke index and the lower net score wins the hole (Rules of Golf, Rule 3.2).

**Variants.** A fixed bet on the match; a bet per hole won; a bet per hole up at the end. Three-Ball Match Play (Rule 21) has three players each playing a separate match against the other two.

**Example.** $10 on the match. A is 3 up with 2 to play and wins 3 and 2. B pays A $10.

**New data.** None.

**Fit.** Whole cents, one settlement. Payout is pairwise, not collect from each. It is the building block for a match-play Nassau, so the two should share an engine.

**Rule questions.**
1. Bet per match, per hole, or per hole up?
2. With 3 or 4 players, is every pair a separate match?
3. Strokes: difference between the two opponents, or existing group-relative ticks? These give different results when the pair does not include the group's lowest handicap.
4. Tied match: push?
5. Do the remaining holes matter once the match is decided?

### 2.3 Wolf

**Play.** Four players tee off in a fixed rotating order. The player whose turn it is to be Wolf decides, hole by hole, whether to take one of the others as a partner (2 v 2) or play alone against the other three. Sides are compared by best ball. The Wolf usually has to decide on each player right after that player's tee shot, before the next one hits.

**Variants.**
- **Lone Wolf:** the Wolf plays alone after seeing the tee shots, for higher stakes.
- **Blind Wolf:** the Wolf declares alone before anyone tees off, for higher stakes again (one source says three or four times normal).
- **Points (sources disagree).** Two opened sources agree on: Wolf and partner win, 2 points each; they lose, 3 points to each opponent; Lone Wolf wins, 4 points. They disagree on a losing Lone Wolf: one gives each opponent 1 point, the other 2.
- **Holes 17 and 18.** With four players the rotation covers 16 holes. One source gives the last two holes to the player in last place; another gives them to the two players with the most points **(sources disagree)**.
- **Ties:** usually no points; some groups carry over.
- Three-player and five-player versions exist.
- Payout: pay the point difference, or a pot.

**Example.** $1 a point, using the 2/3/4 values. Hole 1: Wolf A takes B; their best ball beats C and D. A and B get 2 points each. Paying the difference on that hole alone: C pays A $2 and B $2, D the same. A +$4, B +$4, C -$4, D -$4. Hole 2: Wolf B goes alone and wins, 4 points. B collects $4 from each: B +$12, the others -$4 each.

**New data.** Per hole: who the Wolf is (derivable from the order), the choice (partner and which one, lone, or blind), and at setup the tee order.

**Fit.** Whole points give whole cents. The per-hole choice is a hole-level group fact and fits the existing hole events item. It needs exactly the player count the chosen variant supports.

**Rule questions.**
1. Exact points for each of the four outcomes, and for Blind Wolf.
2. Who is Wolf on 17 and 18?
3. Ties: no points, or carry over?
4. Net or gross best ball? Which strokes?
5. Is it offered for 3 players, and with what rules?
6. How is the tee order chosen?
7. Must the choice be recorded before scores are entered, or is it trusted?

### 2.4 Bingo Bango Bongo

**Play.** Three points on every hole: first ball on the green (bingo), closest to the hole once every ball is on the green (bango), first to hole out (bongo). Scores do not matter, so it suits mixed abilities without handicaps.

**Variants.**
- Strict order of play (farthest from the hole plays first) is part of the game. A player who plays out of turn forfeits the point to the next player to achieve it.
- Double points for winning all three on one hole **(unverified)**.
- No gimmes **(unverified)**.

**Example.** $1 a point, three players. On one hole A is first on, B is closest and B holes out first: A 1, B 2, C 0. Paying the difference: B +$3, A $0, C -$3.

**New data.** Three winners per hole (each a player or none).

**Fit.** Whole points, whole cents, pay the difference. Three taps a hole is the heaviest routine entry of any game here.

**Rule questions.**
1. Value per point, and is the sweep doubled?
2. What if nobody can be given a point (for example, a hole is picked up)?
3. Does a holed shot from off the green win all three?
4. Is the out-of-turn rule enforced by the app or left to the group?

### 2.5 Sixes (Round Robin, Hollywood)

**Play.** Four players. The round is three six-hole matches, 2 v 2, with a different partner each time, so everyone partners everyone once. Each match is a separate bet.

**Variants.** Any 2 v 2 scoring works inside a match (best ball is typical; the format can change between matches). Overall winner can also be whoever wins at least two of the three matches. How pairings are ordered is a group choice.

**Example.** $5 a match, best ball. Holes 1-6: A and B beat C and D. Holes 7-12: A and C tie B and D. Holes 13-18: B and C beat A and D. A: +5, 0, -5 = $0. B: +5, 0, +5 = +$10. C: -5, 0, +5 = $0. D: -5, 0, -5 = -$10.

**New data.** None per hole. The pairing order at setup.

**Fit.** Whole cents. Needs exactly 4 players and an 18-hole round. The engine needs a team concept that the current engines do not have.

**Rule questions.**
1. Scoring inside each match: best ball match play, best ball stroke total, or other?
2. Net or gross, and which strokes?
3. Tied six-hole match: push or carry?
4. How are pairings ordered?
5. Does a match end early once it is decided, and are presses allowed?

### 2.6 Vegas

**Play.** Four players in two fixed teams. On each hole a team's two scores are written as a two-digit number with the lower score first (4 and 5 make 45). The lower number wins the difference in points.

**Variants.**
- **Birdie flip:** a birdie forces the other team to put its higher score first (56 becomes 65). It cancels if both teams birdie.
- **Eagle:** flip and double.
- A score of 10 or more goes first so the number stays smaller **(unverified)**.
- Presses or "rolls" by the trailing team.

**Example.** $1 a point. A 4, B 5 make 45. C 5, D 6 make 56. Difference 11: C and D pay $11 each, A and B receive $11 each. If A had made a birdie 3, the numbers are 35 and a flipped 65: difference 30.

**New data.** None per hole. Teams at setup.

**Fit.** Whole points, whole cents. The swings are large and the point value needs to be small; a cap per hole may be wanted. Exactly 4 players.

**Rule questions.**
1. Gross or net scores in the number? Is a net birdie a birdie?
2. Flip and eagle rules on or off; what cancels?
3. The 10-or-more rule.
4. A cap on points per hole?
5. How are teams chosen, and are they fixed for 18?

### 2.7 Stableford and points games

**Play.** Points per hole against a fixed score, normally par, using net scores. Rule 21 of the Rules of Golf gives: 0 for two or more over, 1 for one over, 2 for level, 3 for one under, 4 for two under, and so on upward. Most points wins.

**Variants.**
- **Modified Stableford** uses other values, including negative ones. One professional event uses 8, 5, 2, 0, -1, -3 for albatross through double bogey or worse.
- Gross instead of net.
- Payout by point difference, a fixed bet to the winner, or a pot.
- St. James Roll (one source): 3, 2, 1, 0 points for beating three, two, one or none of the others on a hole.

**Example.** Net Stableford, $1 a point, three players finishing on 36, 32 and 30. A collects $4 from B and $6 from C; B collects $2 from C. A +$10, B -$2, C -$8.

**New data.** None.

**Fit.** Whole points, whole cents. One caution: the existing ticks are relative to the lowest handicap in the group, which is right for comparing players with each other. Stableford compares each player with par, where the usual practice is full handicap strokes. Relative ticks would still rank the players fairly but would give different point totals from a normal Stableford card.

**Rule questions.**
1. Standard or modified values? Exact table.
2. Net or gross? If net, full course handicap strokes or group-relative ticks?
3. Payout: point difference, fixed bet collected from each, or other?
4. Tie for most points under a fixed-bet payout.
5. Played over 18 only, or also per nine?

### 2.8 Chicago (quota)

**Play.** Each player has a quota of 39 minus course handicap. Points are scored gross: bogey 1, par 2, birdie 4, eagle 8. The result is points minus quota; the best result wins.

**Variants.** Some groups use 36 as the base **(unverified)**. Payout by difference, equal pot split, or winner takes all. Team version with combined quotas.

**Example.** A (handicap 10, quota 29) scores 31, result +2. B (handicap 20, quota 19) scores 24, result +5. At $1 a point B collects $3 from A.

**New data.** None.

**Fit.** Whole points, whole cents. Uses the absolute course handicap rather than relative ticks, which the round already stores.

**Rule questions.** Base number (39 or 36); point table; payout style; ties; quota for a 9-hole round.

### 2.9 Snake

**Play.** A player who three-putts takes the snake and holds it until someone else three-putts. Whoever holds it at the end pays.

**Variants.**
- **Fixed:** the holder pays an agreed amount to each other player.
- **Growing:** the amount rises with every three-putt, by a fixed step or by doubling. One source's example reaches $128 a player after eight three-putts from $1.
- Payment to each other player, or a pot shared among the others.
- Another version makes the player with the most three-putts pay.
- Putts from off the green do not count **(unverified)**.
- Two three-putts on one hole: the snake goes to the last of them to hole out **(unverified)**.
- No gimmes, so every putt is holed.
- Played over 18 in the sources read; per nine was not found **(unverified)**.

**Example.** Fixed $5, four players. Three-putts on hole 3 (A), 11 (C) and 16 (B). B holds the snake and pays $5 to each of the others: B -$15, the rest +$5 each. Doubling from $1: three three-putts make it $1, $2, $4, so B pays $4 each.

**New data.** Per hole, the ordered list of players who three-putted. This is the same shape as `wadMakers`.

**Fit.** The engine is almost a mirror of Wad: an ordered list per hole, a holder, a value that steps, and a payout at the end where the holder pays each instead of collecting from each. Whole cents in the fixed and growing versions. A shared pot can split unevenly (section 4).

**Rule questions.**
1. Fixed, stepped or doubling value? Start and step. Any cap?
2. Does the value rise when the current holder three-putts again?
3. Order when two players three-putt on one hole.
4. Does a putt from the fringe count? Four-putts?
5. Per nine, like Wad, or per 18?
6. Does the holder pay each other player, or a pot?

### 2.10 Junk, Dots, Trash, Garbage

**Play.** A menu of small bonuses, agreed on the first tee, layered on top of a main game. Each achievement earns a dot, and dots are paid at a fixed value.

**Items found, with the definitions given.**

| Item | Definition in sources | Notes |
| --- | --- | --- |
| Birdie (and eagle) | Birdie or better; eagle may count double | Derivable from scores |
| Greenie | Closest on the green, then par or better | Already in Wad, par 3s only; some groups add other holes |
| Sandy | Par or better after being in a bunker | One source counts any bunker, another only greenside up-and-down **(sources disagree)** |
| Barkie | Par or better after hitting a tree | **(unverified)** for the exact wording |
| Arnie | Par on a par 4 or 5 without being in the fairway | One version also requires missing the green in regulation **(sources disagree)** |
| Polie / flaggie | A holed putt longer than the flagstick | One search summary described it as a putt inside that length, which contradicts the others **(sources disagree, unverified)**. One source pays 2 dots |
| Chippie | Holing out from off the green | |
| Sharkie | Par or better after being in water | |
| Closest to the pin, long drive, fairways, greens in regulation | As named | |
| Negative dots | Three-putt, double bogey or worse, penalty, lost ball | Optional |

**Variants.** Any subset; any value per item; pay the difference or a pot; team dots in 2 v 2 games.

**Example.** $1 a dot, four players. A earns 3 dots, B earns 1, C and D none. Each dot collects $1 from each other player. A: +9 - 1 = +$8. B: +3 - 3 = $0. C and D: -$4 each.

**New data.** One flag per item per player per hole, except items that follow from scores (birdies, and negative dots for double bogey).

**Fit.** Each dot is a collect-from-each payment, so this is the closest match to the existing convention. Two overlaps need a decision: Greenies is already a junk item, and a polie is very close to a qualifying Wad make, so `wadMakers` could feed it. The entry burden grows with every item switched on.

**Rule questions.**
1. Which items are offered, and the exact definition of each (the table shows how much they vary).
2. One value for all dots or a value per item?
3. Are birdies gross or net?
4. Can one shot or hole earn several dots?
5. Negative dots: offered at all?
6. If Greenies and junk are both on, is the greenie paid twice?

### 2.11 Closest to the pin and long drive

**Play.** On designated holes, the closest tee shot on the green (usually par 3s), or the longest drive finishing in the fairway (a par 4 or 5), wins.

**Variants.** Every par 3 or only chosen holes; one winner per hole, or one winner for the whole round holding the best shot; long drive must be in the fairway; approach shots eligible from a minimum distance. These details come from search summaries **(unverified)**.

**Example.** $5 on each par 3, four players. A is closest on hole 4 and collects $5 from each: +$15.

**New data.** One winner per designated hole, and the designated holes at setup for long drive.

**Fit.** Same shape as `greenieWinner`: one player or none per hole, collect from each. Closest to the pin is Greenies without the par requirement.

**Rule questions.** Which holes; is par or better required (if so it is Greenies); must the long drive be in the fairway; one prize per hole or per round.

### 2.12 Hammer

**Play.** A match-play bet per hole between two sides. At any moment during a hole a side can "hammer", offering to double the hole. The other side accepts, or declines and loses the hole at the current value.

**Variants.**
- A side cannot hammer twice in a row; the hammer passes back and forth **(unverified)**.
- Either side may throw the first hammer on each hole **(unverified)**; one opened source says the right rotates.
- Air hammer: must be called while the ball is in the air **(unverified)**.
- Limits on hammers per hole or per round.
- Tied holes carrying over were not confirmed in any opened source **(unverified)**.

**Example.** $2 a hole, A v B. A hammers after the tee shots; B accepts ($4). B hammers on the green; A accepts ($8). A wins the hole: B pays $8. Had B declined the first hammer, B would have lost the hole for $2.

**New data.** Per hole: the sequence of hammers, who threw each, and accept or decline. At minimum the final multiplier and whether the hole ended by a decline.

**Fit.** Doubling whole cents stays whole. Two sides only. Decisions happen mid-hole, which is the hardest case for sync (section 3).

**Rule questions.** Who may hammer first; alternation; limit; whether a hammer can come after a ball is holed; tied hole; cap on hole value; 3 or 4 individual players or teams only.

### 2.13 Banker

**Play.** One player is the banker on each hole. Every other player has a separate bet against the banker, and chooses its size between the group minimum and the maximum.

**Variants.**
- In the opened source the banker is the player with the lowest score on the previous hole, and the banker names the hole's maximum. A search summary instead described a rotation **(sources disagree)**.
- Presses: a player may double after their own tee shot and before the banker's; the banker may double back but must double everyone.
- On par 3s a press must be called with the ball in the air and triples the bet.
- Gross or net.
- One search summary said tied holes carry over; this was not in the opened source **(unverified)**.

**Example.** Minimum $1, maximum $5. Banker A makes net 4. B bet $2 and makes 5: A collects $2. C bet $5 and makes 4: push. D bet $1 and makes 3: A pays $1. A +$1, B -$2, C $0, D +$1.

**New data.** Per hole: the banker, each player's stake, and each press.

**Fit.** Whole cents if stakes are whole cents. Payouts are pairwise against the banker. Several entries per hole, some before the hole is played.

**Rule questions.** How the banker is chosen, including the first hole and ties; minimum and maximum; press rules; par-3 rule; tie between a player and the banker; net or gross.

### 2.14 Rabbit

**Play.** The first player to win a hole outright catches the rabbit. If a different player wins a later hole outright, the rabbit is set free, and the next outright winner catches it. Whoever holds it after 9 and after 18 wins the bet for that nine.

**Variants.**
- **Steal:** an outright win by another player takes the rabbit directly, with no free step.
- **Legs:** the holder adds a leg for each further hole won, and the others must win that many to free it.
- If nobody holds it after 9, one source says the holder after 18 wins both bets.
- Pot that grows with every hole won.
- Net in two sources; one source does not say.
- Whether the back nine starts with the rabbit free was not stated consistently **(unverified)**.

**Example.** $5 a nine, four players. A holds the rabbit after 9 and collects $5 from each: +$15. Nobody holds it after 18: no payment for the back nine under the simplest reading.

**New data.** None. The hole winner is the same sole-lowest-net test Skins already makes.

**Fit.** Collect from each, whole cents, per-nine instances like Wad. It overlaps heavily with Skins, so its added value alongside Skins is a product question.

**Rule questions.** Free-then-catch or steal; legs; what happens when nobody holds it at 9 or 18; does the back nine start fresh; net or gross.

### 2.15 Nines (5-3-1, Nine Point)

**Play.** Three players. Nine points on every hole: 5 for the best score, 3 for the middle, 1 for the worst.

**Variants.**
- **Ties** share the points for the tied places: two tied for best get 4 each; two tied for worst get 2 each; all tied get 3 each.
- A sole winner with a birdie takes 7, the others 1 each (one source).
- **Four players:** 5-3-1-0 with ties averaged, which produces fractional points (all four tied is 2.25 each).
- Payout by point difference; a pot; or a version where last place pays both others.
- Nassau-style, as separate front, back and 18 bets.

**Example.** $1 a point, three players, 18-hole totals A 70, B 52, C 40 (162 points, 9 a hole). A collects $18 from B and $30 from C; B collects $12 from C. A +$48, B -$6, C -$42.

**New data.** None.

**Fit.** With three players every tie gives whole points, so whole cents. It fills a gap: most team games need four, and this is the standard threesome game. The four-player version needs care (section 4).

**Rule questions.** Net or gross; tie table; birdie bonus; is a four-player version offered and with what table; payout style.

### 2.16 Aces and Deuces (Acey Ducey)

**Play.** Four players. On each hole the sole lowest score (the ace) collects the ace bet from each other player, and the sole highest score (the deuce) pays the deuce bet to each other player. The ace bet is typically twice the deuce bet.

**Variants.** A tie for low or high usually cancels that bet for the hole; some groups carry it over. Handicaps are recommended for mixed groups.

**Example.** Ace $2, deuce $1. A makes 4, B and C make 5, D makes 6. A collects $2 from each (+$6) and $1 from D (+$7). D pays $1 to each (-$3) and $2 to A (-$5). B and C each pay $2 and receive $1 (-$1 each).

**New data.** None.

**Fit.** Exactly the existing payout shape plus its mirror. Whole cents. Only one source was opened for this game, and it describes foursomes only; use with 3 players is **(unverified)**.

**Rule questions.** Net or gross; ties cancel or carry; ace and deuce values; 3-player play.

### 2.17 Defender

**Play.** One player defends each hole against the others, in a fixed rotation. With three players each defends six holes; with four each defends four and two holes are left out.

**Variants (sources disagree on points).**
- With losses: defender wins 3 and the others lose 1 each; a tie gives the defender 1.5 and the others lose 0.5; a loss costs the defender 3 and gives the others 1 each.
- Without losses: defender wins 3, ties 2, otherwise the others get 1 each.
- A third table appears in a search summary **(unverified)**.

**Example.** No-loss table, $1 a point, three players, one hole: defender A wins, 3 points. Paying the difference, A collects $3 from each: +$6, B and C -$3 each.

**New data.** None per hole. Rotation order at setup.

**Fit.** Pay the difference. The with-losses table has half points.

**Rule questions.** Which table; which two holes are skipped with four players; net or gross; rotation order.

### 2.18 Scotch (Six Point) and Umbrella

**Play.** Two fixed teams of two. Several points are available on each hole. In Six Point Scotch: 2 for low ball, 2 for low team total, 1 for closest to the pin, 1 for a birdie. Winning all of them doubles the hole.

**Variants.** Only natural (gross) birdies count in the source read. Presses for one hole or for the rest of the nine, by the trailing team only. Umbrella scales the points with the hole number **(unverified)**.

**Example.** $1 a point. A and B take low ball, low total and the birdie; C and D take closest: 5 to 1, a difference of 4. C and D pay $4 each, A and B receive $4 each.

**New data.** Closest in regulation per hole; presses.

**Fit.** Whole cents. Exactly four, teams, one tap a hole plus press decisions.

**Rule questions.** Point table; tie on any point; press rules; closest measured when; net or gross for low ball and total.

### 2.19 Split Sixes

**Play.** Three players share six points on each hole according to their scores.

**Variants.** The point table was not confirmed in any opened source **(unverified)**; only the six-points-a-hole structure was.

**New data.** None.

**Fit.** Same engine shape as Nines with a different table. No example is given because the table is unverified.

**Rule questions.** The full point and tie table; net or gross; payout style.

---

## 3. Fit analysis

### 3.1 No new on-course entry (scores, handicaps, par and stroke index only)

Nassau without presses or with automatic presses, individual match play, Stableford and other points games, Chicago, Rabbit, Nines, Split Sixes, Aces and Deuces, Defender, Vegas, Sixes.

Notes:
- Vegas, Sixes and Defender need something chosen **at setup** (teams, pairing order, rotation) but nothing during play.
- These games are pure functions of data the app already syncs. They inherit the current offline and multi-device behavior unchanged: each player's score is their own item, state is derived on read, and a late-arriving score simply changes the derived result.
- The engines need two things they do not have: a **team / best-ball** concept (Sixes, Vegas, 2 v 2 Nassau) and a **pay-the-difference** payout.

### 3.2 One extra tap per hole (hole-level group fact)

| Game | Fact | Closest existing field |
| --- | --- | --- |
| Snake | Ordered list of three-putters | `wadMakers` |
| Closest to the pin, long drive | One winner or none, on designated holes | `greenieWinner` |
| Junk, per item | Players who earned it | `wadMakers` (unordered) |
| Scotch | Closest in regulation | `greenieWinner` |
| Bingo Bango Bongo | Three winners, so three taps | `greenieWinner` three times |

These fit the hole events item as new optional fields. Last-writer-wins per field already keeps one device's greenie from undoing another device's Wad makers, and the same holds for new fields. Order-sensitive lists (Snake) have the same property as `wadMakers`: two devices editing the same hole's list offline will overwrite each other, which is accepted today.

### 3.3 Team or partner selection

| When | Games |
| --- | --- |
| Once at setup | Vegas, Scotch, 2 v 2 Nassau |
| Every six holes (known at setup) | Sixes |
| Every hole, fixed rotation (known at setup) | Defender, the Wolf role itself |
| Every hole, a decision on the course | Wolf (partner, lone or blind), Banker (who is banker depends on the last hole) |

Anything known at setup is round configuration and needs no live sync. All team games here need exactly four players, except Defender and the Wolf variants.

### 3.4 Mid-round decisions

Manual presses (Nassau, Scotch, Vegas), hammers, Wolf's choice, Banker stakes and presses.

Implications:

- **They are inputs, not derived state.** They would be stored as hole-level events, and the engines would stay pure: same inputs, same result.
- **Timing matters to the game but cannot be enforced offline.** A Wolf choice or a hammer is meant to be made before the outcome is known. A device without signal can only record it locally and sync later, so the server cannot prove the order. The app would have to trust the group, as it already does for Wad distance and greenie proximity. Whether that is acceptable is a product decision.
- **Two-sided decisions are the hard case.** A hammer or a declinable press needs an offer from one side and a response from the other, possibly on different devices with no signal. Recording only the agreed outcome after the fact (final multiplier, who conceded) on any one device avoids a live handshake. Hammer and Banker are the games most affected.
- **Conflicts.** One decision per hole, written by whoever records it, fits last-writer-wins. A sequence of decisions in one hole (hammers) is an ordered list with the same overwrite risk as `wadMakers`.
- **Late decisions change money already shown.** A press recorded after the fact changes derived results for holes already played. That is consistent with how score corrections behave today, including stale paid markers.
- **Automatic presses avoid all of this.** They are computed from scores, so they need no entry, no sync and no trust.

### 3.5 Conventions check

| Convention | Holds for | Needs attention |
| --- | --- | --- |
| Integer cents | All fixed-bet and whole-point games | Fractional points and shared pots (section 4) |
| Collect from each | Snake (mirrored), Rabbit, closest to the pin, long drive, junk, Aces and Deuces | Match and team games are side against side; points games pay the difference. Both still produce zero-sum whole-cent deltas that `settle` can net |
| One settlement per round | All | None found. Nothing requires payment mid-round |
| 2 to 4 players | Individual games | Exactly 4: Sixes, Vegas, Scotch, standard Wolf, Aces and Deuces. Best with 3: Nines, Split Sixes, Defender. Two sides: match play, Hammer |
| 18-hole rounds only (current API) | All | Per-nine games (Nassau, Rabbit) split like Wad |

---

## 4. Recommendation

Ranked by weighing popularity, reuse of the existing engines and data model, and entry burden on the course. This is a recommendation for discussion, not a decision.

1. **Nassau, net, with automatic presses as an option.** The most widely described golf bet in the sources. The base game and automatic presses need no new entry and work offline as-is. It brings the match-play engine with it, so individual match play comes almost free. Main cost: the owner has to choose the format for 3 and 4 players, and the payout is side against side. Manual presses can follow later.
2. **Stableford-style points, with Nines as a second point table.** No new entry, small engine, works for 2 to 4 players, and Nines covers threesomes. It introduces the pay-the-difference payout that Wolf, Bingo Bango Bongo and junk would reuse. Open point: relative ticks against full handicap strokes.
3. **Snake.** One tap on the rare hole where someone three-putts, and the engine mirrors Wad almost exactly. It suits the app's putting-game identity. Low cost, low risk.
4. **Wolf.** As popular as Nassau in the lists consulted and the most requested kind of four-player game, but it needs a recorded decision on every hole and has the most disputed rules (points, holes 17 and 18). Best built after the points payout exists.
5. **Junk, starting with a short list.** A natural fit for collect from each and for the hole events item, and Greenies is already one of its items. The risk is entry burden and definition disputes, so start with items that are cheap to record (birdies from scores, closest to the pin, sandies) and add others on request.

Worth a look because it is nearly free: **Rabbit** reuses the Skins hole-winner test and the per-nine structure of Wad. Its overlap with Skins is the reason it is not ranked.

Not recommended for now: **Hammer** and **Banker** (mid-hole, two-sided decisions that fit poorly with offline play), **Bingo Bango Bongo** (three entries on every hole), **Vegas** and **Scotch** (exactly four players, large swings, and several unverified rules).

### Fractional cents and uneven splits

The existing games avoid fractions because every payment is a whole-cent amount paid by each player. These cases would break that and need a rule from the owner before any code is written:

| Case | Why it is a problem | What sources say groups do |
| --- | --- | --- |
| Nines with four players | Averaged ties give fractional points. Paying the difference multiplies points by the number of players, so halves and quarters cancel, but a three-way tie for last gives 4/3 points each. The result is whole cents only if the point value is a multiple of 3 cents; $1.00 a point is not | One source simply states the fractional points. No source says how the money is rounded **(unverified)** |
| Defender, table with losses | Half points on ties | Not addressed **(unverified)** |
| Shared pots (Snake paid to a pot, Rabbit pot, winner-take-all points games) | A pot split between tied or multiple winners may not divide evenly | Not addressed **(unverified)**. Paying each player directly instead of a pot avoids it |
| Stroke-play Nassau with 3 or 4 players | Two players tying for best over a nine would split a bet | Tied bets are usually a push, which avoids the split |
| Skins carryover at the end | Already Open Question 1 in the domain model; splitting among tied players could be uneven | Out of scope here; listed because several games above share the question of what to do with a tie at the end |
| Stakes entered in dollars with odd cents | Doubling and tripling keep whole cents, halving does not | No game found requires halving a stake |

Options to put to the owner, none of them chosen here: restrict point values so results are always whole cents; forbid the variants that produce fractions; or define an explicit rounding rule that still sums to zero. Rounding each player independently must not be used, because deltas must sum to zero for `settle`.

### Could not verify

- Golf Digest's pages on these games could not be opened (blocked), so nothing here rests on them. Some details attributed to search summaries may originate there.
- Hammer: alternation, who hammers first, and tied holes.
- Wolf: points for a losing Lone Wolf and who is Wolf on 17 and 18 (sources disagree).
- Banker: how the banker is chosen (sources disagree) and whether ties carry.
- Vegas: the 10-or-more rule, and whether gross or net is normal.
- Junk: exact definitions of barkie, arnie and polie.
- Split Sixes and Umbrella point tables.
- How groups round fractional results in any game.
- Popularity: no survey or usage data was found; every rating is a judgment.

---

## 5. Sources

### Opened and read

1. https://www.randa.org/en/rog/the-rules-of-golf/rule-3
2. https://www.randa.org/en/rog/the-rules-of-golf/rule-21
3. https://en.wikipedia.org/wiki/Nassau_(bet)
4. https://en.wikipedia.org/wiki/Stableford
5. https://thegolfnewsnet.com/ryan_ballengee/2026/03/13/golf-betting-games-how-to-play-nassau-press-adjust-rules-46015/
6. https://www.nationalclubgolfer.com/club/glossary/nassau-golf-format-explained/
7. https://thegolfnewsnet.com/ryan_ballengee/2024/05/04/golf-betting-games-how-to-play-wolf-rules-46095/
8. https://theleftrough.com/wolf-golf-game/
9. https://help.18birdies.com/article/108-wolf
10. https://golf.com/lifestyle/how-to-play-bingo-bango-bongo/
11. https://golf.com/news/money-games-explained-how-to-play-sixes/
12. https://www.thefriedegg.com/articles/vegas-golf-game
13. https://golf.com/lifestyle/best-golf-gambling-games-how-to-play/
14. https://www.golfcompendium.com/2023/08/chicago-golf-format.html
15. https://www.golfcompendium.com/2025/09/snake-putting-game.html
16. https://thegolfnewsnet.com/ryan_ballengee/2026/03/13/golf-betting-games-how-to-play-snake-rules-44859/
17. https://thegolfnewsnet.com/golfnewsnetteam/2016/07/08/what-is-junk-in-golf-dots-trash-garbage-birdies-greenies-sandies-50976/
18. https://www.golfcompendium.com/2025/10/garbage-golf-game.html
19. https://theleftrough.com/dots-golf-game/
20. https://www.tampabaydowns.com/the-hammer-golf-game-how-to-play/
21. https://www.thefriedegg.com/articles/banker-golf-betting-game
22. https://thegolfnewsnet.com/ryan_ballengee/2016/07/06/golf-betting-games-how-to-play-rabbit-rules-46047/
23. https://www.australiangolfdigest.com.au/how-to-play-rabbit-golf-games-explained/
24. https://www.beezergolf.com/golf-betting-games/rabbit-game-rules
25. https://www.golfcompendium.com/2022/12/nines-golf-game.html
26. https://thegolfnewsnet.com/ryan_ballengee/2026/03/13/golf-betting-games-how-to-play-nines-5-3-1-rules-44877/
27. https://www.golfcompendium.com/2019/02/golf-game-acey-ducey.html
28. https://www.golfcompendium.com/2023/06/defender-golf-game.html
29. https://www.thefriedegg.com/articles/b-draddy-game-week-six-point-scotch

### Known only through search-result summaries (page not opened)

Details resting on these are marked unverified in the text.

30. https://help.18birdies.com/article/482-vegas-golf-betting-game-how-to-play-and-win (Vegas 10-or-more rule)
31. https://help.18birdies.com/article/476-bingo-bango-bongo (sweep doubling, no gimmes)
32. https://www.tcchammer.com/rules (Hammer alternation)
33. https://www.golfmonthly.com/features/the-game/what-is-the-snake-golf-betting-game-67209 (putts from off the green)
34. https://stickapp.golf/games/nassau/ (tied bets)
35. https://stickapp.golf/games/junk/ (junk definitions)
36. https://duckhook.golf/tournaments/dots/ (junk definitions)
37. https://www.liveabout.com/closest-to-the-pin-1560803 (closest to the pin as a side bet)
38. https://parup.golf/faqs/how-do-the-social-side-games-longest-drive-closest-to-the-pin-work/ (long drive in the fairway)
39. https://www.golfcompendium.com/2023/09/umbrella-game-golf-format.html (Umbrella)
40. https://golf.com/lifestyle/defender-golf-gambling-game-threes/ (Defender point table)
41. https://whygolf.com/blogs/whysguyscorner/golf-betting-games (relative popularity)
