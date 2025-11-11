// tests/client/smoke.test.ts
// Minimal Vitest smoke test for client-side suite.

import { describe, it, expect } from "vitest";

describe("smoke - client", () => {
  it("runs a trivial assertion", () => {
    expect(1 + 1).toBe(2);
  });
});
