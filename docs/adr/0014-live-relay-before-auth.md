# ADR-0014: A live relay between phones before auth, keyed by a code the phone picks

- Status: Accepted
- Date: 2026-10-05

## Context

On 2026-10-05 @gillzj00 asked for the event animations to reach the other phones: "if I am Zach and I am the scorer and I score myself as getting a birdie I want the taunting animation to pop up on someone else's phone who I am playing with in as quick to real-time as possible."

The design for that is the WebSocket round sync of [ADR-0004](0004-multi-device-sync.md) and `docs/api.md`: the server stores scores, runs the engines and broadcasts the authoritative state. It needs auth (M1, waiting on Apple Developer Program enrollment) and the rounds API deployed, and neither is. The app today scores a round on one phone, with no round on the server at all.

Options considered:

1. **Wait for auth and the rounds API.** Nothing to replace later, but no live animations until M1 and M3.3 land.
2. **MultipeerConnectivity between the phones** (Bluetooth and peer-to-peer Wi-Fi). No backend, but the range is tens of metres, a foursome spreads out over a hole, and iOS pauses the session in the background.
3. **Polling** a store of recent events. Simple, but seconds of delay at best and a request every few seconds from every phone for five hours.
4. **A relay**: a WebSocket API that fans each frame out to the other connections in the same room, with the room keyed by a short code the scoring phone chooses and tells the others. The server stores no round and reads no message.

## Decision

Option 4, as the first slice of M3.3 (`backend/src/handlers/live.ts`, `infra/environments/dev/live_api.tf`).

- **Rooms by code.** A phone subscribes to a room named by a six-character code (`A-Z`, `0-9`) and publishes JSON messages to it; the server sends each message to every other connection in the room with the time it was sent. A connection is in one room at a time.
- **Opaque messages.** The server validates only that a message is a JSON object in a frame of at most 4 KB. What the app sends (score and game event shapes) is the app's business, so the relay needs no change when the app's events change.
- **Behind the shared client token.** As the courses API ([ADR-0013](0013-courses-api-before-auth.md)): the `$connect` request must carry the `x-wad-client` header with the token in SSM, or API Gateway refuses the connection. The stage is throttled (burst 20, 10 frames per second).
- **Registry in the single table**, two item types with a 6-hour TTL: the members of a room, and the room of a connection (`docs/data-model.md`). A connection that API Gateway reports gone is removed when a message fails to reach it.
- **Same pipeline.** The handler is bundled with the others; the Terraform plan and apply go through the existing workflow and the owner's approval of the `dev` environment.

## Consequences

- Two phones with the code see each other's events within the API Gateway and Lambda round trip, usually well under a second.
- This is **interim, not auth**: anyone with the client token and a room code can read and write that room. The token is the same shared secret as for course lookup, and the code is as private as the group keeps it. Nothing of value is at stake: the relay carries animations and score echoes, and the money math still runs on the scoring phone.
- The server keeps nothing but connection ids. A phone that reconnects has missed what was sent meanwhile; the app treats the relay as best effort.
- When M1 (Cognito) and M3.3 (round sync) land, the authoritative `stateUpdated` flow of `docs/api.md` replaces the relay: the room code becomes the round's join code, the connection is tied to a user and a round, and the relay actions are removed. The registry items are dropped in the same change (the `ROUND#`/`CONN#` item of the target design is already reserved).
- Cost at this volume is a few cents a round (API Gateway charges per message and per connection-minute); Lambda and DynamoDB stay in the free tier.
