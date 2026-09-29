import { describe, expect, it } from "vitest";
import { parseProfileUpdate, ProfileValidationError } from "../../../src/services/profile/validation.js";
import { MAX_HANDICAP_INDEX, MIN_HANDICAP_INDEX } from "../../../src/services/rounds/validation.js";

function code(body: unknown): string {
  try {
    parseProfileUpdate(body);
  } catch (err) {
    if (err instanceof ProfileValidationError) return err.code;
    throw err;
  }
  throw new Error("expected the body to be rejected");
}

describe("parseProfileUpdate", () => {
  it("accepts all three fields", () => {
    expect(parseProfileUpdate({ displayName: "Zach", handicapIndex: 13.1, venmoHandle: "zach-g" })).toEqual({
      displayName: "Zach",
      handicapIndex: 13.1,
      venmoHandle: "zach-g",
    });
  });

  it("accepts any one field and leaves the others out", () => {
    expect(parseProfileUpdate({ displayName: "Zach" })).toEqual({ displayName: "Zach" });
    expect(parseProfileUpdate({ handicapIndex: 7 })).toEqual({ handicapIndex: 7 });
    expect(parseProfileUpdate({ venmoHandle: "zach-g" })).toEqual({ venmoHandle: "zach-g" });
  });

  it("ignores fields it does not know, such as ids", () => {
    expect(parseProfileUpdate({ displayName: "Zach", userId: "u_2", sub: "u_2", PK: "USER#u_2", email: "z@example.com" })).toEqual({
      displayName: "Zach",
    });
  });

  it.each([[undefined], [null], ["text"], [42], [[]], [[{ displayName: "Zach" }]]])("rejects a body that is not an object: %j", (body) => {
    expect(code(body)).toBe("invalid_body");
  });

  it("requires at least one field", () => {
    expect(code({})).toBe("invalid_body");
    expect(code({ userId: "u_2" })).toBe("invalid_body");
  });

  describe("displayName", () => {
    it("trims", () => {
      expect(parseProfileUpdate({ displayName: "  Zach G  " })).toEqual({ displayName: "Zach G" });
    });

    it("takes 1 to 40 characters", () => {
      expect(parseProfileUpdate({ displayName: "Z" })).toEqual({ displayName: "Z" });
      expect(parseProfileUpdate({ displayName: "x".repeat(40) })).toEqual({ displayName: "x".repeat(40) });
      expect(parseProfileUpdate({ displayName: ` ${"x".repeat(40)} ` })).toEqual({ displayName: "x".repeat(40) });
      expect(code({ displayName: "x".repeat(41) })).toBe("invalid_display_name");
    });

    it.each([[null], [""], ["   "], [42], [true], [["Zach"]], [{ name: "Zach" }]])("cannot be cleared or mistyped: %j", (displayName) => {
      expect(code({ displayName })).toBe("invalid_display_name");
    });
  });

  describe("handicapIndex", () => {
    it.each([[MIN_HANDICAP_INDEX], [-1.2], [0], [0.1], [13.1], [36.4], [MAX_HANDICAP_INDEX]])("accepts %d", (handicapIndex) => {
      expect(parseProfileUpdate({ handicapIndex })).toEqual({ handicapIndex });
    });

    it("uses the range of the round validation", () => {
      expect(MIN_HANDICAP_INDEX).toBe(-10);
      expect(MAX_HANDICAP_INDEX).toBe(54);
      expect(code({ handicapIndex: MIN_HANDICAP_INDEX - 0.1 })).toBe("invalid_handicap_index");
      expect(code({ handicapIndex: MAX_HANDICAP_INDEX + 0.1 })).toBe("invalid_handicap_index");
    });

    it.each([[13.15], [0.05], [-1.25], [53.99]])("rejects more than one decimal place: %d", (handicapIndex) => {
      expect(code({ handicapIndex })).toBe("invalid_handicap_index");
    });

    it.each([["13.1"], [true], [[13.1]], [{}], [Number.NaN], [Number.POSITIVE_INFINITY]])("rejects a value that is not a number: %j", (handicapIndex) => {
      expect(code({ handicapIndex })).toBe("invalid_handicap_index");
    });

    it("clears with null", () => {
      expect(parseProfileUpdate({ handicapIndex: null })).toEqual({ handicapIndex: null });
    });

    it("never stores negative zero", () => {
      expect(Object.is(parseProfileUpdate({ handicapIndex: -0 }).handicapIndex, 0)).toBe(true);
    });
  });

  describe("venmoHandle", () => {
    it("strips one leading @ and surrounding spaces", () => {
      expect(parseProfileUpdate({ venmoHandle: "@zach-g" })).toEqual({ venmoHandle: "zach-g" });
      expect(parseProfileUpdate({ venmoHandle: "  @Zach_G1  " })).toEqual({ venmoHandle: "Zach_G1" });
      expect(code({ venmoHandle: "@@zach-g" })).toBe("invalid_venmo_handle");
    });

    it("takes 5 to 30 characters, not counting the @", () => {
      expect(parseProfileUpdate({ venmoHandle: "abcde" })).toEqual({ venmoHandle: "abcde" });
      expect(parseProfileUpdate({ venmoHandle: "a".repeat(30) })).toEqual({ venmoHandle: "a".repeat(30) });
      expect(parseProfileUpdate({ venmoHandle: `@${"a".repeat(30)}` })).toEqual({ venmoHandle: "a".repeat(30) });
      expect(code({ venmoHandle: "abcd" })).toBe("invalid_venmo_handle");
      expect(code({ venmoHandle: "@abcd" })).toBe("invalid_venmo_handle");
      expect(code({ venmoHandle: "a".repeat(31) })).toBe("invalid_venmo_handle");
    });

    it.each([["zach g"], ["zach.g"], ["zach@g"], ["zach/g?x=1"], ["zach\ng"], ["zäch-g"], [""], ["@"], [42], [true], [["zach-g"]]])(
      "rejects %j",
      (venmoHandle) => {
        expect(code({ venmoHandle })).toBe("invalid_venmo_handle");
      },
    );

    it("clears with null", () => {
      expect(parseProfileUpdate({ venmoHandle: null })).toEqual({ venmoHandle: null });
    });
  });

  it("rejects the whole update when one field is invalid", () => {
    expect(code({ displayName: "Zach", handicapIndex: 99 })).toBe("invalid_handicap_index");
  });
});
