# ADR-0013: Deploy the courses API before auth, behind a shared client token

- Status: Accepted
- Date: 2026-09-29

## Context

The app needs course lookup (search and scorecard data) now, but auth (M1, Cognito with Sign in with Apple) waits on Apple Developer Program enrollment. The earlier rule was that nothing public is deployed before auth, because the course provider's free tier allows only about 35 requests a day and an open endpoint would let anyone burn that quota.

On 2026-09-29 @gillzj00 decided to deploy course lookup anyway: the backend handles the provider with the owner's own API key, so the key never has to live on a phone. Nothing else is deployed: no rounds, profile or settlement routes, and no Cognito.

Options considered:

1. **The app calls the provider directly** with the key typed into the phone once. No backend to deploy, but the key sits on every device, and the DynamoDB cache (which is what keeps a handful of users under the daily quota) is not used.
2. **Deploy the courses handler as-is on a public endpoint.** Simplest, but a link in a chat message is enough to exhaust the quota.
3. **Deploy the courses handler behind a shared client token plus throttling.** Not authentication, but enough that drive-by traffic gets a 401 before the provider is called.

## Decision

Option 3. `GET /v1/courses` and `GET /v1/courses/{courseId}` are deployed in dev as one Lambda behind an API Gateway HTTP API (`infra/environments/dev/courses_api.tf`).

- **Client token.** Terraform generates a random token (`random_password`) and stores it as a SecureString at `/wad/dev/client-token`. The handler reads it from SSM once per container, alongside the provider key, and requires every request to carry it in the `x-wad-client` header (compared in constant time). A missing or wrong token is `401 invalid_client_token` before any DynamoDB or provider call. The token is never a Terraform output, never logged, and never committed: a developer fetches it from SSM into the git-ignored `ios/Config/Local.xcconfig` (see `infra/README.md`).
- **Throttling.** The stage is limited to a burst of 5 and 2 requests per second.
- **Least privilege.** The function may only read and write the single table, read the two parameters, and write its own log group.
- **Deploy pipeline.** The Terraform workflow builds the handlers (`npm ci && npm run build`) before plan and apply and also runs on `backend/**` changes.

## Consequences

- The app can look courses up through the API, and the write-through cache in DynamoDB keeps provider calls to one per new course or search.
- This is an **interim guard, not auth**. Anyone with the token, such as a TestFlight build that is shared, can use the quota. The handler still returns `503 course_provider_rate_limited` when the provider's daily limit is hit, so the failure mode is a bad day for course search, not a bill.
- When the Cognito authorizer lands (M1.1), the token check is removed from the handler and the header is dropped from the app; the SSM parameter and `random_password` are deleted in the same change.
- The `POST /v1/courses` and `POST /v1/courses/{courseId}/corrections` routes exist in the handler but are not routed by API Gateway; they also need a caller `sub`, which only the authorizer provides.
