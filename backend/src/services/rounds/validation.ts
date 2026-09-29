import type { Cents, GamesConfig } from "../../shared/types.js";
import { invalid } from "./errors.js";

/** Defaults from docs/domain-model.md, in cents. */
export const GAME_DEFAULTS = {
  skins: { baseCents: 500 },
  wad: { startCents: 700, stepCents: 200 },
  greenies: { amountCents: 500 },
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
