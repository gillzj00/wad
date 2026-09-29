# ADR-0011: Run the game engines on device through JavaScriptCore

- Status: Accepted
- Date: 2026-09-29

## Context

The first usable version of the app is a local-only demo: one phone scores a round and shows the games and the settlement without the API, auth, or sync being in place. That needs the Skins, Wad, Greenies, handicap, and settlement engines on the device.

The engines already exist in TypeScript (`backend/src/engines`). They are pure functions with no I/O and carry the highest test coverage in the repo. The payout math has to be correct, and the server's result stays canonical once the backend is wired in (`docs/architecture.md`), so the device and the server must never disagree.

Options considered:

1. **Port the engines to Swift.** Native types and no bridge, but two implementations of the payout rules that must be kept identical by hand, with two test suites. Every rule change, including each resolved Open Question, would have to land twice.
2. **Bundle the TypeScript engines and run them in JavaScriptCore.** One implementation. JavaScriptCore ships with iOS, so there is no new dependency.
3. **Call the backend for every calculation.** Not possible for a local-only demo, and it does not work with poor signal on the course.

## Decision

Bundle `backend/src/engines` with esbuild into a single script and call it from Swift through JavaScriptCore. Payout math is not ported to Swift.

- `backend/src/engines/index.ts` is the single entry point. `npm run build:ios-engines` bundles it as an IIFE that defines the global `WadEngines` (target ES2020, no Node built-ins) and writes `ios/Wad/Resources/engines.js`.
- The generated bundle is committed, so building the app does not need Node. Backend CI rebuilds it and fails if the result differs from the committed file.
- `EngineBridge` (`ios/Wad/Engine/`) loads the bundle into a `JSContext` and exposes typed Swift functions. Inputs and outputs are `Codable` structs that mirror the TypeScript types and cross the boundary as JSON.
- JavaScript exceptions are rethrown as Swift errors.

## Consequences

- **Single source of truth for payout math.** A rule change is made and tested once, in TypeScript, and the device picks it up through the bundle. The Swift tests reproduce the worked examples in `docs/domain-model.md` through the real bundle to check the bridge, not to re-test the rules.
- **The bundle must be kept in sync.** Any change under `backend/src/engines` (or to the types it imports) requires running `npm run build:ios-engines` and committing the result. CI enforces this. The build has to stay deterministic: the esbuild version is pinned by `package-lock.json`, and the output is not minified so diffs are reviewable.
- **JSON boundary.** The Swift structs are a hand-written mirror of the TypeScript types; a changed field has to be updated on both sides, and a mismatch shows up as a decoding error at runtime rather than at compile time. Money crosses as integer cents and is decoded as `Int`, so a non-integer amount fails to decode instead of being rounded.
- **Performance is irrelevant at this size.** Apps cannot use the JavaScriptCore JIT, so the engines run in the interpreter. A round is at most 18 holes and a handful of players; a call takes well under a millisecond of actual work.
- A `JSContext` is not thread-safe. `EngineBridge` is a non-`Sendable` class, so Swift 6 strict concurrency keeps each instance in one isolation domain.
- When the backend is wired in, the server's result remains canonical (`docs/architecture.md`); the on-device engines then provide instant feedback and offline results from the same code.
