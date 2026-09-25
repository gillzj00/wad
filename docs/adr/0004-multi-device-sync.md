# ADR-0004: Multi-device live sync via WebSocket API, offline-first

- Status: Accepted
- Date: 2026-09-25

## Context

Players each score from their own phone and expect to see the group's scores update live. Course connectivity is unreliable, so the app must also work fully offline and reconcile later.

## Decision

- **Offline-first client:** local SwiftData store is the working copy; a sync engine queues mutations and replays them when online.
- **Live sync:** an **API Gateway WebSocket API**; connection ids are stored per round in DynamoDB and mutations fan out to all live connections (optionally triggered by DynamoDB Streams).
- **Conflict resolution:** each player owns their own scores/bet events; server is authoritative; last-write-wins per field within the owning player's data.

## Alternatives considered

- **AWS AppSync (managed GraphQL subscriptions + Amplify DataStore):** excellent fit for offline+sync out of the box, but pulls in Amplify/AppSync coupling and diverges from the chosen Lambda+API Gateway+DynamoDB stack. Reconsider if custom WebSocket plumbing becomes a burden.
- **Polling:** simpler but poor live UX and wasteful.

## Consequences

- Need a connection registry with TTL and a fan-out Lambda.
- Server-side engines produce the authoritative state broadcast to clients.
