# Data Model — DynamoDB single table

One table, named `wad-<env>` (e.g. `wad-dev`). Access patterns drive the key design. Do not add new tables without an ADR; prefer new item types and GSIs.

Attributes `PK`/`SK` are the primary key. `GSI1PK`/`GSI1SK` back the secondary index `GSI1`. `type` names the item kind. `ttl` (epoch seconds) is set on ephemeral items.

## Item types

| Entity | PK | SK | Notes |
| --- | --- | --- | --- |
| User profile | `USER#<userId>` | `PROFILE` | `userId` = Cognito `sub`. Holds display name, handicap index, Venmo handle. |
| Course | `COURSE#<courseId>` | `PROFILE` | Cached scorecard in `course` (the `Course` type in `backend/src/shared/types.ts`: per-tee par, stroke index, yardage, rating, slope). `courseId` is `gca-<provider id>` for GolfCourseAPI courses or `man-<id>` for manual entries. Kept indefinitely; course data is static. Manual entries also carry `createdBy` (the creator's `userId`) and `createdAt`. Writes are conditional: a manual course is only created if the key is free, and the provider write-through only replaces a course from the same source. |
| Course correction | `COURSE#<courseId>` | `CORRECTION#<submittedAt ISO>#<correctionId>` | A user's suggested fix in `correction` (`CourseCorrection` in `backend/src/shared/courseInput.ts`), with `status: "pending"` and `submittedBy`. Never applied to the course automatically. |
| Course search | `COURSESEARCH#<normalized query>` | `RESULTS` | Cached provider search results. Has `ttl` (7 days); also checked on read because DynamoDB deletes expired items lazily. |
| Round | `ROUND#<roundId>` | `META` | Course id, tee, date, status, base amounts and enabled games. |
| Round player | `ROUND#<roundId>` | `PLAYER#<userId>` | Course handicap for this round, computed ticks per hole, join time. |
| Hole score | `ROUND#<roundId>` | `SCORE#<hole:02d>#<userId>` | One player's gross strokes for one hole. |
| Hole events | `ROUND#<roundId>` | `HOLE#<hole:02d>` | Group-level facts for one hole (see below). Any participant can edit. |
| Game config | `ROUND#<roundId>` | `GAME#<gameType>` | Per-round settings (base value, whether enabled, reset rules). |
| Game state | `ROUND#<roundId>` | `STATE#<gameType>#<segment>` | Derived/checkpointed engine state (e.g. Wad holder+value per nine). Rebuildable from scores. |
| Settlement | `ROUND#<roundId>` | `SETTLEMENT` | Final net positions and pairwise transfers with paid/unpaid status. |
| WS connection | `ROUND#<roundId>` | `CONN#<connectionId>` | Live WebSocket connections for fan-out. Has `ttl`. |
| Join code | `JOINCODE#<code>` | `ROUND` | Maps a short code to a `roundId`. Has `ttl`. |

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
| 8 | List a course's corrections, oldest first (review; not exposed by the API yet) | `PK=COURSE#id, SK begins_with CORRECTION#` |

### GSI1 (user history)
Round items and round-player items carry:
- `GSI1PK = USER#<userId>` (the round's creator, and each participant on their player item)
- `GSI1SK = ROUND#<startEpoch>#<roundId>`

so a user's rounds list newest-first without a scan.

## Consistency & derivation

- **Scores and hole events are the source of truth.** Game state items (`STATE#...`) and the settlement item are **derived** from scores + hole events + game config by the pure engines. They are cached for fast reads and live updates, but must be reproducible by replaying the engines over the inputs. A "recompute round" operation should always be safe.
- **Money is integer cents** everywhere it is stored.
- **TTL** auto-expires `CONN#` items (short, e.g. a few hours) and `JOINCODE#` items (e.g. until round end + a buffer).

## Notes for implementers

- Keep the single-table access patterns above authoritative; if a new screen needs a new pattern, add it here first, then decide between a `begins_with` query, a new GSI, or a derived item.
- The Open Course JSON shape is the reference for the `COURSE#` payload; see [course-data.md](course-data.md).
