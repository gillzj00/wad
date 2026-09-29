import type { DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";
import { describe, expect, it } from "vitest";
import { DynamoCourseCache } from "../../../src/services/courses/cache.js";
import { CourseNotFoundError, CourseService } from "../../../src/services/courses/courseService.js";
import { normalizeCourse } from "../../../src/services/courses/golfCourseApi.js";
import type { CourseProvider } from "../../../src/services/courses/provider.js";
import { validateCorrection, validateManualCourse, ValidationError } from "../../../src/services/courses/validation.js";
import type { Course } from "../../../src/shared/types.js";
import { gcaCourse, manualCourseBody } from "./fixtures.js";

const NOW = new Date("2026-09-29T12:00:00Z");
const TABLE = "wad-test";
const providerCourse = normalizeCourse(gcaCourse, NOW);

type Item = Record<string, unknown>;

/** Stand-in for the document client that also enforces the two condition expressions the cache uses. */
function fakeDb() {
  const items = new Map<string, Item>();
  const db = {
    async send(cmd: { constructor: { name: string }; input: Record<string, unknown> }) {
      if (cmd.constructor.name === "PutCommand") {
        const item = cmd.input.Item as Item;
        const key = `${item.PK}|${item.SK}`;
        const existing = items.get(key);
        const condition = cmd.input.ConditionExpression as string | undefined;
        if (existing && condition) {
          const values = (cmd.input.ExpressionAttributeValues ?? {}) as Record<string, unknown>;
          const sameSource = condition.includes("course.#source = :source") && (existing.course as Course).source === values[":source"];
          if (!sameSource) throw Object.assign(new Error("The conditional request failed"), { name: "ConditionalCheckFailedException" });
        }
        items.set(key, item);
        return {};
      }
      const key = cmd.input.Key as Item;
      return { Item: items.get(`${key.PK}|${key.SK}`) };
    },
  } as unknown as DynamoDBDocumentClient;
  return { db, items };
}

function setup(ids: string[] = ["id-1", "id-2", "id-3"]) {
  const { db, items } = fakeDb();
  const providerCalls: string[] = [];
  const provider: CourseProvider = {
    async search() {
      return [];
    },
    async getCourse(id) {
      providerCalls.push(id);
      return id === providerCourse.courseId ? providerCourse : null;
    },
  };
  const cache = new DynamoCourseCache(db, TABLE, () => NOW);
  const queue = [...ids];
  const service = new CourseService(provider, cache, () => queue.shift()!, () => NOW);
  return { service, cache, items, providerCalls };
}

describe("CourseService.createManualCourse", () => {
  it("stores the course under COURSE#man-<id>/PROFILE with its creator", async () => {
    const { service, items } = setup();
    const course = await service.createManualCourse(validateManualCourse(manualCourseBody()), "user-1");

    expect(course.courseId).toBe("man-id-1");
    expect(course.source).toBe("manual");
    expect(course.fetchedAt).toBe(NOW.toISOString());
    expect(items.get("COURSE#man-id-1|PROFILE")).toEqual({
      PK: "COURSE#man-id-1",
      SK: "PROFILE",
      type: "course",
      course,
      createdBy: "user-1",
      createdAt: NOW.toISOString(),
    });
    expect(await service.getCourse("man-id-1")).toEqual(course);
  });

  it("builds tees in the same shape as provider courses", async () => {
    const { service } = setup();
    const body = manualCourseBody();
    body.tees.push({ ...body.tees[0]!, name: "blue" });
    const course = await service.createManualCourse(validateManualCourse(body), "user-1");

    expect(course.tees.map((t) => t.teeId)).toEqual(["male-blue", "male-red", "male-blue-2"]);
    expect(course.tees[0]).toMatchObject({ par: 72, totalYards: 18 * 350 + 153, courseRating: 71.2, slope: 128, strokeIndexValid: true });
    expect(course.tees[1]).toMatchObject({ par: 72, totalYards: null, courseRating: null, slope: null, strokeIndexValid: true });
    expect(course.tees[0]!.holes).toHaveLength(18);
  });

  it("gives each course its own id", async () => {
    const { service, items } = setup();
    const input = validateManualCourse(manualCourseBody());
    const first = await service.createManualCourse(input, "user-1");
    const second = await service.createManualCourse(input, "user-2");
    expect([first.courseId, second.courseId]).toEqual(["man-id-1", "man-id-2"]);
    expect(items.size).toBe(2);
  });

  it("refuses to replace a course that already has the generated id", async () => {
    const { service, items } = setup(["same", "same"]);
    const input = validateManualCourse(manualCourseBody());
    const first = await service.createManualCourse(input, "user-1");
    await expect(service.createManualCourse({ ...input, courseName: "Other" }, "user-2")).rejects.toThrow();
    expect(items.get("COURSE#man-same|PROFILE")).toMatchObject({ course: first, createdBy: "user-1" });
  });
});

describe("manual and provider courses do not overwrite each other", () => {
  it("never asks the provider for a manual id", async () => {
    const { service, providerCalls } = setup();
    expect(await service.getCourse("man-unknown")).toBeNull();
    expect(providerCalls).toEqual([]);
  });

  it("does not cache a provider result that claims a manual id or source", async () => {
    for (const bad of [
      { ...providerCourse, courseId: "man-id-1" },
      { ...providerCourse, source: "manual" as const },
    ]) {
      const { db, items } = fakeDb();
      const provider: CourseProvider = { search: async () => [], getCourse: async () => bad };
      const service = new CourseService(provider, new DynamoCourseCache(db, TABLE, () => NOW));
      expect(await service.getCourse("gca-7k2m9qb4")).toBeNull();
      expect(items.size).toBe(0);
    }
  });

  it("keeps a manual course when a provider write-through targets the same key", async () => {
    const { service, cache, items } = setup();
    const manual = await service.createManualCourse(validateManualCourse(manualCourseBody()), "user-1");
    await cache.putCourse({ ...providerCourse, courseId: manual.courseId });
    expect(items.get(`COURSE#${manual.courseId}|PROFILE`)).toMatchObject({ course: manual, createdBy: "user-1" });
  });

  it("keeps a provider course when a manual create targets the same key", async () => {
    const { service, cache, items } = setup();
    await service.getCourse(providerCourse.courseId);
    await expect(cache.createCourse({ ...providerCourse, source: "manual" }, "user-1")).rejects.toThrow();
    expect(items.get(`COURSE#${providerCourse.courseId}|PROFILE`)).toEqual({
      PK: `COURSE#${providerCourse.courseId}`,
      SK: "PROFILE",
      type: "course",
      course: providerCourse,
    });
  });

  it("still lets the provider refresh its own course", async () => {
    const { cache } = setup();
    await cache.putCourse(providerCourse);
    const refreshed = { ...providerCourse, courseName: "North (renovated)" };
    await cache.putCourse(refreshed);
    expect(await cache.getCourse(providerCourse.courseId)).toEqual(refreshed);
  });

  it("creating a manual course leaves cached provider courses alone", async () => {
    const { service, items } = setup();
    await service.getCourse(providerCourse.courseId);
    await service.createManualCourse(validateManualCourse(manualCourseBody()), "user-1");
    expect(await service.getCourse(providerCourse.courseId)).toEqual(providerCourse);
    expect([...items.keys()].sort()).toEqual([`COURSE#${providerCourse.courseId}|PROFILE`, "COURSE#man-id-1|PROFILE"]);
  });
});

describe("CourseService.submitCorrection", () => {
  const input = validateCorrection({ teeId: "male-blue", holes: [{ hole: 4, par: 5 }], note: "hole 4 was lengthened" });

  it("stores a pending correction next to the course without changing the course", async () => {
    const { service, items } = setup();
    await service.getCourse(providerCourse.courseId);
    const correction = await service.submitCorrection(providerCourse.courseId, input, "user-9");

    expect(correction).toEqual({
      ...input,
      correctionId: "id-1",
      courseId: providerCourse.courseId,
      status: "pending",
      submittedBy: "user-9",
      submittedAt: NOW.toISOString(),
    });
    expect(items.get(`COURSE#${providerCourse.courseId}|CORRECTION#${NOW.toISOString()}#id-1`)).toEqual({
      PK: `COURSE#${providerCourse.courseId}`,
      SK: `CORRECTION#${NOW.toISOString()}#id-1`,
      type: "courseCorrection",
      correction,
    });
    expect(await service.getCourse(providerCourse.courseId)).toEqual(providerCourse);
  });

  it("accepts corrections to manual courses", async () => {
    const { service, items } = setup();
    const manual = await service.createManualCourse(validateManualCourse(manualCourseBody()), "user-1");
    const correction = await service.submitCorrection(manual.courseId, input, "user-2");
    expect(correction.submittedBy).toBe("user-2");
    expect(items.size).toBe(2);
    expect(await service.getCourse(manual.courseId)).toEqual(manual);
  });

  it("keeps every correction to the same course", async () => {
    const { service, items } = setup();
    await service.getCourse(providerCourse.courseId);
    await service.submitCorrection(providerCourse.courseId, input, "user-1");
    await service.submitCorrection(providerCourse.courseId, input, "user-1");
    expect([...items.keys()].filter((k) => k.includes("|CORRECTION#"))).toHaveLength(2);
  });

  it("rejects an unknown course without asking the provider or storing anything", async () => {
    const { service, items, providerCalls } = setup();
    await expect(service.submitCorrection("gca-zzzzzzzz", input, "user-1")).rejects.toBeInstanceOf(CourseNotFoundError);
    await expect(service.submitCorrection(providerCourse.courseId, input, "user-1")).rejects.toBeInstanceOf(CourseNotFoundError);
    expect(providerCalls).toEqual([]);
    expect(items.size).toBe(0);
  });

  it("rejects a tee that is not on the course", async () => {
    const { service, items } = setup();
    await service.getCourse(providerCourse.courseId);
    const err = await service.submitCorrection(providerCourse.courseId, { ...input, teeId: "male-gold" }, "user-1").catch((e: unknown) => e);
    expect(err).toBeInstanceOf(ValidationError);
    expect((err as ValidationError).field).toBe("teeId");
    expect(items.size).toBe(1);
  });
});
