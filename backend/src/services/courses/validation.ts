// Validation for manual course entry and corrections. Pure: no I/O.
import type { CourseCorrectionInput, HoleCorrection, ManualCourseInput, ManualHoleInput, ManualTeeInput } from "../../shared/courseInput.js";
import type { CourseLocation, TeeGender } from "../../shared/types.js";

export const HOLES_PER_COURSE = 18;
export const MIN_PAR = 3;
export const MAX_PAR = 5;
export const MIN_SLOPE = 55;
export const MAX_SLOPE = 155;
export const MAX_NAME_LENGTH = 100;
export const MAX_NOTE_LENGTH = 500;
export const MAX_TEES = 12;

export class ValidationError extends Error {
  constructor(
    readonly field: string,
    readonly reason: string,
  ) {
    super(`${field} ${reason}`);
    this.name = "ValidationError";
  }
}

type Obj = Record<string, unknown>;

function fail(field: string, reason: string): never {
  throw new ValidationError(field, reason);
}

function isObject(value: unknown): value is Obj {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isAbsent(value: unknown): value is undefined | null {
  return value === undefined || value === null;
}

function requiredString(value: unknown, field: string, maxLength: number): string {
  if (typeof value !== "string" || value.trim() === "") fail(field, "is required");
  const trimmed = value.trim();
  if (trimmed.length > maxLength) fail(field, `must be at most ${maxLength} characters`);
  return trimmed;
}

function optionalString(value: unknown, field: string, maxLength: number): string | null {
  if (isAbsent(value)) return null;
  if (typeof value !== "string") fail(field, "must be a string");
  const trimmed = value.trim();
  if (trimmed.length > maxLength) fail(field, `must be at most ${maxLength} characters`);
  return trimmed === "" ? null : trimmed;
}

function integerInRange(value: unknown, field: string, min: number, max: number): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < min || value > max) fail(field, `must be an integer from ${min} to ${max}`);
  return value;
}

function positiveInteger(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value <= 0) fail(field, "must be a positive integer");
  return value;
}

function positiveNumber(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) fail(field, "must be a positive number");
  return value;
}

function optionalNumberInRange(value: unknown, field: string, min: number, max: number): number | null {
  if (isAbsent(value)) return null;
  if (typeof value !== "number" || !Number.isFinite(value) || value < min || value > max) fail(field, `must be a number from ${min} to ${max}`);
  return value;
}

function gender(value: unknown, field: string): TeeGender {
  if (isAbsent(value)) return "male";
  if (value !== "male" && value !== "female") fail(field, 'must be "male" or "female"');
  return value;
}

function location(value: unknown): CourseLocation {
  if (!isAbsent(value) && !isObject(value)) fail("location", "must be an object");
  const raw: Obj = value ?? {};
  return {
    address: optionalString(raw.address, "location.address", 200),
    city: optionalString(raw.city, "location.city", MAX_NAME_LENGTH),
    state: optionalString(raw.state, "location.state", MAX_NAME_LENGTH),
    country: optionalString(raw.country, "location.country", MAX_NAME_LENGTH),
    latitude: optionalNumberInRange(raw.latitude, "location.latitude", -90, 90),
    longitude: optionalNumberInRange(raw.longitude, "location.longitude", -180, 180),
  };
}

function manualHoles(value: unknown, field: string): ManualHoleInput[] {
  if (!Array.isArray(value) || value.length !== HOLES_PER_COURSE) fail(field, `must list exactly ${HOLES_PER_COURSE} holes`);
  const holes = value.map((raw: unknown, i): ManualHoleInput => {
    const at = `${field}[${i}]`;
    if (!isObject(raw)) fail(at, "must be an object");
    return {
      hole: integerInRange(raw.hole, `${at}.hole`, 1, HOLES_PER_COURSE),
      par: integerInRange(raw.par, `${at}.par`, MIN_PAR, MAX_PAR),
      strokeIndex: integerInRange(raw.strokeIndex, `${at}.strokeIndex`, 1, HOLES_PER_COURSE),
      yardage: isAbsent(raw.yardage) ? null : positiveInteger(raw.yardage, `${at}.yardage`),
    };
  });
  // With exactly 18 entries in range, no duplicates means every value from 1 to 18 appears once.
  if (new Set(holes.map((h) => h.hole)).size !== holes.length) fail(field, `must number the holes 1 to ${HOLES_PER_COURSE} with no repeats`);
  if (new Set(holes.map((h) => h.strokeIndex)).size !== holes.length) {
    fail(`${field}.strokeIndex`, `must use each value from 1 to ${HOLES_PER_COURSE} exactly once`);
  }
  return holes.sort((a, b) => a.hole - b.hole);
}

function manualTee(raw: unknown, field: string): ManualTeeInput {
  if (!isObject(raw)) fail(field, "must be an object");
  const name = requiredString(raw.name, `${field}.name`, MAX_NAME_LENGTH);
  const teeGender = gender(raw.gender, `${field}.gender`);
  const hasRating = !isAbsent(raw.courseRating);
  const hasSlope = !isAbsent(raw.slope);
  if (hasRating && !hasSlope) fail(`${field}.slope`, "is required when courseRating is given");
  if (hasSlope && !hasRating) fail(`${field}.courseRating`, "is required when slope is given");
  return {
    name,
    gender: teeGender,
    courseRating: hasRating ? positiveNumber(raw.courseRating, `${field}.courseRating`) : null,
    slope: hasSlope ? integerInRange(raw.slope, `${field}.slope`, MIN_SLOPE, MAX_SLOPE) : null,
    holes: manualHoles(raw.holes, `${field}.holes`),
  };
}

export function validateManualCourse(body: unknown): ManualCourseInput {
  if (!isObject(body)) fail("body", "must be a JSON object");
  const courseName = requiredString(body.courseName, "courseName", MAX_NAME_LENGTH);
  const clubName = optionalString(body.clubName, "clubName", MAX_NAME_LENGTH) ?? courseName;
  const where = location(body.location);
  if (!Array.isArray(body.tees) || body.tees.length === 0) fail("tees", "must list at least one tee");
  if (body.tees.length > MAX_TEES) fail("tees", `must list at most ${MAX_TEES} tees`);
  const tees = body.tees.map((t: unknown, i) => manualTee(t, `tees[${i}]`));
  return { courseName, clubName, location: where, tees };
}

function holeCorrections(value: unknown): HoleCorrection[] {
  if (isAbsent(value)) return [];
  if (!Array.isArray(value) || value.length > HOLES_PER_COURSE) fail("holes", `must be a list of at most ${HOLES_PER_COURSE} holes`);
  const holes = value.map((raw: unknown, i): HoleCorrection => {
    const at = `holes[${i}]`;
    if (!isObject(raw)) fail(at, "must be an object");
    const hole: HoleCorrection = {
      hole: integerInRange(raw.hole, `${at}.hole`, 1, HOLES_PER_COURSE),
      par: isAbsent(raw.par) ? null : integerInRange(raw.par, `${at}.par`, MIN_PAR, MAX_PAR),
      strokeIndex: isAbsent(raw.strokeIndex) ? null : integerInRange(raw.strokeIndex, `${at}.strokeIndex`, 1, HOLES_PER_COURSE),
      yardage: isAbsent(raw.yardage) ? null : positiveInteger(raw.yardage, `${at}.yardage`),
    };
    if (hole.par === null && hole.strokeIndex === null && hole.yardage === null) fail(at, "must change par, strokeIndex or yardage");
    return hole;
  });
  if (new Set(holes.map((h) => h.hole)).size !== holes.length) fail("holes", "must not repeat a hole");
  return holes.sort((a, b) => a.hole - b.hole);
}

export function validateCorrection(body: unknown): CourseCorrectionInput {
  if (!isObject(body)) fail("body", "must be a JSON object");
  const correction: CourseCorrectionInput = {
    teeId: optionalString(body.teeId, "teeId", MAX_NAME_LENGTH),
    courseRating: isAbsent(body.courseRating) ? null : positiveNumber(body.courseRating, "courseRating"),
    slope: isAbsent(body.slope) ? null : integerInRange(body.slope, "slope", MIN_SLOPE, MAX_SLOPE),
    holes: holeCorrections(body.holes),
    note: optionalString(body.note, "note", MAX_NOTE_LENGTH),
  };
  const changesTee = correction.courseRating !== null || correction.slope !== null || correction.holes.length > 0;
  if (!changesTee && correction.note === null) fail("body", "must include a note or at least one corrected value");
  if (changesTee && correction.teeId === null) fail("teeId", "is required when correcting rating, slope or holes");
  return correction;
}
