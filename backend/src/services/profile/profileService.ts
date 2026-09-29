import type { Profile } from "../../shared/profile.js";
import type { UserId } from "../../shared/types.js";
import { isHandicapIndex } from "../rounds/validation.js";
import type { ProfileStore, StoredProfile } from "./profileStore.js";
import { parseProfileUpdate } from "./validation.js";

const EMPTY: StoredProfile = { displayName: null, handicapIndex: null, venmoHandle: null };

function toProfile(userId: UserId, stored: StoredProfile): Profile {
  // The same test the round service applies before a user can create or join a round.
  const complete = Boolean(stored.displayName?.trim()) && isHandicapIndex(stored.handicapIndex);
  return { userId, ...stored, complete };
}

/** A user reads and writes only their own profile: every call takes the caller's id. */
export class ProfileService {
  constructor(
    private readonly store: ProfileStore,
    private readonly now: () => Date = () => new Date(),
  ) {}

  async getProfile(userId: UserId): Promise<Profile> {
    return toProfile(userId, (await this.store.get(userId)) ?? EMPTY);
  }

  async updateProfile(userId: UserId, body: unknown): Promise<Profile> {
    const fields = parseProfileUpdate(body);
    return toProfile(userId, await this.store.update(userId, fields, this.now().toISOString()));
  }
}
