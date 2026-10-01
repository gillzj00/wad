# ADR-0012: Wolf rules and the "pay the difference" payout

- Status: Accepted
- Date: 2026-09-29

## Context

Wolf was requested as a fourth game. The research in `docs/research/side-games.md` (section 2.3) found that the published rules disagree on several points that change the money: the points for a losing Lone Wolf, who is the Wolf on holes 17 and 18, what a tied hole does, and how the game is paid. The product owner answered the rule questions on 2026-09-29; this records the decisions. The exact rules are in `docs/domain-model.md` (Game 4: Wolf).

## Decision

- **Players:** exactly four. There are no three-player or five-player rules. A round with Wolf enabled and any other number of players has no Wolf state; Wolf is reported as unavailable, like Skins without handicaps.
- **Tee order:** a fixed order of the four players, set for the round. The default is the order the players were added, and it can be reordered before play. The Wolf rotates through it on holes 1-16.
- **Holes 17 and 18:** the Wolf is the player in last place on points, after hole 16 for hole 17 and after hole 17 for hole 18.
- **Choice:** one partner (2 v 2) or Lone Wolf (1 v 3), recorded per hole by the group. Blind Wolf is not played.
- **Winning a hole:** net best ball, with the same relative tick allocation as Skins. A tied hole gives no points and carries nothing over.
- **Points:** Wolf and partner win, 2 each. Wolf and partner lose, 3 to each opponent. Lone Wolf wins, 4. Lone Wolf loses, 1 to each opponent.
- **Money:** a value per point (default $1). Every pair of players settles the difference in their points, so a player's result is `value * (4 * own points - total points)`. Wolf is one game over 18 holes, 18-hole rounds only, and part of the single round settlement.
- **Invalid records** (the partner is the Wolf, the partner is not in the round, a recorded Wolf that contradicts the rotation or is not in last place, a partner together with lone) are reported, score no points, and are never corrected silently.

## Alternatives not chosen

From the research:

- **Blind Wolf**, with its higher stakes. Not played.
- **2 points to each opponent for a losing Lone Wolf.** The sources disagree between 1 and 2; the owner chose 1.
- **Holes 17 and 18 to the two players with the most points.** One source; the owner chose the player in last place.
- **Carrying a tied hole over** to the next hole. Ties give no points.
- **Gross best ball.** The game is net, so that players of different ability can play it, as in Skins.
- **Three-player and five-player versions.**
- **A pot** instead of paying the point difference.

## Consequences

- **A second payout shape.** Wad, Skins and Greenies pay by "collect from each" (ADR-0010). Wolf pays by "pay the difference": the engine turns points into per-player deltas itself and does not use `collectFromEach`. Both shapes produce deltas in whole cents that sum to zero, so the settlement engine takes them unchanged.
- **A team concept in an engine.** The wolf engine compares two sides per hole. The sides exist only inside a hole; no other engine changes.
- **New recorded data.** The Wolf's choice is a hole-level group fact on the existing hole events item (`wolf`), and the tee order is on the round item. No new table or index (`docs/data-model.md`). The round gets a route to set the tee order, and the hole events route takes the Wolf record (`docs/api.md`).
- **Order dependence.** On 17 and 18 the Wolf depends on the standings, so those holes are scored only when every earlier hole is. Holes 1-16 do not depend on each other.
- **The engines bundle changes.** `scoreWolf` is exported from `backend/src/engines/index.ts` and is in `ios/Wad/Resources/engines.js` (ADR-0011). The app does not call it until the Wolf screens are built.
- **Still open:** who is the Wolf on 17 or 18 when players are tied for last place (Open Question 4 in `docs/domain-model.md`). Until it is answered the engine does not pick: the group records the Wolf, who must be one of those tied, and the hole scores nothing until then.
- The tee order is locked once the round has a score or a Wolf record, which is how "before play" is enforced; changing it later would change who was the Wolf on holes already played.
