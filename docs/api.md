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
- `POST /courses` -> create a manual course (same schema) when the provider lacks it
- `POST /courses/{courseId}/corrections` -> submit a correction to a cached course

### Rounds
- `POST /rounds` -> create `{ courseId, teeId, date, holes: 18, games: { skins?: { baseCents }, wad?: { startCents, stepCents }, greenies?: { amountCents } } }`; a game is enabled by including it. `201 { round, joinCode }`; the caller is the first player.
  - `date` is the day of play, `YYYY-MM-DD`.
  - Amounts are non-negative integer cents (`400 invalid_amount`). An amount left out of an included game takes its default: skins 500, wad 700 start and 200 step, greenies 500. `games` is required and may be `{}`; an unknown game is `400 unknown_game`.
  - `holes: 9` is rejected with `400 nine_hole_rounds_unsupported` until the 9-hole handicap rule is decided (domain model, Open Question 3).
  - The course must already be cached (`404 course_not_found`) and have the tee (`404 tee_not_found`). The tee needs 18 holes with valid stroke indexes (`400 tee_not_usable`). The round keeps its own copy of the tee, so later course corrections do not change a round.
- `GET /rounds/{roundId}` -> `{ round }`: meta, players, scores and hole events. Players only (`403 not_a_participant`); `404 round_not_found`. The current game state (`state` below) is added with the scoring API.
- `POST /rounds/join` -> `{ joinCode }` joins the caller to a round and returns `200 { round }`. Joining again is a no-op that returns the round. `404 join_code_not_found` for an unknown or expired code, `409 round_full` when the round already has 4 players.
- `POST /rounds/{roundId}/players` -> add a guest/non-app player `{ displayName, handicapIndex }`; `201 { round, player }`. Players only. `displayName` is at most 40 characters. Guests count toward the 4 players (`409 round_full`) and get a server-generated `userId` starting `guest_`.
- Join codes are 6 characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (no 0/O or 1/I/L). Input is case-insensitive and may contain spaces or hyphens. A code works for 48 hours after the round is created.
- A round has 2 to 4 players. These routes enforce the maximum when players are added; they do not enforce the minimum, since a round starts with only its creator.
- The caller's `displayName` and `handicapIndex` come from their profile; creating or joining without both is `409 profile_incomplete`. `handicapIndex` is a number from -10 to 54; a plus handicap is negative (+1.2 is `-1.2`).
- `courseHandicap` is computed from the handicap index and the tee's rating, slope and par. It is `null` when the tee has no rating and slope, until it is set with the per-round override. `ticksByHole` lists only the holes where the player gets ticks, and is `null` until every player has a course handicap.
- A body that is missing or not JSON is `400 invalid_json`; a missing or mistyped field is `400 invalid_body`.
- `PUT /rounds/{roundId}/players/{userId}/handicap` -> per-round handicap override `{ courseHandicap }` (null clears it)
- `PUT /rounds/{roundId}/scores` -> upsert a gross score for a hole: `{ hole, gross, userId? }`. `userId` defaults to the caller; any participant may set a guest player's score.
- `PUT /rounds/{roundId}/holes/{hole}` -> set the hole's group events `{ wadMakers: [userId, ...], greenieWinner: userId | null }`. `wadMakers` is ordered by when the putts were made. `greenieWinner` is only valid on par 3s and must have scored par or better.
- `GET /rounds/{roundId}/settlement` -> net positions + pairwise transfers (at most one fewer than the players with a non-zero balance)
- `POST /rounds/{roundId}/settlement/transfers/{transferId}/paid` -> mark a transfer paid
- `POST /rounds/{roundId}/recompute` -> re-derive game state and settlement from scores and hole events

### Round shape (illustrative)

The `Round` type in `backend/src/shared/rounds.ts`. `state` is not returned yet.

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
    "skins": [ { "hole": 1, "atStakeCents": 500, "winnerUserId": null, "carried": true } ],
    "wad": { "front": { "holderUserId": "u_1", "valueCents": 900 }, "back": null },
    "greenies": [ { "hole": 3, "winnerUserId": "u_1" } ]
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
