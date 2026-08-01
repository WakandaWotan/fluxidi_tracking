import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { shouldBypassRerouteCache } from "./fluxidi_navigation_worker.js";

describe("RELEASE-P0 reroute cache bypass", () => {
  it("bypasses cache for true deviation reasons", () => {
    for (const reason of [
      "off_route",
      "opposite_direction",
      "wrong_street",
      "forced_detour",
      "wrong_exit",
      "traffic",
    ]) {
      assert.equal(shouldBypassRerouteCache("reroute", reason), true, reason);
    }
  });

  it("does not bypass for manual/unknown or initial route builds", () => {
    assert.equal(shouldBypassRerouteCache("reroute", "manual"), false);
    assert.equal(shouldBypassRerouteCache("reroute", "unknown"), false);
    assert.equal(shouldBypassRerouteCache("route", "off_route"), false);
    assert.equal(shouldBypassRerouteCache("route", "opposite_direction"), false);
  });
});
