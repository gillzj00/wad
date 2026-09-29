import { describe, expect, it } from "vitest";
import { GolfCourseApiProvider, normalizeCourse } from "../../../src/services/courses/golfCourseApi.js";
import { ProviderError } from "../../../src/services/courses/provider.js";
import { gcaCourse, gcaSearch } from "./fixtures.js";

const NOW = new Date("2026-09-29T12:00:00Z");

function fakeFetch(status: number, body: unknown) {
  const calls: { url: string; headers: Record<string, string> }[] = [];
  const fetchFn = (async (url: string, init?: RequestInit) => {
    calls.push({ url, headers: init?.headers as Record<string, string> });
    return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
  }) as typeof fetch;
  return { fetchFn, calls };
}

const provider = (fetchFn: typeof fetch) => new GolfCourseApiProvider(async () => "test-key", fetchFn, () => NOW);

describe("GolfCourseApiProvider", () => {
  it("searches with a bearer token and returns prefixed summaries", async () => {
    const { fetchFn, calls } = fakeFetch(200, gcaSearch);
    const results = await provider(fetchFn).search("maple hollow");

    expect(calls[0]!.url).toBe("https://api.golfcourseapi.com/v1/search?search_query=maple%20hollow");
    expect(calls[0]!.headers.Authorization).toBe("Bearer test-key");
    expect(results).toEqual([
      {
        courseId: "gca-7k2m9qb4",
        clubName: "Maple Hollow Golf Club",
        courseName: "North",
        location: { address: "1 Fairway Rd, Springfield, IL", city: "Springfield", state: "IL", country: "United States", latitude: 39.8, longitude: -89.6 },
      },
    ]);
  });

  it("accepts the course wrapped in { course } (live API) or unwrapped (published spec)", async () => {
    const wrapped = await provider(fakeFetch(200, { course: gcaCourse }).fetchFn).getCourse("gca-7k2m9qb4");
    const unwrapped = await provider(fakeFetch(200, gcaCourse).fetchFn).getCourse("gca-7k2m9qb4");
    expect(wrapped).toEqual(unwrapped);
    expect(wrapped?.courseId).toBe("gca-7k2m9qb4");
  });

  it("returns null without calling the provider for ids it does not own or that are malformed", async () => {
    const { fetchFn, calls } = fakeFetch(200, { course: gcaCourse });
    expect(await provider(fetchFn).getCourse("man-123")).toBeNull();
    expect(await provider(fetchFn).getCourse("gca-NOTVALID")).toBeNull();
    expect(calls).toHaveLength(0);
  });

  it("returns null on 404", async () => {
    expect(await provider(fakeFetch(404, { error: "not found" }).fetchFn).getCourse("gca-7k2m9qb4")).toBeNull();
  });

  it.each([
    [429, "rate_limited"],
    [401, "unauthorized"],
    [403, "unauthorized"],
    [500, "unavailable"],
  ])("maps HTTP %i to a %s provider error", async (status, kind) => {
    await expect(provider(fakeFetch(status, { error: "x" }).fetchFn).search("maple")).rejects.toMatchObject({ kind });
  });

  it("maps network failures to an unavailable provider error", async () => {
    const failing = (async () => {
      throw new TypeError("fetch failed");
    }) as typeof fetch;
    await expect(provider(failing).search("maple")).rejects.toBeInstanceOf(ProviderError);
  });
});

describe("normalizeCourse", () => {
  const course = normalizeCourse(gcaCourse, NOW);

  it("flattens male and female tees with stable, unique ids", () => {
    expect(course.tees.map((t) => [t.teeId, t.gender, t.name])).toEqual([
      ["male-blue", "male", "Blue"],
      ["male-white", "male", "White"],
      ["male-junior", "male", "Junior"],
      ["female-red", "female", "Red"],
      ["female-red-2", "female", "Red"],
    ]);
  });

  it("maps holes with 1-based numbers and handicap as stroke index", () => {
    const blue = course.tees[0]!;
    expect(blue).toMatchObject({ courseRating: 72.1, slope: 131, par: 72, totalYards: 6600, strokeIndexValid: true });
    expect(blue.holes[0]).toEqual({ hole: 1, par: 4, strokeIndex: 7, yardage: 360 });
    expect(blue.holes).toHaveLength(18);
  });

  it("keeps each tee's own stroke indexes", () => {
    expect(course.tees[0]!.holes[1]!.strokeIndex).toBe(11);
    expect(course.tees[3]!.holes[1]!.strokeIndex).toBe(1);
  });

  it("flags tees without usable stroke indexes", () => {
    const junior = course.tees[2]!;
    expect(junior.strokeIndexValid).toBe(false);
    expect(junior.holes[0]!.strokeIndex).toBeNull();
  });

  it("records the source and fetch time", () => {
    expect(course).toMatchObject({ source: "golfcourseapi", scorecardUrl: "https://example.com/maple-hollow-north.pdf", fetchedAt: "2026-09-29T12:00:00.000Z" });
  });
});
