# ADR-0009: Terraform applied via GitHub Actions using GitHub OIDC

- Status: Accepted
- Date: 2026-09-25

## Context

Infrastructure is managed with Terraform and must be applied from CI. CI must reach AWS without long-lived credentials, and there is a bootstrapping chicken-and-egg (CI needs a role, but the role is created by Terraform).

## Decision

- **GitHub OIDC federation:** GitHub Actions assumes an AWS IAM role via OIDC; no static AWS keys are stored in GitHub.
- **Bootstrap once, locally:** `infra/bootstrap/` (run by a human with admin AWS credentials) creates the remote state backend (S3 bucket; state locking uses an S3 lock file via `use_lockfile`), the GitHub OIDC provider, and the CI role (scoped to this repo).
- **CI thereafter:** `terraform plan` on pull requests (plan posted to the PR), `terraform apply` on merge to `main`. Apply is gated on required checks; never bypassed with admin overrides.

## Consequences

- The one-time bootstrap and setting the `AWS_ROLE_ARN` repo variable are prerequisites before the Terraform workflow can run (documented in `infra/README.md`).
- Environments are separate Terraform stacks under `infra/environments/`, each with its own state key.
- No AWS secrets live in the repository or in GitHub Actions secrets.
