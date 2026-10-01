# Geolocation research: course suggestion and hole detection

Status: research only. Nothing here is decided. Section 8 lists the decisions the owner (@gillzj00) has to make before any of it is built. Facts checked against a live source on 2026-09-29 are stated as facts; anything else is marked **(unverified)**.

## 1. Summary

- **Course suggestion is cheap and can be built with data we already have.** GolfCourseAPI returns `location.latitude` / `location.longitude` on both search and course responses (spec version 1.1.0, 2026-09-13), and our `CourseLocation` type already carries them. The provider has **no search by location**; its only search parameter is `search_query` (name). So the nearest-course ranking has to be done by us, over courses we have cached, and the first-ever visit to a course still needs a name search. Effort: S on device, S in the API.
- **Hole detection needs per-hole geometry that the provider does not have.** The realistic sources are OpenStreetMap (free, ODbL, patchy coverage but good where mapped: Oak Glen's 18 championship holes are fully mapped with `ref`, `par` and `handicap`), commercial GPS datasets (iGolf, GolfLogix, Golf Intelligence; roughly $400 to $5,000+ per month or year and negotiated contracts), and geometry we learn ourselves from where players score each hole.
- **Phone GPS is good enough to tell holes apart** (2 to 5 m in the open, worse under trees), but not good enough to be trusted blindly: parallel holes, shared tee complexes, shotgun starts and the clubhouse all produce wrong answers. The product rule should be **suggest, never assume**: a dismissable "You seem to be on hole 8" that the player confirms, never an auto-advance, because money is attached to the hole a score lands on.
- **The licence caveat that matters most:** OSM data is ODbL. Keeping OSM hole geometry as its own data type, keyed to our course id, is a Collective Database and does not pull the provider's scorecard data into share-alike. Merging OSM coordinates into the provider's hole records (or "correcting" one with the other) would create a Derivative Database that we would have to offer under ODbL on request, and the provider forbids redistributing its data. Keep the two in separate items and never mix them at the feature level.
- **Recommended plan:** phase 1 nearest-course suggestion from cached coordinates; phase 2 hole hints from OSM where mapped, with attribution; phase 3 learned tee/green estimates from scoring locations, with consent. Details in section 7.

## 2. Course suggestion

### 2.1 What the data allows

| Question | Answer | Source |
| --- | --- | --- |
| Does the provider give course coordinates? | Yes. `location.latitude` and `location.longitude` (decimal degrees) on `GET /v1/search` and `GET /v1/courses/{id}`, omitted for a few courses. | GolfCourseAPI OpenAPI spec 1.2.0, changelog 1.1.0 |
| Does the provider search by location? | No. `/v1/search` takes only `search_query` and `fuzzy_match`. There is no radius, bbox or nearby endpoint. | Same spec, `paths` |
| Do we store coordinates already? | Yes. `CourseLocation.latitude/longitude` in `backend/src/shared/types.ts`, populated by `golfCourseApi.ts` `normalizeLocation`. Manual courses accept them optionally. | Repo |
| Is a 36-hole facility one course or two in the provider? | **(unverified)** No API key is available in this environment. BlueGolf and Hole19 both list "Oak Glen Golf Course - Championship" and "Oak Glen ... Executive 9" as separate entries, so it is likely the provider also has two entries with the same or nearly the same coordinates. Check with a real key before relying on it. | BlueGolf, Hole19 course pages |

Because the provider cannot answer "what is near me", a nearest-course query can only rank courses **we have already cached** (`COURSE#` items) or courses returned by a name search the user typed. That is fine for the target use: a group plays the same handful of courses, and the suggestion is most valuable on the second visit and later.

### 2.2 Design

1. On the Course step of round setup (`ios/Wad/Setup/RoundSetupView.swift`, `CourseStepView`), when the user has not typed anything yet, ask for **When In Use** location once, in context, with a short explanation.
2. Rank candidate courses by great-circle distance from the fix (haversine is plenty; the earth-shape error is centimetres at these distances). Candidates are the courses cached on the device (SwiftData) first, then, if online, the API's ranked list.
3. Show at most three suggestions with their distance, as a prompt above the search field: "It looks like you are at Oak Glen. Start a round there?" Tapping fills the course; the user still picks the tee.
4. Several courses within about 1 mile (1.6 km): show them all, nearest first, with club and course names and hole count, and do not preselect. Provider coordinates are a single point per course (often the clubhouse or the address geocode), so two courses of one facility can be 0 m apart; only the name distinguishes them.
5. Offline: rank cached courses only. If nothing cached is within 5 km, show nothing (no suggestion is better than a wrong one).

### 2.3 On device vs in the API

| Where | How | Pros | Cons |
| --- | --- | --- | --- |
| Device only (phase 1) | Haversine over the SwiftData course cache | Works offline, no new endpoint, no location leaves the phone | Only courses this phone has seen |
| API (`GET /courses?near=<lat>,<lng>&radius=<km>`) | Scan or GSI over cached `COURSE#` items; DynamoDB has no geo index, so either a full scan (fine at a few thousand items) or a geohash prefix key on a new GSI | All users benefit from each other's cache | Sends location to our backend (privacy manifest must say so); needs a GSI or scan; still cannot discover a course nobody has fetched |

Recommendation: device-only first. Add the API version only when the shared cache is large enough that it finds courses the phone has not seen. Never send raw location in a query string per the privacy rules; if built, put it in a POST body over TLS and do not log it.

### 2.4 Effort

| Step | Size |
| --- | --- |
| Location permission, usage string, privacy manifest entry | S |
| Haversine ranking over the local course cache and the suggestion prompt in `CourseStepView` (depends on M2.4 course search existing on iOS) | S |
| Optional API nearest query with geohash GSI | M |

## 3. Hole detection: data sources

### 3.1 OpenStreetMap

**Tagging scheme (OSM wiki):** a course is `leisure=golf_course` (one area or multipolygon per course; a facility with several courses maps each as its own `leisure=golf_course` with `golf:course=18_hole` / `9_hole` and `golf:course:name`). Inside it: `golf=tee` (area, `ref=<hole>` recommended, `tee=<colour>`), `golf=fairway`, `golf=green` (area), `golf=pin` (node), `golf=bunker`, `golf=hole` (a **way drawn from tee to green along the playing line**, with `ref=<hole number>`, `par`, `handicap` = stroke index, one node fewer than par), `golf=driving_range`, `golf=clubhouse`, `golf=cartpath`. The `golf=hole` way's first node is on the tee side, which gives a usable tee point and a direction of play even where tees lack `ref`.

**Oak Glen, Stillwater MN (checked via Overpass on 2026-09-29):**

- One `leisure=golf_course` multipolygon relation, id 20344653, `name=Oak Glen Golf Course`, `golf:course=18_hole`, `golf:par=72`, with address, phone and website. Centre 45.0702, -92.8341.
- Inside it: **18 `golf=hole` ways, every one with `ref` 1 to 18, `par` and `handicap`**; 30 `golf=tee` areas (none with `ref`); 19 `golf=green` areas (18 plus a practice green); 4 `golf=driving_range`; 1 `golf=clubhouse`. Pins, bunkers, fairways and cart paths are also mapped.
- Data quality: `handicap=7` is tagged on both hole 17 and hole 18, so OSM stroke indexes cannot be trusted as a scorecard source. The scorecard stays with the provider; OSM is geometry only.
- The **9-hole executive course is not mapped**: no second `leisure=golf_course`, and no `golf=hole` ways beyond the 18. A geometry-based detector would only work on the championship course there.
- The neighbouring Stillwater Country Club (about 1.5 km east) is mapped as a separate `leisure=golf_course` way with its own 18 `golf=hole` ways and `ref`s, which is a real-world example of the "several courses nearby" case for course suggestion.

**Coverage elsewhere:** **(unverified)** OSM golf mapping is uneven. Well-known and metro-area courses are often fully mapped; rural nine-holers frequently have only the outline. Treat OSM as a source that works for some courses and design the feature to degrade to "no hint" without it.

**Licence: ODbL 1.0.** Practical consequences for Wad:

- **Attribution** is required wherever the data is used, including a non-map feature. Put "Hole hints use data from OpenStreetMap, ODbL" with a link to openstreetmap.org/copyright in an About or Data licences screen, and a one-line credit near the hint the first time it appears (OSMF Attribution Guidelines).
- **Share-alike** applies to Derivative Databases that are Publicly Used, which includes serving data to app users. A cached copy of OSM golf features per course, unchanged apart from format, is a Derivative Database; we must be willing to hand a copy (or the extraction method) to anyone who asks. That is harmless for OSM-only data.
- **The trap is mixing.** Under the Collective Database Guideline, OSM and non-OSM data in one database stay independent as long as each data type is all-OSM or all-non-OSM per region and they are only linked by references (a database key is explicitly allowed). Attaching OSM tee/green coordinates onto the provider's `CourseHole` records, or using OSM par to correct provider par, would turn the provider's scorecard data into part of a Derivative Database that ODbL says we must offer on request, while GolfCourseAPI's terms forbid redistributing its dataset. So: geometry lives in its own item type, referenced by `courseId`, and never enriches or is enriched by provider fields.
- Learned geometry (section 3.4) must likewise be kept as its own data type if OSM geometry was used to seed or correct it; otherwise it too becomes a Derivative Database. Simplest rule: **learned estimates are computed only from player locations, never from OSM**, so they are ours.

**Getting the data: Overpass API.** The public instance `overpass-api.de` is explicitly for light use: the wiki policy states roughly 10,000 queries and 1 GB per day for a person, divided by 100 for an application, identifying `User-Agent` required, no parallel queries, pause 30 s on 429/406, and commercial use should be self-hosted or paid. During this research the main instance returned 504 "server too busy" on three of five attempts, and `overpass.kumi.systems` returned nothing. It is not suitable as a runtime dependency for the app. Two viable patterns:

1. **Backend fetch-and-cache on first use**, a few queries per new course, retried with backoff, stored in DynamoDB. Query shape: `rel(<course id>); map_to_area; way["golf"~"^(hole|tee|green)$"](area)`, or a bbox around the provider's coordinates when the course area is not found. Well under the "application" budget for our scale.
2. **Self-hosted Overpass** (Docker image `wiktorn/overpass-api`, a state or region extract, 4 GB RAM) or a paid instance, if usage grows. Not worth it until it does.

Course matching between OSM and the provider is by name similarity plus distance from the provider coordinate, with the result stored and correctable by hand.

### 3.2 Commercial course GPS data

| Provider | What it has | Access and price | Notes |
| --- | --- | --- | --- |
| iGolf (iGolf Connect API) | Tee box centres, front/centre/back green points, up to four custom points per hole, fairway/green/hazard perimeters, centreline, elevation; about 40,000 courses | Partner contract; per-transaction or unlimited; **"starts for as little as $5,000 annually"** per their site | The industry default for GPS devices and apps |
| GolfLogix Map Server | Front/centre/back green, tee boxes, hazards, layup points, scorecard, 3D terrain; about 40,000 courses | API, subscription or per request; contact bizdev, no public prices | Consumer-app competitor licensing its maps |
| Golf Intelligence | Scorecard, GPS data, green slope and elevation images; claims every hole worldwide | Published tiers: Tester $49/mo (personal only), Starter $399/mo 10k credits, Basic $999/mo, up to Unlimited $15,000/mo; GPS data costs 2 credits per fetch, cacheable up to one year **per golfer** | Powers Garmin, 18Birdies, Golfshot, SwingU per their site; credits are per golfer not per course, which suits a small group |
| Arccos On-Course Data API | Player shot data from Arccos users, not course maps | Licence agreement | Not a course-geometry source |
| Hole19, SwingU, Golfshot | Consumer apps; no public developer data licensing found | n/a | **(unverified)** that no private licensing exists |
| Apple MapKit | Golf course POIs (`MKPointOfInterestCategory.golf`, searchable with `MKLocalPointsOfInterestRequest`), map tiles, no hole geometry | Free with the platform; Apple attribution built in | Useful for a map behind the suggestion and as a second source of candidate courses near the user; not licensed for building a stored database from search results (Apple Maps terms, **unverified** wording) |

For a friends-and-family app with a $10/month course-data budget, only Golf Intelligence's Starter tier is even in range, and $399/month is far above the project's cost posture. Commercial data is the right answer if Wad ever becomes a product with revenue; it is not the right answer for phase 2.

### 3.3 Apple MapKit

No hole data. Worth using for two things: rendering a map with the course suggestion (and later the hint), and `MKLocalSearch` with the golf POI category as a fallback candidate list when nothing is cached nearby. Note that Apple's search results carry their own terms; use them for display and matching, not to populate our course cache.

### 3.4 Learn-as-you-play

The app already knows when a score is entered for hole N. If, at that moment, it records the phone's location (with horizontal accuracy), then over a handful of rounds each course accumulates clusters of "hole N was scored here" points. Scoring usually happens on or beside the green, or at the next tee, so each cluster is a noisy estimate of the green-to-next-tee area of hole N.

- **Accuracy:** with a 2 to 5 m fix and clusters 100 m or more apart, three to five rounds on a course are enough for a robust median per hole. Clusters from players who score several holes at once, or at the turn, are outliers and need trimming (drop points whose timestamp is within 20 s of another score by the same player, use the median not the mean).
- **What it cannot do:** it never learns the tee of hole 1 or the direction of play, and it learns nothing until the course has been played.
- **Privacy:** these are fine-grained location traces linked to a user and a time. Store per-course, per-hole aggregates only (median point, count, spread), never raw traces, and compute them on device or in a job that discards the raw points. Ask for consent separately from the location permission ("Help Wad learn this course's layout"). The privacy manifest must then declare precise location as collected and linked to identity if any of it reaches the backend.
- **Licence:** entirely ours, as long as OSM data is not used to seed or correct it.

## 4. Detection approaches and expected reliability

Inputs: a location fix (typically 2 to 5 m horizontal accuracy in the open per the smartphone GNSS studies cited below, 5 m or worse under tree canopy, tens of metres if only Wi-Fi or cell is available), heading and speed when moving, the round's current hole and which holes are scored, and whatever geometry the course has.

| Approach | Needs | How it works | Fails on | Reliability (judgment) |
| --- | --- | --- | --- | --- |
| Nearest tee | Tee points (OSM tee areas or `golf=hole` first node; learned next-tee clusters) | Distance from the fix to each hole's tee; suggest the nearest if within about 40 m and clearly nearer than the runner-up | Shared tee complexes (two holes' tees within 30 m are common), walking past a tee, the range and putting green | Good at the tee, meaningless mid-hole |
| Point in polygon | Full hole geometry (fairway, green, rough polygons) | Test which hole's polygons contain the fix | Parallel holes with shared rough, cart paths between holes, unmapped rough | Best mid-hole where mapped; OSM often lacks fairway polygons |
| Nearest hole line | `golf=hole` ways | Perpendicular distance from the fix to each hole's centreline, weighted by along-line position | Adjacent parallel holes whose lines are 50 m apart, doglegs | Good; this is what the OSM hole way is for, and Oak Glen has all 18 |
| Sequence prior | Nothing beyond the round | After scoring N the prior is N+1; then N and N+2; a hint is only shown when geometry agrees with the prior or beats it by a wide margin | Shotgun starts (prior wraps 18 to 1), back-nine starts (prior starts at 10), skipped holes | Strong tie-breaker; removes most parallel-hole errors |
| Dwell time | Location stream | Only consider a hole once the player has been within its area for 60 s or more; ignore fixes while moving faster than about 4 m/s (cart between holes) | Slow play near a boundary; carts parked beside the wrong green | Removes flicker between adjacent holes |
| Heading and direction | Course of travel from Core Location, hole way direction | On a mapped hole way, movement roughly along the tee-to-green direction supports that hole; movement against it supports the neighbouring hole played the other way | Walking back to a cart or a lost ball | Useful only for parallel holes played in opposite directions, which is exactly where the others fail |
| Learned clusters | Section 3.4 | Nearest cluster centre, gated by the sequence prior | Anything not yet played on this course | Improves with use; complements OSM |

Combining them: score each hole as `w1 * geometry_match + w2 * sequence_prior + w3 * dwell`, show a hint only when the best hole beats the second best by a clear margin and differs from the hole the screen is on, and never show a hint for a hole that is already scored by this player. Special cases:

- **Shotgun and back-nine starts:** let the round record a starting hole (a setup option), and let the prior wrap around 18. A first hint on a hole other than 1 when nothing is scored yet is shown as "Starting on 10?" rather than assumed.
- **Clubhouse, range, putting green, car park:** treat OSM `golf=clubhouse` and `golf=driving_range` areas, and anything more than 60 m from every hole, as "off course"; show no hint and pause updates after a few minutes stationary there.
- **Cart vs walking:** fixes in a moving cart are fine (GPS does not care) but the player is between holes; the speed gate handles it. Carts also spend time on paths that run between two holes, which is why dwell matters.
- **Battery:** the standard location service at `kCLLocationAccuracyBest` is the most expensive configuration and is meant for a plugged-in device. For hole hints, `kCLLocationAccuracyNearestTenMeters` with a 10 to 15 m `distanceFilter` is enough (holes are 100 m or more apart) and much cheaper; `CLLocationUpdate.liveUpdates` (iOS 17) pauses automatically when the phone is stationary. Significant-change updates are the wrong tool: they fire on about 500 m moves using cell and Wi-Fi, which is coarser than a hole. A 4 to 5 hour round with updates only while the app is in the foreground costs a few percent of battery; continuous background updates cost substantially more and show the blue status indicator. **(unverified)** exact percentages; measure on a real round.

What to expect overall: with OSM hole ways, the sequence prior and dwell, a correct hint on most tees and greens and a suppressed hint (no suggestion) in the ambiguous cases. A wrong hint that the player must read and dismiss is the failure mode to design against, not the missing hint.

## 5. Privacy, permissions and battery

- **Authorization level:** When In Use is sufficient for everything in this document. The app is in the foreground while scoring, and iOS keeps delivering updates to a When In Use app in the background if `UIBackgroundModes` includes `location` and `allowsBackgroundLocationUpdates` is set (with the blue indicator). Always authorization is only needed for the system to launch the app on region events; the "it looks like you are at Oak Glen" nudge as a notification when the app is closed would need it (geofences via `CLMonitor`, limited to 20 conditions and a practical minimum radius near 100 m). Recommendation: do not ask for Always; the suggestion appears when the user opens the app.
- **Reduced accuracy:** users can grant approximate location (roughly 1 to 20 km). That is enough for course suggestion in most towns but not for 36-hole facilities or for any hole hint. Use `requestTemporaryFullAccuracyAuthorization(withPurposeKey:)` with an `NSLocationTemporaryUsageDescriptionDictionary` entry only when the user starts a round with hints on.
- **Info.plist:** `NSLocationWhenInUseUsageDescription` (required; App Store rejects a location request without it), the temporary-accuracy dictionary above, and `UIBackgroundModes: location` only if background hints are wanted. These go in `ios/project.yml` (the project is generated by XcodeGen).
- **Privacy manifest:** the repo has no `PrivacyInfo.xcprivacy` yet. Location is not a "required reason" API, but as soon as location is collected the manifest's `NSPrivacyCollectedDataTypes` must list `NSPrivacyCollectedDataTypePreciseLocation` (or `CoarseLocation`) with `NSPrivacyCollectedDataTypeLinked`, `NSPrivacyCollectedDataTypeTracking` (false) and purposes (`NSPrivacyCollectedDataTypePurposeAppFunctionality`). If location never leaves the device (phase 1 and OSM-only phase 2), it is not "collected" in App Store terms and the App Privacy label need not list it; phase 3 or an API nearest query changes that. **(unverified)** interpretation of "collected" for on-device-only use; check the App Store privacy details definitions before submission.
- **Data minimisation:** never put coordinates in URL query strings; never log fixes; store aggregates not traces; make hints an opt-in toggle in the round.
- **Multi-device (M3.3):** each phone detects for its own player. Do not broadcast location over the round WebSocket; broadcast nothing until a player has actually scored. A later refinement is a group hint ("Zach and Sam scored 8; you are on 8?") derived from other players' scores, which needs no location sharing at all and is probably the better signal.

## 6. Fit with the project

| Area | Change | Size |
| --- | --- | --- |
| Data model | New item `COURSE#<courseId>` / `GEOMETRY#<source>` holding per-hole geometry: for `osm`, the hole ways (as coordinate lists), tee and green centroids, the OSM element ids, the OSM timestamp, and `licence: "ODbL-1.0"`, `attribution`; for `learned`, per-hole median point, count and spread. One item per source so provider and OSM data are never merged (section 3.1). Needs a note in `docs/data-model.md`; no new table. | S |
| API | `GET /courses/{courseId}/geometry` returning the OSM item (and its attribution string) if present, else 404; a backend job or lazy fetch that populates it via Overpass with backoff. Optionally `POST /courses/{courseId}/geometry/observations` for phase 3 aggregates. | M |
| iOS: setup | Location permission flow, haversine ranking, suggestion prompt in `CourseStepView`; depends on the course search screen (M2.4). | S |
| iOS: scoring | A `HoleLocator` that consumes `CLLocationUpdate.liveUpdates`, holds the current geometry, and publishes a `suggestedHole`; `HoleScoringView` shows a dismissable banner with "Go to hole 8" that only changes `holeNumber` when tapped. A `startingHole` on the round for shotgun and back-nine starts. | M |
| iOS: learning | Record a location sample on each score save in `RoundScorer`, aggregate per course on device, sync aggregates. Opt-in toggle. | M |
| Permissions and manifest | Usage strings in `project.yml`; add `PrivacyInfo.xcprivacy`. | S |
| Attribution | Data licences screen listing GolfCourseAPI and OpenStreetMap (ODbL). | S |
| Cost | Overpass: free at our volume, but unreliable; self-hosting is a small EC2 or container and not worth it yet. DynamoDB: negligible. Commercial data: $400 per month and up, out of scope. | n/a |

## 7. Recommended phased plan

**Phase 1: nearest-course suggestion (S).** When In Use permission asked on the Course step, haversine over the local course cache, top three within 5 km shown as a prompt, all shown when several are within a mile, nothing assumed. Manual courses get a "use my location" button that fills in `latitude/longitude` so they participate too. No backend change.

**Phase 2: hole hints from OSM where mapped (M).** Backend fetches and caches OSM golf features per course on demand, stored as a separate item with licence and provenance; client downloads them with the course. Locator combines the nearest-hole-line score, the sequence prior and dwell; shows a banner, never auto-advances. Attribution screen. Courses without OSM holes simply show no hints.

**Phase 3: learned geometry (M).** Opt-in recording of the scoring location, per-course per-hole aggregates, used as a second geometry source for courses OSM does not cover and to improve tee-side estimates. Kept independent of OSM data.

**Later, if the app grows:** an API nearest-course query over the shared cache, and a commercial GPS dataset if revenue justifies it.

## 8. Decisions for the owner

1. Is course suggestion worth a location permission prompt at all, given that groups usually play the same few courses? (The recommendation is yes, as phase 1 is small.)
2. Hole hints: banner that the player taps, or a stronger nudge such as a haptic when the suggested hole changes? Auto-advance is not recommended.
3. Accept OSM as a data source with ODbL attribution in the app and a commitment to keep it separate from provider data? (Required for phase 2.)
4. Should Overpass be called from our backend (recommended, cached, with backoff) or should a self-hosted instance be budgeted from the start?
5. Phase 3 consent model: a per-user toggle, a per-round toggle, or off entirely? And do aggregates sync to the backend or stay on the device?
6. Should the round record a starting hole (needed for shotgun and back-nine starts, and useful regardless of geolocation)?
7. Verify with a real API key whether GolfCourseAPI lists Oak Glen's championship and executive courses separately, and whether both carry coordinates.
8. Confirm with the provider's terms that a nearest-course ranking over our cached coordinates is "internal use" (it exposes no bulk data; only names and distances of a few courses).

## 9. Sources

Opened and read on 2026-09-29 unless noted.

Provider and repo
- GolfCourseAPI OpenAPI spec (changelog 1.1.0 adds coordinates; `/v1/search` parameters): https://api.golfcourseapi.com/docs/api/openapi.yml
- GolfCourseAPI pricing page: https://golfcourseapi.com
- `backend/src/shared/types.ts`, `backend/src/services/courses/golfCourseApi.ts`, `docs/course-data.md`, `docs/adr/0008-course-data-source.md`

OpenStreetMap
- Golf course tagging overview: https://wiki.openstreetmap.org/wiki/Tag:leisure%3Dgolf_course
- `golf=hole` (way from tee to green, `ref`, `par`, `handicap`): https://wiki.openstreetmap.org/wiki/Tag:golf%3Dhole
- `golf=tee` (`ref` for hole number, `tee` for colour): https://wiki.openstreetmap.org/wiki/Tag:golf%3Dtee
- `golf:course` key (`18_hole`, `9_hole`, several courses per facility): https://wiki.openstreetmap.org/wiki/Key:golf:course
- Overpass API and usage policy: https://wiki.openstreetmap.org/wiki/Overpass_API
- Overpass queries run against https://overpass-api.de/api/interpreter for Oak Glen relation 20344653 (results summarised in section 3.1)
- Self-hosted Overpass Docker image: https://github.com/wiktorn/Overpass-API
- ODbL Produced Work guideline: https://osmfoundation.org/wiki/Licence/Community_Guidelines/Produced_Work_-_Guideline
- Collective Database guideline: https://osmfoundation.org/wiki/Licence/Community_Guidelines/Collective_Database_Guideline_Guideline and https://wiki.openstreetmap.org/wiki/Collective_Database_Guideline
- Attribution guidelines: https://osmfoundation.org/wiki/Licence/Attribution_Guidelines
- Licence and legal FAQ (Publicly Use, what must be offered): https://osmfoundation.org/wiki/Licence/Licence_and_Legal_FAQ

Commercial data
- iGolf course data: https://igolf.com/solutions/golf-course-data/ and https://igolf.com/developers-igolf/ (via search summary; the "$5,000 annually" figure is from their developer page as summarised, **unverified** directly)
- GolfLogix map licensing: https://www.golflogix.com/page/map-licensing-inquiries/
- Golf Intelligence pricing and caching terms: https://golfintelligence.com/api-pricing/
- Arccos On-Course Data API licence agreement (draft PDF, via search): https://cdn.arccosgolf.com/documents/on_course_data_api/draft-arccos_api_license_agreement-2023_03_09.pdf

Oak Glen
- Hole19 executive course page (9 holes, par 29): https://www.hole19golf.com/courses/oak-glen-golf-course-executive
- BlueGolf course profiles (championship and executive listed separately, via search): https://course.bluegolf.com/bluegolf/course/course/oakglengcmn/index.htm and https://course.bluegolf.com/bluegolf/course/course/oakglen/index.htm
- Explore Minnesota profile (27 holes, via search): https://www.exploreminnesota.com/profile/oak-glen-golf-course/5385

Apple platform
- Requesting authorization: https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services (page did not render for the fetch tool; key names confirmed via the privacy manifest and temporary accuracy pages, **partly unverified**)
- Temporary full accuracy: https://developer.apple.com/documentation/corelocation/cllocationmanager/requesttemporaryfullaccuracyauthorization(withpurposekey:completion:)
- Privacy manifest collected data types: https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes
- Background location updates: https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background
- Energy guide, reduce location accuracy and duration: https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/LocationBestPractices.html
- WWDC23 Discover streamlined location updates (`CLLocationUpdate.liveUpdates`, stationary pausing): https://developer.apple.com/videos/play/wwdc2023/10180/
- CLMonitor condition limits (20) and minimum practical radius, Apple forums: https://developer.apple.com/forums/thread/731294
- MapKit golf POI category: https://developer.apple.com/documentation/mapkit/mkpointofinterestcategory and https://developer.apple.com/documentation/mapkit/mklocalpointsofinterestrequest
- Significant-change vs standard service energy (third-party measurement): https://medium.com/@emillz/location-services-and-battery-life-a274f893f04b

GPS accuracy
- Smartphone GNSS accuracy under canopy (MDPI Forests 2022): https://doi.org/10.3390/f13101591
- Smartphone vs specialist GNSS receivers, open sky medians (Ecological Solutions and Evidence): https://besjournals.onlinelibrary.wiley.com/doi/full/10.1002/2688-8319.70015
