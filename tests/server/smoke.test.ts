// tests/server/smoke.test.ts
// Minimal Vitest smoke test for server-side suite.
import { describe, it, expect } from "vitest";

describe("smoke - server", () => {
  it("runs a trivial assertion", () => {
    expect(true).toBe(true);
  });
});
