import { describe, expect, it } from "vitest";
import { handler } from "../src/handlers/health.js";

describe("health handler", () => {
  it("returns ok", async () => {
    const res = await handler();
    expect(res).toMatchObject({ statusCode: 200 });
    expect(JSON.parse((res as { body: string }).body)).toEqual({ status: "ok" });
  });
});
