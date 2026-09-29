# Data Model — DynamoDB single table

One table, named `wad-<env>` (e.g. `wad-dev`). Access patterns drive the key design. Do not add new tables without an ADR; prefer new item types and GSIs.

Attributes `PK`/`SK` are the primary key. `GSI1PK`/`GSI1SK` back the secondary index `GSI1`. `type` names the item kind. `ttl` (epoch seconds) is set on ephemeral items.

## Item types

| Entity | PK | SK | Notes |
| --- | --- | --- | --- |
| User profile | `USER#<userId>` | `PROFILE` | `userId` = Cognito `sub`. Holds display name, handicap index, Venmo handle. |
| Course | `COURSE#<courseId>` | `PROFILE` | Cached scorecard in `course` (the `Course` type in `backend/src/shared/types.ts`: per-tee par, stroke index, yardage, rating, slope). `courseId` is `gca-<provider id>` for GolfCourseAPI courses or `man-<id>` for manual entries. Kept indefinitely; course data is static. |
| Course search | `COURSESEARCH#<normalized query>` | `RESULTS` | Cached provider search results. Has `ttl` (7 days); also checked on read because DynamoDB deletes expired items lazily. |
| Round | `ROUND#<roundId>` | `META` | Course id, a copy of the tee (rating, slope, par and stroke index per hole), date, status, join code, creator, `games` (enabled games and their amounts in cents) and `playerCount`. |
| Round player | `ROUND#<roundId>` | `PLAYER#<userId>` | Display name, handicap index, course handicap for this round (null on an unrated tee), `guest` flag, join time. Ticks are derived on read. A guest's `userId` starts `guest_`. |
| Hole score | `ROUND#<roundId>` | `SCORE#<hole:02d>#<userId>` | One player's gross strokes for one hole. |
| Hole events | `ROUND#<roundId>` | `HOLE#<hole:02d>` | Group-level facts for one hole (see below). Any participant can edit. |
| Game config | `ROUND#<roundId>` | `GAME#<gameType>` | Reserved. Game settings currently live in `games` on the round item; nothing writes this item. |
| Game state | `ROUND#<roundId>` | `STATE#<gameType>#<segment>` | Derived/checkpointed engine state (e.g. Wad holder+value per nine). Rebuildable from scores. |
| Settlement | `ROUND#<roundId>` | `SETTLEMENT` | Final net positions and pairwise transfers with paid/unpaid status. |
| WS connection | `ROUND#<roundId>` | `CONN#<connectionId>` | Live WebSocket connections for fan-out. Has `ttl`. |
| Join code | `JOINCODE#<code>` | `ROUND` | Maps a short code to a `roundId`. Has `ttl` (48 hours after the round is created); also checked on read. |

Hole score item: `gross` — integer strokes for that player on that hole.

Hole events item (group facts, consumed by engines; see `docs/domain-model.md`):
- `wadMakers` — ordered list of user ids whose first putt on the green was holed from at least a flagstick's length, in the order made. Empty when nobody qualified. A user appears at most once.
- `greenieWinner` — user id or null; par 3s only. Must be a player who scored par or better on the hole.

## Access patterns

| # | Pattern | Query |
| --- | --- | --- |
| 1 | Get a user profile | `PK=USER#id, SK=PROFILE` |
| 2 | Get a course | `PK=COURSE#id, SK=PROFILE` |
| 3 | Get everything about a round (meta, players, scores, state) | `PK=ROUND#id` (query all SKs) |
| 4 | Get one player's scores in a round | `PK=ROUND#id, SK begins_with SCORE#` then filter, or per-hole direct gets |
| 5 | Resolve a join code to a round | `PK=JOINCODE#code, SK=ROUND` |
| 6 | List a user's rounds (history) | `GSI1: GSI1PK=USER#id, GSI1SK begins_with ROUND#` |
| 7 | Fan out to live connections for a round | `PK=ROUND#id, SK begins_with CONN#` |

### GSI1 (user history)
Round items and round-player items carry:
- `GSI1PK = USER#<userId>` (the round's creator, and each participant on their player item)
- `GSI1SK = ROUND#<startEpoch>#<roundId>`

so a user's rounds list newest-first without a scan. `startEpoch` is when the round was created, in epoch seconds. Guest player items carry neither attribute.

## Consistency & derivation

- **Scores and hole events are the source of truth.** Game state items (`STATE#...`) and the settlement item are **derived** from scores + hole events + game config by the pure engines. They are cached for fast reads and live updates, but must be reproducible by replaying the engines over the inputs. A "recompute round" operation should always be safe.
- **Money is integer cents** everywhere it is stored.
- **Round writes are conditional transactions.** Creating a round writes the join code, the round and the creator's player item together, each with `attribute_not_exists(PK)`; a join code collision cancels the write and it is retried with a new code. Adding a player increments `playerCount` on the round with the condition `playerCount < 4` and puts the player item with `attribute_not_exists(PK)`, so concurrent joins cannot exceed four players or add someone twice.
- **TTL** auto-expires `CONN#` items (short, e.g. a few hours) and `JOINCODE#` items (48 hours after the round is created).

## Notes for implementers

- Keep the single-table access patterns above authoritative; if a new screen needs a new pattern, add it here first, then decide between a `begins_with` query, a new GSI, or a derived item.
- The Open Course JSON shape is the reference for the `COURSE#` payload; see [course-data.md](course-data.md).
