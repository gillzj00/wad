# ADR-0001: Record architecture decisions

- Status: Accepted
- Date: 2026-09-25

## Context

Multiple agents will iterate on this project in parallel. Decisions need to be discoverable and their rationale preserved so later work does not silently contradict earlier reasoning.

## Decision

We keep lightweight Architecture Decision Records in `docs/adr/`, numbered sequentially. Each records context, the decision, and consequences. When a decision changes, add a new ADR that supersedes the old one (mark the old one `Superseded by ADR-XXXX`) rather than editing history.

## Consequences

- A new significant decision (new AWS service, new table, new external dependency, a resolved Open Question) warrants an ADR.
- `docs/PLAN.md` links to ADRs from its decisions table.
