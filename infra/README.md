# Infrastructure (Terraform)

All AWS resources are defined here and applied through GitHub Actions using GitHub OIDC (no long-lived AWS keys). See [ADR-0009](../docs/adr/0009-terraform-github-oidc.md).

```
infra/
  bootstrap/            # run ONCE, locally, by a human with admin AWS creds
  modules/              # reusable modules (added per milestone: dynamodb, api, lambda, cognito, ...)
  environments/
    dev/                # the dev stack; applied by CI
```

## One-time bootstrap

The bootstrap creates the remote state backend, the GitHub OIDC provider, and the CI role. It runs locally because CI cannot yet assume a role that does not exist.

1. Authenticate to AWS with admin credentials for the target account:
   ```
   aws sso login          # or export AWS_PROFILE / credentials
   aws sts get-caller-identity
   ```
2. Apply the bootstrap:
   ```
   terraform -chdir=infra/bootstrap init
   terraform -chdir=infra/bootstrap apply
   ```
3. Note the outputs:
   - `state_bucket` and `lock_table` -> used by each environment's `backend.tf`.
   - `ci_role_arn` -> set this as the GitHub Actions **repository variable** `AWS_ROLE_ARN`:
     ```
     gh variable set AWS_ROLE_ARN --body "<ci_role_arn>"
     gh variable set AWS_REGION --body "us-east-1"
     ```
4. Point the dev backend at the created bucket (edit `environments/dev/backend.tf` if the bucket name differs from the default) and initialize:
   ```
   terraform -chdir=infra/environments/dev init
   ```

The bootstrap state is local by design (it creates the very bucket that would store remote state). Commit nothing sensitive; `*.tfvars` and state files are gitignored.

## Day-to-day

- Changes to `infra/**` on a pull request run `fmt`/`validate`/`plan` (plan posted to the PR).
- Merges to `main` run `apply` via the CI role.
- Run `terraform fmt -recursive infra` before committing; CI enforces formatting.
- Never introduce static AWS access keys and never use admin override to force an apply.

## Environments

`dev` first. Add `prod` later by copying `environments/dev` to `environments/prod` with its own `backend.tf` state key and variables.
