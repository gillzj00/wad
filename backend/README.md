# Backend (TypeScript on AWS Lambda)

Serverless API behind API Gateway (HTTP + WebSocket) backed by a single DynamoDB table. Not yet scaffolded - created in milestone **M0.4** (see [../docs/roadmap/milestones.md](../docs/roadmap/milestones.md)).

## Intended structure

```
backend/
  src/
    handlers/   # thin Lambda adapters (parse, authorize, call service, respond)
    services/   # business logic + DynamoDB access
    engines/    # PURE game logic (Skins/Wad/Greenies, handicaps) - no I/O, fully tested
    shared/     # types shared with the client, matching docs/api.md
  test/
  package.json
```

## Rules that matter here

- **Engines are pure.** No I/O, no clock, no randomness passed implicitly - deterministic and unit-tested. This is where the money math lives; correctness is paramount. Do not implement rules that are still [Open Questions](../docs/domain-model.md#open-questions).
- **Money is integer cents.** Never floats.
- Keep the DynamoDB access aligned with [../docs/data-model.md](../docs/data-model.md) (single table).

## When scaffolding (M0.4)

- Set up TypeScript (Node 20 target), a test runner, `lint`/`typecheck`/`build`/`test` npm scripts, and a Lambda bundler.
- Commit `package-lock.json` (the CI workflow caches on it and runs `npm ci`).
- The CI workflow (`.github/workflows/backend-ci.yml`) auto-activates once `backend/package.json` exists.
- Update the commands in [../CLAUDE.md](../CLAUDE.md) if they differ.
