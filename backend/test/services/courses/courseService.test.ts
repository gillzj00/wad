import { describe, expect, it } from "vitest";
import type { CourseCache } from "../../../src/services/courses/cache.js";
import { CourseService, QueryTooShortError, SEARCH_TTL_SECONDS } from "../../../src/services/courses/courseService.js";
import { normalizeCourse, normalizeSummary } from "../../../src/services/courses/golfCourseApi.js";
import type { CourseProvider } from "../../../src/services/courses/provider.js";
import type { Course, CourseSummary } from "../../../src/shared/types.js";
import { gcaCourse } from "./fixtures.js";

const course = normalizeCourse(gcaCourse, new Date("2026-09-29T12:00:00Z"));
const summary = normalizeSummary(gcaCourse);

class MemoryCache implements CourseCache {
  courses = new Map<string, Course>();
  searches = new Map<string, { results: CourseSummary[]; ttl: number }>();
  async getCourse(id: string) {
    return this.courses.get(id) ?? null;
  }
  async putCourse(c: Course) {
    this.courses.set(c.courseId, c);
  }
  async createCourse(c: Course) {
    this.courses.set(c.courseId, c);
  }
  async putCorrection() {}
  async getSearch(q: string) {
    return this.searches.get(q)?.results ?? null;
  }
  async putSearch(q: string, results: CourseSummary[], ttl: number) {
    this.searches.set(q, { results, ttl });
  }
}

function fakeProvider() {
  const calls = { search: [] as string[], getCourse: [] as string[] };
  const provider: CourseProvider = {
    async search(q) {
      calls.search.push(q);
      return [summary];
    },
    async getCourse(id) {
      calls.getCourse.push(id);
      return id === course.courseId ? course : null;
    },
  };
  return { provider, calls };
}

describe("CourseService.search", () => {
  it("normalizes the query, calls the provider once, then serves from cache", async () => {
    const { provider, calls } = fakeProvider();
    const cache = new MemoryCache();
    const service = new CourseService(provider, cache);

    expect(await service.search("  Maple   HOLLOW ")).toEqual([summary]);
    expect(await service.search("maple hollow")).toEqual([summary]);
    expect(calls.search).toEqual(["maple hollow"]);
    expect(cache.searches.get("maple hollow")!.ttl).toBe(SEARCH_TTL_SECONDS);
  });

  it("rejects queries shorter than 3 characters without calling the provider", async () => {
    const { provider, calls } = fakeProvider();
    const service = new CourseService(provider, new MemoryCache());
    await expect(service.search(" ab ")).rejects.toBeInstanceOf(QueryTooShortError);
    expect(calls.search).toHaveLength(0);
  });
});

describe("CourseService.getCourse", () => {
  it("fetches once, then serves from cache", async () => {
    const { provider, calls } = fakeProvider();
    const service = new CourseService(provider, new MemoryCache());
    expect(await service.getCourse(course.courseId)).toEqual(course);
    expect(await service.getCourse(course.courseId)).toEqual(course);
    expect(calls.getCourse).toEqual([course.courseId]);
  });

  it("returns null and caches nothing for an unknown course", async () => {
    const { provider } = fakeProvider();
    const cache = new MemoryCache();
    expect(await new CourseService(provider, cache).getCourse("gca-zzzzzzzz")).toBeNull();
    expect(cache.courses.size).toBe(0);
  });
});
