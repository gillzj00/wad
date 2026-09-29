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
}

export interface GamesConfig {
  skins?: { baseCents: Cents };
  wad?: { startCents: Cents; stepCents: Cents };
  greenies?: { amountCents: Cents };
}

/** Net money change per player; positive = owed to them. Sums to zero. */
export type Deltas = Record<UserId, Cents>;
