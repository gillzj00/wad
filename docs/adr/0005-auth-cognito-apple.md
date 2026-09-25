# ADR-0005: Auth via Cognito federated with Sign in with Apple

- Status: Accepted
- Date: 2026-09-25

## Context

Need low-friction, private sign-in for an iOS app, integrated with API Gateway authorization, without operating our own credential store.

## Decision

Use an **Amazon Cognito User Pool** with **Sign in with Apple** as a federated identity provider. The iOS app uses `ASAuthorizationController`; Cognito issues JWTs; API Gateway (HTTP + WebSocket) validates them. The user id is the Cognito `sub`.

## Consequences

- Requires an Apple Developer account and a Services ID / key for Sign in with Apple, wired into Cognito (Terraform + secrets).
- If any third-party login is offered later, Apple's App Store rules require Sign in with Apple anyway, so this is future-proof.
- No passwords to store or reset in v1.
