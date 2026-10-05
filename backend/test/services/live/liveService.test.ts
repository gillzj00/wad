import { describe, expect, it, vi } from "vitest";
import { LiveError, LiveService, MAX_FRAME_BYTES, parseFrame, ROOM_TTL_SECONDS } from "../../../src/services/live/liveService.js";
import { birdie, fakePoster, fakeRegistry, NOW, score } from "./fixtures.js";

function setup() {
  const clock = { now: NOW };
  const reg = fakeRegistry();
  const post = fakePoster();
  return { ...reg, ...post, clock, service: new LiveService(reg.registry, post.poster, () => clock.now) };
}

/** The LiveError code a call rejects with, or undefined when it resolves. */
async function errorCode(promise: Promise<unknown>): Promise<string | undefined> {
  try {
    await promise;
    return undefined;
  } catch (err) {
    if (err instanceof LiveError) return err.code;
    throw err;
  }
}

const relayed = (message: unknown) => ({ event: "message", roundCode: "ABC123", message, sentAt: NOW.toISOString() });

describe("subscribe", () => {
  it("puts the connection in the room and counts the members, itself included", async () => {
    const { service, rooms, ttls } = setup();
    expect(await service.subscribe("c1", "ABC123")).toEqual({ roundCode: "ABC123", members: 1 });
    expect(await service.subscribe("c2", "ABC123")).toEqual({ roundCode: "ABC123", members: 2 });
    expect([...rooms.get("ABC123")!]).toEqual(["c1", "c2"]);
    expect(ttls.get("c1")).toBe(Math.floor(NOW.getTime() / 1000) + ROOM_TTL_SECONDS);
    expect(ROOM_TTL_SECONDS).toBe(6 * 60 * 60);
  });

  it("rejects a round code that is not 6 characters of A-Z or 0-9", async () => {
    const { service, rooms } = setup();
    for (const bad of ["abc123", "ABC12", "ABC1234", "ABC-12", "ABC 12", "", 123, null, undefined, {}]) {
      expect(await errorCode(service.subscribe("c1", bad))).toBe("invalid_message");
    }
    expect(rooms.size).toBe(0);
  });

  it("moves a connection that subscribes to another room", async () => {
    const { service, rooms, roomOf } = setup();
    await service.subscribe("c1", "ABC123");
    await service.subscribe("c2", "ABC123");
    expect(await service.subscribe("c1", "XYZ789")).toEqual({ roundCode: "XYZ789", members: 1 });
    expect([...rooms.get("ABC123")!]).toEqual(["c2"]);
    expect(roomOf.get("c1")).toBe("XYZ789");
  });

  it("renews the ttl when a connection subscribes to its room again", async () => {
    const { service, rooms, ttls, clock } = setup();
    await service.subscribe("c1", "ABC123");
    clock.now = new Date(NOW.getTime() + 60_000);
    expect(await service.subscribe("c1", "ABC123")).toEqual({ roundCode: "ABC123", members: 1 });
    expect([...rooms.get("ABC123")!]).toEqual(["c1"]);
    expect(ttls.get("c1")).toBe(Math.floor(clock.now.getTime() / 1000) + ROOM_TTL_SECONDS);
  });
});

describe("publish", () => {
  it("relays the app's messages unchanged to the other members, not the sender, with the time sent", async () => {
    const { service, posted } = setup();
    await service.subscribe("c1", "ABC123");
    await service.subscribe("c2", "ABC123");
    await service.subscribe("c3", "ABC123");
    for (const message of [birdie, score]) {
      posted.length = 0;
      expect(await service.publish("c1", "ABC123", message)).toEqual({ roundCode: "ABC123", delivered: 2 });
      expect(posted.map((p) => p.connectionId)).toEqual(["c2", "c3"]);
      expect(posted.map((p) => JSON.parse(p.data))).toEqual([relayed(message), relayed(message)]);
    }
  });

  it("delivers to nobody when the sender is alone", async () => {
    const { service, posted } = setup();
    await service.subscribe("c1", "ABC123");
    expect(await service.publish("c1", "ABC123", score)).toEqual({ roundCode: "ABC123", delivered: 0 });
    expect(posted).toEqual([]);
  });

  it("rejects a publish from a connection that is not subscribed to that room", async () => {
    const { service, posted } = setup();
    await service.subscribe("c2", "ABC123");
    expect(await errorCode(service.publish("c1", "ABC123", score))).toBe("not_subscribed");
    await service.subscribe("c1", "XYZ789");
    expect(await errorCode(service.publish("c1", "ABC123", score))).toBe("not_subscribed");
    expect(await errorCode(service.publish("c1", "abc123", score))).toBe("invalid_message");
    expect(posted).toEqual([]);
  });

  it("rejects a message that is not a JSON object", async () => {
    const { service, posted } = setup();
    await service.subscribe("c1", "ABC123");
    await service.subscribe("c2", "ABC123");
    for (const bad of [null, undefined, [], "x", 1, true]) {
      expect(await errorCode(service.publish("c1", "ABC123", bad))).toBe("invalid_message");
    }
    expect(posted).toEqual([]);
  });

  it("forgets a connection that is gone and does not count it", async () => {
    const { service, posted, gone, rooms, roomOf } = setup();
    for (const id of ["c1", "c2", "c3"]) await service.subscribe(id, "ABC123");
    gone.add("c2");
    expect(await service.publish("c1", "ABC123", score)).toEqual({ roundCode: "ABC123", delivered: 1 });
    expect(posted.map((p) => p.connectionId)).toEqual(["c3"]);
    expect([...rooms.get("ABC123")!]).toEqual(["c1", "c3"]);
    expect(roomOf.has("c2")).toBe(false);
  });

  it("does not count a connection whose post failed some other way, and keeps it in the room", async () => {
    const { service, posted, failing, rooms } = setup();
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    try {
      for (const id of ["c1", "c2", "c3"]) await service.subscribe(id, "ABC123");
      failing.add("c2");
      expect(await service.publish("c1", "ABC123", score)).toEqual({ roundCode: "ABC123", delivered: 1 });
      expect(posted.map((p) => p.connectionId)).toEqual(["c3"]);
      expect([...rooms.get("ABC123")!]).toEqual(["c1", "c2", "c3"]);
      expect(log).toHaveBeenCalledTimes(1);
    } finally {
      log.mockRestore();
    }
  });
});

describe("disconnect", () => {
  it("removes the connection from its room", async () => {
    const { service, rooms, roomOf } = setup();
    await service.subscribe("c1", "ABC123");
    await service.subscribe("c2", "ABC123");
    await service.disconnect("c1");
    expect([...rooms.get("ABC123")!]).toEqual(["c2"]);
    expect(roomOf.has("c1")).toBe(false);
  });

  it("is a no-op for a connection that never subscribed", async () => {
    const { service, rooms } = setup();
    await service.disconnect("c1");
    expect(rooms.size).toBe(0);
  });
});

describe("parseFrame", () => {
  it("returns the frame with its action", () => {
    expect(parseFrame('{"action":"ping"}')).toEqual({ action: "ping" });
    expect(parseFrame('{"action":"subscribe","roundCode":"ABC123"}')).toEqual({ action: "subscribe", roundCode: "ABC123" });
  });

  it("rejects a frame over 4096 bytes, counting bytes rather than characters", () => {
    const frame = (pad: string) => JSON.stringify({ action: "publish", roundCode: "ABC123", message: { pad } });
    const room = MAX_FRAME_BYTES - Buffer.byteLength(frame(""));
    expect(parseFrame(frame("x".repeat(room))).action).toBe("publish");
    expect(() => parseFrame(frame("x".repeat(room + 1)))).toThrow(expect.objectContaining({ code: "invalid_message" }));
    // Two bytes per character: over the limit with fewer characters than bytes.
    expect(Buffer.byteLength(frame("\u00e9".repeat(room))) > MAX_FRAME_BYTES).toBe(true);
    expect(() => parseFrame(frame("\u00e9".repeat(room)))).toThrow(expect.objectContaining({ code: "invalid_message" }));
  });

  it("rejects a frame that is not a JSON object", () => {
    for (const bad of ["", "not json", "42", "[]", "null", '"ping"', '{"action":"ping"']) {
      expect(() => parseFrame(bad)).toThrow(expect.objectContaining({ code: "invalid_message" }));
    }
  });

  it("rejects a frame without a string action", () => {
    for (const bad of ["{}", '{"action":1}', '{"action":null}', '{"roundCode":"ABC123"}']) {
      expect(() => parseFrame(bad)).toThrow(expect.objectContaining({ code: "unknown_action" }));
    }
  });
});
