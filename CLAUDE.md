# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Wad is an iPhone golf app for scoring and settling side-bets (Wad, Skins, Greenies) during a round. This repository is in the **planning/scaffolding stage** — read the docs before writing code. The authoritative sources are:

- `docs/PLAN.md` — roadmap and scope
- `docs/architecture.md` — system design (iOS + serverless AWS backend)
- `docs/domain-model.md` — exact rules for each game (Wad, Skins, Greenies) and handicap allocation. **Read this before touching any scoring/betting logic.** It also lists OPEN QUESTIONS that must be resolved with the product owner (@gillzj00) before implementing the affected rules — do not silently guess them.
- `docs/data-model.md` — DynamoDB single-table design
- `docs/api.md` — HTTP + WebSocket API contract
- `docs/roadmap/milestones.md` — independently grabbable work items with acceptance criteria
- `docs/adr/` — architecture decision records (why, not just what)

## Architecture (big picture)

Three components, each in its own top-level directory:

- **`ios/`** — native SwiftUI app (iOS 17+). Offline-first: a local store is the working copy during a round; mutations queue and sync to the backend when connectivity allows (golf courses have poor signal). Each player owns their own scores, which keeps sync conflicts rare.
- **`backend/`** — TypeScript on AWS Lambda behind API Gateway. Two surfaces: an **HTTP API** for CRUD (users, courses, rounds, settlement) and a **WebSocket API** for live multi-device round sync (fan-out via DynamoDB-stored connection IDs). The **game engines** (Skins/Wad/Greenies) are pure, deterministic functions with no I/O — keep them that way so they are unit-testable and reusable on device if ever needed.
- **`infra/`** — Terraform. `bootstrap/` is applied once by a human with admin AWS credentials (creates remote state, GitHub OIDC provider, and the CI role). Everything else is applied by GitHub Actions on merge to `main`.

Data lives in a **single DynamoDB table** (see `docs/data-model.md`); do not add new tables without an ADR. Auth is **Cognito federated with Sign in with Apple**; API Gateway validates Cognito JWTs.

## Commands

Backend (`backend/`, Node 22 via `.nvmrc`; vitest, eslint, esbuild):
- `npm install` — install dependencies
- `npm test` — run the unit test suite (game engines have the highest coverage bar)
- `npm test -- <pattern>` — run test files whose path matches, e.g. `npm test -- engines/skins`
- `npm run lint` / `npm run typecheck` — static checks
- `npm run build` — bundle each `src/handlers/*.ts` into `dist/<name>/index.mjs`

iOS (`ios/`, once scaffolded):
- Open the Xcode project and build/run, or `xcodebuild -scheme Wad -destination 'platform=iOS Simulator,name=iPhone 16' build`
- `xcodebuild test -scheme Wad -destination 'platform=iOS Simulator,name=iPhone 16'` — run tests

Infrastructure (`infra/`):
- `terraform -chdir=infra/environments/dev init`
- `terraform -chdir=infra/environments/dev plan`
- `terraform fmt -recursive infra` — required before commit; CI enforces it
- `apply` is done through CI, not locally (except the one-time `infra/bootstrap`)

## Conventions

- **Commits:** Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`, `ci:`). Small, focused commits — one logical change each. Do not mention Claude/AI or add co-author/generated-by footers.
- **Pull requests:** All changes go through PRs (no direct pushes to `main`). Request `@gillzj00` as reviewer. Keep titles/descriptions short and free of any AI/tool mentions.
- **Merging (authorized by @gillzj00 for this repo):** Claude may squash-merge its own PRs, including `infra/` changes, once every check on the PR has completed successfully. GitHub does not enforce this (no branch protection on this plan), so verify it: run `gh pr checks <num> --watch` and merge only if all checks passed, with `gh pr merge <num> --squash`. Never merge with failing, pending, or cancelled checks, and never use `--admin`. **Exception:** if an `infra/` change would add more than $20/month in AWS cost (estimate it from the plan), do not merge; leave the PR for @gillzj00 with the estimate in the description.
- **No emojis** anywhere in code, comments, commit messages, or PR descriptions.
- **Money:** never use floating-point for currency. Represent amounts as integer cents.
- **Terraform:** OIDC only — never introduce long-lived AWS access keys. `apply` runs in GitHub Actions on merge to `main`; review the plan posted on the PR before merging. `infra/bootstrap` is applied locally by @gillzj00, not by CI.
- **Secrets:** none in the repo. Use `.env.example` / `*.tfvars.example` templates; real values come from CI secrets / AWS.

## Working style

- Prefer editing existing files over creating new ones; keep solutions simple and focused.
- When a game rule is ambiguous, check the OPEN QUESTIONS list in `docs/domain-model.md` and ask rather than guessing — the payout math has to be correct.
