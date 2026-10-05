// Routes: $connect, $disconnect and $default of the live relay WebSocket API (ADR-0014).
import { ApiGatewayManagementApiClient } from "@aws-sdk/client-apigatewaymanagementapi";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { SSMClient } from "@aws-sdk/client-ssm";
import { DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";
import type { APIGatewayProxyResultV2, APIGatewayProxyWebsocketEventV2 } from "aws-lambda";
import { ApiGatewayConnectionPoster, type ConnectionPoster } from "../services/live/connectionPoster.js";
import { DynamoLiveRegistry, type LiveRegistry } from "../services/live/liveRegistry.js";
import { LiveError, type LiveErrorCode, LiveService, parseFrame } from "../services/live/liveService.js";
import { CLIENT_TOKEN_HEADER, clientTokenMatches } from "../shared/clientToken.js";
import { error, json } from "../shared/http.js";
import { requireEnv, ssmValue } from "../shared/ssm.js";

/** The $connect event also carries the handshake headers, which the aws-lambda types leave out. */
export type LiveEvent = APIGatewayProxyWebsocketEventV2 & { headers?: Record<string, string | undefined> };

/** What the sender of a frame gets back, as the body of the $default route response. */
export type LiveReply =
  | { event: "subscribed"; roundCode: string; members: number }
  | { event: "published"; roundCode: string; delivered: number }
  | { event: "pong" }
  | { event: "error"; code: LiveErrorCode };

export interface LiveDeps {
  registry: LiveRegistry;
  /** A poster for the stage the event came through; the endpoint is https://<domainName>/<stage>. */
  posterFor: (endpoint: string) => ConnectionPoster;
  clientToken: () => Promise<string>;
  now?: () => Date;
}

/** WebSocket $connect events keep header names as the client sent them, unlike HTTP API events. */
function header(event: LiveEvent, name: string): string | undefined {
  const headers = event.headers ?? {};
  const key = Object.keys(headers).find((k) => k.toLowerCase() === name);
  return key === undefined ? undefined : headers[key];
}

function frameText(event: LiveEvent): string {
  const body = event.body ?? "";
  return event.isBase64Encoded ? Buffer.from(body, "base64").toString("utf8") : body;
}

async function reply(service: LiveService, connectionId: string, event: LiveEvent): Promise<LiveReply> {
  try {
    const frame = parseFrame(frameText(event));
    switch (frame.action) {
      case "subscribe":
        return { event: "subscribed", ...(await service.subscribe(connectionId, frame.roundCode)) };
      case "publish":
        return { event: "published", ...(await service.publish(connectionId, frame.roundCode, frame.message)) };
      case "ping":
        return { event: "pong" };
      default:
        return { event: "error", code: "unknown_action" };
    }
  } catch (err) {
    if (err instanceof LiveError) return { event: "error", code: err.code };
    throw err;
  }
}

export function createHandler(deps: LiveDeps) {
  return async (event: LiveEvent): Promise<APIGatewayProxyResultV2> => {
    const { routeKey, connectionId, domainName, stage } = event.requestContext;
    if (routeKey === "$connect") {
      // A non-2xx status makes API Gateway refuse the connection; the body is not delivered.
      if (!clientTokenMatches(header(event, CLIENT_TOKEN_HEADER), await deps.clientToken())) {
        return error(401, "invalid_client_token", `a valid ${CLIENT_TOKEN_HEADER} header is required`);
      }
      return { statusCode: 200 };
    }
    const service = new LiveService(deps.registry, deps.posterFor(`https://${domainName}/${stage}`), deps.now);
    if (routeKey === "$disconnect") {
      await service.disconnect(connectionId);
      return { statusCode: 200 };
    }
    return json(200, await reply(service, connectionId, event));
  };
}

let handlerInstance: ReturnType<typeof createHandler> | undefined;

export async function handler(event: LiveEvent): Promise<APIGatewayProxyResultV2> {
  if (!handlerInstance) {
    const db = DynamoDBDocumentClient.from(new DynamoDBClient({}));
    // The endpoint is fixed per stage, so in practice this holds one client.
    const clients = new Map<string, ApiGatewayManagementApiClient>();
    handlerInstance = createHandler({
      registry: new DynamoLiveRegistry(db, requireEnv("TABLE_NAME")),
      posterFor: (endpoint) => {
        let client = clients.get(endpoint);
        if (!client) {
          client = new ApiGatewayManagementApiClient({ endpoint });
          clients.set(endpoint, client);
        }
        return new ApiGatewayConnectionPoster(client);
      },
      clientToken: ssmValue(new SSMClient({}), requireEnv("CLIENT_TOKEN_PARAM")),
    });
  }
  return handlerInstance(event);
}
