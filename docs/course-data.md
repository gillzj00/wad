# Course & Scorecard Data

We need, per course and tee set: **par per hole**, **stroke index per hole** (1-18 difficulty), **yardage per tee**, **course rating**, and **slope rating**. This drives the scorecard UI and the handicap-tick allocation for Skins.

## Decision

Use a **licensed course API with local caching**, not scraping. Primary provider: **GolfCourseAPI** (https://golfcourseapi.com). Adopt the CC-BY **Open Course** JSON model as our internal schema. Provide manual entry + a user-correction flow for gaps. See [ADR-0008](adr/0008-course-data-source.md).

## Why (research summary)

- **GolfCourseAPI** returns exactly the fields we need per tee (`tee_name`, `course_rating`, `slope_rating`, `total_yards`, `par_total`, and a `holes[]` array with `par`, `yardage`, and `handicap`/stroke index), covering ~30,000 courses. Free tier ~35 requests/day (email signup); Pro ~$9.99/mo (10k/day); Enterprise ~$24.99/mo. Its terms permit **caching and internal use inside our own app** but prohibit redistributing/reselling the raw dataset.
- Course data is essentially **static**, so caching each course on first fetch keeps us far under rate limits and makes the ongoing cost negligible.
- **Rejected alternatives:**
  - *Scraping* course sites / BlueGolf / USGA NCRDB — brittle, ToS/robots and CFAA exposure, and NCRDB generally does not even publish per-hole stroke index (403s automated access).
  - *Unofficial GHIN endpoints* (reverse-engineered `api.ghin.com`) — violates USGA/GHIN terms and risks access revocation/legal action; not acceptable for a shipped app. The sanctioned route is the USGA **GPA program** (application + license), a possible future integration.
- **Fallbacks / scale-up:** `golfapi.io` (explicit commercial + caching license, credit-based pricing), or **RYZE Golf** via RapidAPI (20,000+ courses). Seed gaps from the **Open Course** CC-BY dataset and let users submit corrections.

Key URLs: https://golfcourseapi.com · https://api.golfcourseapi.com/docs/api/ · https://golfcourseapi.com/terms/ · https://golfapi.io · https://opensourcegolf.com/open-course.html

## Implementation notes

- Wrap the provider behind a `CourseProvider` interface (`search(query)`, `getCourse(id)`), so switching/adding providers later is isolated. The API key lives in Secrets/SSM, never in the repo.
- On `getCourse`, **write-through cache** the normalized course into DynamoDB (`COURSE#<id>`); serve subsequent reads from cache. Store a `source` and `fetchedAt`.
- Normalize provider payloads into the Open Course shape at the adapter boundary so the rest of the system (and the client) sees one schema regardless of source.
- Manual courses get a generated `courseId` and `source: "manual"`; corrections are stored as `COURSE#<id>` correction items for later review/merge (do not silently overwrite provider data).
- **Compliance:** never expose a bulk export/dump of course data from our API (respect the no-redistribution terms). The client fetches courses one at a time for use in rounds.
