# Status

Source of truth for the orchestrated build-out. Updated after every merged PR. After any context summarization, re-read this file first.

Last updated: 2026-10-01 (after #66)

## Current phase

**Phase 1 demo is complete and ready to install** (merged in #16, #18, #20, #22). Waiting for @gillzj00 to connect the phone; then run `ios/scripts/install-device.sh`. Delete any older install of Wad from the phone first (schema changed, no migration).

**Phase 2 — backend:** the four listed items are merged (#24, #26, #28, #30); the documented handicap override route followed (#32). Remaining milestones (M1, M2.2/M2.4 deploy, M3.3, M3.4/M3.5, M5.2, M6) depend on auth, deploys or iOS sign-in and wait on Apple Developer Program enrollment or a decision from @gillzj00. Original scope: M3.1 round lifecycle API, M3.2 scoring API, M5.1 settlement API, M2.3 manual course entry. Handler code and tests only. No M1 auth, no Sign in with Apple, nothing that deploys a public endpoint until @gillzj00 confirms Apple Developer Program enrollment. Any `infra/` PR needs explicit approval in chat.

## Phase 1 task list

| # | Task | State | PR |
| --- | --- | --- | --- |
| P1.1 | ADR-0011, engine bundle, JavaScriptCore bridge | done | #16 |
| P1.2 | Round models and setup flow | done | #18 |
| P1.3 | Hole-by-hole scoring, UI walkthrough test | done | #20 |
| P1.4 | Settlement screen, full 18-hole UI walkthrough | done | #22 |
| P1.5 | Install on device | done 2026-09-30 (installed on the owner's iPhone from main at #61) | - |

## Phase 2 task list

| # | Task | State | PR |
| --- | --- | --- | --- |
| M3.1 | Round lifecycle API (code and tests; not deployed) | done | #26 |
| M2.3 | Manual course entry + corrections (code and tests; not deployed) | done | #24 |
| M3.2 | Scoring API (code and tests; not deployed) | done | #28 |
| M5.1 | Settlement API (code and tests; not deployed) | done | #30 |
| M3.1b | Per-round handicap override route (code and tests; not deployed) | done | #32 |

## Phase 3 task list (approved by @gillzj00 on 2026-09-29)

| # | Task | Touches | State | PR |
| --- | --- | --- | --- | --- |
| P3.1 | UI tests for setup validation and round delete; fixed a crash after removing a player and validation messages being off screen | ios/ | done | #39 |
| P3.2 | M1.2 profile API handler (code and tests only; no auth infra, no deploy) | backend/ | done | #35 |
| P3.3 | Research other popular side-bet games (docs/research/side-games.md) | docs/ | done | #37 |
| P3.4 | Venmo deep links, paid tracking and round history in the demo app (local only); install-device.sh no longer picks an unavailable phone | ios/ | done | #41 |
| P3.5 | Golf-themed visual design for the app (visual only; classic golf palette, light and dark, app icon) | ios/ | done | #43 |
| W1 | Wolf: rules in domain model + ADR-0012, engine, engine bundle, backend state and settlement | docs/, backend/ | done | #49 |
| S1 | Score entry: every hole defaults to a saved par for every player, behind a setup toggle that is on by default | ios/ | done | #59 |
| I1 | PRIORITY: deploy the courses API (Lambda + HTTP API, throttled, `x-wad-client` token guard, no auth yet); owner chose option B on 2026-09-29 | infra/, backend/, .github/ | merged with @gillzj00's approval (plan 14/0/0); apply ran from main | #54 |
| H1 | Repo hardening: audit, history rewrite (tfplan purged), public switch with branch protection, `dev` environment reviewer, fork-PR approval, secret scanning; workflows hardened and SHA-pinned, apply gated on `dev` | .github/, infra/, root docs, GitHub settings | done (bootstrap trust-policy apply pending, see questions) | #57 |
| H2 | iOS CI split into unit-tests and ui-tests jobs; UI suite pruned to 3 smoke tests (owner: UI tests cost too much) | .github/, ios/scripts | done | #62 |
| G1 | Research: geolocation for course suggestion and hole detection (docs/research/geolocation.md) | docs/ | done | #58 |
| C1 | Course lookup in round setup against the deployed API (debounced, cache-first, 7-day on-device cache, tee pick fills par/stroke index/rating/slope, manual entry stays), default course Oak Glen or the last pick on the phone, "Near me" ranking of cached courses (geolocation phase 1) | ios/ | done | #64 |
| T1 | Death metal theme replaces the golf theme entirely (owner decision 2026-09-29: skulls, fire, chains; no theme picker), original artwork only, new app icon | ios/ | done | #66 |
| T2 | Event animations (requested 2026-09-29, revised): full-screen, deliberately over the top, with haptics. Wolf hole won: a wolf baring its teeth plus a howl sound and vibration. Greenie: a golf ball falls from the sky like a bomb and blows the green apart. Wad taken: a skeleton hand making it rain money. Skins won: a skeletal hand being skinned. Score animations (added 2026-09-29, bowling-alley style): eagle or better: a bald eagle soars across the screen and screeches; hole in one: the loudest of all, fireworks and champagne bottles popping, long vibration; albatross (proposed, to confirm): a huge albatross dives out of a lightning storm, rips the flag out of the hole and flies off with it, with a thunderclap; a score of 8: a snowman that falls apart; birdie: a middle finger ("the bird") shown to every OTHER player, in the demo shown on the scoring phone addressed to the others. Original art and sounds only (synthesized howl, no downloaded audio); Reduce Motion gives a still image; a mute switch in settings. Plays on the scoring phone in the local demo; showing it on every player's phone needs live sync (M3.3, after auth) | ios/ | in flight (branch `feat/ios-event-animations`); owner saw a first cut on 2026-10-01 and rejected its look, so the presentation layer is being rebuilt on SpriteKit (particle emitters, action choreography, shaders) with code-drawn subjects rendered to textures | - |
| W2 | Wolf in the demo app: setup, tee order, per-hole choice, status, settlement | ios/ | in flight (branch `feat/ios-wolf`) | - |

## Tasks in flight

- T2 event animations (subagent, branch `feat/ios-event-animations`), kept to new files under `ios/Wad/Events/`, rebased onto the theme.
- W2 Wolf in the app (subagent, branch `feat/ios-wolf`), kept to new files under `ios/Wad/Wolf/` plus small hooks in setup, scoring and settlement; whichever of T2 and W2 merges second rebases first.
- The one-iOS-task-at-a-time rule was relaxed on 2026-10-01 at the owner's request: T1 and T2 run in parallel, conflicts are limited to the generated project (regenerated with xcodegen) and recolored views.

## Open PRs

- none

## Decisions made

- Repo is public since 2026-09-30 (free Actions minutes). Merge policy as clarified by @gillzj00: Claude may squash-merge its own PRs (authored by the owner's account) once every required check is green; `infra/` PRs still need the owner's approval in chat; every Terraform apply additionally waits for the owner's approval in the `dev` environment. Required checks on main: unit-tests, ui-tests, build-test, plan (strict, up to date). SHA pinning of actions is required.
- Course lookup (2026-09-29): option B, deploy the courses API before auth with the owner's provider key staying in AWS. This overrides the earlier no-public-endpoint rule for this one endpoint. Interim quota guard: API Gateway throttling plus a shared `x-wad-client` token in SSM; replaced by Cognito in M1.1. Recorded in ADR-0013 (I1).
- Animations (owner, 2026-10-01): the snowman plays for a score of exactly 8 only; the albatross animation (dives out of a lightning storm, rips the flag out, thunderclap) is confirmed. The presentation uses SpriteKit (built in, no dependency); subjects stay original and code-drawn.
- Theme (#66): both appearances are dark (light = ash variant, dark = pitch); palette charcoal, card, rule, maroon, crimson, blood, ember, bone, ash; money won is ember, money owed is blood; all 14 text/background pairs are at least 4.5:1 and a unit test enforces it.
- Wolf rules accepted by @gillzj00 on 2026-09-29: four players only; points 2 (Wolf and partner win, each), 3 (each opponent when they lose), 4 (Lone Wolf wins), 1 (each opponent when Lone Wolf loses); no Blind Wolf; Wolf on 17 and 18 is the player in last place on points; tied hole scores nothing and nothing carries; net best ball with the Skins ticks; $1 a point by default, every pair settles the point difference; tee order is the order players were added, reorderable before play; the Wolf's choice is recorded per hole and can be corrected.
- Engines run on device through JavaScriptCore from an esbuild bundle of `backend/src/engines`; payout math is not ported to Swift. To be recorded in ADR-0011 (P1.1).
- The engine bundle is generated by a backend script and committed under `ios/`, so building the app does not need Node. Backend CI fails if the committed bundle is stale.
- Phase 1 rounds are always 18 holes with no mid-round leaving, which avoids Open Questions 2 and 3.
- Open Question 1: the unresolved skins carryover is displayed and never paid out.
- Handicaps (revised after @gillzj00 asked on 2026-09-29): manual course entry takes an optional course rating and slope. When given, a player enters their handicap index and the app computes the course handicap through the engine's `courseHandicap`, with a per-round override. Without rating/slope the course handicap is entered directly. The course API is not used in Phase 1 (local-only; the key stays in SSM and `GET /courses` is not deployed until auth).
- ADR-0011 accepted and merged (#16).
- `Wad.xcodeproj` is regenerated with xcodegen, never hand-merged. Parallel `ios/` tasks are allowed when their files barely overlap (owner, 2026-10-01); the later PR rebases onto the earlier one.
- Course lookup in the app (#64): the base URL and `x-wad-client` token reach the app only through the git-ignored `ios/Config/Local.xcconfig` (Info.plist keys); a build without them works by hand. The default tee is the first usable men's tee in the API's order (Blue at Oak Glen); the last course and tee picked on the phone become the next default. Nearest-course suggestion ranks only courses cached on the phone, never preselects, and no coordinate leaves the device.

## Questions waiting on @gillzj00

- Approve (or dismiss) the pending `dev` environment deployment for the Terraform run on main triggered by #57 (https://github.com/gillzj00/wad/actions/runs/36874649636); it plans no infrastructure changes. The bootstrap apply from #57 is done (owner, 2026-10-01).
- Default tee for course lookup (#64): the first usable men's tee in the API's order. Say if a specific tee by name is wanted instead.

- The per-round handicap override route was already in docs/api.md, so it was queued without a decision (M3.1b).
- M3.2 choices to confirm (implemented and documented in #28): a member writes only their own score, any member writes guests' scores and hole events; `gross: null` clears a score, gross is 1-20; a greenie winner already over par is rejected with 400, a winner with no score yet is accepted and shows as pending; game state is the raw engine output and is never stored; skins state is null until every player has a course handicap.
- Event animations on every player's phone (asked 2026-09-29): in the one-device demo they play on the scoring phone only. Showing them on everyone's phone needs the WebSocket sync (M3.3), which waits on auth and Apple enrollment. Confirm that is acceptable for now.
- Wolf, tie for last place before hole 17 or 18 (asked 2026-09-29): who is the Wolf? Until answered, the app asks the group to pick the Wolf among the tied players and the engine never picks.
- Which other new games to build, if any (research in docs/research/side-games.md, #37). Recommended order: Nassau, Stableford-style points with Nines, Snake, Wolf, Junk. Each has rule questions listed in the document that must be answered before any implementation.
- Profile API choices to confirm (#35): `GET /me` with no profile returns 200 with null fields and `complete: false`; `PUT /me` is a partial update; display name cannot be cleared; Venmo handle is 5-30 letters, digits, hyphens or underscores, stored without `@` and not checked against Venmo; profile changes do not alter rounds already joined; only `sub` is taken from the token.
- Handicap override choices to confirm (#32): any player in the round may set or clear any player's override; whole numbers from -10 to 54; the round response shows the effective course handicap plus `courseHandicapOverride`.
- M5.1 choices to confirm (implemented and documented in #30): settlement is provisional until every hole is scored and there are no issues; marking paid is refused until then (409); payer or payee may mark paid/unpaid, any player for a guest's transfer; an unresolved skins carryover is exposed and does not block final; a transfer id is derived from round, payer, payee and amount so a score correction makes old paid markers stale instead of moving them.
- M3.1 choices to confirm (docs were silent; implemented and documented in #26): 9-hole rounds rejected with 400 (Open Question 3 unresolved); 4-player cap enforced, 2-player minimum not enforced at the API; creating or joining needs a profile with display name and handicap index (409 otherwise; assumes the M1.2 attribute names); on a tee without rating/slope the course handicap and ticks are null (no per-round override in the API yet); course must already be stored; join codes are 6 characters and valid 48 hours; joining is not blocked by round status or existing scores.
- M2.3 choices to confirm (docs were silent; implemented and documented in #24): corrections are stored as pending suggestions and never change the course; corrections return 404 unless the course is already stored; manual courses are 18 holes, par 3-5, 1-12 tees; tee gender defaults to male; manual courses are reachable by id only (no search) and there is no API yet to review or apply corrections.
- Setup choices to confirm (defaults in use until told otherwise): plus handicaps typed as "+1.2"; $0 game amounts allowed; course name required.

## Known gaps

- Courses API deployed and working 2026-09-30: the first deploy crashed at cold start (ESM bundle without `require`, fixed in #61); after the redeploy, requests without `x-wad-client` return 401 and an authenticated search for "oak glen" returns the provider's results, including Oak Glen Golf Course (Stillwater, MN; 18-hole course id `gca-y8jqwys2`, Executive Nine `gca-0zg07p94`). Base URL from the Terraform output `api_base_url`; token in SSM `/wad/dev/client-token`.
- GitHub Actions refused to start jobs from 2026-09-29 23:45 UTC ("recent account payments have failed or your spending limit needs to be increased"). No PR can be merged until CI runs; @gillzj00 was notified. W1 (#49) was verified locally instead: 580 backend tests, lint, typecheck, build, and the iOS unit tests with the new bundle.
- With "Start every hole at par" on (the default, by owner decision 2026-09-29), a new round reads 18 of 18 and its settlement is Final from the start; results count pars on unplayed holes. The toggle can be switched off per round.
- The phone runs iOS 26.6.2 (answered 2026-09-29), the same major version as local verification. iOS 17 remains untested.
- Device install needs the phone near the Mac (USB, or unlocked on the same Wi-Fi). Personal Team builds expire after 7 days. `ios/scripts/install-device.sh` now reports this clearly (#41).
- Simulator access cannot be granted over Remote Control, so screens are verified by the XCUITest walkthrough (setup and scoring since #20) rather than by manual tapping. Optional manual pass when @gillzj00 is back at the Mac.
- Demo verification (as of #39: 83 unit tests and 6 UI tests, including setup validation and round delete with a relaunch). Earlier: 83 unit tests and 3 UI tests (full 18-hole round by taps through to settlement, and a seeded round with an unresolved carryover) pass locally on iOS 26 and in CI on iOS 18. A device-architecture build of main compiles unsigned. Signing and install on the phone are unverified until it is connected.
- Hole events are last-writer-wins per field: two devices recording different Wad makers on the same hole at the same moment can lose one maker. Conditional writes were not called for by the docs; revisit with WebSocket sync (M3.3).
- Venmo: the deep link format is undocumented by Venmo; verified on the owner's phone on 2026-09-30 (Venmo opened with the payment filled in). The app still falls back to the web link or marking paid by hand.
- The update keeps saved rounds: a store written by the previous build opens with the new models (#41, unit test plus a manual check on the simulator).
- Theme (#66): nav bar title attributes stay on the UIKit proxy (a custom UINavigationBarAppearance hid the large title on iOS 26), so on iOS 18 the light-mode nav bar background is the system material rather than charcoal; light-mode alerts remain system dialogs; the chain overlay on the scoring bars overlaps the list edge by about 4pt. Checked at accessibility-extra-large Dynamic Type on the settlement screen; iOS 17 untested.
- Course lookup (#64): on iOS 17 a denied location permission shows as "could not be found" after the 15 s timeout (the denial flags on CLLocationUpdate are iOS 18+). The provider's daily quota is about 35 requests; the app caches searches and courses for 7 days and serves stale copies when the API fails. The round does not store the course or tee ids; the draft only notes the selection.
- CI ui-tests flaked once on #64 (round delete test timed out on the suite's cold first launch, 10 s); a rerun passed. The app icon is a first version (the W does not follow the flag's wave; dark and tinted variants are opaque).
- Backend concurrency tests run against an in-memory fake, not real DynamoDB.
- Wad makes that the engine ignores are not shown on the settlement screen.
- iOS CI runs Xcode 16.4 with an iOS 18 simulator; local runs use iOS 26. Controls in list section headers were not hittable for XCUITest on iOS 18, so they were moved into full-width rows (#20).
- The `Round` SwiftData schema changed with no migration; delete any older install of the app before installing.

## Blocked / deferred

- M1 auth, Sign in with Apple, any public endpoint deploy: waiting on Apple Developer Program enrollment.
- Device install: waiting for the phone to be connected (`ios/scripts/install-device.sh`).
