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
- `GET /courses?q=<search>` -> list of course summaries (proxied+cached from provider)
- `GET /courses/{courseId}` -> full course incl. tees and per-hole par/strokeIndex/yardage
- `POST /courses` -> create a manual course (same schema) when the provider lacks it
- `POST /courses/{courseId}/corrections` -> submit a correction to a cached course

### Rounds
- `POST /rounds` -> create `{ courseId, tee, date, games: { skins?, wad?, greenies? }, baseAmounts }`; returns round + `joinCode`
- `GET /rounds/{roundId}` -> full round (meta, players, scores, current game state)
- `POST /rounds/join` -> `{ joinCode }` joins the caller to a round
- `POST /rounds/{roundId}/players` -> add a guest/non-app player (name + handicap index)
- `PUT /rounds/{roundId}/scores` -> upsert the caller's score for a hole:
  `{ hole, gross, wadFirstPuttFromFlagstick?, greenInRegulationOffTee? }`
- `GET /rounds/{roundId}/settlement` -> net positions + minimal pairwise transfers
- `POST /rounds/{roundId}/settlement/transfers/{transferId}/paid` -> mark a transfer paid
- `POST /rounds/{roundId}/recompute` -> re-derive game state and settlement from scores

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
    { "userId": "u_1", "hole": 4, "gross": 4, "wadFirstPuttFromFlagstick": true }
  ],
  "state": {
    "skins": [ { "hole": 1, "atStakeCents": 500, "winnerUserId": null, "carried": true } ],
    "wad": { "front": { "holderUserId": "u_1", "valueCents": 900 }, "back": null },
    "greenies": [ { "hole": 3, "earnedBy": ["u_1"] } ]
  }
}
```

## WebSocket API

Used only while a round is live. Auth via token on `$connect` (query string or subprotocol). The server tracks the connection against the round for fan-out.

Client -> server actions:
- `{ "action": "subscribe", "roundId": "r_abc" }`
- `{ "action": "score", "roundId": "r_abc", "hole": 4, "gross": 4, "wadFirstPuttFromFlagstick": true }`

Server -> client events (broadcast to the round):
- `{ "event": "scoreUpdated", "roundId": "r_abc", "userId": "u_1", "hole": 4, ... }`
- `{ "event": "stateUpdated", "roundId": "r_abc", "state": { ...as above... } }`
- `{ "event": "playerJoined", "roundId": "r_abc", "player": { ... } }`

The authoritative game state in `stateUpdated` is produced by the server-side engines after each mutation. Clients may compute optimistically but must reconcile to server state.

## Errors

JSON `{ "error": { "code": "string", "message": "string" } }` with conventional HTTP status codes (400 validation, 401 auth, 403 not a round participant, 404, 409 conflict, 429 rate limit, 500).

## Versioning

Path-versioned (`/v1`). Breaking changes bump the version; the shared types are the contract of record.
