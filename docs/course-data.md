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

- The provider sits behind a `CourseProvider` interface (`search(query)`, `getCourse(id)`) in `backend/src/services/courses/`, so switching or adding providers is isolated. The API key is an SSM SecureString at `/wad/<env>/golfcourseapi/key`, read by the Lambda at cold start; never in the repo.
- On `getCourse`, **write-through cache** the normalized course into DynamoDB (`COURSE#<id>`) and serve later reads from cache. Search results are cached too (`COURSESEARCH#<query>`, 7 days), because the free tier allows only about 35 requests a day; queries shorter than 3 characters are rejected.
- Provider payloads are normalized at the adapter into our own `Course` type (`backend/src/shared/types.ts`), so the rest of the system sees one schema regardless of source. Our ids are `gca-<provider id>` so another source can be added without collisions.

### GolfCourseAPI specifics (verified against the live API, 2026-09-29)

- Auth: `Authorization: Bearer <key>`. Endpoints: `GET /v1/search?search_query=`, `GET /v1/courses/{id}`. Ids are 8-character lowercase strings.
- The published spec shows `GET /v1/courses/{id}` returning the course unwrapped; the live API wraps it as `{ "course": ... }`. The adapter accepts both.
- Tees are grouped into `male` and `female`, and **each tee has its own holes**: pars and stroke indexes (`handicap`) can differ between tees, even within a gender. A round must therefore pin one tee and use that tee's pars and stroke indexes.
- Search results carry only tee counts, so showing a scorecard always needs a course fetch.
- Responses carry no rate-limit headers; a `429` maps to `503 course_provider_rate_limited` for our clients.
- Manual courses get a generated `courseId` and `source: "manual"`; corrections are stored as `COURSE#<id>` correction items for later review/merge (do not silently overwrite provider data).
- **Compliance:** never expose a bulk export/dump of course data from our API (respect the no-redistribution terms). The client fetches courses one at a time for use in rounds.
