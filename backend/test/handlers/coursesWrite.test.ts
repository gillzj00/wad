import type { APIGatewayProxyEventV2, APIGatewayProxyStructuredResultV2 } from "aws-lambda";
import { describe, expect, it } from "vitest";
import { createHandler } from "../../src/handlers/courses.js";
import type { CourseCache } from "../../src/services/courses/cache.js";
import { CourseService } from "../../src/services/courses/courseService.js";
import type { CourseCorrection } from "../../src/shared/courseInput.js";
import type { Course } from "../../src/shared/types.js";
import { manualCourseBody } from "../services/courses/fixtures.js";

const NOW = new Date("2026-09-29T12:00:00Z");
const CREATE = "POST /v1/courses";
const CORRECT = "POST /v1/courses/{courseId}/corrections";

function setup() {
  const courses = new Map<string, { course: Course; createdBy?: string }>();
  const corrections: CourseCorrection[] = [];
  const cache: CourseCache = {
    getCourse: async (id) => courses.get(id)?.course ?? null,
    putCourse: async (course) => void courses.set(course.courseId, { course }),
    createCourse: async (course, createdBy) => void courses.set(course.courseId, { course, createdBy }),
    putCorrection: async (correction) => void corrections.push(correction),
    getSearch: async () => null,
    putSearch: async () => {},
  };
  const providerCalls: string[] = [];
  const provider = {
    search: async () => [],
    getCourse: async (id: string) => {
      providerCalls.push(id);
      return null;
    },
  };
  let n = 0;
  const handler = createHandler(new CourseService(provider, cache, () => `id-${++n}`, () => NOW));
  return { handler, courses, corrections, providerCalls };
}

interface Request {
  body?: unknown;
  rawBody?: string;
  sub?: unknown;
  courseId?: string;
  base64?: boolean;
  noAuthorizer?: boolean;
}

function event(routeKey: string, req: Request): APIGatewayProxyEventV2 {
  const text = req.rawBody ?? (req.body === undefined ? undefined : JSON.stringify(req.body));
  return {
    routeKey,
    body: text !== undefined && req.base64 ? Buffer.from(text).toString("base64") : text,
    isBase64Encoded: req.base64 ?? false,
    pathParameters: req.courseId ? { courseId: req.courseId } : undefined,
    requestContext: req.noAuthorizer ? {} : { authorizer: { jwt: { claims: req.sub === undefined ? {} : { sub: req.sub } } } },
  } as unknown as APIGatewayProxyEventV2;
}

async function call(handler: ReturnType<typeof createHandler>, routeKey: string, req: Request) {
  const res = (await handler(event(routeKey, req))) as APIGatewayProxyStructuredResultV2;
  return { status: res.statusCode, body: JSON.parse(res.body as string) };
}

describe("POST /v1/courses", () => {
  it("creates a manual course owned by the caller", async () => {
    const { handler, courses } = setup();
    const res = await call(handler, CREATE, { body: manualCourseBody(), sub: "user-1" });

    expect(res.status).toBe(201);
    expect(res.body.course).toMatchObject({ courseId: "man-id-1", source: "manual", courseName: "Back Forty", clubName: "Cedar Ridge Golf Club" });
    expect(res.body.course.tees).toHaveLength(2);
    expect(courses.get("man-id-1")).toEqual({ course: res.body.course, createdBy: "user-1" });
  });

  it("makes the course readable through GET /v1/courses/{courseId}", async () => {
    const { handler, providerCalls } = setup();
    const created = await call(handler, CREATE, { body: manualCourseBody(), sub: "user-1" });
    const read = await call(handler, "GET /v1/courses/{courseId}", { courseId: created.body.course.courseId });
    expect(read).toEqual({ status: 200, body: { course: created.body.course } });
    expect(providerCalls).toEqual([]);
  });

  it("accepts a base64-encoded body", async () => {
    const { handler } = setup();
    expect((await call(handler, CREATE, { body: manualCourseBody(), sub: "user-1", base64: true })).status).toBe(201);
  });

  it("ignores ids, sources and owners sent by the client", async () => {
    const { handler, courses } = setup();
    const body = { ...manualCourseBody(), courseId: "gca-7k2m9qb4", source: "golfcourseapi", createdBy: "someone-else" };
    const res = await call(handler, CREATE, { body, sub: "user-1" });
    expect(res.body.course).toMatchObject({ courseId: "man-id-1", source: "manual" });
    expect([...courses.keys()]).toEqual(["man-id-1"]);
    expect(courses.get("man-id-1")!.createdBy).toBe("user-1");
  });

  it("returns 401 without a caller and stores nothing", async () => {
    const { handler, courses } = setup();
    for (const req of [{ noAuthorizer: true }, {}, { sub: "" }, { sub: 42 }]) {
      const res = await call(handler, CREATE, { body: manualCourseBody(), ...req });
      expect(res.status).toBe(401);
      expect(res.body.error.code).toBe("unauthorized");
    }
    expect(courses.size).toBe(0);
  });

  it("returns 400 for a missing or malformed body", async () => {
    const { handler } = setup();
    for (const req of [{}, { rawBody: "" }, { rawBody: "{not json" }]) {
      const res = await call(handler, CREATE, { ...req, sub: "user-1" });
      expect(res.status).toBe(400);
      expect(res.body.error.code).toBe("invalid_body");
    }
  });

  it("returns 400 naming the field that failed validation", async () => {
    const { handler, courses } = setup();
    const body = manualCourseBody();
    body.tees[0]!.slope = 200;
    const res = await call(handler, CREATE, { body, sub: "user-1" });
    expect(res).toEqual({
      status: 400,
      body: { error: { code: "validation_failed", message: "tees[0].slope must be an integer from 55 to 155", field: "tees[0].slope" } },
    });
    expect(courses.size).toBe(0);
  });
});

describe("POST /v1/courses/{courseId}/corrections", () => {
  const correction = { teeId: "male-blue", holes: [{ hole: 4, par: 5 }], note: "hole 4 was lengthened" };

  async function withCourse() {
    const ctx = setup();
    const created = await call(ctx.handler, CREATE, { body: manualCourseBody(), sub: "user-1" });
    return { ...ctx, course: created.body.course as Course };
  }

  it("stores a pending correction from the caller and leaves the course unchanged", async () => {
    const { handler, courses, corrections, course } = await withCourse();
    const res = await call(handler, CORRECT, { body: correction, sub: "user-2", courseId: course.courseId });

    expect(res.status).toBe(201);
    expect(res.body.correction).toEqual({
      correctionId: "id-2",
      courseId: course.courseId,
      status: "pending",
      submittedBy: "user-2",
      submittedAt: NOW.toISOString(),
      teeId: "male-blue",
      courseRating: null,
      slope: null,
      holes: [{ hole: 4, par: 5, strokeIndex: null, yardage: null }],
      note: "hole 4 was lengthened",
    });
    expect(corrections).toEqual([res.body.correction]);
    expect(courses.get(course.courseId)!.course).toEqual(course);
  });

  it("returns 404 for an unknown course", async () => {
    const { handler, corrections, providerCalls } = setup();
    const res = await call(handler, CORRECT, { body: correction, sub: "user-1", courseId: "gca-zzzzzzzz" });
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe("course_not_found");
    expect(corrections).toEqual([]);
    expect(providerCalls).toEqual([]);
  });

  it("returns 401 without a caller", async () => {
    const { handler, corrections, course } = await withCourse();
    for (const req of [{ noAuthorizer: true }, {}, { sub: "" }]) {
      expect((await call(handler, CORRECT, { body: correction, courseId: course.courseId, ...req })).status).toBe(401);
    }
    expect(corrections).toEqual([]);
  });

  it("returns 400 for invalid corrections", async () => {
    const { handler, corrections, course } = await withCourse();
    const post = (body: unknown) => call(handler, CORRECT, { body, sub: "user-2", courseId: course.courseId });

    expect((await post({})).body.error).toMatchObject({ code: "validation_failed", field: "body" });
    expect((await post({ ...correction, teeId: "male-gold" })).body.error).toMatchObject({ code: "validation_failed", field: "teeId" });
    const badPar = await post({ teeId: "male-blue", holes: [{ hole: 4, par: 9 }] });
    expect(badPar.status).toBe(400);
    expect(badPar.body.error.field).toBe("holes[0].par");
    expect((await call(handler, CORRECT, { rawBody: "nope", sub: "user-2", courseId: course.courseId })).body.error.code).toBe("invalid_body");
    expect(corrections).toEqual([]);
  });
});
