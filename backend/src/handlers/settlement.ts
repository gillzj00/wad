// Routes: GET /v1/rounds/{roundId}/settlement,
// POST and DELETE /v1/rounds/{roundId}/settlement/transfers/{transferId}/paid
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";
import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from "aws-lambda";
import { RoundError, type RoundErrorKind } from "../services/rounds/errors.js";
import { DynamoRoundStore } from "../services/rounds/roundStore.js";
import { SettlementService } from "../services/rounds/settlementService.js";
import { callerId } from "../shared/auth.js";
import { error, json } from "../shared/http.js";

const ROUTES = new Set([
  "GET /v1/rounds/{roundId}/settlement",
  "POST /v1/rounds/{roundId}/settlement/transfers/{transferId}/paid",
  "DELETE /v1/rounds/{roundId}/settlement/transfers/{transferId}/paid",
]);

const STATUS: Record<RoundErrorKind, number> = { validation: 400, not_found: 404, forbidden: 403, conflict: 409 };

export function createHandler(service: SettlementService) {
  return async (event: APIGatewayProxyEventV2): Promise<APIGatewayProxyResultV2> => {
    if (!ROUTES.has(event.routeKey)) return error(404, "route_not_found", `no route for ${event.routeKey}`);
    const userId = callerId(event);
    if (!userId) return error(401, "unauthorized", "a valid token is required");
    const roundId = event.pathParameters?.roundId ?? "";
    const transferId = event.pathParameters?.transferId ?? "";
    try {
      switch (event.routeKey) {
        case "GET /v1/rounds/{roundId}/settlement":
          return json(200, { settlement: await service.getSettlement(userId, roundId) });
        case "POST /v1/rounds/{roundId}/settlement/transfers/{transferId}/paid":
          return json(200, { settlement: await service.markPaid(userId, roundId, transferId) });
        default:
          return json(200, { settlement: await service.markUnpaid(userId, roundId, transferId) });
      }
    } catch (err) {
      if (err instanceof RoundError) return error(STATUS[err.kind], err.code, err.message);
      throw err;
    }
  };
}

let handlerInstance: ReturnType<typeof createHandler> | undefined;

export async function handler(event: APIGatewayProxyEventV2): Promise<APIGatewayProxyResultV2> {
  if (!handlerInstance) {
    const tableName = process.env.TABLE_NAME;
    if (!tableName) throw new Error("missing environment variable TABLE_NAME");
    const db = DynamoDBDocumentClient.from(new DynamoDBClient({}));
    handlerInstance = createHandler(new SettlementService(new DynamoRoundStore(db, tableName)));
  }
  return handlerInstance(event);
}
