import type { APIGatewayProxyEventV2, APIGatewayProxyStructuredResultV2 } from "aws-lambda";
import { describe, expect, it } from "vitest";
import { createHandler } from "../../src/handlers/settlement.js";
import { RoundError, type RoundErrorKind } from "../../src/services/rounds/errors.js";
import type { SettlementService } from "../../src/services/rounds/settlementService.js";

const GET = "GET /v1/rounds/{roundId}/settlement";
const PAID = "POST /v1/rounds/{roundId}/settlement/transfers/{transferId}/paid";
const UNPAID = "DELETE /v1/rounds/{roundId}/settlement/transfers/{transferId}/paid";

function event(routeKey: string, options: { sub?: unknown; roundId?: string; transferId?: string } = {}) {
  const sub = "sub" in options ? options.sub : "u_1";
  return {
    routeKey,
    requestContext: sub === undefined ? {} : { authorizer: { jwt: { claims: { sub }, scopes: [] } } },
    pathParameters: { roundId: options.roundId ?? "r_1", ...(options.transferId ? { transferId: options.transferId } : {}) },
    isBase64Encoded: false,
  } as unknown as APIGatewayProxyEventV2;
}

async function call(service: Partial<SettlementService>, e: APIGatewayProxyEventV2) {
  const res = (await createHandler(service as SettlementService)(e)) as APIGatewayProxyStructuredResultV2;
  return { status: res.statusCode, body: JSON.parse(res.body as string) };
}

const settlement = { roundId: "r_1", status: "final" } as never;

describe("settlement handler", () => {
  it("gets the settlement for the caller", async () => {
    const calls: unknown[] = [];
    const service = {
      getSettlement: async (...args: unknown[]) => {
        calls.push(args);
        return settlement;
      },
    };
    const res = await call(service, event(GET, { sub: "u_2" }));
    expect(res).toEqual({ status: 200, body: { settlement: { roundId: "r_1", status: "final" } } });
    expect(calls).toEqual([["u_2", "r_1"]]);
  });

  it("marks a transfer paid without a body", async () => {
    const calls: unknown[] = [];
    const service = {
      markPaid: async (...args: unknown[]) => {
        calls.push(args);
        return settlement;
      },
    };
    const res = await call(service, event(PAID, { sub: "u_3", transferId: "t_abc" }));
    expect(res).toEqual({ status: 200, body: { settlement: { roundId: "r_1", status: "final" } } });
    expect(calls).toEqual([["u_3", "r_1", "t_abc"]]);
  });

  it("marks a transfer unpaid", async () => {
    const calls: unknown[] = [];
    const service = {
      markUnpaid: async (...args: unknown[]) => {
        calls.push(args);
        return settlement;
      },
    };
    const res = await call(service, event(UNPAID, { transferId: "t_abc" }));
    expect(res).toEqual({ status: 200, body: { settlement: { roundId: "r_1", status: "final" } } });
    expect(calls).toEqual([["u_1", "r_1", "t_abc"]]);
  });

  it.each([GET, PAID, UNPAID])("returns 401 without a caller: %s", async (routeKey) => {
    // No service methods: the handler must not reach the service.
    for (const sub of [undefined, "", 42, null]) {
      const res = await call({}, event(routeKey, { sub, transferId: "t_abc" }));
      expect(res.status).toBe(401);
      expect(res.body.error.code).toBe("unauthorized");
    }
  });

  it("ignores a user id anywhere other than the authorizer claims", async () => {
    const e = event(PAID, { sub: undefined, transferId: "t_abc" });
    e.headers = { "x-user-id": "u_1", authorization: "Bearer u_1" };
    e.queryStringParameters = { userId: "u_1", sub: "u_1" };
    e.body = JSON.stringify({ userId: "u_1", paidBy: "u_1" });
    expect((await call({}, e)).status).toBe(401);
  });

  it.each<[RoundErrorKind, number]>([
    ["validation", 400],
    ["forbidden", 403],
    ["not_found", 404],
    ["conflict", 409],
  ])("maps a %s error to %i", async (kind, status) => {
    const service = {
      markPaid: async () => {
        throw new RoundError(kind, "some_code", "some message");
      },
    };
    const res = await call(service, event(PAID, { transferId: "t_abc" }));
    expect(res).toEqual({ status, body: { error: { code: "some_code", message: "some message" } } });
  });

  it("does not swallow unexpected errors", async () => {
    const service = {
      getSettlement: async () => {
        throw new Error("boom");
      },
    };
    await expect(call(service, event(GET))).rejects.toThrow("boom");
  });

  it("returns 404 for an unknown route", async () => {
    const res = await call({}, event("PUT /v1/rounds/{roundId}/settlement"));
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe("route_not_found");
  });
});
