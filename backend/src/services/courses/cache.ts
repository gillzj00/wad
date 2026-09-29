import { type DynamoDBDocumentClient, GetCommand, PutCommand } from "@aws-sdk/lib-dynamodb";
import type { CourseCorrection } from "../../shared/courseInput.js";
import type { Course, CourseSummary, UserId } from "../../shared/types.js";

export interface CourseCache {
  getCourse(courseId: string): Promise<Course | null>;
  /** Write-through for provider courses. Never replaces a course that came from a different source. */
  putCourse(course: Course): Promise<void>;
  /** Stores a new course; fails if the id is already taken. */
  createCourse(course: Course, createdBy: UserId): Promise<void>;
  putCorrection(correction: CourseCorrection): Promise<void>;
  getSearch(query: string): Promise<CourseSummary[] | null>;
  putSearch(query: string, results: CourseSummary[], ttlSeconds: number): Promise<void>;
}

function isConditionFailure(err: unknown): boolean {
  return err instanceof Error && err.name === "ConditionalCheckFailedException";
}

/** Single-table storage; see docs/data-model.md for the item layout. */
export class DynamoCourseCache implements CourseCache {
  constructor(
    private readonly db: DynamoDBDocumentClient,
    private readonly tableName: string,
    private readonly now: () => Date = () => new Date(),
  ) {}

  async getCourse(courseId: string): Promise<Course | null> {
    const res = await this.db.send(new GetCommand({ TableName: this.tableName, Key: { PK: `COURSE#${courseId}`, SK: "PROFILE" } }));
    return (res.Item?.course as Course | undefined) ?? null;
  }

  async putCourse(course: Course): Promise<void> {
    try {
      await this.db.send(
        new PutCommand({
          TableName: this.tableName,
          Item: { PK: `COURSE#${course.courseId}`, SK: "PROFILE", type: "course", course },
          ConditionExpression: "attribute_not_exists(PK) OR course.#source = :source",
          ExpressionAttributeNames: { "#source": "source" },
          ExpressionAttributeValues: { ":source": course.source },
        }),
      );
    } catch (err) {
      // The stored course came from another source; leave it as it is.
      if (!isConditionFailure(err)) throw err;
    }
  }

  async createCourse(course: Course, createdBy: UserId): Promise<void> {
    await this.db.send(
      new PutCommand({
        TableName: this.tableName,
        Item: { PK: `COURSE#${course.courseId}`, SK: "PROFILE", type: "course", course, createdBy, createdAt: course.fetchedAt },
        ConditionExpression: "attribute_not_exists(PK)",
      }),
    );
  }

  async putCorrection(correction: CourseCorrection): Promise<void> {
    await this.db.send(
      new PutCommand({
        TableName: this.tableName,
        Item: {
          PK: `COURSE#${correction.courseId}`,
          SK: `CORRECTION#${correction.submittedAt}#${correction.correctionId}`,
          type: "courseCorrection",
          correction,
        },
        ConditionExpression: "attribute_not_exists(PK)",
      }),
    );
  }

  async getSearch(query: string): Promise<CourseSummary[] | null> {
    const res = await this.db.send(new GetCommand({ TableName: this.tableName, Key: { PK: `COURSESEARCH#${query}`, SK: "RESULTS" } }));
    const item = res.Item;
    // DynamoDB deletes expired items lazily, so check the TTL on read as well.
    if (!item || (item.ttl as number) <= this.epochSeconds()) return null;
    return item.results as CourseSummary[];
  }

  async putSearch(query: string, results: CourseSummary[], ttlSeconds: number): Promise<void> {
    await this.db.send(
      new PutCommand({
        TableName: this.tableName,
        Item: { PK: `COURSESEARCH#${query}`, SK: "RESULTS", type: "courseSearch", results, ttl: this.epochSeconds() + ttlSeconds },
      }),
    );
  }

  private epochSeconds(): number {
    return Math.floor(this.now().getTime() / 1000);
  }
}
