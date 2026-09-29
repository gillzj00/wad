# Backend (TypeScript on AWS Lambda)

Serverless API behind API Gateway (HTTP + WebSocket) backed by a single DynamoDB table. Runs on the Lambda Node.js 22 runtime.

## Commands

Use Node 22 (`nvm use` reads `.nvmrc`).

```
npm install
npm test                  # all tests (vitest)
npm test -- engines/skins # tests whose path matches a pattern
npm run test:watch        # watch mode
npm run typecheck
npm run lint
npm run build             # bundles each src/handlers/*.ts to dist/<name>/index.mjs
```

## Structure

```
backend/
  src/
    handlers/   # thin Lambda adapters (parse, authorize, call service, respond); one bundle per file
    services/   # business logic + DynamoDB access
    engines/    # PURE game logic (Skins/Wad/Greenies, handicaps) - no I/O, fully tested
    shared/     # types shared with the client, matching docs/api.md
  test/         # vitest tests, mirroring src/
  scripts/      # build tooling
```

## Rules that matter here

- **Engines are pure.** No I/O, no clock, no randomness - deterministic and unit-tested. This is where the money math lives; correctness is paramount. Do not implement rules that are still [Open Questions](../docs/domain-model.md#open-questions).
- **Money is integer cents.** Never floats.
- Keep the DynamoDB access aligned with [../docs/data-model.md](../docs/data-model.md) (single table).
- TypeScript is pinned to 6.0.x because `typescript-eslint` does not yet support TypeScript 7.
