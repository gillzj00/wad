# Roadmap & Milestones

Work is organized into milestones, each a set of independently grabbable tasks with acceptance criteria. Tasks within a milestone are mostly parallelizable; dependencies are noted. Grab a task, branch, open a PR requesting `@gillzj00`. Do not implement anything gated on an [Open Question](../domain-model.md#open-questions) until it is resolved.

Status legend: `[ ]` todo, `[~]` in progress, `[x]` done.

## M0 — Foundations

- [x] **M0.1 Terraform bootstrap** (`infra/bootstrap/`): S3 state bucket (versioned, encrypted; S3 lock file for locking), GitHub OIDC provider, CI IAM role scoped to this repo. Human-run once. AC: `terraform apply` in bootstrap succeeds; outputs the role ARN and state bucket.
- [x] **M0.2 Remote state + dev stack skeleton** (`infra/environments/dev/`): backend config pointing at the bootstrap bucket; providers; empty stack that plans clean. AC: `terraform init && plan` succeeds in CI using OIDC.
- [x] **M0.3 Terraform CI** (`.github/workflows/terraform.yml`): fmt check + validate + plan on PR (plan posted to PR), apply on merge to `main`, via OIDC. AC: PR shows a plan; merge applies. (Skeleton provided.)
- [x] **M0.4 Backend project scaffold** (`backend/`): TypeScript, test runner, lint/typecheck, bundler for Lambda, `shared/` types matching `docs/api.md`. AC: `npm test`/`lint`/`build` run green on an empty suite.
- [x] **M0.5 Backend CI** (`.github/workflows/backend-ci.yml`): install, typecheck, lint, test on PRs touching `backend/`. (Skeleton provided.)
- [x] **M0.6 iOS project scaffold** (`ios/`): SwiftUI app, SwiftData store, unit test target, app skeleton (tab shell). AC: builds and tests pass in CI.
- [x] **M0.7 iOS CI** (`.github/workflows/ios-ci.yml`): build + test on PRs touching `ios/`. (Skeleton provided.)

## M1 — Accounts & auth  (depends on M0)

- [ ] **M1.1 Cognito + Sign in with Apple** (Terraform module `infra/modules/cognito`): user pool, app client, Apple IdP, API Gateway JWT authorizer wiring.
- [~] **M1.2 Profile API**: `GET/PUT /me` (display name, handicap index, Venmo handle) with the DynamoDB user item. Handler code done; deploying waits on auth (M1.1).
- [ ] **M1.3 iOS auth flow**: Sign in with Apple, token storage in Keychain, authenticated API client.
- [ ] **M1.4 iOS profile screen**: view/edit profile incl. handicap index and Venmo handle.

## M2 — Courses & scorecards  (depends on M0; parallel with M1)

- [x] **M2.1 CourseProvider adapter**: GolfCourseAPI client behind the interface; normalize to our `Course` type; API key from SSM.
- [~] **M2.2 Course caching**: write-through cache to DynamoDB `COURSE#`, cached searches; `GET /courses` search + `GET /courses/{id}`. Handler code done; **deploying it (Lambda + HTTP API) waits on auth (M1.1)** so the provider quota is not exposed on a public endpoint.
- [x] **M2.3 Manual course entry + corrections**: `POST /courses`, `POST /courses/{id}/corrections`. Handler code done; corrections are stored as pending suggestions. Deploying waits on auth (M1.1), like M2.2.
- [x] **M2.4 iOS course search + scorecard view**: search, select tee, render the scorecard (par + stroke index per hole). The course step of round setup searches the deployed API, picks a tee and fills the holes, with an on-device cache, Oak Glen as the default course, and a "Near me" suggestion from the cached courses (geolocation phase 1). The Courses tab has the same search, "Near me" and the courses cached on the phone, and a course screen with a tee picker, the tee's scorecard and "Start a round here", which opens setup prefilled; see `ios/README.md`, Course lookup. Manual courses through `POST /courses` wait for auth (M1.1), with M2.3.

## M3 — Rounds & scoring  (depends on M1, M2)

- [x] **M3.1 Round lifecycle API**: create round (+ join code), join, add guest player, get round. Handler code done; deploying waits on auth (M1.1).
- [x] **M3.2 Scoring API**: `PUT /rounds/{id}/scores` with per-game flags; recompute endpoint. Handler code done; deploying waits on auth (M1.1).
- [ ] **M3.3 WebSocket sync**: `$connect`/`$disconnect`/actions, connection registry, fan-out (DynamoDB Streams). AC: two clients see each other's scores live.
- [ ] **M3.4 iOS round flow**: create/join, hole-by-hole scoring UI incl. Wad/Greenies flags, live group view.
- [ ] **M3.5 iOS offline queue**: mutations persist locally and replay on reconnect; full-round reconcile on reconnect.

## M4 — Game engines  (pure logic; can start once domain model is confirmed, parallel with M3)

- [x] **M4.1 Handicap allocation**: course handicap computation + tick allocation. Table-driven unit tests incl. the 15-vs-7 example and >18 wrap-around.
- [x] **M4.2 Skins engine**: net winner per hole, pushes/carryovers through 18, collect-from-each settlement. Expose (do not pay out) any carryover unresolved after the final hole (Open Question 1).
- [x] **M4.3 Wad engine**: ordered makes per hole, start value then +step per make, separate front/back instances, holder collects from each at the end of each nine.
- [x] **M4.4 Greenies engine**: par-3 winner validation (par or better), collect-from-each settlement.
- [x] **M4.5 Settlement aggregator**: combine all games into net positions + pairwise transfers (integer cents).

## M5 — Settlement & payout  (depends on M4)

- [x] **M5.1 Settlement API**: `GET /rounds/{id}/settlement`, mark transfer paid. Handler code done; deploying waits on auth (M1.1).
- [ ] **M5.2 iOS settlement screen**: show who owes whom; Venmo deep links pre-filled; mark paid; graceful fallback if Venmo absent.

## M6 — Polish  (depends on prior)

- [ ] **M6.1 Round history** (GSI1) + iOS history screen.
- [ ] **M6.2 Push notifications** (turn/settlement reminders) - optional.
- [ ] **M6.3 Edge cases**: player leaves mid-round, score corrections, recompute integrity.
- [ ] **M6.4 App Store readiness**: privacy manifest, icons, TestFlight.

## Suggested first agents

1. M0.1-M0.3 (infra + CI) - unblocks everything.
2. M0.4-M0.7 (project scaffolds) - unblocks feature work.
3. M4.1 + M4.4 (handicap + greenies engines) - pure logic, unblocked, high value.
