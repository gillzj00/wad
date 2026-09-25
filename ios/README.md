# iOS app (SwiftUI)

Native SwiftUI app for iPhone (iOS 17+), offline-first with live round sync. Not yet scaffolded - this is created in milestone **M0.6** (see [../docs/roadmap/milestones.md](../docs/roadmap/milestones.md)).

## Intended shape

- SwiftUI + SwiftData local store (the working copy during a round).
- A sync engine that queues mutations offline and replays them; a WebSocket client for live updates.
- An API client generated from / matching the contract in [../docs/api.md](../docs/api.md).
- Sign in with Apple via `ASAuthorizationController`; tokens in Keychain.

## When scaffolding (M0.6)

- Create the Xcode project here (`ios/Wad.xcodeproj` or a Swift Package + app target) with a `Wad` scheme.
- Add a unit test target; wire it into `.github/workflows/ios-ci.yml` (the workflow auto-activates once an `.xcodeproj`/`.xcworkspace` exists).
- Update the build/test commands in [../CLAUDE.md](../CLAUDE.md) if they differ.

See [../docs/architecture.md](../docs/architecture.md) for the client design and conflict strategy.
