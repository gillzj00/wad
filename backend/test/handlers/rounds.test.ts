import type { APIGatewayProxyEventV2, APIGatewayProxyStructuredResultV2 } from "aws-lambda";
import { describe, expect, it } from "vitest";
import { createHandler } from "../../src/handlers/rounds.js";
import { RoundError, type RoundErrorKind } from "../../src/services/rounds/errors.js";
import type { RoundService } from "../../src/services/rounds/roundService.js";

const ROUTES = [
  "POST /v1/rounds",
  "GET /v1/rounds/{roundId}",
  "POST /v1/rounds/join",
  "POST /v1/rounds/{roundId}/players",
  "PUT /v1/rounds/{roundId}/scores",
  "PUT /v1/rounds/{roundId}/holes/{hole}",
  "POST /v1/rounds/{roundId}/recompute",
  "PUT /v1/rounds/{roundId}/players/{userId}/handicap",
];

function event(
  routeKey: string,
  options: { sub?: unknown; body?: unknown; rawBody?: string; roundId?: string; hole?: string; userId?: string; base64?: boolean } = {},
) {
  const sub = "sub" in options ? options.sub : "u_1";
  const text = options.rawBody ?? (options.body === undefined ? undefined : JSON.stringify(options.body));
  return {
    routeKey,
    requestContext: sub === undefined ? {} : { authorizer: { jwt: { claims: { sub }, scopes: [] } } },
    pathParameters: options.roundId
      ? { roundId: options.roundId, ...(options.hole ? { hole: options.hole } : {}), ...(options.userId ? { userId: options.userId } : {}) }
      : undefined,
    body: text !== undefined && options.base64 ? Buffer.from(text).toString("base64") : text,
    isBase64Encoded: options.base64 ?? false,
  } as unknown as APIGatewayProxyEventV2;
}

async function call(service: Partial<RoundService>, e: APIGatewayProxyEventV2) {
  const res = (await createHandler(service as RoundService)(e)) as APIGatewayProxyStructuredResultV2;
  return { status: res.statusCode, body: JSON.parse(res.body as string) };
}

const round = { roundId: "r_1", joinCode: "ABCD2F" } as never;

describe("rounds handler", () => {
  it("creates a round for the caller", async () => {
    const calls: unknown[] = [];
    const service = {
      createRound: async (userId: string, body: unknown) => {
        calls.push([userId, body]);
        return round;
      },
    };
    const res = await call(service, event("POST /v1/rounds", { body: { courseId: "c" } }));
    expect(res).toEqual({ status: 201, body: { round: { roundId: "r_1", joinCode: "ABCD2F" }, joinCode: "ABCD2F" } });
    expect(calls).toEqual([["u_1", { courseId: "c" }]]);
  });

  it("decodes a base64 body", async () => {
    const service = { joinRound: async (_userId: string, body: unknown) => ({ roundId: (body as { joinCode: string }).joinCode }) as never };
    const res = await call(service, event("POST /v1/rounds/join", { body: { joinCode: "ABCD2F" }, base64: true }));
    expect(res).toEqual({ status: 200, body: { round: { roundId: "ABCD2F" } } });
  });

  it("gets a round", async () => {
    const service = { getRound: async (userId: string, roundId: string) => ({ roundId, createdBy: userId }) as never };
    const res = await call(service, event("GET /v1/rounds/{roundId}", { roundId: "r_1", sub: "u_2" }));
    expect(res).toEqual({ status: 200, body: { round: { roundId: "r_1", createdBy: "u_2" } } });
  });

  it("joins a round", async () => {
    const service = { joinRound: async () => round };
    const res = await call(service, event("POST /v1/rounds/join", { body: { joinCode: "ABCD2F" } }));
    expect(res).toEqual({ status: 200, body: { round: { roundId: "r_1", joinCode: "ABCD2F" } } });
  });

  it("adds a guest", async () => {
    const calls: unknown[] = [];
    const service = {
      addGuest: async (...args: unknown[]) => {
        calls.push(args);
        return { round, player: { userId: "guest_1" } as never };
      },
    };
    const res = await call(service, event("POST /v1/rounds/{roundId}/players", { roundId: "r_1", body: { displayName: "Pat", handicapIndex: 10 } }));
    expect(res).toEqual({ status: 201, body: { round: { roundId: "r_1", joinCode: "ABCD2F" }, player: { userId: "guest_1" } } });
    expect(calls).toEqual([["u_1", "r_1", { displayName: "Pat", handicapIndex: 10 }]]);
  });

  it("sets a score", async () => {
    const calls: unknown[] = [];
    const service = {
      putScore: async (...args: unknown[]) => {
        calls.push(args);
        return round;
      },
    };
    const res = await call(service, event("PUT /v1/rounds/{roundId}/scores", { roundId: "r_1", sub: "u_2", body: { hole: 4, gross: 5 } }));
    expect(res).toEqual({ status: 200, body: { round: { roundId: "r_1", joinCode: "ABCD2F" } } });
    expect(calls).toEqual([["u_2", "r_1", { hole: 4, gross: 5 }]]);
  });

  it("sets a hole's events", async () => {
    const calls: unknown[] = [];
    const service = {
      putHoleEvents: async (...args: unknown[]) => {
        calls.push(args);
        return round;
      },
    };
    const body = { wadMakers: ["u_2", "u_1"], greenieWinner: null };
    const res = await call(service, event("PUT /v1/rounds/{roundId}/holes/{hole}", { roundId: "r_1", hole: "4", body }));
    expect(res).toEqual({ status: 200, body: { round: { roundId: "r_1", joinCode: "ABCD2F" } } });
    expect(calls).toEqual([["u_1", "r_1", "4", body]]);
  });

  it("sets a player's handicap override", async () => {
    const calls: unknown[] = [];
    const service = {
      putHandicapOverride: async (...args: unknown[]) => {
        calls.push(args);
        return round;
      },
    };
    const route = "PUT /v1/rounds/{roundId}/players/{userId}/handicap";
    const set = await call(service, event(route, { roundId: "r_1", userId: "guest_1", sub: "u_2", body: { courseHandicap: 15 } }));
    expect(set).toEqual({ status: 200, body: { round: { roundId: "r_1", joinCode: "ABCD2F" } } });
    const cleared = await call(service, event(route, { roundId: "r_1", userId: "u_1", body: { courseHandicap: null } }));
    expect(cleared.status).toBe(200);
    expect(calls).toEqual([
      ["u_2", "r_1", "guest_1", { courseHandicap: 15 }],
      ["u_1", "r_1", "u_1", { courseHandicap: null }],
    ]);
  });

  it("takes the player of a handicap override from the path, not the body", async () => {
    const calls: unknown[] = [];
    const service = {
      putHandicapOverride: async (...args: unknown[]) => {
        calls.push(args);
        return round;
      },
    };
    const body = { courseHandicap: 15, userId: "u_3" };
    await call(service, event("PUT /v1/rounds/{roundId}/players/{userId}/handicap", { roundId: "r_1", userId: "u_2", body }));
    expect(calls).toEqual([["u_1", "r_1", "u_2", body]]);
  });

  it("recomputes the state without a body", async () => {
    const calls: unknown[] = [];
    const service = {
      recompute: async (...args: unknown[]) => {
        calls.push(args);
        return { skins: null } as never;
      },
    };
    const res = await call(service, event("POST /v1/rounds/{roundId}/recompute", { roundId: "r_1", sub: "u_3" }));
    expect(res).toEqual({ status: 200, body: { state: { skins: null } } });
    expect(calls).toEqual([["u_3", "r_1"]]);
  });

  it.each(ROUTES)("returns 401 without a caller: %s", async (routeKey) => {
    // No service methods: the handler must not reach the service.
    for (const sub of [undefined, "", 42, null]) {
      const res = await call({}, event(routeKey, { sub, roundId: "r_1", body: {} }));
      expect(res.status).toBe(401);
      expect(res.body.error.code).toBe("unauthorized");
    }
  });

  it("ignores a user id anywhere other than the authorizer claims", async () => {
    const e = event("GET /v1/rounds/{roundId}", { sub: undefined, roundId: "r_1" });
    e.headers = { "x-user-id": "u_1", authorization: "Bearer u_1" };
    e.queryStringParameters = { userId: "u_1", sub: "u_1" };
    expect((await call({}, e)).status).toBe(401);
  });

  it.each([
    "POST /v1/rounds",
    "POST /v1/rounds/join",
    "POST /v1/rounds/{roundId}/players",
    "PUT /v1/rounds/{roundId}/scores",
    "PUT /v1/rounds/{roundId}/holes/{hole}",
    "PUT /v1/rounds/{roundId}/players/{userId}/handicap",
  ])("returns 400 for a missing or malformed body: %s", async (routeKey) => {
    for (const rawBody of [undefined, "", "{not json"]) {
      const res = await call({}, event(routeKey, { roundId: "r_1", hole: "4", userId: "u_2", ...(rawBody === undefined ? {} : { rawBody }) }));
      expect(res.status).toBe(400);
      expect(res.body.error.code).toBe("invalid_json");
    }
  });

  it.each<[RoundErrorKind, number]>([
    ["validation", 400],
    ["forbidden", 403],
    ["not_found", 404],
    ["conflict", 409],
  ])("maps a %s error to %i", async (kind, status) => {
    const service = {
      getRound: async () => {
        throw new RoundError(kind, "some_code", "some message");
      },
    };
    const res = await call(service, event("GET /v1/rounds/{roundId}", { roundId: "r_1" }));
    expect(res).toEqual({ status, body: { error: { code: "some_code", message: "some message" } } });
  });

  it("does not swallow unexpected errors", async () => {
    const service = {
      getRound: async () => {
        throw new Error("boom");
      },
    };
    await expect(call(service, event("GET /v1/rounds/{roundId}", { roundId: "r_1" }))).rejects.toThrow("boom");
  });

  it("returns 404 for an unknown route", async () => {
    const res = await call({}, event("DELETE /v1/rounds/{roundId}", { roundId: "r_1" }));
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe("route_not_found");
  });
});
