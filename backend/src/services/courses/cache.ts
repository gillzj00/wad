import { type DynamoDBDocumentClient, GetCommand, PutCommand } from "@aws-sdk/lib-dynamodb";
import type { Course, CourseSummary } from "../../shared/types.js";

export interface CourseCache {
  getCourse(courseId: string): Promise<Course | null>;
  putCourse(course: Course): Promise<void>;
  getSearch(query: string): Promise<CourseSummary[] | null>;
  putSearch(query: string, results: CourseSummary[], ttlSeconds: number): Promise<void>;
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
    await this.db.send(
      new PutCommand({
        TableName: this.tableName,
        Item: { PK: `COURSE#${course.courseId}`, SK: "PROFILE", type: "course", course },
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
