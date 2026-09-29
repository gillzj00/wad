import type { APIGatewayProxyResultV2 } from "aws-lambda";

export async function handler(): Promise<APIGatewayProxyResultV2> {
  return {
    statusCode: 200,
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ status: "ok" }),
  };
}
