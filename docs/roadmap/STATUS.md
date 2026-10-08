# Status

Source of truth for the orchestrated build-out. Updated after every merged PR. After any context summarization, re-read this file first.

Last updated: 2026-10-08 (after #83)

## Current phase

**Phase 1 demo is complete and installed** (merged in #16, #18, #20, #22). It was installed on the owner's iPhone on 2026-09-30 from main at #61. Reinstall with `ios/scripts/install-device.sh` when a newer build is wanted (Personal Team builds expire after 7 days). If the schema changed since the installed build, delete the older install of Wad first (no migration).

**Phase 2 — backend:** the four listed items are merged (#24, #26, #28, #30); the documented handicap override route followed (#32). Remaining milestones (M1, M2.2/M2.4 deploy, M3.3, M3.4/M3.5, M5.2, M6) depend on auth, deploys or iOS sign-in and wait on Apple Developer Program enrollment or a decision from @gillzj00. Original scope: M3.1 round lifecycle API, M3.2 scoring API, M5.1 settlement API, M2.3 manual course entry. Handler code and tests only. No M1 auth, no Sign in with Apple, nothing that deploys a public endpoint until @gillzj00 confirms Apple Developer Program enrollment. Any `infra/` PR needs explicit approval in chat.

**Phase 4 — scoring polish and live relay** started 2026-10-05: four PRs are merged (#79, #80, #81, #83). The relay API (#82) waits for @gillzj00's approval.

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
| T2 | Event animations (requested 2026-09-29, revised): full-screen, deliberately over the top, with haptics. Wolf hole won: a wolf baring its teeth plus a howl sound and vibration. Greenie: a golf ball falls from the sky like a bomb and blows the green apart. Wad taken: a skeleton hand making it rain money. Skins won: a skeletal hand being skinned. Score animations (added 2026-09-29, bowling-alley style): eagle or better: a bald eagle soars across the screen and screeches; hole in one: the loudest of all, fireworks and champagne bottles popping, long vibration; albatross (proposed, to confirm): a huge albatross dives out of a lightning storm, rips the flag out of the hole and flies off with it, with a thunderclap; a score of 8: a snowman that falls apart; birdie: a middle finger ("the bird") shown to every OTHER player, in the demo shown on the scoring phone addressed to the others. Original art and sounds only (synthesized howl, no downloaded audio); Reduce Motion gives a still image; a mute switch in settings. Plays on the scoring phone in the local demo; showing it on every player's phone needs live sync (M3.3, after auth) | ios/ | done (SpriteKit shows, synthesized sound, haptics, settings switches, Reduce Motion stills; Wolf show triggers through a hook filled by W2) | #68 |
| T2b | Art pass on the nine animation subjects after owner feedback on #68: anatomy-based, cel-shaded, outlined art; the birdie is a skeletal finger | ios/ | done | #71 |
| W2 | Wolf in the demo app: setup, tee order, per-hole choice, 17/18 tie prompt (the group picks, the engine never does), live points, pay-the-difference settlement, Wolf show trigger | ios/ | done | #69 |
| T2c | Generated art for the animation subjects, per `docs/art/animation-assets.md` | ios/, docs/ | superseded: on 2026-10-02 the owner judged the code-drawn shows unacceptable and halted all animation work ("we are going to go a different route"); the route is the owner's to name. PR #74 (wolf jaw and eagle framing) was closed unmerged. | - |
| C2 | Courses tab: course search, course detail with tees and scorecard, start a round from a course (the owner found the placeholder tab and could not search) | ios/ | done (search, Near me, Recent from the on-device cache, course detail with tee menu and scorecard, Start a round here) | #76 |
| C3 | Adjustable "Near me" radius in miles in the Courses tab | ios/ | done 2026-10-02 | #78 |

## Phase 4 task list

| # | Task | Touches | State | PR |
| --- | --- | --- | --- | --- |
| P4.1 | Round complete pop-up on the scoring screen: a sheet offers "Round summary" (the settlement) or "Keep scoring" when a change completes the round, or is made on the last hole of an already complete round; once dismissed it stays away until another hole is visited (`RoundCompletionPrompt`, `AppNavigation.pendingRoute`) | ios/ | done 2026-10-05 | #79 |
| P4.2 | Skins carryover toggle: engine `SkinsInput.carryover` (default true), API `games.skins.carryover` (`400 invalid_carryover`), `Round.skinsCarryover`, setup toggle "Carry pushed holes over", detail row, scoring wording; domain model and API docs updated; on-device engine bundle regenerated | backend/, ios/, docs/ | done 2026-10-05 | #80 |
| P4.3 | Scorecard editing: tap a player's score on the round detail scorecard to edit it in `ScoreEditSheet`; Hole, Par, Out, In and Total are not editable; the sheet closes when a show starts | ios/ | done 2026-10-05 | #81 |
| P4.4a | Live relay API (ADR-0014): WebSocket API Gateway stage `live`, rooms keyed by a 6-character code, messages opaque to the server, shared `x-wad-client` token, 6-hour TTL | infra/, backend/, docs/ | open, waits for the owner's approval in chat (plan 17 add / 1 change / 0 destroy, under $1/month) | #82 |
| P4.4b | iOS live client (`ios/Wad/Live/`): "Share live" on the round detail shows a 6-character code (`Round.liveCode`); "Follow a round" on the Rounds tab plays the scoring phone's game events through the same shows and keeps a feed; `EventCenter.relay`/`relayScores` hooks; needs `WAD_LIVE_URL` in `ios/Config/Local.xcconfig`, nothing connects without it; 309 unit tests on main | ios/ | done 2026-10-08 | #83 |
| P4.5 | Score entry fix (owner, 2026-10-08): shows play only when every player has a score on the hole, in both the before and after snapshot; "Start every hole at par" defaults off; the scoring phone skips its own shows while sharing live (followers still get them) | ios/ | in flight | - |

## Tasks in flight

- P4.5 | Score entry fix (owner, 2026-10-08): shows play only when every player has a score on the hole, in both the before and after snapshot; "Start every hole at par" defaults off; the scoring phone skips its own shows while sharing live (followers still get them) | ios/ | in flight | -
- Animation work is closed: the owner halted it 2026-10-02 and said 2026-10-05 to stop worrying about graphics; the existing shows stay and are reused by the live relay.
- The one-iOS-task-at-a-time rule was relaxed on 2026-10-01 at the owner's request: T1 and T2 run in parallel, conflicts are limited to the generated project (regenerated with xcodegen) and recolored views.

## Open PRs

- #82 Live relay API (infra, backend, docs; ADR-0014). Waits for the owner's approval in chat. Next steps: after the owner approves, merge; the Terraform apply then waits for the owner's approval in the `dev` GitHub Environment; then `terraform -chdir=infra/environments/dev output -raw live_ws_url` goes into `ios/Config/Local.xcconfig` as `WAD_LIVE_URL` (documented in `ios/Config/Local.xcconfig.example` and `infra/README.md`). Caveat: the PR adds an account-level API Gateway CloudWatch logs role (`aws_api_gateway_account`), required for WebSocket access logs; it would overwrite an existing setting if the account had one.

## Decisions made

- Repo is public since 2026-09-30 (free Actions minutes). Merge policy as clarified by @gillzj00: Claude may squash-merge its own PRs (authored by the owner's account) once every required check is green; `infra/` PRs still need the owner's approval in chat; every Terraform apply additionally waits for the owner's approval in the `dev` environment. Required checks on main: unit-tests, ui-tests, build-test, plan (strict, up to date). SHA pinning of actions is required.
- Course lookup (2026-09-29): option B, deploy the courses API before auth with the owner's provider key staying in AWS. This overrides the earlier no-public-endpoint rule for this one endpoint. Interim quota guard: API Gateway throttling plus a shared `x-wad-client` token in SSM; replaced by Cognito in M1.1. Recorded in ADR-0013 (I1).
- Art rule relaxed (owner, 2026-10-01): original or generated art, no stock downloads. The animation subjects may be generated PNGs; the asset pack and prompts are in `docs/art/animation-assets.md`. No image generation connector exists in the registry, so the owner either generates the files in any image model or provides an API key outside the repo.
- Animations (owner, 2026-10-01): the snowman plays for a score of exactly 8 only; the albatross animation (dives out of a lightning storm, rips the flag out, thunderclap) is confirmed. The presentation uses SpriteKit (built in, no dependency); subjects stay original and code-drawn.
- Animations (#68): events are derived from engine state before and after each change on the scoring screen and play only when they newly appear, so corrections never replay a show; several events from one change play in the fixed order hole in one, albatross, eagle, greenie, Wad, skin, Wolf, snowman, birdie. Sounds are synthesized at runtime; the silent switch mutes them; settings has animation and sound switches; Reduce Motion shows a paused poster frame. SpriteKit is used for the shows (built in, no dependency). On Xcode 16.4 SKNode is main-actor isolated, so the scene code is explicitly @MainActor.
- Theme (#66): both appearances are dark (light = ash variant, dark = pitch); palette charcoal, card, rule, maroon, crimson, blood, ember, bone, ash; money won is ember, money owed is blood; all 14 text/background pairs are at least 4.5:1 and a unit test enforces it.
- Wolf rules accepted by @gillzj00 on 2026-09-29: four players only; points 2 (Wolf and partner win, each), 3 (each opponent when they lose), 4 (Lone Wolf wins), 1 (each opponent when Lone Wolf loses); no Blind Wolf; Wolf on 17 and 18 is the player in last place on points; tied hole scores nothing and nothing carries; net best ball with the Skins ticks; $1 a point by default, every pair settles the point difference; tee order is the order players were added, reorderable before play; the Wolf's choice is recorded per hole and can be corrected.
- Engines run on device through JavaScriptCore from an esbuild bundle of `backend/src/engines`; payout math is not ported to Swift. To be recorded in ADR-0011 (P1.1).
- The engine bundle is generated by a backend script and committed under `ios/`, so building the app does not need Node. Backend CI fails if the committed bundle is stale.
- Phase 1 rounds are always 18 holes with no mid-round leaving, which avoids Open Questions 2 and 3.
- Open Question 1: the unresolved skins carryover is displayed and never paid out.
- Handicaps (revised after @gillzj00 asked on 2026-09-29): manual course entry takes an optional course rating and slope. When given, a player enters their handicap index and the app computes the course handicap through the engine's `courseHandicap`, with a per-round override. Without rating/slope the course handicap is entered directly. The course API is not used in Phase 1 (local-only; the key stays in SSM and `GET /courses` is not deployed until auth).
- ADR-0011 accepted and merged (#16).
- `Wad.xcodeproj` is regenerated with xcodegen, never hand-merged. Parallel `ios/` tasks are allowed when their files barely overlap (owner, 2026-10-01); the later PR merges `origin/main` in (never rebase).
- Course lookup in the app (#64): the base URL and `x-wad-client` token reach the app only through the git-ignored `ios/Config/Local.xcconfig` (Info.plist keys); a build without them works by hand. The default tee is the first usable men's tee in the API's order (Blue at Oak Glen); the last course and tee picked on the phone become the next default. Nearest-course suggestion ranks only courses cached on the phone, never preselects, and no coordinate leaves the device.

- Animations (owner, 2026-10-05): "quit worrying too much about the graphics"; the existing shows stay as they are and are reused by the live relay. No further art work.
- Round complete pop-up (#79): once per hole visit; a change that completes the round always shows it; swiping it away counts as "Keep scoring"; the settlement screen keeps its "Settlement" title, the button says "Round summary".
- Skins carryover (#80): a plain `Round` attribute (not in `GameSettings`); stored API config always states `carryover` for new rounds, `gameState` defaults missing values to true; with carryover off the "Nothing carried in" sentence is dropped everywhere; Open Question 1 stays open.
- Scorecard editing (#81): `PlayerScoreRow` is reused whole in the sheet; summary cells have accessibility labels "Out 12", "Total 73"; the row keeps the `scorecard.Out.<name>` identifier the walkthrough test reads.
- Live relay (ADR-0014, #82/#83): interim relay before auth, behind the shared `x-wad-client` token, rooms keyed by a 6-character code the scoring phone generates (`Round.liveCode`), messages opaque to the server, 6-hour TTL, 4096-byte frames, replies travel as the `$default` route response, stage named `live`. App: one role at a time (sharing or following), `relay` and `relayScores` hooks on `EventCenter`, follower enqueues received events only when its shows are enabled, 401 stops reconnecting, ping every 30 s, backoff 1 to 30 s.
- Orchestration (2026-10-08): subagents run on sonnet (mechanical work) or opus (feature work), never on the orchestrator's model.
- Merge mechanics: required checks are strict, so after each merge the next PR needs `origin/main` merged in (never rebase, never force-push; for `ios/Wad.xcodeproj/project.pbxproj` take main's copy and run `xcodegen` in `ios/`). Watch runs with `gh run list --commit <sha>`; `gh pr checks --watch` exits before the iOS checks register. `gh pr create --reviewer gillzj00` is a no-op because the PRs are authored by the owner's account.

## Questions waiting on @gillzj00

- Approve PR #82 in chat (infra), then the `dev` environment apply.
- "Start every hole at par" (2026-10-08): the fix in flight defaults it off and keeps the toggle. Say if the option should be removed entirely.
- The scoring phone while sharing live (2026-10-08): the fix in flight never plays shows on it while sharing. Say if a "Play shows on this phone" switch is wanted instead.
- Candidate next features offered 2026-10-05, no answer yet: local-only Profile tab (name, handicap index, Venmo handle to prefill setup); scorecard export as an image; Nassau or Stableford (`docs/research/side-games.md`); 9-hole rounds (Open Question 3) and a mid-round leaver (Open Question 2); hole detection from location (`docs/research/geolocation.md`, phase 2); Apple Developer Program enrollment to unblock M1 auth, TestFlight and a longer-lived device install.
- Default tee for course lookup (#64): the first usable men's tee in the API's order. Say if a specific tee by name is wanted instead.

- The per-round handicap override route was already in docs/api.md, so it was queued without a decision (M3.1b).
- M3.2 choices to confirm (implemented and documented in #28): a member writes only their own score, any member writes guests' scores and hole events; `gross: null` clears a score, gross is 1-20; a greenie winner already over par is rejected with 400, a winner with no score yet is accepted and shows as pending; game state is the raw engine output and is never stored; skins state is null until every player has a course handicap.
- Event animations on every player's phone (asked 2026-09-29): answered by #83, followers get the shows, pending the relay API (#82) being applied.
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
- With "Start every hole at par" on (the default, by owner decision 2026-09-29), a new round reads 18 of 18 and its settlement is Final from the start; results count pars on unplayed holes. The toggle can be switched off per round. The default flips to off in P4.5 (in flight).
- Score entry (reported by the owner 2026-10-08, fixed by P4.5 in flight): with the par default on, every hole is complete from the start, so entering scores one player at a time with + and - played the skin show after every step that changed who had the lowest net.
- Live relay end-to-end on two devices is untested until #82 is applied; the message contract is in `docs/api.md` ("Live relay (dev, interim)") and `docs/adr/0014-live-relay-before-auth.md`.
- Worktrees for merged PRs were removed on 2026-10-08; `.claude/worktrees/` keeps only the ones for open PRs.
- The phone runs iOS 26.6.2 (answered 2026-09-29), the same major version as local verification. iOS 17 remains untested.
- Device install needs the phone near the Mac (USB, or unlocked on the same Wi-Fi). Personal Team builds expire after 7 days. `ios/scripts/install-device.sh` now reports this clearly (#41).
- Simulator access cannot be granted over Remote Control, so screens are verified by the XCUITest walkthrough (setup and scoring since #20) rather than by manual tapping. Optional manual pass when @gillzj00 is back at the Mac.
- Demo verification: 309 unit tests and 3 UI smoke tests on main as of #83. Earlier: 83 unit tests and 6 UI tests as of #39, then 83 unit tests and 3 UI tests (full 18-hole round to settlement, seeded round with an unresolved carryover) on iOS 26 locally and iOS 18 in CI. A device-architecture build of main compiled unsigned; the app has been installed on the phone since 2026-09-30.
- Hole events are last-writer-wins per field: two devices recording different Wad makers on the same hole at the same moment can lose one maker. Conditional writes were not called for by the docs; revisit with WebSocket sync (M3.3).
- Venmo: the deep link format is undocumented by Venmo; verified on the owner's phone on 2026-09-30 (Venmo opened with the payment filled in). The app still falls back to the web link or marking paid by hand.
- The update keeps saved rounds: a store written by the previous build opens with the new models (#41, unit test plus a manual check on the simulator).
- Theme (#66): nav bar title attributes stay on the UIKit proxy (a custom UINavigationBarAppearance hid the large title on iOS 26), so on iOS 18 the light-mode nav bar background is the system material rather than charcoal; light-mode alerts remain system dialogs; the chain overlay on the scoring bars overlaps the list edge by about 4pt. Checked at accessibility-extra-large Dynamic Type on the settlement screen; iOS 17 untested.
- Course lookup (#64): on iOS 17 a denied location permission shows as "could not be found" after the 15 s timeout (the denial flags on CLLocationUpdate are iOS 18+). The provider's daily quota is about 35 requests; the app caches searches and courses for 7 days and serves stale copies when the API fails. The round does not store the course or tee ids; the draft only notes the selection.
- Animations (#68) play on the scoring phone, and since #83 also on phones following the round live once the relay API (#82) is deployed. The owner judged the subjects still crude on 2026-10-01; T2b is the art pass. The ceiling for code-drawn art is a flat cel-shaded cartoon; anything beyond needs authored vector or Rive/Lottie assets, which would change the art-in-code rule.
- The W2 subagent force-pushed (with lease) its own PR branch after a rebase on 2026-10-01; main was untouched, but the owner's rule is no force-push anywhere. Briefs now say: merge main, never rebase a pushed branch.
- Animation shows (#68, #71) stay in the app as merged but are frozen: the owner rejected their look on 2026-10-02 and will choose a different route. Art pass (#71) leftovers (now moot): the wolf's lower fangs are hidden at the open-jaw hold frame (the jaw sprite sits behind the head); the eagle's hold frame catches the near wing partly off screen; the eagle coverts still read a little paddle-like on the up-flap. Small choreography tweaks, or moot once generated art lands.
- CI ui-tests flaked once on #64 (round delete test timed out on the suite's cold first launch, 10 s); a rerun passed.
- Backend concurrency tests run against an in-memory fake, not real DynamoDB.
- Wad makes that the engine ignores are not shown on the settlement screen.
- iOS CI runs Xcode 16.4 with an iOS 18 simulator; local runs use iOS 26. Controls in list section headers were not hittable for XCUITest on iOS 18, so they were moved into full-width rows (#20).
- The `Round` SwiftData schema changed with no migration; delete any older install of the app before installing.

## Blocked / deferred

- M1 auth, Sign in with Apple, any public endpoint deploy: waiting on Apple Developer Program enrollment.
- Device install: waiting for the phone to be connected (`ios/scripts/install-device.sh`).
