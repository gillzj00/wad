# Architecture

## Overview

Wad is a native iOS client backed by a serverless AWS API. The design goals, in priority order: correct money math, usable with poor course connectivity, near-zero cost when idle, and cleanly scalable if usage grows.

```
 iPhone (SwiftUI, iOS 17+)                         AWS (Terraform-managed)
 +-----------------------------+
 |  UI (SwiftUI)               |          HTTPS (JWT)   +-----------------------------+
 |  ViewModels                 | <--------------------> |  API Gateway HTTP API       |
 |  Local store (SwiftData)    |                        |    Cognito JWT authorizer   |
 |  Sync engine (offline queue)|                        |         |                   |
 |  WebSocket client           | <----- WSS (JWT) ----> |  API Gateway WebSocket API  |
 +-----------------------------+                        |         |                   |
                                                        |      Lambda (TypeScript)    |
                                                        |         |                   |
                                                        |      DynamoDB (single table)|
                                                        |         ^                   |
                                                        |  Cognito User Pool          |
                                                        |    + Sign in with Apple IdP |
                                                        |  GolfCourseAPI (cached in DDB)|
                                                        +-----------------------------+
```

## Client (iOS)

- **SwiftUI** app targeting iOS 17+. **Offline-first**: a local **SwiftData** store is the working copy during a round. All user actions mutate the local store immediately; a **sync engine** queues mutations and replays them to the backend when connectivity is available.
- **Conflict strategy:** each player owns their own scores and their own bet events (e.g. "I made the Wad on hole 4"), so concurrent edits rarely collide. Server is authoritative; resolution is last-write-wins **per field**, scoped to the owning player. The game engines run server-side on authoritative data; the client may run them locally for instant feedback but the server's result is canonical.
- **Live round:** while online, the client holds a WebSocket connection scoped to the active round and receives other players' updates as they happen. On reconnect it does a full round fetch to reconcile anything missed while offline.

## Backend (serverless)

- **HTTP API (API Gateway v2)** for request/response CRUD: auth/profile, courses, rounds, scores, settlement. A **Cognito JWT authorizer** protects routes; the caller's `sub` is the user id.
- **WebSocket API (API Gateway)** for real-time round sync. On `$connect` the token is validated and the connection id is stored against the round; score/bet mutations fan out to all live connections for that round. Connection records carry a TTL so stale ones self-expire.
- **Lambda (TypeScript, Node 22 runtime)** implements handlers. Structure:
  - `handlers/` — thin adapters (parse, authorize, call service, format response).
  - `services/` — business logic and DynamoDB access.
  - `engines/` — **pure** game logic (Skins/Wad/Greenies, handicap allocation). No I/O, fully unit-tested. This is the highest-value, highest-risk code; treat it accordingly.
  - `shared/` — types shared with the client contract (see `docs/api.md`).
- **DynamoDB single table** (see [data-model.md](data-model.md)). DynamoDB Streams can trigger the WebSocket fan-out Lambda so writes and broadcasts stay consistent.

Why serverless + DynamoDB: it scales to effectively $0 when only one person uses it, and up transparently under load, with no servers to manage. See [ADR-0002](adr/0002-serverless-dynamodb.md). The relational-modeling tradeoff (bets/reconciliation) is handled by keeping the money math in pure engines rather than in the database.

## Auth

Amazon Cognito User Pool with **Sign in with Apple** as a federated identity provider. The iOS app uses `ASAuthorizationController`; Cognito issues JWTs; API Gateway authorizers validate them. See [ADR-0005](adr/0005-auth-cognito-apple.md).

## Course data

Course scorecards come from **GolfCourseAPI** via a backend adapter, and each fetched course is **cached in DynamoDB** (data is static). A manual-entry + user-correction path covers gaps. The internal schema follows the CC-BY **Open Course** model. No scraping and no unofficial GHIN endpoints. See [course-data.md](course-data.md) and [ADR-0008](adr/0008-course-data-source.md).

## Handicaps

Stored as a handicap index on the user profile (manual for v1). A `HandicapProvider` interface abstracts the source so a future GHIN/USGA integration (via the official GPA program) can be added without touching the engines. See [ADR-0006](adr/0006-handicap-source.md).

## Payments / settlement

No money moves through the backend. The settlement service computes net positions and a small set of pairwise transfers (at most one fewer than the players owed or owing); the client opens **Venmo deep links** pre-filled with amount and note. The user confirms in Venmo, then marks the transfer paid in Wad. See [ADR-0007](adr/0007-payments-venmo-deeplinks.md).

## Infrastructure & delivery

All AWS resources are defined in **Terraform** under `infra/`. A one-time **bootstrap** (run locally by a human with admin credentials) creates the remote state backend (an S3 bucket; locking uses an S3 lock file), the **GitHub OIDC** provider, and the CI role. Thereafter **GitHub Actions** runs `terraform plan` on pull requests and `terraform apply` on merge to `main`, assuming the CI role via OIDC — no long-lived AWS keys exist. See [ADR-0009](adr/0009-terraform-github-oidc.md) and [infra/README.md](../infra/README.md).

## Environments

Start with a single `dev` environment. `prod` is added later by copying `infra/environments/dev` to `infra/environments/prod` with its own state key and variables. Keeping environments as separate Terraform stacks (not workspaces) keeps blast radius small.
