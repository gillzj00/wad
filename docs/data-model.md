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
| Round | `ROUND#<roundId>` | `META` | Course id, a copy of the tee (rating, slope, par and stroke index per hole), date, status, join code, creator, `games` (enabled games and their amounts in cents) and `playerCount`. |
| Round player | `ROUND#<roundId>` | `PLAYER#<userId>` | Display name, handicap index, course handicap for this round (null on an unrated tee), `guest` flag, join time. Ticks are derived on read. A guest's `userId` starts `guest_`. |
| Hole score | `ROUND#<roundId>` | `SCORE#<hole:02d>#<userId>` | One player's gross strokes for one hole. |
| Hole events | `ROUND#<roundId>` | `HOLE#<hole:02d>` | Group-level facts for one hole (see below). Any participant can edit. |
| Game config | `ROUND#<roundId>` | `GAME#<gameType>` | Reserved. Game settings currently live in `games` on the round item; nothing writes this item. |
| Game state | `ROUND#<roundId>` | `STATE#<gameType>#<segment>` | Reserved. Game state is computed by the engines on every read; nothing writes this item. |
| Settlement | `ROUND#<roundId>` | `SETTLEMENT` | Reserved. Positions and transfers are derived by the engines on every read; nothing writes this item. |
| Transfer paid | `ROUND#<roundId>` | `SETTLEMENT#PAID#<transferId>` | Marks one derived transfer as paid. Holds `transferId`, `from`, `to`, `amountCents`, `paidAt`, `paidBy`. |
| WS connection | `ROUND#<roundId>` | `CONN#<connectionId>` | Live WebSocket connections for fan-out. Has `ttl`. |
| Join code | `JOINCODE#<code>` | `ROUND` | Maps a short code to a `roundId`. Has `ttl` (48 hours after the round is created); also checked on read. |

Hole score item: `userId`, `hole` and `gross` — integer strokes for that player on that hole. Clearing a score deletes the item.

Hole events item (group facts, consumed by engines; see `docs/domain-model.md`):
- `hole` — the hole number.
- `wadMakers` — ordered list of user ids whose first putt on the green was holed from at least a flagstick's length, in the order made. Empty when nobody qualified. A user appears at most once.
- `greenieWinner` — user id or null; par 3s only. Must be a player who scored par or better on the hole. The winner can be recorded before their score, and the score can be corrected afterwards, so the stored winner is not proof of a paid greenie: the engine decides.
- Either field can be absent when only the other has been set; an absent `wadMakers` reads as empty and an absent `greenieWinner` as null.

Both items also carry `updatedAt` (ISO timestamp) and `updatedBy` (the caller's user id) from the last write.

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
| 9 | List a round's paid transfers | `PK=ROUND#id, SK begins_with SETTLEMENT#PAID#` |

### GSI1 (user history)
Round items and round-player items carry:
- `GSI1PK = USER#<userId>` (the round's creator, and each participant on their player item)
- `GSI1SK = ROUND#<startEpoch>#<roundId>`

so a user's rounds list newest-first without a scan. `startEpoch` is when the round was created, in epoch seconds. Guest player items carry neither attribute.

## Consistency & derivation

- **Scores and hole events are the source of truth.** Game state and the settlement are **derived** from scores + hole events + game config by the pure engines. Game state is not stored: it is computed when a round is read, so it cannot go stale and a "recompute round" operation is always safe. If state is ever cached in `STATE#...` items it must stay reproducible by replaying the engines over the inputs.
- **Score and hole event writes are unconditional, last writer wins** (ADR-0004). Each player's score on a hole is its own item, written with a put (or a delete to clear it), so players scoring the same hole at the same time never overwrite each other and a repeated write is harmless. Hole events are written with an update that sets only the fields sent, so the wad makers and the greenie winner of a hole are last-writer-wins separately.
- **Paid markers are tied to the transfer they were made for.** Transfers are not stored. `transferId` is a digest of the round id, payer, payee and amount, and the marker stores those values too; a marker counts only for a current transfer with the same id, payer, payee and amount. After a score correction a changed transfer has a new id, so an old marker matches nothing and is reported as a stale payment instead of marking another transfer paid. The marker is written with `attribute_not_exists(PK)`, so marking twice keeps the first; unmarking is a delete.
- **Money is integer cents** everywhere it is stored.
- **Round writes are conditional transactions.** Creating a round writes the join code, the round and the creator's player item together, each with `attribute_not_exists(PK)`; a join code collision cancels the write and it is retried with a new code. Adding a player increments `playerCount` on the round with the condition `playerCount < 4` and puts the player item with `attribute_not_exists(PK)`, so concurrent joins cannot exceed four players or add someone twice.
- **TTL** auto-expires `CONN#` items (short, e.g. a few hours) and `JOINCODE#` items (48 hours after the round is created).

## Notes for implementers

- Keep the single-table access patterns above authoritative; if a new screen needs a new pattern, add it here first, then decide between a `begins_with` query, a new GSI, or a derived item.
- The Open Course JSON shape is the reference for the `COURSE#` payload; see [course-data.md](course-data.md).
