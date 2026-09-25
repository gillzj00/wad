# ADR-0007: Settlement via computed debts + Venmo deep links

- Status: Accepted
- Date: 2026-09-25

## Context

We want to reconcile bets at the end of a match, ideally with Venmo. Venmo has **no general public API** for sending person-to-person payments; the realistic integration is a **deep link** that pre-fills a payment the user confirms in the Venmo app.

## Decision

The backend computes each player's net position across all games and reduces it to a minimal set of pairwise transfers. The iOS app opens **Venmo deep links** pre-filled with recipient, amount, and note. The user confirms in Venmo, then marks the transfer paid in Wad. **No money moves through our backend.**

## Alternatives considered

- **In-app ledger only:** simplest; keep as a fallback if a user lacks Venmo.
- **Real payment processing (Stripe/PayPal):** money-transmission compliance and fees; overkill for friendly bets. Rejected.

## Consequences

- No financial regulatory burden on the backend.
- Depends on Venmo's deep-link URL scheme; the app must degrade gracefully to "mark settled" if Venmo is not installed.
- Store each player's Venmo handle on their profile (optional).
