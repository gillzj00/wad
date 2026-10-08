import { ConnectionGoneError, type ConnectionPoster } from "../../../src/services/live/connectionPoster.js";
import type { LiveRegistry } from "../../../src/services/live/liveRegistry.js";

export const NOW = new Date("2026-10-05T15:00:00Z");

/** In-memory registry: the connections of each room, and the room and ttl of each connection. */
export function fakeRegistry() {
  const rooms = new Map<string, Set<string>>();
  const roomOf = new Map<string, string>();
  const ttls = new Map<string, number>();
  const registry: LiveRegistry = {
    async roomOf(connectionId) {
      return roomOf.get(connectionId) ?? null;
    },
    async join(connectionId, roundCode, ttl) {
      const previous = roomOf.get(connectionId);
      if (previous !== undefined && previous !== roundCode) rooms.get(previous)?.delete(connectionId);
      if (!rooms.has(roundCode)) rooms.set(roundCode, new Set());
      rooms.get(roundCode)!.add(connectionId);
      roomOf.set(connectionId, roundCode);
      ttls.set(connectionId, ttl);
    },
    async remove(roundCode, connectionId) {
      rooms.get(roundCode)?.delete(connectionId);
      roomOf.delete(connectionId);
    },
    async members(roundCode) {
      return [...(rooms.get(roundCode) ?? [])];
    },
  };
  return { registry, rooms, roomOf, ttls };
}

/** A poster that records what it sends. Connections in `gone` are reported gone; those in `failing` fail some other way. */
export function fakePoster() {
  const posted: { connectionId: string; data: string }[] = [];
  const gone = new Set<string>();
  const failing = new Set<string>();
  const poster: ConnectionPoster = {
    async post(connectionId, data) {
      if (gone.has(connectionId)) throw new ConnectionGoneError(connectionId);
      if (failing.has(connectionId)) throw new Error(`fake poster: ${connectionId} failed`);
      posted.push({ connectionId, data });
    },
  };
  return { poster, posted, gone, failing };
}

/** The shapes the app sends; the server does not interpret them. */
export const birdie = {
  type: "gameEvent",
  kind: "birdie",
  hole: 4,
  playerIDs: ["p1"],
  playerNames: ["Zach"],
  otherNames: ["Sam", "Alex"],
  amountCents: null,
};
export const score = { type: "score", playerID: "p1", playerName: "Zach", hole: 4, par: 4, gross: 3 };
