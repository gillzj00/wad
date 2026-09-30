import type { Cents, GamesConfig } from "../../shared/types.js";
import { invalid } from "./errors.js";

/** Defaults from docs/domain-model.md, in cents. */
export const GAME_DEFAULTS = {
  skins: { baseCents: 500 },
  wad: { startCents: 700, stepCents: 200 },
  greenies: { amountCents: 500 },
  wolf: { pointCents: 100 },
} as const satisfies Required<GamesConfig>;

export const MAX_DISPLAY_NAME_LENGTH = 40;
export const MIN_HANDICAP_INDEX = -10;
export const MAX_HANDICAP_INDEX = 54;

export interface CreateRoundInput {
  courseId: string;
  teeId: string;
  date: string;
  games: GamesConfig;
}

export interface GuestInput {
  displayName: string;
  handicapIndex: number;
}

type Fields = Record<string, unknown>;

function object(value: unknown, name: string): Fields {
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw invalid("invalid_body", `${name} must be an object`);
  return value as Fields;
}

function nonEmptyString(value: unknown, name: string): string {
  if (typeof value !== "string" || value.trim() === "") throw invalid("invalid_body", `${name} must be a non-empty string`);
  return value.trim();
}

function isCalendarDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().startsWith(value);
}

function cents(game: Fields, gameName: string, field: string, fallback: Cents): Cents {
  const value = game[field];
  if (value === undefined) return fallback;
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw invalid("invalid_amount", `games.${gameName}.${field} must be a non-negative integer number of cents`);
  }
  return value;
}

function parseGames(value: unknown): GamesConfig {
  const games: GamesConfig = {};
  for (const [name, settings] of Object.entries(object(value, "games"))) {
    const path = `games.${name}`;
    switch (name) {
      case "skins":
        games.skins = { baseCents: cents(object(settings, path), name, "baseCents", GAME_DEFAULTS.skins.baseCents) };
        break;
      case "wad": {
        const wad = object(settings, path);
        games.wad = {
          startCents: cents(wad, name, "startCents", GAME_DEFAULTS.wad.startCents),
          stepCents: cents(wad, name, "stepCents", GAME_DEFAULTS.wad.stepCents),
        };
        break;
      }
      case "greenies":
        games.greenies = { amountCents: cents(object(settings, path), name, "amountCents", GAME_DEFAULTS.greenies.amountCents) };
        break;
      default:
        throw invalid("unknown_game", `unknown game "${name}"`);
    }
  }
  return games;
}

export function parseCreateRound(body: unknown): CreateRoundInput {
  const raw = object(body, "body");
  const courseId = nonEmptyString(raw.courseId, "courseId");
  const teeId = nonEmptyString(raw.teeId, "teeId");
  const date = nonEmptyString(raw.date, "date");
  if (!isCalendarDate(date)) throw invalid("invalid_date", "date must be a calendar date formatted YYYY-MM-DD");
  if (raw.holes === 9) {
    throw invalid("nine_hole_rounds_unsupported", "9-hole rounds are not supported yet; create an 18-hole round");
  }
  if (raw.holes !== 18) throw invalid("invalid_holes", "holes must be 18");
  return { courseId, teeId, date, games: parseGames(raw.games) };
}

export function parseJoinCode(body: unknown): string {
  return nonEmptyString(object(body, "body").joinCode, "joinCode");
}

export function isHandicapIndex(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= MIN_HANDICAP_INDEX && value <= MAX_HANDICAP_INDEX;
}

/** The per-round override takes the same range as the handicap index, in whole strokes. */
export const MIN_COURSE_HANDICAP = MIN_HANDICAP_INDEX;
export const MAX_COURSE_HANDICAP = MAX_HANDICAP_INDEX;

/** The override to store; null clears it. */
export function parseHandicapOverride(body: unknown): number | null {
  const value = object(body, "body").courseHandicap;
  if (value === undefined) throw invalid("invalid_body", "courseHandicap is required; send null to clear the override");
  if (value === null) return null;
  if (typeof value !== "number" || !Number.isInteger(value) || value < MIN_COURSE_HANDICAP || value > MAX_COURSE_HANDICAP) {
    throw invalid(
      "invalid_course_handicap",
      `courseHandicap must be a whole number from ${MIN_COURSE_HANDICAP} to ${MAX_COURSE_HANDICAP}, or null to clear the override; a plus handicap is negative`,
    );
  }
  return value === 0 ? 0 : value; // never -0
}

export function parseGuest(body: unknown): GuestInput {
  const raw = object(body, "body");
  const displayName = nonEmptyString(raw.displayName, "displayName");
  if (displayName.length > MAX_DISPLAY_NAME_LENGTH) {
    throw invalid("invalid_display_name", `displayName must be at most ${MAX_DISPLAY_NAME_LENGTH} characters`);
  }
  if (!isHandicapIndex(raw.handicapIndex)) {
    throw invalid(
      "invalid_handicap_index",
      `handicapIndex must be a number from ${MIN_HANDICAP_INDEX} to ${MAX_HANDICAP_INDEX}; a plus handicap is negative`,
    );
  }
  return { displayName, handicapIndex: raw.handicapIndex };
}

export const MAX_HOLE = 18;
/** Highest gross score accepted for one hole. */
export const MAX_GROSS = 20;
const MAX_WAD_MAKERS = 4;

export interface ScoreInput {
  hole: number;
  /** Null clears the score. */
  gross: number | null;
  /** Left out: the caller. */
  userId?: string;
}

/** Only the fields that were sent are written. */
export interface HoleEventsInput {
  wadMakers?: string[];
  greenieWinner?: string | null;
}

function holeNumber(value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1 || value > MAX_HOLE) {
    throw invalid("invalid_hole", `hole must be a whole number from 1 to ${MAX_HOLE}`);
  }
  return value;
}

/** The `{hole}` path parameter: "4" or "04". */
export function parseHoleParam(value: string | undefined): number {
  return holeNumber(value !== undefined && /^\d{1,2}$/.test(value) ? Number(value) : null);
}

export function parseScore(body: unknown): ScoreInput {
  const raw = object(body, "body");
  const hole = holeNumber(raw.hole);
  if (raw.gross === undefined) throw invalid("invalid_body", "gross is required; send null to clear the score");
  if (raw.gross !== null && (typeof raw.gross !== "number" || !Number.isInteger(raw.gross) || raw.gross < 1 || raw.gross > MAX_GROSS)) {
    throw invalid("invalid_gross", `gross must be a whole number from 1 to ${MAX_GROSS}, or null to clear the score`);
  }
  if (raw.userId === undefined) return { hole, gross: raw.gross };
  return { hole, gross: raw.gross, userId: nonEmptyString(raw.userId, "userId") };
}

export function parseHoleEvents(body: unknown): HoleEventsInput {
  const raw = object(body, "body");
  const input: HoleEventsInput = {};
  if (raw.wadMakers !== undefined) {
    if (!Array.isArray(raw.wadMakers) || raw.wadMakers.length > MAX_WAD_MAKERS) {
      throw invalid("invalid_body", `wadMakers must be a list of at most ${MAX_WAD_MAKERS} user ids`);
    }
    const makers = raw.wadMakers.map((m, i) => nonEmptyString(m, `wadMakers[${i}]`));
    if (new Set(makers).size !== makers.length) {
      throw invalid("duplicate_wad_maker", "a player can make the wad only once on a hole");
    }
    input.wadMakers = makers;
  }
  if (raw.greenieWinner !== undefined) {
    input.greenieWinner = raw.greenieWinner === null ? null : nonEmptyString(raw.greenieWinner, "greenieWinner");
  }
  if (input.wadMakers === undefined && input.greenieWinner === undefined) {
    throw invalid("invalid_body", "send wadMakers, greenieWinner or both");
  }
  return input;
}
