import { type ApiGatewayManagementApiClient, GoneException, PostToConnectionCommand } from "@aws-sdk/client-apigatewaymanagementapi";

/** Thrown by a poster when the connection no longer exists, so the caller can forget it. */
export class ConnectionGoneError extends Error {
  constructor(readonly connectionId: string) {
    super(`connection ${connectionId} is gone`);
    this.name = "ConnectionGoneError";
  }
}

/** Sends text frames to WebSocket connections. */
export interface ConnectionPoster {
  /** Rejects with ConnectionGoneError when the connection no longer exists. */
  post(connectionId: string, data: string): Promise<void>;
}

function isGone(err: unknown): boolean {
  if (err instanceof GoneException) return true;
  const e = err as { name?: unknown; $metadata?: { httpStatusCode?: unknown } } | null;
  return e?.name === "GoneException" || e?.$metadata?.httpStatusCode === 410;
}

/** Posts through the management API of one WebSocket stage (the client's endpoint is https://<domainName>/<stage>). */
export class ApiGatewayConnectionPoster implements ConnectionPoster {
  constructor(private readonly client: Pick<ApiGatewayManagementApiClient, "send">) {}

  async post(connectionId: string, data: string): Promise<void> {
    try {
      await this.client.send(new PostToConnectionCommand({ ConnectionId: connectionId, Data: data }));
    } catch (err) {
      if (isGone(err)) throw new ConnectionGoneError(connectionId);
      throw err;
    }
  }
}
