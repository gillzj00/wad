// Adapter for GolfCourseAPI (https://api.golfcourseapi.com/docs/api/).
// Normalizes its responses into our Course shape. Its terms allow caching for
// use inside the app but not redistributing the data, so never expose a bulk
// export of what is fetched here.
import type { Course, CourseHole, CourseLocation, CourseSummary, Tee, TeeGender } from "../../shared/types.js";
import { type CourseProvider, ProviderError } from "./provider.js";

const BASE_URL = "https://api.golfcourseapi.com/v1";
const ID_PREFIX = "gca-";
const PROVIDER_ID = /^[0-9abcdefghjkmnpqrstvwxyz]{8}$/;

interface GcaLocation {
  address?: string;
  city?: string;
  state?: string;
  country?: string;
  latitude?: number;
  longitude?: number;
}

interface GcaHole {
  par?: number;
  yardage?: number;
  handicap?: number;
}

interface GcaTee {
  tee_name?: string;
  course_rating?: number;
  slope_rating?: number;
  total_yards?: number;
  par_total?: number;
  holes?: GcaHole[];
}

export interface GcaCourse {
  id: string;
  club_name?: string;
  course_name?: string;
  scorecard_url?: string;
  location?: GcaLocation;
  tees?: Partial<Record<TeeGender, GcaTee[]>>;
}

type Fetch = typeof fetch;

export class GolfCourseApiProvider implements CourseProvider {
  constructor(
    private readonly apiKey: () => Promise<string>,
    private readonly fetchFn: Fetch = fetch,
    private readonly now: () => Date = () => new Date(),
  ) {}

  async search(query: string): Promise<CourseSummary[]> {
    const body = await this.get(`/search?search_query=${encodeURIComponent(query)}`);
    const courses = (body as { courses?: GcaCourse[] } | null)?.courses ?? [];
    return courses.map(normalizeSummary);
  }

  async getCourse(courseId: string): Promise<Course | null> {
    if (!courseId.startsWith(ID_PREFIX)) return null;
    const providerId = courseId.slice(ID_PREFIX.length);
    if (!PROVIDER_ID.test(providerId)) return null;
    const body = await this.get(`/courses/${providerId}`);
    if (body === null) return null;
    // The published spec shows the course unwrapped; the live API wraps it in { course }.
    const raw = ((body as { course?: GcaCourse }).course ?? body) as GcaCourse;
    return normalizeCourse(raw, this.now());
  }

  private async get(path: string): Promise<unknown> {
    let res: Response;
    try {
      res = await this.fetchFn(`${BASE_URL}${path}`, {
        headers: { Authorization: `Bearer ${await this.apiKey()}`, Accept: "application/json" },
        signal: AbortSignal.timeout(8000),
      });
    } catch (err) {
      throw new ProviderError("unavailable", `course provider request failed: ${String(err)}`);
    }
    if (res.status === 404) return null;
    if (res.status === 429) throw new ProviderError("rate_limited", "course provider rate limit reached");
    if (res.status === 401 || res.status === 403) throw new ProviderError("unauthorized", `course provider rejected the API key (${res.status})`);
    if (!res.ok) throw new ProviderError("unavailable", `course provider returned ${res.status}`);
    return res.json();
  }
}

export function normalizeSummary(raw: GcaCourse): CourseSummary {
  return {
    courseId: `${ID_PREFIX}${raw.id}`,
    clubName: raw.club_name ?? "",
    courseName: raw.course_name ?? raw.club_name ?? "",
    location: normalizeLocation(raw.location),
  };
}

export function normalizeCourse(raw: GcaCourse, fetchedAt: Date): Course {
  const tees: Tee[] = [];
  const usedIds = new Set<string>();
  for (const gender of ["male", "female"] as const) {
    for (const t of raw.tees?.[gender] ?? []) {
      const tee = normalizeTee(t, gender);
      let id = tee.teeId;
      for (let n = 2; usedIds.has(id); n++) id = `${tee.teeId}-${n}`;
      usedIds.add(id);
      tees.push({ ...tee, teeId: id });
    }
  }
  return {
    ...normalizeSummary(raw),
    source: "golfcourseapi",
    scorecardUrl: raw.scorecard_url ?? null,
    tees,
    fetchedAt: fetchedAt.toISOString(),
  };
}

function normalizeTee(raw: GcaTee, gender: TeeGender): Tee {
  const name = raw.tee_name?.trim() || "Unnamed";
  const holes: CourseHole[] = (raw.holes ?? []).map((h, i) => ({
    hole: i + 1,
    par: h.par ?? 0,
    strokeIndex: typeof h.handicap === "number" && h.handicap > 0 ? h.handicap : null,
    yardage: h.yardage ?? null,
  }));
  const indexes = holes.map((h) => h.strokeIndex);
  const strokeIndexValid =
    holes.length > 0 && indexes.every((si) => si !== null) && new Set(indexes).size === holes.length && holes.every((h) => h.par > 0);
  return {
    teeId: `${gender}-${slug(name)}`,
    name,
    gender,
    courseRating: raw.course_rating ?? null,
    slope: raw.slope_rating ?? null,
    par: raw.par_total ?? holes.reduce((sum, h) => sum + h.par, 0),
    totalYards: raw.total_yards ?? null,
    holes,
    strokeIndexValid,
  };
}

function normalizeLocation(raw: GcaLocation | undefined): CourseLocation {
  return {
    address: raw?.address ?? null,
    city: raw?.city ?? null,
    state: raw?.state ?? null,
    country: raw?.country ?? null,
    latitude: raw?.latitude ?? null,
    longitude: raw?.longitude ?? null,
  };
}

function slug(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "tee";
}
