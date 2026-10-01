# Wad

Wad is an iPhone app for tracking scores and side-bets during a round of golf. Bring it to the course to keep score for your group and settle up the money games at the end.

## Supported games

- **Wad** — a putting game. Make your first putt on a green from at least a flagstick's length away and you take the Wad. It starts at $7 and every qualifying make after that adds $2. Whoever holds it at the end of each nine collects its value from each other player.
- **Skins** — net match play for money. Handicap strokes ("ticks") are allocated to the hardest holes based on the difference between players' course handicaps. The sole net winner of a hole collects the skin from each other player; ties carry the value to the next hole.
- **Greenies** — a par-3 game. Hit the green off the tee and make par or better; if several players do, the closest tee shot wins. The winner collects from each other player.

At the end of the match the app nets out who owes whom across every game and helps you settle up with pre-filled Venmo payments.

## Status

Pre-development. This repository currently contains the plan, architecture, and infrastructure/CI scaffolding. See **[docs/PLAN.md](docs/PLAN.md)** for the roadmap and **[docs/roadmap/milestones.md](docs/roadmap/milestones.md)** for grabbable work items.

## Architecture at a glance

- **iOS app** — native SwiftUI (iOS 17+), offline-first with real-time sync during a round.
- **Backend** — serverless AWS: API Gateway (HTTP + WebSocket) → Lambda (TypeScript) → DynamoDB single-table. Scales to near-zero cost for a single user.
- **Auth** — Amazon Cognito federated with Sign in with Apple.
- **Infrastructure** — Terraform, applied through GitHub Actions via GitHub OIDC (no long-lived AWS keys).

Full detail lives in [docs/architecture.md](docs/architecture.md).

## Repository layout

| Path | Purpose |
| --- | --- |
| `docs/` | Plan, architecture, domain model, data model, API contract, ADRs, roadmap |
| `ios/` | SwiftUI application (Xcode project) |
| `backend/` | TypeScript Lambda functions and shared game engines |
| `infra/` | Terraform: `bootstrap/`, reusable `modules/`, per-env stacks under `environments/` |
| `.github/workflows/` | CI/CD, including Terraform plan-on-PR / apply-on-main |

## Public repository

This repository is public so the project can use GitHub Actions freely. Some things are deliberately not in it:

- **Secrets and keys** — no AWS access keys (CI assumes an IAM role through GitHub OIDC), no course-data provider key (it lives in AWS SSM), no client tokens. `.env` files and `*.tfvars` are gitignored; only the `*.example` templates are committed.
- **Apple signing** — the development team id lives in the gitignored `ios/Config/Local.xcconfig` (copy `Local.xcconfig.example`). Provisioning profiles and certificates are never committed.
- **Device identifiers** — no real device UDIDs; the test fixtures use synthetic ids.
- **AWS account details and Terraform state** — the account id, state bucket and role ARN are GitHub repository variables, state stays in S3, and saved plans (`tfplan`) are gitignored.

How changes land: every change goes through a pull request. `main` is protected (no direct pushes, force pushes or deletions; status checks required; applies to administrators). Pull requests from forks run CI only after the owner approves the run, get a read-only token and cannot assume the AWS role. A Terraform apply runs only on a merge to `main` and waits for the owner's approval as the required reviewer of the `dev` GitHub Environment.

Security issues: see [SECURITY.md](SECURITY.md).

## Getting started

The project is not yet buildable. The first task is Milestone 0 (foundations) in [docs/roadmap/milestones.md](docs/roadmap/milestones.md), which includes the one-time Terraform bootstrap described in [infra/README.md](infra/README.md).
