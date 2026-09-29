import { randomUUID } from "node:crypto";
import type { CourseCorrection, CourseCorrectionInput, ManualCourseInput, ManualTeeInput } from "../../shared/courseInput.js";
import type { Course, CourseSummary, Tee, UserId } from "../../shared/types.js";
import type { CourseCache } from "./cache.js";
import { slug } from "./golfCourseApi.js";
import type { CourseProvider } from "./provider.js";
import { ValidationError } from "./validation.js";

export const MIN_QUERY_LENGTH = 3;
/** Search results are cached for a week; the provider's free tier allows only a few dozen requests a day. */
export const SEARCH_TTL_SECONDS = 7 * 24 * 60 * 60;
/** Manual course ids never go to the provider, and provider ids never start with this. */
export const MANUAL_ID_PREFIX = "man-";

export class QueryTooShortError extends Error {
  constructor() {
    super(`search query must be at least ${MIN_QUERY_LENGTH} characters`);
    this.name = "QueryTooShortError";
  }
}

export class CourseNotFoundError extends Error {
  constructor(courseId: string) {
    super(`no course with id ${courseId}`);
    this.name = "CourseNotFoundError";
  }
}

export function normalizeQuery(query: string): string {
  return query.trim().toLowerCase().replace(/\s+/g, " ");
}

function isManualId(courseId: string): boolean {
  return courseId.startsWith(MANUAL_ID_PREFIX);
}

function manualTees(inputs: ManualTeeInput[]): Tee[] {
  const usedIds = new Set<string>();
  return inputs.map((input) => {
    const base = `${input.gender}-${slug(input.name)}`;
    let teeId = base;
    for (let n = 2; usedIds.has(teeId); n++) teeId = `${base}-${n}`;
    usedIds.add(teeId);
    const everyYardage = input.holes.every((h) => h.yardage !== null);
    return {
      teeId,
      name: input.name,
      gender: input.gender,
      courseRating: input.courseRating,
      slope: input.slope,
      par: input.holes.reduce((sum, h) => sum + h.par, 0),
      totalYards: everyYardage ? input.holes.reduce((sum, h) => sum + (h.yardage ?? 0), 0) : null,
      holes: input.holes,
      strokeIndexValid: true,
    };
  });
}

export class CourseService {
  constructor(
    private readonly provider: CourseProvider,
    private readonly cache: CourseCache,
    private readonly newId: () => string = randomUUID,
    private readonly now: () => Date = () => new Date(),
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
    if (isManualId(courseId)) return null;
    const course = await this.provider.getCourse(courseId);
    if (!course || course.source === "manual" || isManualId(course.courseId)) return null;
    await this.cache.putCourse(course);
    return course;
  }

  async createManualCourse(input: ManualCourseInput, createdBy: UserId): Promise<Course> {
    const course: Course = {
      courseId: `${MANUAL_ID_PREFIX}${this.newId()}`,
      clubName: input.clubName,
      courseName: input.courseName,
      location: input.location,
      source: "manual",
      scorecardUrl: null,
      tees: manualTees(input.tees),
      fetchedAt: this.now().toISOString(),
    };
    await this.cache.createCourse(course, createdBy);
    return course;
  }

  /**
   * Stores the correction as a pending suggestion; the course itself is not changed.
   * Only looks at stored courses, so it never spends provider quota.
   */
  async submitCorrection(courseId: string, input: CourseCorrectionInput, submittedBy: UserId): Promise<CourseCorrection> {
    const course = await this.cache.getCourse(courseId);
    if (!course) throw new CourseNotFoundError(courseId);
    if (input.teeId !== null && !course.tees.some((t) => t.teeId === input.teeId)) {
      throw new ValidationError("teeId", "does not match a tee on this course");
    }
    const correction: CourseCorrection = {
      ...input,
      correctionId: this.newId(),
      courseId,
      status: "pending",
      submittedBy,
      submittedAt: this.now().toISOString(),
    };
    await this.cache.putCorrection(correction);
    return correction;
  }
}
