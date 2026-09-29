import type { APIGatewayProxyEventV2, APIGatewayProxyStructuredResultV2 } from "aws-lambda";
import { describe, expect, it } from "vitest";
import { createHandler } from "../../src/handlers/courses.js";
import { type CourseService, QueryTooShortError } from "../../src/services/courses/courseService.js";
import { ProviderError } from "../../src/services/courses/provider.js";

const event = (routeKey: string, extra: Partial<APIGatewayProxyEventV2> = {}) => ({ routeKey, ...extra }) as APIGatewayProxyEventV2;

async function call(service: Partial<CourseService>, e: APIGatewayProxyEventV2) {
  const res = (await createHandler(service as CourseService)(e)) as APIGatewayProxyStructuredResultV2;
  return { status: res.statusCode, body: JSON.parse(res.body as string) };
}

describe("courses handler", () => {
  it("searches with the q parameter", async () => {
    const res = await call({ search: async (q) => [{ courseId: q } as never] }, event("GET /v1/courses", { queryStringParameters: { q: "maple" } }));
    expect(res).toEqual({ status: 200, body: { courses: [{ courseId: "maple" }] } });
  });

  it("returns 400 for a short query", async () => {
    const res = await call(
      {
        search: async () => {
          throw new QueryTooShortError();
        },
      },
      event("GET /v1/courses", { queryStringParameters: { q: "ab" } }),
    );
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe("query_too_short");
  });

  it("returns a course or 404", async () => {
    const service = { getCourse: async (id: string) => (id === "gca-7k2m9qb4" ? ({ courseId: id } as never) : null) };
    expect(await call(service, event("GET /v1/courses/{courseId}", { pathParameters: { courseId: "gca-7k2m9qb4" } }))).toEqual({
      status: 200,
      body: { course: { courseId: "gca-7k2m9qb4" } },
    });
    const missing = await call(service, event("GET /v1/courses/{courseId}", { pathParameters: { courseId: "gca-zzzzzzzz" } }));
    expect(missing.status).toBe(404);
    expect(missing.body.error.code).toBe("course_not_found");
  });

  it("returns 503 when the provider rate limit is hit and 502 for other provider failures", async () => {
    const failing = (kind: "rate_limited" | "unavailable") => ({
      search: async () => {
        throw new ProviderError(kind, "x");
      },
    });
    const e = event("GET /v1/courses", { queryStringParameters: { q: "maple" } });
    expect((await call(failing("rate_limited"), e)).status).toBe(503);
    expect((await call(failing("unavailable"), e)).status).toBe(502);
  });

  it("returns 404 for an unknown route", async () => {
    expect((await call({}, event("GET /v1/nope"))).status).toBe(404);
  });
});
