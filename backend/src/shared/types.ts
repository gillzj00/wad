// Domain types shared by the engines and handlers. They mirror docs/api.md;
// keep the two in sync.

/** Money is always integer cents. */
export type Cents = number;

export type UserId = string;

export interface HoleInfo {
  /** 1-based hole number. */
  hole: number;
  par: number;
  /** 1 = hardest hole on the course. */
  strokeIndex: number;
}

export interface Player {
  userId: UserId;
  displayName: string;
  courseHandicap: number;
}

export interface Score {
  userId: UserId;
  hole: number;
  gross: number;
}

export interface HoleEvents {
  hole: number;
  /** Players whose first putt was holed from at least a flagstick's length, in the order made. */
  wadMakers: UserId[];
  /** Par 3s only; must have scored par or better. */
  greenieWinner: UserId | null;
  /** Wolf only; absent when nothing is recorded for the hole. */
  wolf?: WolfEvent;
}

export type WolfChoice = "partner" | "lone";

/**
 * What the group recorded for Wolf on a hole. The record can be wrong (a
 * partner together with "lone", say); the wolf engine reports that, it is not
 * prevented by the type.
 */
export interface WolfEvent {
  /** The Wolf takes one partner, or plays alone. Null or absent: not chosen yet. */
  choice?: WolfChoice | null;
  /** The partner, with choice "partner". */
  partnerUserId?: UserId | null;
  /**
   * Who the Wolf is. Only needed on holes 17 and 18 when players are tied for
   * last place; elsewhere the engine derives the Wolf and checks this against it.
   */
  wolfUserId?: UserId | null;
}

export interface GamesConfig {
  /** `carryover` left out means true: a pushed hole's value carries to the next hole. */
  skins?: { baseCents: Cents; carryover?: boolean };
  wad?: { startCents: Cents; stepCents: Cents };
  greenies?: { amountCents: Cents };
  /** Needs exactly four players. */
  wolf?: { pointCents: Cents };
}

/** Net money change per player; positive = owed to them. Sums to zero. */
export type Deltas = Record<UserId, Cents>;

export type TeeGender = "male" | "female";

export interface CourseHole {
  hole: number;
  par: number;
  /** Null when the source has no stroke index for the hole. */
  strokeIndex: number | null;
  yardage: number | null;
}

export interface Tee {
  /** Stable within a course, e.g. "male-blue". */
  teeId: string;
  name: string;
  gender: TeeGender;
  courseRating: number | null;
  slope: number | null;
  par: number;
  totalYards: number | null;
  holes: CourseHole[];
  /** Every hole has a stroke index and they are unique, so handicaps can be allocated. */
  strokeIndexValid: boolean;
}

export interface CourseLocation {
  address: string | null;
  city: string | null;
  state: string | null;
  country: string | null;
  latitude: number | null;
  longitude: number | null;
}

export interface CourseSummary {
  courseId: string;
  clubName: string;
  courseName: string;
  location: CourseLocation;
}

export interface Course extends CourseSummary {
  source: "golfcourseapi" | "manual";
  scorecardUrl: string | null;
  tees: Tee[];
  /** ISO timestamp of when the data was fetched or entered. */
  fetchedAt: string;
}
