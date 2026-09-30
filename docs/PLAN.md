# Wad — Project Plan

This is the master plan. It is intended to be iterated on by multiple agents working in parallel. Keep it current: when a decision is made, record it in an ADR (`docs/adr/`) and update the relevant doc; when scope changes, update this file.

## 1. Vision

An iPhone app you take onto the golf course to keep score for your group and run friendly money games — **Wad**, **Skins**, **Greenies**, and **Wolf** — then settle up at the end with pre-filled Venmo payments. It knows the course, shows the scorecard, and applies each game's rules (including handicap strokes) automatically so nobody has to do the math on the 18th green.

## 2. Product scope

### In scope (v1)
- Accounts with Sign in with Apple; a stored handicap index per player.
- Course lookup with real scorecard data (par, stroke index, yardage, rating, slope per tee).
- Create a round, invite others via a join code, everyone scores from their own phone with live sync.
- The games, scored automatically:
  - **Wad** (putting game, resets every 9)
  - **Skins** (net, with handicap ticks and carryovers)
  - **Greenies** (par-3 game)
  - **Wolf** (four players, net best ball for points, with a rotating Wolf)
- End-of-round settlement: net who owes whom across all games, open Venmo pre-filled, track paid/unpaid.
- Works with poor/no signal on the course (offline-first, syncs later).

### Out of scope (v1)
- Android (native iOS only for now; see [ADR-0003](adr/0003-ios-swiftui.md)).
- Automatic GHIN handicap sync (manual entry; adapter interface for later — see [ADR-0006](adr/0006-handicap-source.md)).
- In-app real money movement / payment processing (Venmo deep links only — see [ADR-0007](adr/0007-payments-venmo-deeplinks.md)).
- Full tournament/league management, GPS rangefinder, shot tracking, stat analytics.

## 3. Key decisions (locked)

| Area | Decision | ADR |
| --- | --- | --- |
| iOS | Native SwiftUI, iOS 17+, offline-first | [0003](adr/0003-ios-swiftui.md) |
| Backend | Serverless: API Gateway + Lambda (TypeScript) + DynamoDB single-table | [0002](adr/0002-serverless-dynamodb.md) |
| Real-time | Multi-device live sync via API Gateway WebSocket API | [0004](adr/0004-multi-device-sync.md) |
| Auth | Cognito federated with Sign in with Apple | [0005](adr/0005-auth-cognito-apple.md) |
| Handicaps | Manual entry now; pluggable provider for GHIN later | [0006](adr/0006-handicap-source.md) |
| Payments | Compute net debts, settle via Venmo deep links | [0007](adr/0007-payments-venmo-deeplinks.md) |
| Course data | Licensed API (GolfCourseAPI) + local cache; no scraping | [0008](adr/0008-course-data-source.md) |
| IaC/CD | Terraform via GitHub Actions using GitHub OIDC | [0009](adr/0009-terraform-github-oidc.md) |
| Game rules | "Collect from each" payouts, one settlement per round | [0010](adr/0010-game-rules.md) |
| Engines on device | Bundle the TypeScript engines and run them in JavaScriptCore; no Swift port | [0011](adr/0011-engines-on-device-javascriptcore.md) |
| Wolf rules | Four players, 2/3/4/1 points, net best ball, last place is the Wolf on 17 and 18, "pay the difference" payout | [0012](adr/0012-wolf-rules.md) |
| Courses API before auth | Deploy course lookup now behind a shared client token and throttling; interim until Cognito | [0013](adr/0013-courses-api-before-auth.md) |

## 4. Architecture summary

See [architecture.md](architecture.md) for detail.

```
 iPhone (SwiftUI)                      AWS
 +-------------------+        +--------------------------------+
 | Local store       |  HTTP  |  API Gateway (HTTP API)        |
 | (offline queue)   |<------>|    -> Lambda (TS) -> DynamoDB   |
 |                   |        |                                |
 | Live round view   |   WS   |  API Gateway (WebSocket API)   |
 |                   |<------>|    -> Lambda -> DynamoDB        |
 +-------------------+        |  Cognito (Sign in with Apple)  |
                              |  Course API cache in DynamoDB  |
                              +--------------------------------+
```

## 5. Milestones

Detailed, grabbable tasks with acceptance criteria are in [roadmap/milestones.md](roadmap/milestones.md).

- **M0 Foundations** — repo, Terraform bootstrap + remote state, CI/CD (Terraform plan/apply, backend & iOS CI), shared TypeScript types.
- **M1 Accounts & auth** — Cognito + Sign in with Apple; user profile + handicap index API and screens.
- **M2 Courses & scorecards** — course search/detail via GolfCourseAPI with DynamoDB caching; Open Course schema; manual entry + correction fallback.
- **M3 Rounds & scoring** — create/join round, hole-by-hole scoring, WebSocket live sync, offline buffering.
- **M4 Game engines** — pure, tested Skins / Wad / Greenies / Wolf engines wired into the round.
- **M5 Settlement** — net debts across games, Venmo deep links, paid/unpaid tracking.
- **M6 Polish** — round history, notifications, edge-case handling, App Store readiness.

Engines (M4) are pure functions and can be built in parallel with the backend/iOS plumbing (M3) once the domain model is agreed.

## 6. Open questions

The core game rules are settled ([ADR-0010](adr/0010-game-rules.md), [ADR-0012](adr/0012-wolf-rules.md)). These edge cases remain, tracked in [domain-model.md](domain-model.md#open-questions):

- **Skins:** what happens to a carryover that is still unresolved after the final hole.
- **Leaving mid-round:** how a departing player's games are settled.
- **Handicaps for 9-hole rounds:** which handicap a 9-hole round uses.
- **Wolf:** who is the Wolf on 17 or 18 when players are tied for last place.

## 7. How agents should work here

Read [../CLAUDE.md](../CLAUDE.md). Grab a milestone item, work on a feature branch, open a PR requesting `@gillzj00`, keep commits small and conventional, and never guess an OPEN QUESTION — ask.
