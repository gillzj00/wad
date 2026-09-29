import type { Course, CourseSummary } from "../../shared/types.js";

export interface CourseProvider {
  search(query: string): Promise<CourseSummary[]>;
  /** Null when the provider has no course with this id. */
  getCourse(courseId: string): Promise<Course | null>;
}

export type ProviderErrorKind = "rate_limited" | "unauthorized" | "unavailable";

export class ProviderError extends Error {
  constructor(
    readonly kind: ProviderErrorKind,
    message: string,
  ) {
    super(message);
    this.name = "ProviderError";
  }
}
