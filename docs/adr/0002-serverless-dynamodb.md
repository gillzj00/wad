# ADR-0002: Serverless backend on Lambda + API Gateway + DynamoDB

- Status: Accepted
- Date: 2026-09-25

## Context

The app must be cost-effective when there is essentially one user, but scale without re-architecture if it grows. The owner suggested Lambda.

## Decision

Backend is serverless: **API Gateway** (HTTP + WebSocket) -> **AWS Lambda** (TypeScript, Node 22) -> **DynamoDB** single table. Pay-per-use across the board.

## Alternatives considered

- **Aurora Serverless v2 (Postgres):** nicer relational modeling for bets, but has a minimum ACU cost floor (always-on baseline), which fails the "near-zero when idle" goal.
- **ECS Fargate + RDS:** always-on baseline cost and more infra to operate.

The relational-modeling downside of DynamoDB is mitigated by keeping the money math in **pure engine functions** rather than in database queries; the DB only stores scores and derived state.

## Consequences

- Requires disciplined single-table design (see `docs/data-model.md`).
- Scales to ~$0 at rest and up transparently under load.
- Real-time needs a WebSocket API + connection registry rather than a persistent server (see ADR-0004).
