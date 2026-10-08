# Terraform modules

Reusable modules, added per milestone and consumed by the environment stacks under `infra/environments/`.

Modules:
- `lambda/` — one Lambda function from a prebuilt handler bundle (packaging, role, log group).

Planned modules:
- `dynamodb/` — extract the single-table definition from the dev stack once a second environment exists.
- `cognito/` — user pool, app client, Sign in with Apple IdP, JWT authorizer wiring (M1).
- `api-http/` — API Gateway HTTP API + routes + integrations, once there is more than the courses API (the HTTP API lives in the dev stack until then).
- `api-ws/` — API Gateway WebSocket API + routes + connection handling (M3), once the live relay becomes the round sync (the WebSocket API lives in the dev stack until then).

Keep modules small and composable; document inputs/outputs in each module's own README.
