import type { DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";
import { describe, expect, it } from "vitest";
import { DynamoCourseCache } from "../../../src/services/courses/cache.js";
import { normalizeSummary } from "../../../src/services/courses/golfCourseApi.js";
import { gcaCourse } from "./fixtures.js";

const NOW = new Date("2026-09-29T12:00:00Z");
const NOW_S = NOW.getTime() / 1000;

/** Minimal stand-in for the document client: stores items by PK/SK. */
function fakeDb() {
  const items = new Map<string, Record<string, unknown>>();
  const sent: { name: string; input: Record<string, unknown> }[] = [];
  const db = {
    async send(cmd: { constructor: { name: string }; input: Record<string, unknown> }) {
      sent.push({ name: cmd.constructor.name, input: cmd.input });
      if (cmd.constructor.name === "PutCommand") {
        const item = cmd.input.Item as Record<string, unknown>;
        items.set(`${item.PK}|${item.SK}`, item);
        return {};
      }
      const key = cmd.input.Key as Record<string, unknown>;
      return { Item: items.get(`${key.PK}|${key.SK}`) };
    },
  } as unknown as DynamoDBDocumentClient;
  return { db, items, sent };
}

describe("DynamoCourseCache", () => {
  const summary = normalizeSummary(gcaCourse);

  it("stores search results under COURSESEARCH#<query> with a TTL", async () => {
    const { db, sent } = fakeDb();
    await new DynamoCourseCache(db, "wad-test", () => NOW).putSearch("maple", [summary], 60);
    expect(sent[0]).toEqual({
      name: "PutCommand",
      input: { TableName: "wad-test", Item: { PK: "COURSESEARCH#maple", SK: "RESULTS", type: "courseSearch", results: [summary], ttl: NOW_S + 60 } },
    });
  });

  it("treats a search past its TTL as a miss even if DynamoDB has not deleted it yet", async () => {
    const { db } = fakeDb();
    let now = NOW;
    const cache = new DynamoCourseCache(db, "wad-test", () => now);
    await cache.putSearch("maple", [summary], 60);
    expect(await cache.getSearch("maple")).toEqual([summary]);
    now = new Date(NOW.getTime() + 61_000);
    expect(await cache.getSearch("maple")).toBeNull();
  });

  it("round-trips a course under COURSE#<id>/PROFILE", async () => {
    const { db, items } = fakeDb();
    const cache = new DynamoCourseCache(db, "wad-test", () => NOW);
    const course = { ...summary, source: "golfcourseapi" as const, scorecardUrl: null, tees: [], fetchedAt: NOW.toISOString() };
    await cache.putCourse(course);
    expect(items.has("COURSE#gca-7k2m9qb4|PROFILE")).toBe(true);
    expect(await cache.getCourse("gca-7k2m9qb4")).toEqual(course);
    expect(await cache.getCourse("gca-missing1")).toBeNull();
  });
});
