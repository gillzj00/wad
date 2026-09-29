import { describe, expect, it } from "vitest";
import { addDeltas, collectFromEach, zeroDeltas } from "../../src/engines/money.js";

describe("money helpers", () => {
  it("collectFromEach moves the amount from every other player to the winner", () => {
    const d = zeroDeltas(["a", "b", "c", "d"]);
    collectFromEach(d, ["a", "b", "c", "d"], "c", 500);
    expect(d).toEqual({ a: -500, b: -500, c: 1500, d: -500 });
  });

  it("rejects fractional cents", () => {
    expect(() => collectFromEach(zeroDeltas(["a", "b"]), ["a", "b"], "a", 2.5)).toThrow();
  });

  it("addDeltas sums per player", () => {
    expect(addDeltas({ a: 100, b: -100 }, { a: -50, b: 50 }, { c: 0 })).toEqual({ a: 50, b: -50, c: 0 });
  });
});
