# ADR-0003: Native SwiftUI iOS app

- Status: Accepted
- Date: 2026-09-25

## Context

The product is explicitly an iPhone app for on-course use. Connectivity on courses is poor, and native integrations (Sign in with Apple, MapKit, Venmo/Apple deep links) matter.

## Decision

Build a **native SwiftUI** app targeting **iOS 17+**, using **SwiftData** for the local offline store.

## Alternatives considered

- **React Native / Expo:** would share TypeScript with the backend and ease a future Android port, but adds friction for deep native/offline behavior.
- **Flutter:** strong cross-platform UI, but a new language for the stack and no code sharing with the backend.

## Consequences

- iOS-only for v1; Android is out of scope.
- Best-in-class offline and native UX; no cross-platform code sharing.
- Client contract with the backend is defined in `docs/api.md`.
