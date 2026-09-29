# ADR-0010: Game rules and payout model

- Status: Accepted
- Date: 2026-09-29

## Context

The initial domain model left several payout rules open (Open Questions 1-8 in the first draft of `docs/domain-model.md`). The product owner answered them; this records the decisions.

## Decision

- **Payout shape:** every game uses "collect from each": the winner collects the amount from each other player. All results are netted into one settlement per round (after hole 9 for a 9-hole round, after 18 otherwise).
- **Wad:** start value and step are configurable per round (defaults $7 and $2). The first qualifying make of an instance takes the Wad at the start value; every later make adds the step, including the current holder making another. Several players can make qualifying putts on one hole; they are recorded in order. The holder at the end of each nine collects the current value from each other player.
- **Wad capture:** the app records, per hole, the ordered list of players who made a qualifying putt. There is no distance entry; the group judges "flagstick length or longer" on the course.
- **Skins:** sole lowest net score wins and collects the hole value from each other player. Ties push and carry (next hole = carried + base). Carryovers continue through the turn.
- **Greenies:** eligible = tee shot on the green and par or better. At most one greenie per par 3; if several players are eligible, the closest tee shot to the pin wins. Recorded per hole as the winner (or none). This replaces the earlier "every eligible player earns one and they wash" description.
- **Handicaps:** default is the WHS course handicap computed from Handicap Index, slope, rating, and par for the selected tee, with a per-round override.

## Consequences

- Wad makes and the greenie winner are **hole-level group facts**, not per-player flags, so they move from the per-player score item to a per-hole item (`docs/data-model.md`) with their own API endpoint (`docs/api.md`). Any participant can edit them.
- Engines for Skins, Wad, and Greenies are unblocked (milestones M4.2-M4.4).
- Still open: an unresolved Skins carryover after the final hole, and a player leaving mid-round (see `docs/domain-model.md`).
