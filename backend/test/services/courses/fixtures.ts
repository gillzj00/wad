import type { GcaCourse } from "../../../src/services/courses/golfCourseApi.js";

// A made-up course in GolfCourseAPI's response shape. Real provider data must
// not be committed (its terms forbid redistribution).
const pars = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 5, 3, 4, 4];
const menSi = [7, 11, 17, 3, 1, 15, 9, 5, 13, 8, 18, 2, 10, 6, 12, 16, 4, 14];
const womenSi = [5, 1, 17, 9, 3, 15, 7, 11, 13, 6, 18, 2, 12, 8, 4, 16, 10, 14];

const holes = (si: number[], yards: number) => pars.map((par, i) => ({ par, yardage: yards + i, handicap: si[i]! }));

export const gcaCourse: GcaCourse = {
  id: "7k2m9qb4",
  club_name: "Maple Hollow Golf Club",
  course_name: "North",
  scorecard_url: "https://example.com/maple-hollow-north.pdf",
  location: { address: "1 Fairway Rd, Springfield, IL", city: "Springfield", state: "IL", country: "United States", latitude: 39.8, longitude: -89.6 },
  tees: {
    male: [
      { tee_name: "Blue", course_rating: 72.1, slope_rating: 131, total_yards: 6600, par_total: 72, holes: holes(menSi, 360) },
      { tee_name: "White", course_rating: 70.3, slope_rating: 125, total_yards: 6200, par_total: 72, holes: holes(menSi, 340) },
      // Missing stroke indexes: cannot be used for handicap allocation.
      { tee_name: "Junior", course_rating: 64, slope_rating: 110, total_yards: 4000, par_total: 72, holes: pars.map((par) => ({ par, yardage: 220 })) },
    ],
    female: [
      { tee_name: "Red", course_rating: 71.4, slope_rating: 127, total_yards: 5300, par_total: 72, holes: holes(womenSi, 290) },
      // Same name as the Red tee above: must still get a unique tee id.
      { tee_name: "Red", course_rating: 70.8, slope_rating: 125, total_yards: 5100, par_total: 72, holes: holes(womenSi, 280) },
    ],
  },
};

export const gcaSearch = {
  courses: [
    {
      id: gcaCourse.id,
      club_name: gcaCourse.club_name,
      course_name: gcaCourse.course_name,
      location: gcaCourse.location,
      tees: { male: 3, female: 2 },
    },
  ],
};
