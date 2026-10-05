import type { APIGatewayProxyStructuredResultV2 } from "aws-lambda";
import { describe, expect, it } from "vitest";
import { createHandler, type LiveEvent } from "../../src/handlers/live.js";
import { CLIENT_TOKEN_HEADER } from "../../src/shared/clientToken.js";
import { birdie, fakePoster, fakeRegistry, NOW, score } from "../services/live/fixtures.js";

const TOKEN = "test-client-token";
const DOMAIN = "ws.example.test";
const STAGE = "live";

function setup() {
  const reg = fakeRegistry();
  const post = fakePoster();
  const endpoints: string[] = [];
  const handler = createHandler({
    registry: reg.registry,
    posterFor: (endpoint) => {
      endpoints.push(endpoint);
      return post.poster;
    },
    clientToken: async () => TOKEN,
    now: () => NOW,
  });
  const call = async (e: LiveEvent) => {
    const res = (await handler(e)) as APIGatewayProxyStructuredResultV2;
    return { status: res.statusCode, body: res.body === undefined ? undefined : JSON.parse(res.body) };
  };
  return { ...reg, ...post, endpoints, call };
}

function event(
  routeKey: string,
  connectionId: string,
  options: { headers?: Record<string, string>; body?: unknown; rawBody?: string; base64?: boolean } = {},
): LiveEvent {
  const text = options.rawBody ?? (options.body === undefined ? undefined : JSON.stringify(options.body));
  return {
    requestContext: { routeKey, connectionId, domainName: DOMAIN, stage: STAGE },
    headers: options.headers,
    body: text !== undefined && options.base64 ? Buffer.from(text).toString("base64") : text,
    isBase64Encoded: options.base64 ?? false,
  } as unknown as LiveEvent;
}

const connect = (headers?: Record<string, string>) => event("$connect", "c1", headers ? { headers } : {});
const frame = (connectionId: string, body: unknown) => event("$default", connectionId, { body });
const subscribe = (connectionId: string, roundCode = "ABC123") => frame(connectionId, { action: "subscribe", roundCode });
const publish = (connectionId: string, message: unknown, roundCode = "ABC123") => frame(connectionId, { action: "publish", roundCode, message });

describe("$connect", () => {
  it("accepts the client token, whatever the case of the header name", async () => {
    const { call, rooms, roomOf } = setup();
    expect(await call(connect({ [CLIENT_TOKEN_HEADER]: TOKEN }))).toEqual({ status: 200, body: undefined });
    expect(await call(connect({ "X-Wad-Client": TOKEN }))).toEqual({ status: 200, body: undefined });
    // Connecting subscribes to nothing.
    expect(rooms.size).toBe(0);
    expect(roomOf.size).toBe(0);
  });

  it("refuses a connection without the token or with a wrong one, and keeps the token out of the reply", async () => {
    const { call } = setup();
    for (const e of [
      connect(),
      connect({}),
      ...["", "nope", `${TOKEN}x`, TOKEN.slice(0, -1), TOKEN.toUpperCase()].map((bad) => connect({ [CLIENT_TOKEN_HEADER]: bad })),
    ]) {
      const res = await call(e);
      expect(res.status).toBe(401);
      expect(res.body.error.code).toBe("invalid_client_token");
      expect(JSON.stringify(res.body)).not.toContain(TOKEN);
    }
  });
});

describe("$default", () => {
  it("subscribes and reports the members, itself included", async () => {
    const { call } = setup();
    expect(await call(subscribe("c1"))).toEqual({ status: 200, body: { event: "subscribed", roundCode: "ABC123", members: 1 } });
    expect(await call(subscribe("c2"))).toEqual({ status: 200, body: { event: "subscribed", roundCode: "ABC123", members: 2 } });
  });

  it("moves a connection that subscribes to another room", async () => {
    const { call, rooms } = setup();
    await call(subscribe("c1"));
    await call(subscribe("c2"));
    expect((await call(subscribe("c1", "XYZ789"))).body).toEqual({ event: "subscribed", roundCode: "XYZ789", members: 1 });
    expect([...rooms.get("ABC123")!]).toEqual(["c2"]);
  });

  it("answers a bad round code with invalid_message", async () => {
    const { call } = setup();
    expect((await call(subscribe("c1", "abc123"))).body).toEqual({ event: "error", code: "invalid_message" });
    expect((await call(frame("c1", { action: "subscribe" }))).body).toEqual({ event: "error", code: "invalid_message" });
  });

  it("publishes to the other members through the stage's management endpoint", async () => {
    const { call, posted, endpoints } = setup();
    for (const id of ["c1", "c2", "c3"]) await call(subscribe(id));
    expect(await call(publish("c1", birdie))).toEqual({ status: 200, body: { event: "published", roundCode: "ABC123", delivered: 2 } });
    expect(posted.map((p) => p.connectionId)).toEqual(["c2", "c3"]);
    expect(JSON.parse(posted[0]!.data)).toEqual({ event: "message", roundCode: "ABC123", message: birdie, sentAt: NOW.toISOString() });
    expect(new Set(endpoints)).toEqual(new Set([`https://${DOMAIN}/${STAGE}`]));
    expect((await call(publish("c2", score))).body).toEqual({ event: "published", roundCode: "ABC123", delivered: 2 });
    expect(JSON.parse(posted.at(-1)!.data).message).toEqual(score);
  });

  it("refuses a publish from a connection that is not subscribed to the room", async () => {
    const { call, posted } = setup();
    await call(subscribe("c2"));
    expect((await call(publish("c1", score))).body).toEqual({ event: "error", code: "not_subscribed" });
    await call(subscribe("c1", "XYZ789"));
    expect((await call(publish("c1", score))).body).toEqual({ event: "error", code: "not_subscribed" });
    expect(posted).toEqual([]);
  });

  it("refuses a message that is not a JSON object", async () => {
    const { call, posted } = setup();
    await call(subscribe("c1"));
    await call(subscribe("c2"));
    for (const bad of ["x", 1, null, ["a"]]) expect((await call(publish("c1", bad))).body).toEqual({ event: "error", code: "invalid_message" });
    expect((await call(frame("c1", { action: "publish", roundCode: "ABC123" }))).body).toEqual({ event: "error", code: "invalid_message" });
    expect(posted).toEqual([]);
  });

  it("forgets a connection that is gone and does not count it", async () => {
    const { call, gone, rooms, posted } = setup();
    for (const id of ["c1", "c2", "c3"]) await call(subscribe(id));
    gone.add("c2");
    expect((await call(publish("c1", score))).body).toEqual({ event: "published", roundCode: "ABC123", delivered: 1 });
    expect(posted.map((p) => p.connectionId)).toEqual(["c3"]);
    expect([...rooms.get("ABC123")!]).toEqual(["c1", "c3"]);
  });

  it("refuses a frame over 4096 bytes", async () => {
    const { call, posted } = setup();
    await call(subscribe("c1"));
    await call(subscribe("c2"));
    const res = await call(publish("c1", { ...score, note: "x".repeat(4096) }));
    expect(res.body).toEqual({ event: "error", code: "invalid_message" });
    expect(posted).toEqual([]);
  });

  it("answers a ping with a pong, also when the frame is base64 encoded", async () => {
    const { call } = setup();
    expect((await call(frame("c1", { action: "ping" }))).body).toEqual({ event: "pong" });
    expect((await call(event("$default", "c1", { body: { action: "ping" }, base64: true }))).body).toEqual({ event: "pong" });
  });

  it("answers an unknown or missing action with unknown_action", async () => {
    const { call } = setup();
    expect((await call(frame("c1", { action: "dance" }))).body).toEqual({ event: "error", code: "unknown_action" });
    expect((await call(frame("c1", {}))).body).toEqual({ event: "error", code: "unknown_action" });
  });

  it("answers a frame that is not a JSON object with invalid_message", async () => {
    const { call } = setup();
    for (const rawBody of ["not json", "", "[]", '"ping"']) {
      expect((await call(event("$default", "c1", { rawBody }))).body).toEqual({ event: "error", code: "invalid_message" });
    }
    expect((await call(event("$default", "c1"))).body).toEqual({ event: "error", code: "invalid_message" });
  });
});

describe("$disconnect", () => {
  it("removes the connection from its room", async () => {
    const { call, rooms } = setup();
    await call(subscribe("c1"));
    await call(subscribe("c2"));
    expect(await call(event("$disconnect", "c1"))).toEqual({ status: 200, body: undefined });
    expect([...rooms.get("ABC123")!]).toEqual(["c2"]);
    expect((await call(publish("c2", score))).body).toEqual({ event: "published", roundCode: "ABC123", delivered: 0 });
  });

  it("is fine for a connection that never subscribed", async () => {
    const { call } = setup();
    expect((await call(event("$disconnect", "c9"))).status).toBe(200);
  });
});
