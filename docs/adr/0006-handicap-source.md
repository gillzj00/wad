# ADR-0006: Manual handicap entry now, pluggable provider for GHIN later

- Status: Accepted
- Date: 2026-09-25

## Context

Skins needs each player's handicap to allocate ticks. The obvious source is GHIN, but the USGA/GHIN has **no open public API**; sanctioned access is via the USGA **GPA program** (application + license), which we do not control and which could block the MVP. Reverse-engineered GHIN endpoints violate USGA terms.

## Decision

For v1, store a **handicap index on the user profile via manual entry**. Abstract the source behind a `HandicapProvider` interface so an official GHIN/USGA integration can be added later without changing the game engines.

## Consequences

- MVP has no external dependency for handicaps.
- Course handicap is computed from the index + selected tee's slope/rating (see `docs/domain-model.md`).
- A future ADR will cover pursuing GPA access and implementing a `GhinHandicapProvider`.
