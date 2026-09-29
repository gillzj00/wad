import type { APIGatewayProxyResultV2 } from "aws-lambda";

export function json(statusCode: number, body: unknown): APIGatewayProxyResultV2 {
  return { statusCode, headers: { "content-type": "application/json" }, body: JSON.stringify(body) };
}

/** Error body format from docs/api.md. */
export function error(statusCode: number, code: string, message: string): APIGatewayProxyResultV2 {
  return json(statusCode, { error: { code, message } });
}
