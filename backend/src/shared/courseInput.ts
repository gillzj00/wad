// Request and response shapes for manual course entry and corrections.
// They mirror docs/api.md; keep the two in sync.
import type { CourseLocation, TeeGender, UserId } from "./types.js";

export interface ManualHoleInput {
  hole: number;
  par: number;
  strokeIndex: number;
  yardage: number | null;
}

export interface ManualTeeInput {
  name: string;
  gender: TeeGender;
  courseRating: number | null;
  slope: number | null;
  holes: ManualHoleInput[];
}

/** A validated POST /courses body with the optional fields filled in. */
export interface ManualCourseInput {
  courseName: string;
  clubName: string;
  location: CourseLocation;
  tees: ManualTeeInput[];
}

/** Null means "no change suggested" for that field. */
export interface HoleCorrection {
  hole: number;
  par: number | null;
  strokeIndex: number | null;
  yardage: number | null;
}

/** A validated POST /courses/{courseId}/corrections body. */
export interface CourseCorrectionInput {
  teeId: string | null;
  courseRating: number | null;
  slope: number | null;
  holes: HoleCorrection[];
  note: string | null;
}

export interface CourseCorrection extends CourseCorrectionInput {
  correctionId: string;
  courseId: string;
  /** Corrections are suggestions; nothing applies them to the course yet. */
  status: "pending";
  submittedBy: UserId;
  submittedAt: string;
}
