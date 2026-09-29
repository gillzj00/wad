# API Contract

Two surfaces: an **HTTP API** for CRUD and a **WebSocket API** for live round sync. All HTTP routes except the health check require a valid Cognito JWT (`Authorization: Bearer <token>`); the caller's user id is the token `sub`. All money fields are **integer cents**. This contract is the boundary between `ios/` and `backend/`; keep the shared types in `backend/src/shared/` in sync with it and update this doc when it changes.

## HTTP API

Base path: `/v1`.

### Health
- `GET /health` -> `200 { "status": "ok" }` (no auth)

### Profile
- `GET /me` -> current user's profile
- `PUT /me` -> update `{ displayName, handicapIndex, venmoHandle }`

### Courses
- `GET /courses?q=<search>` -> `{ courses: CourseSummary[] }`, proxied from the provider and cached for 7 days per normalized query. `q` must be at least 3 characters (`400 query_too_short`); clients should debounce, since the provider's free tier allows only a few dozen requests a day.
- `GET /courses/{courseId}` -> `{ course: Course }`: tees (each with its own pars and stroke indexes, grouped by `gender`) and per-hole par/strokeIndex/yardage. A tee with `strokeIndexValid: false` cannot be used for handicap strokes. `404 course_not_found` if unknown.
- Provider failures: `503 course_provider_rate_limited` when the provider's daily limit is hit, `502 course_provider_unavailable` otherwise.
- Shapes are the `CourseSummary` / `Course` types in `backend/src/shared/types.ts`.
- `POST /courses` -> `201 { course: Course }`: create a manual course when the provider lacks it. Body: `{ courseName, clubName?, location?: { address?, city?, state?, country?, latitude?, longitude? }, tees: [{ name, gender?: "male" | "female", courseRating?, slope?, holes: [{ hole, par, strokeIndex, yardage? }] }] }`.
  - `courseName` is required; `clubName` defaults to it. 1 to 12 tees; `gender` defaults to `"male"`.
  - `courseRating` (positive) and `slope` (integer 55-155) are optional but must be given together.
  - Each tee lists exactly 18 holes numbered 1-18, `par` 3-5, `strokeIndex` a permutation of 1-18, `yardage` an optional positive integer. 9-hole courses are not supported.
  - The server generates `courseId` (`man-<uuid>`), sets `source: "manual"` and records the caller as the creator; ids, sources and owners in the body are ignored. Manual courses are read with `GET /courses/{courseId}` and do not appear in search.
- `POST /courses/{courseId}/corrections` -> `201 { correction: CourseCorrection }`: suggest a correction to a stored course (provider or manual). Body: `{ teeId?, courseRating?, slope?, holes?: [{ hole, par?, strokeIndex?, yardage? }], note? }` with at least a `note` (up to 500 characters) or one corrected value; `teeId` is required, and must be a tee of the course, when values are corrected. The correction is stored as `status: "pending"` for later review and **does not change the course**. `404 course_not_found` if the course is not stored.
- Both `POST` routes return `401 unauthorized` without a caller `sub`, `400 invalid_body` when the body is not JSON, and `400 validation_failed` with the offending field in `error.field` and in the message (e.g. `tees[0].holes[5].par`).
- Request and correction shapes are in `backend/src/shared/courseInput.ts`.

### Rounds
- `POST /rounds` -> create `{ courseId, teeId, date, holes: 18, games: { skins?: { baseCents }, wad?: { startCents, stepCents }, greenies?: { amountCents } } }`; a game is enabled by including it. `201 { round, joinCode }`; the caller is the first player.
  - `date` is the day of play, `YYYY-MM-DD`.
  - Amounts are non-negative integer cents (`400 invalid_amount`). An amount left out of an included game takes its default: skins 500, wad 700 start and 200 step, greenies 500. `games` is required and may be `{}`; an unknown game is `400 unknown_game`.
  - `holes: 9` is rejected with `400 nine_hole_rounds_unsupported` until the 9-hole handicap rule is decided (domain model, Open Question 3).
  - The course must already be cached (`404 course_not_found`) and have the tee (`404 tee_not_found`). The tee needs 18 holes with valid stroke indexes (`400 tee_not_usable`). The round keeps its own copy of the tee, so later course corrections do not change a round.
- `GET /rounds/{roundId}` -> `{ round }`: meta, players, scores and hole events. Players only (`403 not_a_participant`); `404 round_not_found`. `state` is the current game state, computed by the engines on every read (see Game state).
- `POST /rounds/join` -> `{ joinCode }` joins the caller to a round and returns `200 { round }`. Joining again is a no-op that returns the round. `404 join_code_not_found` for an unknown or expired code, `409 round_full` when the round already has 4 players.
- `POST /rounds/{roundId}/players` -> add a guest/non-app player `{ displayName, handicapIndex }`; `201 { round, player }`. Players only. `displayName` is at most 40 characters. Guests count toward the 4 players (`409 round_full`) and get a server-generated `userId` starting `guest_`.
- Join codes are 6 characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (no 0/O or 1/I/L). Input is case-insensitive and may contain spaces or hyphens. A code works for 48 hours after the round is created.
- A round has 2 to 4 players. These routes enforce the maximum when players are added; they do not enforce the minimum, since a round starts with only its creator.
- The caller's `displayName` and `handicapIndex` come from their profile; creating or joining without both is `409 profile_incomplete`. `handicapIndex` is a number from -10 to 54; a plus handicap is negative (+1.2 is `-1.2`).
- `courseHandicap` is computed from the handicap index and the tee's rating, slope and par. It is `null` when the tee has no rating and slope, until it is set with the per-round override. `ticksByHole` lists only the holes where the player gets ticks, and is `null` until every player has a course handicap.
- A body that is missing or not JSON is `400 invalid_json`; a missing or mistyped field is `400 invalid_body`.
- `PUT /rounds/{roundId}/players/{userId}/handicap` -> per-round handicap override `{ courseHandicap }` (null clears it)
- `PUT /rounds/{roundId}/scores` -> upsert a gross score for a hole: `{ hole, gross, userId? }`; `200 { round }`. `userId` defaults to the caller; any participant may set a guest player's score.
  - `hole` is a whole number 1-18 (`400 invalid_hole`). `gross` is a whole number 1-20 (`400 invalid_gross`), or `null` to clear the score. `userId` must be a player in the round (`400 unknown_player`).
  - A player sets only their own score; setting or clearing another member's is `403 not_score_owner`.
  - Each player's score on a hole is its own item and the last write wins, so writing the same score again changes nothing and players scoring the same hole at once do not affect each other.
- `PUT /rounds/{roundId}/holes/{hole}` -> set the hole's group events `{ wadMakers?: [userId, ...], greenieWinner?: userId | null }`; `200 { round }`. Any participant may. `wadMakers` is ordered by when the putts were made.
  - Send either field or both (`400 invalid_body` for neither). Only the fields sent are written, and the last write wins per field, so one device setting the greenie does not undo the wad makers another device set.
  - `{hole}` is 1-18 (`400 invalid_hole`). `wadMakers` has at most 4 ids, each a player in the round (`400 unknown_player`) and listed once (`400 duplicate_wad_maker`); `[]` clears it.
  - `greenieWinner` must be a player in the round (`400 unknown_player`) and the hole a par 3 (`400 not_a_par_three`); `null` clears it. A winner whose stored score on the hole is over par is rejected (`400 greenie_winner_over_par`). A winner with no score yet is accepted, because scores and hole events can arrive in any order; the greenie is `pending` in `state` until the score arrives, and `invalid` (not paid) if that score, or a later correction, is over par.
- `GET /rounds/{roundId}/settlement` -> `200 { settlement }`: net positions + pairwise transfers (at most one fewer than the players with a non-zero balance). Players only (`403 not_a_participant`); `404 round_not_found`. See Settlement.
- `POST /rounds/{roundId}/settlement/transfers/{transferId}/paid` -> mark a transfer paid; `200 { settlement }`. No body.
- `DELETE /rounds/{roundId}/settlement/transfers/{transferId}/paid` -> mark a transfer unpaid; `200 { settlement }`.
- `POST /rounds/{roundId}/recompute` -> `200 { state }`: re-derive the game state from the stored scores and hole events. No body. Players only. State is not stored, so this writes nothing and returns the same `state` as `GET /rounds/{roundId}`; settlement is re-derived by the settlement API.

### Game state

`state` is what the engines in `backend/src/engines` return, unchanged (`RoundState` in `backend/src/shared/rounds.ts`). A game that is not enabled is left out.

- `skins`: `{ holes, deltas, complete, carryOutCents }`, or `null` until every player has a course handicap. Each hole has `status` (`won`, `pushed` or `pending`), `carriedInCents`, `atStakeCents`, `winnerUserId` and `net`. A hole is `pending` while it, or an earlier hole, is missing a score. When `complete` is true and `carryOutCents` is not zero, the last hole was pushed: that carryover is unresolved and is **not paid** (domain model, Open Question 1).
- `wad`: `{ instances, deltas, ignored }` with one instance per nine (`segment` `front` or `back`): `holderUserId`, `valueCents`, `makes` and `complete`. The holder is paid in `deltas` once every player has a score on the nine's last hole.
- `greenies`: `{ holes, deltas }` with one entry per par 3: `winnerUserId` and `status` (`none`, `awarded`, `pending` or `invalid`). Only `awarded` is paid.
- `deltas` is each player's running result in that game, in cents; positive is owed to them.

### Settlement

The settlement is derived on every read from the game state: `positions` and `transfers` are what the `settle` engine returns for the `deltas` of the enabled games. Nothing is stored except the paid markers. The `Settlement` type is in `backend/src/shared/settlement.ts`.

```json
{
  "roundId": "r_abc",
  "status": "final",
  "incompleteHoles": [],
  "issues": [],
  "games": { "skins": { "u_1": 1500, "u_2": -1500 }, "wad": { "u_1": 0, "u_2": 0 }, "greenies": { "u_1": -500, "u_2": 500 } },
  "positions": { "u_1": 1000, "u_2": -1000 },
  "transfers": [
    { "transferId": "t_3f9c0a1b2c3d4e5f6a7b8c9d", "from": "u_2", "to": "u_1", "amountCents": 1000, "toVenmoHandle": "zach-g", "paid": true, "paidAt": "2026-10-03T20:00:00.000Z", "paidBy": "u_2" }
  ],
  "skinsCarryover": { "amountCents": 500, "unresolved": true },
  "stalePayments": []
}
```

- `status` is `final` when every player has a score on every hole and `issues` is empty; otherwise `provisional`. A provisional settlement shows where the round stands and is not what is owed. `incompleteHoles` lists the holes missing a score.
- `issues` lists what keeps the result from being final, each `{ code, hole, userId, message }`:
  - `skins_unavailable`: skins is enabled but a player has no course handicap, so skins is not in the positions (`games.skins` is `null`).
  - `greenie_pending` / `greenie_invalid`: a recorded greenie that is not paid (see Game state). Clear or correct the winner, or the score, to resolve it.
  - `wad_make_ignored`: a recorded wad make the engine ignored.
- `games` holds each enabled game's `deltas`. `positions` has every player, positive is owed to them, and sums to zero.
- `skinsCarryover` is the skins `carryOutCents`, or `null` when skins is not enabled or unavailable. With `unresolved: true` the last hole was pushed: the amount is shown and is **never part of a position or transfer** (domain model, Open Question 1).
- `toVenmoHandle` is the payee's `venmoHandle` from their profile, or `null` (no handle, or a guest). The client builds the Venmo deep link; the server builds no links and moves no money.
- `transferId` is derived from the round, payer, payee and amount. A score correction that changes a transfer gives it a new id, so a paid marker never moves to a different transfer or amount. A marker that matches no current transfer is listed in `stalePayments` (`{ transferId, from, to, amountCents, paidAt, paidBy }`) so the client can show that a payment was recorded before the correction.
- Marking paid or unpaid:
  - Only the payer or the payee may (`403 not_transfer_party`). A guest has no account, so any player may mark a transfer that a guest pays or receives.
  - `404 transfer_not_found` when the id is not a transfer of the current settlement. `DELETE` also accepts the id of a stale payment, to remove it.
  - Marking paid needs a final settlement: `409 round_incomplete` while holes are missing scores, `409 settlement_has_issues` while there are issues. Marking unpaid is always allowed.
  - Both are idempotent. Marking a paid transfer again keeps the first `paidAt` and `paidBy`.

### Round shape (illustrative)

The `Round` type in `backend/src/shared/rounds.ts`.

```json
{
  "roundId": "r_abc",
  "course": { "courseId": "c_1", "name": "...", "teeId": "male-blue", "tee": "Blue" },
  "date": "2026-10-03",
  "holeCount": 18,
  "status": "in_progress",
  "joinCode": "ABCD2F",
  "createdBy": "u_1",
  "createdAt": "2026-10-03T14:00:00.000Z",
  "games": { "skins": { "baseCents": 500 }, "wad": { "startCents": 700, "stepCents": 200 }, "greenies": { "amountCents": 500 } },
  "players": [
    { "userId": "u_1", "displayName": "Zach", "handicapIndex": 13.1, "courseHandicap": 15, "ticksByHole": { "1": 1, "3": 1 }, "guest": false, "joinedAt": "2026-10-03T14:00:00.000Z" }
  ],
  "scores": [
    { "userId": "u_1", "hole": 4, "gross": 4 }
  ],
  "holes": [
    { "hole": 4, "wadMakers": ["u_2", "u_1"], "greenieWinner": null }
  ],
  "state": {
    "skins": {
      "holes": [ { "hole": 1, "status": "pushed", "carriedInCents": 0, "atStakeCents": 500, "winnerUserId": null, "net": { "u_1": 4, "u_2": 4 } } ],
      "deltas": { "u_1": 0, "u_2": 0 },
      "complete": false,
      "carryOutCents": 500
    },
    "wad": {
      "instances": [ { "segment": "front", "holderUserId": "u_1", "valueCents": 900, "makes": [ { "hole": 4, "userId": "u_2", "valueCents": 700 }, { "hole": 4, "userId": "u_1", "valueCents": 900 } ], "complete": false } ],
      "deltas": { "u_1": 0, "u_2": 0 },
      "ignored": []
    },
    "greenies": {
      "holes": [ { "hole": 3, "winnerUserId": "u_1", "status": "pending" } ],
      "deltas": { "u_1": 0, "u_2": 0 }
    }
  }
}
```

## WebSocket API

Used only while a round is live. Auth via token on `$connect` (query string or subprotocol). The server tracks the connection against the round for fan-out.

Client -> server actions:
- `{ "action": "subscribe", "roundId": "r_abc" }`
- `{ "action": "score", "roundId": "r_abc", "hole": 4, "gross": 4 }`
- `{ "action": "holeEvents", "roundId": "r_abc", "hole": 4, "wadMakers": ["u_2", "u_1"], "greenieWinner": null }`

Server -> client events (broadcast to the round):
- `{ "event": "scoreUpdated", "roundId": "r_abc", "userId": "u_1", "hole": 4, ... }`
- `{ "event": "holeUpdated", "roundId": "r_abc", "hole": 4, "wadMakers": [...], "greenieWinner": null }`
- `{ "event": "stateUpdated", "roundId": "r_abc", "state": { ...as above... } }`
- `{ "event": "playerJoined", "roundId": "r_abc", "player": { ... } }`

The authoritative game state in `stateUpdated` is produced by the server-side engines after each mutation. Clients may compute optimistically but must reconcile to server state.

## Errors

JSON `{ "error": { "code": "string", "message": "string" } }` with conventional HTTP status codes (400 validation, 401 auth, 403 not a round participant, 404, 409 conflict, 429 rate limit, 500).

## Versioning

Path-versioned (`/v1`). Breaking changes bump the version; the shared types are the contract of record.
