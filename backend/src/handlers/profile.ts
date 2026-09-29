// Routes: GET /v1/me, PUT /v1/me
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";
import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from "aws-lambda";
import { ProfileService } from "../services/profile/profileService.js";
import { DynamoProfileStore } from "../services/profile/profileStore.js";
import { ProfileValidationError } from "../services/profile/validation.js";
import { callerId } from "../shared/auth.js";
import { error, json } from "../shared/http.js";

const ROUTES = new Set(["GET /v1/me", "PUT /v1/me"]);

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

export function createHandler(service: ProfileService) {
  return async (event: APIGatewayProxyEventV2): Promise<APIGatewayProxyResultV2> => {
    if (!ROUTES.has(event.routeKey)) return error(404, "route_not_found", `no route for ${event.routeKey}`);
    // The only source of the user id: nothing in the path, query, headers or body names a user.
    const userId = callerId(event);
    if (!userId) return error(401, "unauthorized", "a valid token is required");
    try {
      if (event.routeKey === "GET /v1/me") return json(200, { profile: await service.getProfile(userId) });
      return json(200, { profile: await service.updateProfile(userId, parseBody(event)) });
    } catch (err) {
      if (err instanceof InvalidJsonError) return error(400, "invalid_json", "the request body must be JSON");
      if (err instanceof ProfileValidationError) return error(400, err.code, err.message);
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
    handlerInstance = createHandler(new ProfileService(new DynamoProfileStore(db, tableName)));
  }
  return handlerInstance(event);
}
