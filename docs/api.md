# API Contract

Two surfaces: an **HTTP API** for CRUD and a **WebSocket API** for live round sync. All HTTP routes except the health check require a valid Cognito JWT (`Authorization: Bearer <token>`); the caller's user id is the token `sub`. All money fields are **integer cents**. This contract is the boundary between `ios/` and `backend/`; keep the shared types in `backend/src/shared/` in sync with it and update this doc when it changes.

## HTTP API

Base path: `/v1`.

### Health
- `GET /health` -> `200 { "status": "ok" }` (no auth)

### Profile
- `GET /me` -> `200 { profile }`: the caller's profile, `{ userId, displayName, handicapIndex, venmoHandle, complete }` (the `Profile` type in `backend/src/shared/profile.ts`).
  - A field that is not set is `null`. A user who has never saved a profile gets `200` with every field `null` and `complete: false`, not a 404.
  - `complete` is true when the profile has a display name and a handicap index, which is what creating or joining a round needs (`409 profile_incomplete` otherwise).
- `PUT /me` -> update `{ displayName?, handicapIndex?, venmoHandle? }`; `200 { profile }` with the profile after the write.
  - Send any of the three fields, at least one (`400 invalid_body` for none, or for a body that is not an object). Only the fields sent are written and the last write wins per field, so two devices editing different fields do not undo each other. Other fields in the body are ignored.
  - `displayName` is trimmed and must be 1 to 40 characters (`400 invalid_display_name`). It cannot be cleared: `null` and an empty string are rejected.
  - `handicapIndex` is a number from -10 to 54 with at most one decimal place (`400 invalid_handicap_index`); a plus handicap is negative (+1.2 is `-1.2`). `null` clears it. It is entered by the user (ADR-0006).
  - `venmoHandle` is 5 to 30 letters, digits, hyphens or underscores (`400 invalid_venmo_handle`). One leading `@` is accepted and removed; the handle is stored and returned without it. `null` clears it. The server does not check that the handle exists on Venmo.
  - A body that is missing or not JSON is `400 invalid_json`.
- The user is always the caller, from the token `sub`; `401 unauthorized` without it. No route takes a user id, so a user can read and write only their own profile. Nothing else from the token is stored.
- A profile change does not change rounds the user is already in: a round keeps the display name and handicap index the player had when they were added. The settlement reads the payee's `venmoHandle` from the profile on every read.

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

#### Deployment (dev)

Interim, until the Cognito authorizer exists ([ADR-0013](adr/0013-courses-api-before-auth.md)). Only the two `GET` routes are deployed; the `POST` routes are not routed.

- Base URL: the `api_base_url` Terraform output of `infra/environments/dev` (an `execute-api` URL; routes are under `/v1`).
- Every request must carry `x-wad-client: <token>`; otherwise `401 invalid_client_token`, returned before the cache or the provider is touched. The token is a shared secret in SSM, not a user identity; `infra/README.md` explains how to fetch it for a local app build. It is not a substitute for the `Authorization` header this contract will require once auth lands.
- Throttling: burst 5, sustained 2 requests per second across all clients (`429` from API Gateway when exceeded), to protect the provider's daily quota of about 35 requests.

### Rounds
- `POST /rounds` -> create `{ courseId, teeId, date, holes: 18, games: { skins?: { baseCents, carryover }, wad?: { startCents, stepCents }, greenies?: { amountCents }, wolf?: { pointCents } } }`; a game is enabled by including it. `201 { round, joinCode }`; the caller is the first player.
  - `date` is the day of play, `YYYY-MM-DD`.
  - Amounts are non-negative integer cents (`400 invalid_amount`). An amount left out of an included game takes its default: skins 500, wad 700 start and 200 step, greenies 500, wolf 100 a point. `games` is required and may be `{}`; an unknown game is `400 unknown_game`.
  - `skins.carryover` is a boolean (`400 invalid_carryover`), `true` when left out: a pushed hole's value carries to the next hole. With `false` a push pays nothing and the next hole is worth `baseCents` again. The stored config of a round created before this setting existed has no `carryover`, which means `true`.
  - `holes: 9` is rejected with `400 nine_hole_rounds_unsupported` until the 9-hole handicap rule is decided (domain model, Open Question 3).
  - Wolf needs exactly four players. A round is created with one player, so creating a round with `wolf` is always accepted; while the round does not have exactly four players, `state.wolf` is `null` and the settlement has the issue `wolf_unavailable` (see Game state and Settlement).
  - The course must already be cached (`404 course_not_found`) and have the tee (`404 tee_not_found`). The tee needs 18 holes with valid stroke indexes (`400 tee_not_usable`). The round keeps its own copy of the tee, so later course corrections do not change a round.
- `GET /rounds/{roundId}` -> `{ round }`: meta, players, scores and hole events. Players only (`403 not_a_participant`); `404 round_not_found`. `state` is the current game state, computed by the engines on every read (see Game state).
- `POST /rounds/join` -> `{ joinCode }` joins the caller to a round and returns `200 { round }`. Joining again is a no-op that returns the round. `404 join_code_not_found` for an unknown or expired code, `409 round_full` when the round already has 4 players.
- `POST /rounds/{roundId}/players` -> add a guest/non-app player `{ displayName, handicapIndex }`; `201 { round, player }`. Players only. `displayName` is at most 40 characters. Guests count toward the 4 players (`409 round_full`) and get a server-generated `userId` starting `guest_`.
- Join codes are 6 characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (no 0/O or 1/I/L). Input is case-insensitive and may contain spaces or hyphens. A code works for 48 hours after the round is created.
- A round has 2 to 4 players. These routes enforce the maximum when players are added; they do not enforce the minimum, since a round starts with only its creator.
- The caller's `displayName` and `handicapIndex` come from their profile; creating or joining without both is `409 profile_incomplete`. `handicapIndex` is a number from -10 to 54; a plus handicap is negative (+1.2 is `-1.2`).
- `courseHandicap` is the handicap the games use. It is computed from the handicap index and the tee's rating, slope and par, unless the player has a per-round override, which replaces it. It is `null` when the tee has no rating and slope and the player has no override. `courseHandicapOverride` is the override, or `null` when there is none. `ticksByHole` lists only the holes where the player gets ticks, and is `null` until every player has a course handicap.
- A body that is missing or not JSON is `400 invalid_json`; a missing or mistyped field is `400 invalid_body`.
- `PUT /rounds/{roundId}/players/{userId}/handicap` -> set the player's course handicap for this round only: `{ courseHandicap }`; `200 { round }`. The group decides handicaps, so any participant may set or clear the override of any player in the round, guests included. Players only (`403 not_a_participant`); `404 round_not_found`.
  - `courseHandicap` is a whole number from -10 to 54 (`400 invalid_course_handicap`); a plus handicap is negative. `null` clears the override and the player is back on the computed course handicap, which is `null` on a tee with no rating and slope. Leaving the field out is `400 invalid_body`.
  - `{userId}` must be a player in the round (`400 unknown_player`).
  - The override is stored next to the computed course handicap, not over it. The last write wins, and writing the same value again changes nothing.
  - Ticks, skins and the settlement use the override from the next read, also for holes already scored. On a tee with no rating and slope, skins is available once every player has an override. A transfer that changes gets a new id, so a paid marker made before the change is listed in `stalePayments` (see Settlement).
- `PUT /rounds/{roundId}/scores` -> upsert a gross score for a hole: `{ hole, gross, userId? }`; `200 { round }`. `userId` defaults to the caller; any participant may set a guest player's score.
  - `hole` is a whole number 1-18 (`400 invalid_hole`). `gross` is a whole number 1-20 (`400 invalid_gross`), or `null` to clear the score. `userId` must be a player in the round (`400 unknown_player`).
  - A player sets only their own score; setting or clearing another member's is `403 not_score_owner`.
  - Each player's score on a hole is its own item and the last write wins, so writing the same score again changes nothing and players scoring the same hole at once do not affect each other.
- `PUT /rounds/{roundId}/holes/{hole}` -> set the hole's group events `{ wadMakers?: [userId, ...], greenieWinner?: userId | null, wolf?: { choice?, partnerUserId?, wolfUserId? } | null }`; `200 { round }`. Any participant may. `wadMakers` is ordered by when the putts were made.
  - Send at least one field (`400 invalid_body` for none). Only the fields sent are written, and the last write wins per field, so one device setting the greenie does not undo the wad makers another device set. `wolf` is one field: it is written as a whole.
  - `{hole}` is 1-18 (`400 invalid_hole`). `wadMakers` has at most 4 ids, each a player in the round (`400 unknown_player`) and listed once (`400 duplicate_wad_maker`); `[]` clears it.
  - `greenieWinner` must be a player in the round (`400 unknown_player`) and the hole a par 3 (`400 not_a_par_three`); `null` clears it. A winner whose stored score on the hole is over par is rejected (`400 greenie_winner_over_par`). A winner with no score yet is accepted, because scores and hole events can arrive in any order; the greenie is `pending` in `state` until the score arrives, and `invalid` (not paid) if that score, or a later correction, is over par.
  - `wolf` is what the group recorded for Wolf on the hole; `null` clears it. `choice` is `"partner"` with `partnerUserId`, or `"lone"`. `wolfUserId` names the Wolf and is only needed on hole 17 or 18 when players are tied for last place (domain model, Open Question 4); it can be sent before the choice. Fields left out are stored as `null`; an object with none of the three set is `400 invalid_body`, as is a `choice` other than the two.
    - The round must have Wolf enabled (`400 wolf_not_enabled`) and Wolf must be available, which takes exactly four players, each with a course handicap (`409 wolf_unavailable`).
    - `partnerUserId` and `wolfUserId` must be players in the round (`400 unknown_player`).
    - The record is then checked by the wolf engine against the round as it is, and rejected with `400 wolf_<reason>` when the engine finds it invalid: `wolf_partner_is_wolf`, `wolf_partner_and_lone`, `wolf_partner_missing`, `wolf_wolf_contradicts_rotation` (holes 1-16) and `wolf_wolf_not_in_last_place` (17 and 18, once the standings are known).
    - A record that was valid when written can become invalid later, for example when a corrected score changes who was in last place. It is then `invalid` in `state.wolf`, scores no points, and is a settlement issue; nothing is rewritten.
- `PUT /rounds/{roundId}/tee-order` -> set the order the players tee off in: `{ teeOrder: [userId, ...] }`; `200 { round }`. Players only (`403 not_a_participant`); `404 round_not_found`. Any participant may.
  - `teeOrder` lists every player in the round exactly once (`400 invalid_tee_order`); an id that is not a player is `400 unknown_player`.
  - The order can be changed only before play: once the round has a score or a Wolf record it is `409 tee_order_locked`. Clearing them opens it again. The check reads the round and then writes, so a score written at the same moment can slip past it.
  - `round.teeOrder` is always every player's id in tee order. Until an order is set it is the order the players were added. A player who joins after the order was set goes to the end. Wolf uses it for the rotation on holes 1-16; nothing else uses it yet.
  - The last write wins, and writing the same order again changes nothing.
- `GET /rounds/{roundId}/settlement` -> `200 { settlement }`: net positions + pairwise transfers (at most one fewer than the players with a non-zero balance). Players only (`403 not_a_participant`); `404 round_not_found`. See Settlement.
- `POST /rounds/{roundId}/settlement/transfers/{transferId}/paid` -> mark a transfer paid; `200 { settlement }`. No body.
- `DELETE /rounds/{roundId}/settlement/transfers/{transferId}/paid` -> mark a transfer unpaid; `200 { settlement }`.
- `POST /rounds/{roundId}/recompute` -> `200 { state }`: re-derive the game state from the stored scores and hole events. No body. Players only. State is not stored, so this writes nothing and returns the same `state` as `GET /rounds/{roundId}`; settlement is re-derived by the settlement API.

### Game state

`state` is what the engines in `backend/src/engines` return, unchanged (`RoundState` in `backend/src/shared/rounds.ts`). A game that is not enabled is left out.

- `skins`: `{ holes, deltas, complete, carryOutCents }`, or `null` until every player has a course handicap. Each hole has `status` (`won`, `pushed` or `pending`), `carriedInCents`, `atStakeCents`, `winnerUserId` and `net`. A hole is `pending` while it, or an earlier hole, is missing a score. When `complete` is true and `carryOutCents` is not zero, the last hole was pushed: that carryover is unresolved and is **not paid** (domain model, Open Question 1). With `games.skins.carryover` false, `carriedInCents` is always 0, `atStakeCents` is always `baseCents` and `carryOutCents` is always 0, so nothing is ever unresolved.
- `wad`: `{ instances, deltas, ignored }` with one instance per nine (`segment` `front` or `back`): `holderUserId`, `valueCents`, `makes` and `complete`. The holder is paid in `deltas` once every player has a score on the nine's last hole.
- `greenies`: `{ holes, deltas }` with one entry per par 3: `winnerUserId` and `status` (`none`, `awarded`, `pending` or `invalid`). Only `awarded` is paid.
- `wolf`: `{ teeOrder, holes, points, deltas, complete }` (`WolfResult` in `backend/src/engines/wolf.ts`), or `null` while Wolf is unavailable: the round does not have exactly four players, or a player has no course handicap.
  - Each hole has `wolfUserId`, `status`, `invalidReason`, `choice`, `partnerUserId`, `lastPlace`, `wolfSide`, `opponents`, `wolfSideNet`, `opponentsNet`, `net` and `points` (the points awarded on the hole, per player).
  - `status` is `won_by_wolf_side`, `won_by_opponents`, `tied`, `pending`, `needs_wolf` or `invalid`. Only the two `won_` statuses award points. `pending`: a score or the choice is missing, or (17 and 18) an earlier hole is not scored yet. `needs_wolf`: hole 17 or 18 with a tie for last place and no recorded Wolf; `lastPlace` lists the players who can be recorded. `invalid`: see `invalidReason` (`partner_and_lone`, `partner_missing`, `partner_not_a_player`, `wolf_not_a_player`, `partner_is_wolf`, `wolf_contradicts_rotation`, `wolf_not_in_last_place`).
  - `wolfUserId` is `null` while the Wolf is not known. The sides and their scores are `null` unless the hole is scored. `lastPlace` is `null` on holes 1-16 and while the standings are not known.
  - `points` on the result is each player's running total, from scored holes only, and `deltas` is `pointCents * (4 * own points - total points)`. `complete` is true when all 18 holes are won or tied.
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
  - `skins_unavailable`: skins is enabled but a player has no course handicap, so skins is not in the positions (`games.skins` is `null`). Set the player's per-round handicap override to resolve it.
  - `greenie_pending` / `greenie_invalid`: a recorded greenie that is not paid (see Game state). Clear or correct the winner, or the score, to resolve it.
  - `wad_make_ignored`: a recorded wad make the engine ignored.
  - `wolf_unavailable`: wolf is enabled but the round does not have exactly four players, or a player has no course handicap, so wolf is not in the positions (`games.wolf` is `null`).
  - `wolf_needs_wolf`: hole 17 or 18 has players tied for last place and no recorded Wolf, so it scores no points. Record the Wolf with `wolfUserId` on the hole to resolve it.
  - `wolf_invalid`: the hole's Wolf record is invalid and scores no points; the message names the reason. Correct or clear the record, or the score that made it invalid.
  - `wolf_pending`: every player has a score on the hole and Wolf still cannot score it: the choice is not recorded (`userId` is the Wolf), or it is hole 17 or 18 waiting for an earlier hole (`userId` is `null`). A hole that is missing a score is in `incompleteHoles` instead.
- `games` holds each enabled game's `deltas`, `wolf` included; the example above is a round without wolf. `positions` has every player, positive is owed to them, and sums to zero.
- `skinsCarryover` is the skins `carryOutCents`, or `null` when skins is not enabled or unavailable. With `unresolved: true` the last hole was pushed: the amount is shown and is **never part of a position or transfer** (domain model, Open Question 1). In a round with `games.skins.carryover` false it is always `{ "amountCents": 0, "unresolved": false }`.
- `toVenmoHandle` is the payee's `venmoHandle` from their profile, or `null` (no handle, or a guest). The client builds the Venmo deep link; the server builds no links and moves no money.
- `transferId` is derived from the round, payer, payee and amount. A score correction or a handicap override that changes a transfer gives it a new id, so a paid marker never moves to a different transfer or amount. A marker that matches no current transfer is listed in `stalePayments` (`{ transferId, from, to, amountCents, paidAt, paidBy }`) so the client can show that a payment was recorded before the correction.
- Marking paid or unpaid:
  - Only the payer or the payee may (`403 not_transfer_party`). A guest has no account, so any player may mark a transfer that a guest pays or receives.
  - `404 transfer_not_found` when the id is not a transfer of the current settlement. `DELETE` also accepts the id of a stale payment, to remove it.
  - Marking paid needs a final settlement: `409 round_incomplete` while holes are missing scores, `409 settlement_has_issues` while there are issues. Marking unpaid is always allowed.
  - Both are idempotent. Marking a paid transfer again keeps the first `paidAt` and `paidBy`.

### Round shape (illustrative)

The `Round` type in `backend/src/shared/rounds.ts`. A hole with a Wolf record also has `wolf`, for example `{ "hole": 4, "wadMakers": [], "greenieWinner": null, "wolf": { "choice": "partner", "partnerUserId": "u_2", "wolfUserId": null } }`, and a round with Wolf enabled has `state.wolf`.

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
  "games": { "skins": { "baseCents": 500, "carryover": true }, "wad": { "startCents": 700, "stepCents": 200 }, "greenies": { "amountCents": 500 } },
  "players": [
    { "userId": "u_1", "displayName": "Zach", "handicapIndex": 13.1, "courseHandicap": 15, "courseHandicapOverride": null, "ticksByHole": { "1": 1, "3": 1 }, "guest": false, "joinedAt": "2026-10-03T14:00:00.000Z" }
  ],
  "teeOrder": ["u_1"],
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

### Live relay (dev, interim)

Deployed before auth and the rounds API exist ([ADR-0014](adr/0014-live-relay-before-auth.md)): phones in the same room receive each other's messages, and the server does not read them. The target contract below replaces it when auth (M1) and round sync (M3.3) land.

- URL: the `live_ws_url` Terraform output of `infra/environments/dev` (a `wss://` URL). JSON text frames.
- `$connect` must carry `x-wad-client: <token>`, the same shared token as the courses API (`infra/README.md` says how to fetch it); otherwise API Gateway refuses the connection with a 401. Connecting subscribes to nothing.
- Client -> server actions (`action` selects what happens; every reply goes to the sender only):
  - `{ "action": "subscribe", "roundCode": "ABC123" }`: joins the room. `roundCode` must match `^[A-Z0-9]{6}$`. A connection is in one room at a time: subscribing again moves it, or renews the subscription when it is the same room. Reply `{ "event": "subscribed", "roundCode": "ABC123", "members": 2 }`, the connections in the room, this one included.
  - `{ "action": "publish", "roundCode": "ABC123", "message": { ... } }`: sends `message`, a JSON object, to every other connection in the room; the sender must be subscribed to that room. Reply `{ "event": "published", "roundCode": "ABC123", "delivered": 1 }`, the number of other connections the message reached. A connection that is gone is dropped from the room and not counted.
  - `{ "action": "ping" }`: reply `{ "event": "pong" }`. The app sends one every 30 seconds to keep the connection warm; API Gateway drops an idle connection after 10 minutes and any connection after 2 hours, and a subscription expires 6 hours after the last subscribe.
- Server -> client: `{ "event": "message", "roundCode": "ABC123", "message": { ... }, "sentAt": "2026-10-05T15:00:00.000Z" }` to the other members of the room, with the message as published.
- Errors are replies to the sender, `{ "event": "error", "code": "..." }`: `invalid_message` (a frame over 4096 bytes, not JSON or not a JSON object; a bad `roundCode`; a `message` that is not a JSON object), `not_subscribed` (a publish to a room the connection is not in) or `unknown_action` (no `action`, or one other than the three). A publish is checked in that order: the room code, then the subscription, then the message.
- Limits: frames of at most 4096 bytes; the stage is throttled to a burst of 20 and 10 frames per second across all clients.
- The payload is opaque to the server. The app sends `{ "type": "gameEvent", "kind": "birdie", "hole": 4, "playerIDs": ["p1"], "playerNames": ["Zach"], "otherNames": ["Sam", "Alex"], "amountCents": null }` and `{ "type": "score", "playerID": "p1", "playerName": "Zach", "hole": 4, "par": 4, "gross": 3 }`; those shapes are the app's and change without a server change.

### Target contract

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
