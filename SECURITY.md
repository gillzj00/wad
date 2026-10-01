# Security policy

Wad is a small, pre-release hobby project. There is no bug bounty, but reports are read and acted on.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Instead use GitHub's private vulnerability reporting for this repository: **Security** tab, then **Report a vulnerability** (`https://github.com/gillzj00/wad/security/advisories/new`). If that is unavailable, contact the owner, [@gillzj00](https://github.com/gillzj00), through GitHub.

Include what you found, where (file, endpoint or commit), and how to reproduce it. You can expect an acknowledgement within a week. Please give reasonable time for a fix before disclosing publicly.

## Scope

In scope:

- The code in this repository: the iOS app, the Lambda backend and the game engines, and the Terraform under `infra/`.
- The GitHub Actions workflows and the way CI obtains AWS credentials (OIDC).
- Anything committed to the repository that should not be public (credentials, identifiers, state).

Out of scope:

- The `dev` AWS environment's availability. It is a development stack with request throttling; denial-of-service reports and load testing are not wanted.
- Third-party services the project depends on (AWS, GitHub, Apple, the course-data provider). Report those to the provider.
- Findings that require a compromised or jailbroken device, or physical access to an unlocked phone.
- The rules and payouts of the golf games themselves; those are product questions, not vulnerabilities.
- Social engineering of the owner or contributors.

## Supported versions

Only the `main` branch is supported. There are no releases yet.
