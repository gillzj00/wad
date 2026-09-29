import type { HoleInfo } from "../../src/shared/types.js";

// A par-72 course. Stroke index 1 is hole 5, 2 is hole 12, and so on.
const pars = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 5, 3, 4, 4];
const strokeIndexes = [7, 11, 17, 3, 1, 15, 9, 5, 13, 8, 18, 2, 10, 6, 12, 16, 4, 14];

export const course18: HoleInfo[] = pars.map((par, i) => ({
  hole: i + 1,
  par,
  strokeIndex: strokeIndexes[i]!,
}));

export const front9: HoleInfo[] = course18.slice(0, 9);
