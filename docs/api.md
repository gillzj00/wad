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
- `POST /rounds` -> create `{ courseId, teeId, date, holes: 9 | 18, games: { skins?: { baseCents }, wad?: { startCents, stepCents }, greenies?: { amountCents } } }`; a game is enabled by including it. Returns round + `joinCode`
- `GET /rounds/{roundId}` -> full round (meta, players, scores, hole events, current game state)
- `POST /rounds/join` -> `{ joinCode }` joins the caller to a round
- `POST /rounds/{roundId}/players` -> add a guest/non-app player (name + handicap index)
- `PUT /rounds/{roundId}/players/{userId}/handicap` -> per-round handicap override `{ courseHandicap }` (null clears it)
- `PUT /rounds/{roundId}/scores` -> upsert a gross score for a hole: `{ hole, gross, userId? }`. `userId` defaults to the caller; any participant may set a guest player's score.
- `PUT /rounds/{roundId}/holes/{hole}` -> set the hole's group events `{ wadMakers: [userId, ...], greenieWinner: userId | null }`. `wadMakers` is ordered by when the putts were made. `greenieWinner` is only valid on par 3s and must have scored par or better.
- `GET /rounds/{roundId}/settlement` -> net positions + pairwise transfers (at most one fewer than the players with a non-zero balance)
- `POST /rounds/{roundId}/settlement/transfers/{transferId}/paid` -> mark a transfer paid
- `POST /rounds/{roundId}/recompute` -> re-derive game state and settlement from scores and hole events

### Round summary shape (illustrative)
```json
{
  "roundId": "r_abc",
  "course": { "courseId": "c_1", "name": "...", "tee": "Blue" },
  "status": "in_progress",
  "games": { "skins": { "baseCents": 500 }, "wad": { "startCents": 700, "stepCents": 200 }, "greenies": { "amountCents": 500 } },
  "players": [
    { "userId": "u_1", "displayName": "Zach", "courseHandicap": 15, "ticksByHole": { "1": 1, "3": 1 } }
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
