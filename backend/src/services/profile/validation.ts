import { isHandicapIndex, MAX_DISPLAY_NAME_LENGTH, MAX_HANDICAP_INDEX, MIN_HANDICAP_INDEX } from "../rounds/validation.js";

export const MIN_VENMO_HANDLE_LENGTH = 5;
export const MAX_VENMO_HANDLE_LENGTH = 30;

const VENMO_HANDLE = new RegExp(`^[A-Za-z0-9_-]{${MIN_VENMO_HANDLE_LENGTH},${MAX_VENMO_HANDLE_LENGTH}}$`);

export class ProfileValidationError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "ProfileValidationError";
  }
}

/** Only the fields that were sent; null clears a field. */
export interface ProfileUpdate {
  displayName?: string;
  handicapIndex?: number | null;
  venmoHandle?: string | null;
}

const invalid = (code: string, message: string) => new ProfileValidationError(code, message);

function displayName(value: unknown): string {
  const name = typeof value === "string" ? value.trim() : "";
  const length = [...name].length;
  if (length < 1 || length > MAX_DISPLAY_NAME_LENGTH) {
    throw invalid("invalid_display_name", `displayName must be 1 to ${MAX_DISPLAY_NAME_LENGTH} characters; it cannot be cleared`);
  }
  return name;
}

function handicapIndex(value: unknown): number | null {
  if (value === null) return null;
  if (!isHandicapIndex(value) || Number(value.toFixed(1)) !== value) {
    throw invalid(
      "invalid_handicap_index",
      `handicapIndex must be a number from ${MIN_HANDICAP_INDEX} to ${MAX_HANDICAP_INDEX} with at most one decimal place, or null to clear it; a plus handicap is negative`,
    );
  }
  return value === 0 ? 0 : value; // never -0
}

function venmoHandle(value: unknown): string | null {
  if (value === null) return null;
  const handle = typeof value === "string" ? value.trim().replace(/^@/, "") : "";
  if (!VENMO_HANDLE.test(handle)) {
    throw invalid(
      "invalid_venmo_handle",
      `venmoHandle must be ${MIN_VENMO_HANDLE_LENGTH} to ${MAX_VENMO_HANDLE_LENGTH} letters, digits, hyphens or underscores, or null to clear it`,
    );
  }
  return handle;
}

/** Any subset of the three fields, at least one. Other fields in the body are ignored. */
export function parseProfileUpdate(body: unknown): ProfileUpdate {
  if (typeof body !== "object" || body === null || Array.isArray(body)) throw invalid("invalid_body", "body must be an object");
  const raw = body as Record<string, unknown>;
  const update: ProfileUpdate = {};
  if (raw.displayName !== undefined) update.displayName = displayName(raw.displayName);
  if (raw.handicapIndex !== undefined) update.handicapIndex = handicapIndex(raw.handicapIndex);
  if (raw.venmoHandle !== undefined) update.venmoHandle = venmoHandle(raw.venmoHandle);
  if (Object.keys(update).length === 0) throw invalid("invalid_body", "send at least one of displayName, handicapIndex and venmoHandle");
  return update;
}
