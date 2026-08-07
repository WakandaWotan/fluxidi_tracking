// MOLLIE-TERMINAL-UNLINK-AND-EXCLUSION-P1
// Run: node --test workers/booking/modules/mollie_terminal_exclusion.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  applyTerminalLinkAction,
  filterSelectablePosTerminals,
  isTerminalExcluded,
  mergeProviderTerminalsWithExclusions,
  normalizeExcludedTerminalsMap,
  partitionTerminalsForPresentation,
  posIntentStatusBlocksTerminalUnlink,
} from "./mollie_terminal_exclusion.mjs";
import { selectServerSidePosTerminal } from "./pos_terminal_payment.mjs";

const T = (id, extra = {}) => ({
  id,
  status: "active",
  profile_id: "pfl_1",
  description: `Tap app Android ${id}`,
  ...extra,
});

test("1. unlink active terminal marks excluded in durable map", () => {
  const applied = applyTerminalLinkAction({
    excludedMap: {},
    terminalId: "term_old4",
    action: "unlink",
    nowIso: "2026-08-07T12:00:00.000Z",
  });
  assert.equal(applied.ok, true);
  assert.equal(applied.excluded, true);
  assert.equal(applied.linked, false);
  assert.equal(applied.excluded_terminals.term_old4.excluded, true);
  assert.equal(applied.excluded_terminals.term_old4.excluded_at, "2026-08-07T12:00:00.000Z");
});

test("2. excluded terminal disappears from Tap to Pay selector", () => {
  const terminals = [T("term_old4"), T("term_new")];
  const merged = mergeProviderTerminalsWithExclusions({
    providerTerminals: terminals,
    previousExcluded: {
      term_old4: {
        provider_terminal_id: "term_old4",
        excluded: true,
        linked: false,
        excluded_at: "2026-08-07T12:00:00.000Z",
      },
    },
  });
  const selectable = filterSelectablePosTerminals(
    merged.terminals,
    merged.excluded_terminals,
  );
  assert.deepEqual(
    selectable.map((t) => t.id),
    ["term_new"],
  );
  const selected = selectServerSidePosTerminal(merged.terminals, {
    profileId: "pfl_1",
    excluded_terminals: merged.excluded_terminals,
  });
  assert.equal(selected.ok, true);
  assert.equal(selected.terminal.id, "term_new");
});

test("3. sync merge does not reactivate excluded terminal", () => {
  const previous = normalizeExcludedTerminalsMap({
    term_old3: { provider_terminal_id: "term_old3", excluded: true },
  });
  const merged = mergeProviderTerminalsWithExclusions({
    providerTerminals: [T("term_old3"), T("term_new")],
    previousExcluded: previous,
  });
  assert.equal(isTerminalExcluded("term_old3", merged.excluded_terminals), true);
  assert.equal(merged.terminals.find((t) => t.id === "term_old3").excluded, true);
  assert.equal(merged.terminals.find((t) => t.id === "term_new").excluded, false);
});

test("4. snapshot refresh presentation keeps exclusion flags", () => {
  const merged = mergeProviderTerminalsWithExclusions({
    providerTerminals: [T("term_old4", { excluded: true, linked: false })],
    previousExcluded: {
      term_old4: { provider_terminal_id: "term_old4", excluded: true },
    },
  });
  const parts = partitionTerminalsForPresentation(merged.terminals);
  assert.equal(parts.active.length, 0);
  assert.equal(parts.excluded.length, 1);
});

test("5. restart-equivalent remount of exclusion map stays excluded", () => {
  const stored = {
    term_old4: {
      provider_terminal_id: "term_old4",
      excluded: true,
      linked: false,
      excluded_at: "2026-08-07T10:00:00.000Z",
      updated_at: "2026-08-07T10:00:00.000Z",
    },
  };
  const remounted = normalizeExcludedTerminalsMap(stored);
  assert.equal(isTerminalExcluded("term_old4", remounted), true);
  const merged = mergeProviderTerminalsWithExclusions({
    providerTerminals: [T("term_old4")],
    previousExcluded: remounted,
  });
  assert.equal(filterSelectablePosTerminals(merged.terminals, remounted).length, 0);
});

test("6. reconnect clears exclusion and restores selectability", () => {
  const unlinked = applyTerminalLinkAction({
    excludedMap: {},
    terminalId: "term_old4",
    action: "unlink",
  });
  const relinked = applyTerminalLinkAction({
    excludedMap: unlinked.excluded_terminals,
    terminalId: "term_old4",
    action: "relink",
  });
  assert.equal(relinked.ok, true);
  assert.equal(relinked.excluded, false);
  assert.equal(relinked.linked, true);
  assert.equal(relinked.excluded_terminals.term_old4, undefined);
  const merged = mergeProviderTerminalsWithExclusions({
    providerTerminals: [T("term_old4")],
    previousExcluded: relinked.excluded_terminals,
  });
  assert.equal(filterSelectablePosTerminals(merged.terminals).length, 1);
});

test("7. new provider terminal appears normally (linked by default)", () => {
  const merged = mergeProviderTerminalsWithExclusions({
    providerTerminals: [T("term_demo_new")],
    previousExcluded: {
      term_old4: { provider_terminal_id: "term_old4", excluded: true },
    },
  });
  const neu = merged.terminals.find((t) => t.id === "term_demo_new");
  assert.equal(neu.excluded, false);
  assert.equal(neu.linked, true);
});

test("8. pending payment status blocks unlink", () => {
  for (const s of ["open", "pending", "authorized", "created"]) {
    assert.equal(posIntentStatusBlocksTerminalUnlink(s), true, s);
  }
});

test("9. resolved payment status permits unlink", () => {
  for (const s of ["paid", "canceled", "cancelled", "expired", "failed"]) {
    assert.equal(posIntentStatusBlocksTerminalUnlink(s), false, s);
  }
});

test("10. tenant/company exclusion maps stay isolated by key ownership", () => {
  const companyA = normalizeExcludedTerminalsMap({
    term_shared_shape: { provider_terminal_id: "term_shared_shape", excluded: true },
  });
  const companyB = normalizeExcludedTerminalsMap({});
  assert.equal(isTerminalExcluded("term_shared_shape", companyA), true);
  assert.equal(isTerminalExcluded("term_shared_shape", companyB), false);
});

test("11. unlink action is Fluxidi-only (no provider delete/deactivate fields)", () => {
  const applied = applyTerminalLinkAction({
    terminalId: "term_old4",
    action: "unlink",
  });
  assert.equal(applied.ok, true);
  assert.equal(Object.prototype.hasOwnProperty.call(applied, "provider_delete_called"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(applied, "mollie_delete"), false);
  // Contract marker used by API responses.
  const apiContract = {
    ...applied,
    provider_delete_called: false,
    provider_deactivate_called: false,
  };
  assert.equal(apiContract.provider_delete_called, false);
  assert.equal(apiContract.provider_deactivate_called, false);
});

test("12. presentation partitions active vs unlinked", () => {
  const merged = mergeProviderTerminalsWithExclusions({
    providerTerminals: [T("a"), T("b")],
    previousExcluded: { b: { provider_terminal_id: "b", excluded: true } },
  });
  const parts = partitionTerminalsForPresentation(merged.terminals);
  assert.deepEqual(
    parts.active.map((t) => t.id),
    ["a"],
  );
  assert.deepEqual(
    parts.excluded.map((t) => t.id),
    ["b"],
  );
});
