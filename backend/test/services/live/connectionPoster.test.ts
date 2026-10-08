import { describe, expect, it } from "vitest";
import { ApiGatewayConnectionPoster, ConnectionGoneError } from "../../../src/services/live/connectionPoster.js";

function fakeClient(failure?: Error) {
  const sent: { name: string; input: unknown }[] = [];
  const client = {
    async send(cmd: { constructor: { name: string }; input: unknown }) {
      sent.push({ name: cmd.constructor.name, input: cmd.input });
      if (failure) throw failure;
      return {};
    },
  };
  return { client: client as never, sent };
}

describe("ApiGatewayConnectionPoster", () => {
  it("posts the data to the connection", async () => {
    const { client, sent } = fakeClient();
    await new ApiGatewayConnectionPoster(client).post("c1", '{"event":"pong"}');
    expect(sent).toEqual([{ name: "PostToConnectionCommand", input: { ConnectionId: "c1", Data: '{"event":"pong"}' } }]);
  });

  it("reports a gone connection, by exception name or by a 410", async () => {
    for (const failure of [
      Object.assign(new Error("Gone"), { name: "GoneException" }),
      Object.assign(new Error("Gone"), { $metadata: { httpStatusCode: 410 } }),
    ]) {
      const poster = new ApiGatewayConnectionPoster(fakeClient(failure).client);
      await expect(poster.post("c1", "{}")).rejects.toBeInstanceOf(ConnectionGoneError);
      await expect(poster.post("c1", "{}")).rejects.toMatchObject({ connectionId: "c1" });
    }
  });

  it("rethrows any other failure", async () => {
    const failure = Object.assign(new Error("Forbidden"), { name: "ForbiddenException", $metadata: { httpStatusCode: 403 } });
    await expect(new ApiGatewayConnectionPoster(fakeClient(failure).client).post("c1", "{}")).rejects.toBe(failure);
  });
});
