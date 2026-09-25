# ADR-0008: Course data via licensed API with local caching

- Status: Accepted
- Date: 2026-09-25

## Context

We need per-hole par and stroke index, per-tee yardage, and course/slope ratings. Options range from licensed APIs to scraping to unofficial GHIN endpoints. See `docs/course-data.md` for the full research.

## Decision

Use a **licensed course API with write-through caching in DynamoDB**, behind a `CourseProvider` interface. Primary provider **GolfCourseAPI** (returns exactly the needed fields, ~30k courses, ~$9.99/mo Pro, permits internal caching). Internal schema follows the CC-BY **Open Course** model. Provide manual entry + user corrections for gaps.

## Alternatives considered

- **Scraping** course sites / BlueGolf / USGA NCRDB: brittle, ToS/CFAA exposure, and NCRDB lacks per-hole stroke index. Rejected.
- **Unofficial GHIN endpoints:** violate USGA terms, risk access revocation/legal action. Rejected.
- **golfapi.io / RYZE via RapidAPI:** viable fallbacks/scale-up options.

## Consequences

- Requires a provider API key (stored in SSM/Secrets, not the repo).
- Must **not** expose a bulk export of course data (no-redistribution terms).
- Caching keeps cost and rate-limit usage negligible since course data is static.
