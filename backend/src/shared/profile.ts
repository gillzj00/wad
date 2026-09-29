import type { UserId } from "./types.js";

/** The caller's profile, as returned by GET and PUT /v1/me (docs/api.md). */
export interface Profile {
  userId: UserId;
  displayName: string | null;
  /** A plus handicap is negative. */
  handicapIndex: number | null;
  /** Stored without the leading "@". */
  venmoHandle: string | null;
  /** True when the profile has what a round needs: a display name and a handicap index. */
  complete: boolean;
}
