import { describe, expect, it } from "vitest";
import { validateCorrection, validateManualCourse, ValidationError } from "../../../src/services/courses/validation.js";
import { manualCourseBody } from "./fixtures.js";

type Body = ReturnType<typeof manualCourseBody>;
type Loose = Record<string, unknown>;

/** Runs the validator on a body changed by `change` and returns the field it rejects. */
function rejectedField(change: (body: Body) => void): string {
  const body = manualCourseBody();
  change(body);
  return fieldOf(() => validateManualCourse(body));
}

function fieldOf(run: () => unknown): string {
  try {
    run();
  } catch (err) {
    if (err instanceof ValidationError) return err.field;
    throw err;
  }
  throw new Error("expected a ValidationError");
}

const hole = (body: Body, tee: number, index: number) => body.tees[tee]!.holes[index]! as Loose;
const tee = (body: Body, index: number) => body.tees[index]! as Loose;

describe("validateManualCourse", () => {
  it("accepts a valid course and fills in the optional fields", () => {
    const course = validateManualCourse(manualCourseBody());
    expect(course.courseName).toBe("Back Forty");
    expect(course.clubName).toBe("Cedar Ridge Golf Club");
    expect(course.location).toEqual({ address: null, city: "Springfield", state: "IL", country: null, latitude: null, longitude: null });
    expect(course.tees[0]).toMatchObject({ name: "Blue", gender: "male", courseRating: 71.2, slope: 128 });
    expect(course.tees[0]!.holes[0]).toEqual({ hole: 1, par: 4, strokeIndex: 7, yardage: 350 });
    expect(course.tees[1]).toMatchObject({ name: "Red", gender: "male", courseRating: null, slope: null });
    expect(course.tees[1]!.holes[0]!.yardage).toBeNull();
  });

  it("uses the course name as the club name when none is given", () => {
    const body = manualCourseBody() as Loose;
    delete body.clubName;
    expect(validateManualCourse(body).clubName).toBe("Back Forty");
  });

  it("sorts holes that arrive out of order", () => {
    const body = manualCourseBody();
    body.tees[0]!.holes.reverse();
    expect(validateManualCourse(body).tees[0]!.holes.map((h) => h.hole)).toEqual(Array.from({ length: 18 }, (_, i) => i + 1));
  });

  it("rejects a body that is not an object", () => {
    for (const body of [null, "course", 3, []]) expect(fieldOf(() => validateManualCourse(body))).toBe("body");
  });

  it("requires a name", () => {
    expect(rejectedField((b) => delete (b as Loose).courseName)).toBe("courseName");
    expect(rejectedField((b) => (b.courseName = "   "))).toBe("courseName");
    expect(rejectedField((b) => ((b as Loose).courseName = 42))).toBe("courseName");
    expect(rejectedField((b) => (b.courseName = "x".repeat(101)))).toBe("courseName");
  });

  it("rejects a club name or location of the wrong type", () => {
    expect(rejectedField((b) => ((b as Loose).clubName = 7))).toBe("clubName");
    expect(rejectedField((b) => ((b as Loose).location = "Springfield"))).toBe("location");
    expect(rejectedField((b) => ((b.location as Loose).city = 5))).toBe("location.city");
    expect(rejectedField((b) => ((b.location as Loose).latitude = 91))).toBe("location.latitude");
  });

  it("requires between 1 and 12 tees", () => {
    expect(rejectedField((b) => delete (b as Loose).tees)).toBe("tees");
    expect(rejectedField((b) => (b.tees = []))).toBe("tees");
    expect(rejectedField((b) => (b.tees = Array.from({ length: 13 }, () => b.tees[0]!)))).toBe("tees");
    expect(rejectedField((b) => ((b.tees as unknown[])[1] = "red"))).toBe("tees[1]");
  });

  it("requires a tee name and a known gender", () => {
    expect(rejectedField((b) => delete tee(b, 1).name)).toBe("tees[1].name");
    expect(rejectedField((b) => (tee(b, 0).gender = "mixed"))).toBe("tees[0].gender");
  });

  it("requires rating and slope together", () => {
    expect(rejectedField((b) => delete tee(b, 0).slope)).toBe("tees[0].slope");
    expect(rejectedField((b) => delete tee(b, 0).courseRating)).toBe("tees[0].courseRating");
  });

  it("requires a positive rating", () => {
    for (const rating of [0, -70.1, "71.2", Number.NaN]) expect(rejectedField((b) => (tee(b, 0).courseRating = rating))).toBe("tees[0].courseRating");
  });

  it("requires an integer slope from 55 to 155", () => {
    for (const slope of [54, 156, 120.5, "128"]) expect(rejectedField((b) => (tee(b, 0).slope = slope))).toBe("tees[0].slope");
    for (const slope of [55, 155]) {
      const body = manualCourseBody();
      tee(body, 0).slope = slope;
      expect(validateManualCourse(body).tees[0]!.slope).toBe(slope);
    }
  });

  it("requires exactly 18 holes", () => {
    expect(rejectedField((b) => delete tee(b, 0).holes)).toBe("tees[0].holes");
    expect(rejectedField((b) => b.tees[0]!.holes.pop())).toBe("tees[0].holes");
    expect(rejectedField((b) => (b.tees[0]!.holes = b.tees[0]!.holes.slice(0, 9)))).toBe("tees[0].holes");
    expect(rejectedField((b) => b.tees[0]!.holes.push({ hole: 19, par: 4, strokeIndex: 1, yardage: 300 }))).toBe("tees[0].holes");
    expect(rejectedField((b) => ((b.tees[0]!.holes as unknown[])[4] = 4))).toBe("tees[0].holes[4]");
  });

  it("requires holes numbered 1 to 18 with no repeats", () => {
    for (const n of [0, 19, 1.5, "2"]) expect(rejectedField((b) => (hole(b, 0, 1).hole = n))).toBe("tees[0].holes[1].hole");
    expect(rejectedField((b) => delete hole(b, 0, 1).hole)).toBe("tees[0].holes[1].hole");
    expect(rejectedField((b) => (hole(b, 0, 1).hole = 1))).toBe("tees[0].holes");
  });

  it("requires par from 3 to 5", () => {
    for (const par of [2, 6, 4.5, "4", null]) expect(rejectedField((b) => (hole(b, 1, 2).par = par))).toBe("tees[1].holes[2].par");
  });

  it("requires stroke indexes to be a permutation of 1 to 18", () => {
    for (const si of [0, 19, 2.5, null]) expect(rejectedField((b) => (hole(b, 0, 3).strokeIndex = si))).toBe("tees[0].holes[3].strokeIndex");
    expect(rejectedField((b) => (hole(b, 0, 3).strokeIndex = hole(b, 0, 4).strokeIndex))).toBe("tees[0].holes.strokeIndex");
  });

  it("requires yardage, when given, to be a positive integer", () => {
    for (const yards of [0, -150, 410.5, "400"]) expect(rejectedField((b) => (hole(b, 0, 5).yardage = yards))).toBe("tees[0].holes[5].yardage");
  });

  it("names the field in the message", () => {
    const body = manualCourseBody();
    hole(body, 0, 5).par = 7;
    expect(() => validateManualCourse(body)).toThrow("tees[0].holes[5].par must be an integer from 3 to 5");
  });
});

describe("validateCorrection", () => {
  it("accepts corrected values for a tee", () => {
    expect(validateCorrection({ teeId: "male-blue", slope: 130, holes: [{ hole: 7, par: 5 }, { hole: 2, yardage: 512 }], note: " card changed " })).toEqual({
      teeId: "male-blue",
      courseRating: null,
      slope: 130,
      holes: [
        { hole: 2, par: null, strokeIndex: null, yardage: 512 },
        { hole: 7, par: 5, strokeIndex: null, yardage: null },
      ],
      note: "card changed",
    });
  });

  it("accepts a note on its own", () => {
    expect(validateCorrection({ note: "the club renamed the course" })).toEqual({
      teeId: null,
      courseRating: null,
      slope: null,
      holes: [],
      note: "the club renamed the course",
    });
  });

  it("rejects an empty correction", () => {
    expect(fieldOf(() => validateCorrection({}))).toBe("body");
    expect(fieldOf(() => validateCorrection({ teeId: "male-blue", holes: [] }))).toBe("body");
    expect(fieldOf(() => validateCorrection("fix it"))).toBe("body");
  });

  it("requires a tee when values are corrected", () => {
    expect(fieldOf(() => validateCorrection({ slope: 130 }))).toBe("teeId");
    expect(fieldOf(() => validateCorrection({ holes: [{ hole: 1, par: 4 }] }))).toBe("teeId");
  });

  it("applies the same ranges as course entry", () => {
    const base = { teeId: "male-blue" };
    expect(fieldOf(() => validateCorrection({ ...base, slope: 156 }))).toBe("slope");
    expect(fieldOf(() => validateCorrection({ ...base, courseRating: 0 }))).toBe("courseRating");
    expect(fieldOf(() => validateCorrection({ ...base, holes: "all" }))).toBe("holes");
    expect(fieldOf(() => validateCorrection({ ...base, holes: [{ hole: 19, par: 4 }] }))).toBe("holes[0].hole");
    expect(fieldOf(() => validateCorrection({ ...base, holes: [{ hole: 1, par: 6 }] }))).toBe("holes[0].par");
    expect(fieldOf(() => validateCorrection({ ...base, holes: [{ hole: 1, strokeIndex: 0 }] }))).toBe("holes[0].strokeIndex");
    expect(fieldOf(() => validateCorrection({ ...base, holes: [{ hole: 1, yardage: 1.5 }] }))).toBe("holes[0].yardage");
    expect(fieldOf(() => validateCorrection({ ...base, holes: [{ hole: 1 }] }))).toBe("holes[0]");
    expect(fieldOf(() => validateCorrection({ ...base, holes: [{ hole: 1, par: 4 }, { hole: 1, par: 5 }] }))).toBe("holes");
    expect(fieldOf(() => validateCorrection({ note: "x".repeat(501) }))).toBe("note");
    expect(fieldOf(() => validateCorrection({ note: 12 }))).toBe("note");
  });
});
