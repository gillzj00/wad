import { ConnectionGoneError, type ConnectionPoster } from "./connectionPoster.js";
import type { LiveRegistry } from "./liveRegistry.js";

/**
 * The live relay (ADR-0014): phones in the same room, keyed by a short code
 * the scoring phone chooses, receive each other's messages. The messages are
 * opaque to the server. Interim until the authoritative round sync of
 * docs/api.md exists.
 */

export const ROUND_CODE_PATTERN = /^[A-Z0-9]{6}$/;
/** Largest frame accepted, in bytes. */
export const MAX_FRAME_BYTES = 4096;
/** How long a subscription lives without being renewed; API Gateway drops a connection after two hours anyway. */
export const ROOM_TTL_SECONDS = 6 * 60 * 60;

export type LiveErrorCode = "not_subscribed" | "invalid_message" | "unknown_action";

export class LiveError extends Error {
  constructor(
    readonly code: LiveErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "LiveError";
  }
}

export type JsonObject = Record<string, unknown>;

export function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** A frame from a client: a JSON object with a string `action`, at most MAX_FRAME_BYTES. */
export function parseFrame(text: string): JsonObject & { action: string } {
  if (Buffer.byteLength(text) > MAX_FRAME_BYTES) throw new LiveError("invalid_message", `a frame is at most ${MAX_FRAME_BYTES} bytes`);
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new LiveError("invalid_message", "a frame must be JSON");
  }
  if (!isJsonObject(parsed)) throw new LiveError("invalid_message", "a frame must be a JSON object");
  const { action } = parsed;
  if (typeof action !== "string") throw new LiveError("unknown_action", "a frame needs an action");
  return { ...parsed, action };
}

export interface Subscribed {
  roundCode: string;
  /** Connections in the room, this one included. */
  members: number;
}

export interface Published {
  roundCode: string;
  /** The other connections the message reached. */
  delivered: number;
}

/** What every other member of the room receives. */
export interface RelayedMessage {
  event: "message";
  roundCode: string;
  message: JsonObject;
  sentAt: string;
}

export class LiveService {
  constructor(
    private readonly registry: LiveRegistry,
    private readonly poster: ConnectionPoster,
    private readonly now: () => Date = () => new Date(),
  ) {}

  /** Puts the connection in the room, out of any other room it was in. */
  async subscribe(connectionId: string, roundCode: unknown): Promise<Subscribed> {
    const code = validRoundCode(roundCode);
    await this.registry.join(connectionId, code, Math.floor(this.now().getTime() / 1000) + ROOM_TTL_SECONDS);
    const others = (await this.registry.members(code)).filter((id) => id !== connectionId);
    return { roundCode: code, members: others.length + 1 };
  }

  /** Sends the message to every other member of the room the connection is subscribed to. */
  async publish(connectionId: string, roundCode: unknown, message: unknown): Promise<Published> {
    const code = validRoundCode(roundCode);
    if ((await this.registry.roomOf(connectionId)) !== code) throw new LiveError("not_subscribed", `subscribe to ${code} before publishing to it`);
    if (!isJsonObject(message)) throw new LiveError("invalid_message", "message must be a JSON object");
    const relayed: RelayedMessage = { event: "message", roundCode: code, message, sentAt: this.now().toISOString() };
    const data = JSON.stringify(relayed);
    const others = (await this.registry.members(code)).filter((id) => id !== connectionId);
    const delivered = await Promise.all(others.map((id) => this.deliver(code, id, data)));
    return { roundCode: code, delivered: delivered.filter(Boolean).length };
  }

  /** Takes the connection out of its room; a no-op when it is in none. */
  async disconnect(connectionId: string): Promise<void> {
    const room = await this.registry.roomOf(connectionId);
    if (room !== null) await this.registry.remove(room, connectionId);
  }

  private async deliver(roundCode: string, connectionId: string, data: string): Promise<boolean> {
    try {
      await this.poster.post(connectionId, data);
      return true;
    } catch (err) {
      if (err instanceof ConnectionGoneError) {
        await this.registry.remove(roundCode, connectionId);
        return false;
      }
      // One receiver's failure must not keep the message from the others; the sender sees it in `delivered`.
      console.error("live relay: post to connection failed", err);
      return false;
    }
  }
}

function validRoundCode(value: unknown): string {
  if (typeof value !== "string" || !ROUND_CODE_PATTERN.test(value)) throw new LiveError("invalid_message", "roundCode must be 6 characters, A-Z or 0-9");
  return value;
}
