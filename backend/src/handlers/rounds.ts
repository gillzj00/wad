// Routes: POST /v1/rounds, GET /v1/rounds/{roundId}, POST /v1/rounds/join,
// POST /v1/rounds/{roundId}/players, PUT /v1/rounds/{roundId}/scores,
// PUT /v1/rounds/{roundId}/holes/{hole}, POST /v1/rounds/{roundId}/recompute,
// PUT /v1/rounds/{roundId}/players/{userId}/handicap, PUT /v1/rounds/{roundId}/tee-order
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";
import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from "aws-lambda";
import { RoundError, type RoundErrorKind } from "../services/rounds/errors.js";
import { RoundService } from "../services/rounds/roundService.js";
import { DynamoRoundStore } from "../services/rounds/roundStore.js";
import { callerId } from "../shared/auth.js";
import { error, json } from "../shared/http.js";

const ROUTES = new Set([
  "POST /v1/rounds",
  "GET /v1/rounds/{roundId}",
  "POST /v1/rounds/join",
  "POST /v1/rounds/{roundId}/players",
  "PUT /v1/rounds/{roundId}/scores",
  "PUT /v1/rounds/{roundId}/holes/{hole}",
  "POST /v1/rounds/{roundId}/recompute",
  "PUT /v1/rounds/{roundId}/players/{userId}/handicap",
  "PUT /v1/rounds/{roundId}/tee-order",
]);

const STATUS: Record<RoundErrorKind, number> = { validation: 400, not_found: 404, forbidden: 403, conflict: 409 };

class InvalidJsonError extends Error {}

function parseBody(event: APIGatewayProxyEventV2): unknown {
  if (!event.body) throw new InvalidJsonError();
  const text = event.isBase64Encoded ? Buffer.from(event.body, "base64").toString("utf8") : event.body;
  try {
    return JSON.parse(text);
  } catch {
    throw new InvalidJsonError();
  }
}

export function createHandler(service: RoundService) {
  return async (event: APIGatewayProxyEventV2): Promise<APIGatewayProxyResultV2> => {
    if (!ROUTES.has(event.routeKey)) return error(404, "route_not_found", `no route for ${event.routeKey}`);
    const userId = callerId(event);
    if (!userId) return error(401, "unauthorized", "a valid token is required");
    const roundId = event.pathParameters?.roundId ?? "";
    try {
      switch (event.routeKey) {
        case "POST /v1/rounds": {
          const round = await service.createRound(userId, parseBody(event));
          return json(201, { round, joinCode: round.joinCode });
        }
        case "GET /v1/rounds/{roundId}":
          return json(200, { round: await service.getRound(userId, roundId) });
        case "POST /v1/rounds/join":
          return json(200, { round: await service.joinRound(userId, parseBody(event)) });
        case "PUT /v1/rounds/{roundId}/scores":
          return json(200, { round: await service.putScore(userId, roundId, parseBody(event)) });
        case "PUT /v1/rounds/{roundId}/holes/{hole}":
          return json(200, { round: await service.putHoleEvents(userId, roundId, event.pathParameters?.hole, parseBody(event)) });
        case "PUT /v1/rounds/{roundId}/players/{userId}/handicap":
          return json(200, { round: await service.putHandicapOverride(userId, roundId, event.pathParameters?.userId, parseBody(event)) });
        case "PUT /v1/rounds/{roundId}/tee-order":
          return json(200, { round: await service.putTeeOrder(userId, roundId, parseBody(event)) });
        case "POST /v1/rounds/{roundId}/recompute":
          return json(200, { state: await service.recompute(userId, roundId) });
        default:
          return json(201, await service.addGuest(userId, roundId, parseBody(event)));
      }
    } catch (err) {
      if (err instanceof InvalidJsonError) return error(400, "invalid_json", "the request body must be JSON");
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
    handlerInstance = createHandler(new RoundService(new DynamoRoundStore(db, tableName)));
  }
  return handlerInstance(event);
}
