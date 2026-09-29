import type { Course, CourseSummary } from "../../shared/types.js";
import type { CourseCache } from "./cache.js";
import type { CourseProvider } from "./provider.js";

export const MIN_QUERY_LENGTH = 3;
/** Search results are cached for a week; the provider's free tier allows only a few dozen requests a day. */
export const SEARCH_TTL_SECONDS = 7 * 24 * 60 * 60;

export class QueryTooShortError extends Error {
  constructor() {
    super(`search query must be at least ${MIN_QUERY_LENGTH} characters`);
    this.name = "QueryTooShortError";
  }
}

export function normalizeQuery(query: string): string {
  return query.trim().toLowerCase().replace(/\s+/g, " ");
}

export class CourseService {
  constructor(
    private readonly provider: CourseProvider,
    private readonly cache: CourseCache,
  ) {}

  async search(rawQuery: string): Promise<CourseSummary[]> {
    const query = normalizeQuery(rawQuery);
    if (query.length < MIN_QUERY_LENGTH) throw new QueryTooShortError();
    const cached = await this.cache.getSearch(query);
    if (cached) return cached;
    const results = await this.provider.search(query);
    await this.cache.putSearch(query, results, SEARCH_TTL_SECONDS);
    return results;
  }

  /** Course data is static, so a cached course is served without refetching. */
  async getCourse(courseId: string): Promise<Course | null> {
    const cached = await this.cache.getCourse(courseId);
    if (cached) return cached;
    const course = await this.provider.getCourse(courseId);
    if (course) await this.cache.putCourse(course);
    return course;
  }
}
