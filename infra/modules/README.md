# Terraform modules

Reusable modules, added per milestone and consumed by the environment stacks under `infra/environments/`.

Planned modules:
- `dynamodb/` — extract the single-table definition from the dev stack once a second environment exists.
- `cognito/` — user pool, app client, Sign in with Apple IdP, JWT authorizer wiring (M1).
- `api-http/` — API Gateway HTTP API + routes + integrations (M1+).
- `api-ws/` — API Gateway WebSocket API + routes + connection handling (M3).
- `lambda/` — reusable Lambda function (packaging, role, log group) used by the API modules.

Keep modules small and composable; document inputs/outputs in each module's own README.
