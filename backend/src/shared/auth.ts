import type { APIGatewayProxyEventV2, APIGatewayProxyEventV2WithJWTAuthorizer } from "aws-lambda";
import type { UserId } from "./types.js";

/** The caller's user id: the `sub` claim validated by the API Gateway JWT authorizer. */
export function callerId(event: APIGatewayProxyEventV2): UserId | null {
  const claims = (event as Partial<APIGatewayProxyEventV2WithJWTAuthorizer>).requestContext?.authorizer?.jwt?.claims;
  const sub = claims?.sub;
  return typeof sub === "string" && sub.length > 0 ? sub : null;
}
