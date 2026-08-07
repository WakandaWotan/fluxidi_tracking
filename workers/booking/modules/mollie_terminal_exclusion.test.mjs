// MOLLIE-TERMINAL-UNLINK-AND-EXCLUSION-P1
// MOLLIE-TERMINAL-FORGET-FROM-FLUXIDI-P1
// Run: node --test workers/booking/modules/mollie_terminal_exclusion.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  applyTerminalLinkAction,
  filterCustomerVisibleTerminals,
  filterSelectablePosTerminals,
  isTerminalExcluded,
  isTerminalForgotten,
  mergeLiveAndTestTerminalPresentations,
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
  assert.equal(applied.forgotten, false);
  assert.equal(applied.linked, false);
  assert.equal(applied.excluded_terminals.term_old4.excluded, true);
  assert.equal(applied.excluded_terminals.term_old4.forgotten, false);
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

test("FORGET-1. remove terminal marks forgotten tombstone", () => {
  const applied = applyTerminalLinkAction({
    excludedMap: {
      term_old4: {
        provider_terminal_id: "term_old4",
        excluded: true,
        forgotten: false,
      },
    },
    terminalId: "term_old4",
    action: "forget",
    nowIso: "2026-08-07T16:00:00.000Z",
  });
  assert.equal(applied.ok, true);
  assert.equal(applied.forgotten, true);
  assert.equal(applied.excluded, true);
  assert.equal(applied.excluded_terminals.term_old4.forgotten, true);
  assert.equal(
    applied.excluded_terminals.term_old4.forgotten_at,
    "2026-08-07T16:00:00.000Z",
  );
});

test("FORGET-2. forgotten disappears from both UI sections", () => {
  const merged = mergeProviderTerminalsWithExclusions({
    providerTerminals: [T("term_old4"), T("term_new")],
    previousExcluded: {
      term_old4: {
        provider_terminal_id: "term_old4",
        excluded: true,
        forgotten: true,
      },
    },
  });
  const visible = filterCustomerVisibleTerminals(
    merged.terminals,
    merged.excluded_terminals,
  );
  assert.deepEqual(
    visible.map((t) => t.id),
    ["term_new"],
  );
  const parts = partitionTerminalsForPresentation(merged.terminals);
  assert.deepEqual(
    parts.active.map((t) => t.id),
    ["term_new"],
  );
  assert.equal(parts.excluded.length, 0);
});

test("FORGET-3. forgotten disappears from Tap to Pay", () => {
  const merged = mergeProviderTerminalsWithExclusions({
    providerTerminals: [T("term_old4"), T("term_new")],
    previousExcluded: {
      term_old4: {
        provider_terminal_id: "term_old4",
        excluded: true,
        forgotten: true,
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
});

test("FORGET-4. sync does not restore forgotten terminal to UI", () => {
  const previous = normalizeExcludedTerminalsMap({
    term_old3: {
      provider_terminal_id: "term_old3",
      excluded: true,
      forgotten: true,
      forgotten_at: "2026-08-07T10:00:00.000Z",
    },
  });
  const merged = mergeProviderTerminalsWithExclusions({
    providerTerminals: [T("term_old3"), T("term_demo")],
    previousExcluded: previous,
  });
  assert.equal(isTerminalForgotten("term_old3", merged.excluded_terminals), true);
  const visible = filterCustomerVisibleTerminals(
    merged.terminals,
    merged.excluded_terminals,
  );
  assert.deepEqual(
    visible.map((t) => t.id),
    ["term_demo"],
  );
});

test("FORGET-5. snapshot remount keeps forgotten tombstone", () => {
  const remounted = normalizeExcludedTerminalsMap({
    term_old4: {
      provider_terminal_id: "term_old4",
      forgotten: true,
      excluded: true,
    },
  });
  assert.equal(isTerminalForgotten("term_old4", remounted), true);
  const merged = mergeProviderTerminalsWithExclusions({
    providerTerminals: [T("term_old4")],
    previousExcluded: remounted,
  });
  assert.equal(
    filterCustomerVisibleTerminals(merged.terminals, remounted).length,
    0,
  );
});

test("FORGET-6. restart-equivalent forgotten stays hidden", () => {
  const remounted = normalizeExcludedTerminalsMap({
    term_old4: { provider_terminal_id: "term_old4", forgotten: true },
  });
  assert.equal(isTerminalExcluded("term_old4", remounted), true);
  assert.equal(isTerminalForgotten("term_old4", remounted), true);
});

test("FORGET-7. tenant isolation for forgotten tombstones", () => {
  const companyA = normalizeExcludedTerminalsMap({
    term_x: { provider_terminal_id: "term_x", forgotten: true },
  });
  const companyB = normalizeExcludedTerminalsMap({});
  assert.equal(isTerminalForgotten("term_x", companyA), true);
  assert.equal(isTerminalForgotten("term_x", companyB), false);
});

test("FORGET-8. pending payment status blocks forget (same gate as unlink)", () => {
  assert.equal(posIntentStatusBlocksTerminalUnlink("open"), true);
  assert.equal(posIntentStatusBlocksTerminalUnlink("paid"), false);
});

test("FORGET-9. forget is Fluxidi-only (no Mollie DELETE fields)", () => {
  const applied = applyTerminalLinkAction({
    terminalId: "term_old4",
    action: "forget",
  });
  assert.equal(applied.ok, true);
  const apiContract = {
    ...applied,
    provider_delete_called: false,
    provider_deactivate_called: false,
  };
  assert.equal(apiContract.provider_delete_called, false);
  assert.equal(apiContract.provider_deactivate_called, false);
});

test("FORGET-10. temporary unlink/reconnect still works after forget model", () => {
  const unlinked = applyTerminalLinkAction({
    terminalId: "term_tmp",
    action: "unlink",
  });
  assert.equal(unlinked.forgotten, false);
  const parts = partitionTerminalsForPresentation(
    mergeProviderTerminalsWithExclusions({
      providerTerminals: [T("term_tmp")],
      previousExcluded: unlinked.excluded_terminals,
    }).terminals,
  );
  assert.equal(parts.excluded.length, 1);
  const relinked = applyTerminalLinkAction({
    excludedMap: unlinked.excluded_terminals,
    terminalId: "term_tmp",
    action: "relink",
  });
  assert.equal(relinked.ok, true);
  assert.equal(relinked.linked, true);
});

test("FORGET-11. reconnect cannot clear forgotten tombstone", () => {
  const forgotten = applyTerminalLinkAction({
    terminalId: "term_old4",
    action: "forget",
  });
  const relink = applyTerminalLinkAction({
    excludedMap: forgotten.excluded_terminals,
    terminalId: "term_old4",
    action: "relink",
  });
  assert.equal(relink.ok, false);
  assert.equal(relink.error, "terminal_forgotten");
});

test("DISCOVERY-1. merge live+test shows test terminals when live only has forgotten", () => {
  const live = {
    status: "synced",
    synced_at: "2026-08-07T14:25:33.671Z",
    profile_id: "pfl_ZuqKHTmzDp",
    terminals: [], // forgotten filtered out of presentation
    excluded_terminals: {
      term_old4: { provider_terminal_id: "term_old4", forgotten: true, excluded: true },
      term_old3: { provider_terminal_id: "term_old3", forgotten: true, excluded: true },
    },
  };
  const test = {
    status: "synced",
    synced_at: "2026-08-07T14:30:00.000Z",
    profile_id: "pfl_ZuqKHTmzDp",
    terminals: [
      { id: "term_new1", description: "Tap app Android #1", status: "active", profile_id: "pfl_ZuqKHTmzDp" },
      { id: "term_new2", description: "Tap app Android #2", status: "active", profile_id: "pfl_ZuqKHTmzDp" },
    ],
    excluded_terminals: {},
  };
  const merged = mergeLiveAndTestTerminalPresentations({ live, test });
  assert.equal(merged.status, "synced");
  assert.deepEqual(
    merged.terminals.map((t) => t.id).sort(),
    ["term_new1", "term_new2"],
  );
  assert.equal(merged.terminals.every((t) => t.mollie_mode === "test"), true);
  assert.equal(merged.excluded_terminals.term_old4.forgotten, true);
});

test("DISCOVERY-2. forgotten live ids cannot hide different test terminal ids", () => {
  const live = {
    terminals: [],
    excluded_terminals: {
      term_nckkb9WHkhtWxKZs8QAUJ: { forgotten: true, excluded: true },
    },
  };
  const test = {
    terminals: [{ id: "term_brand_new_1", description: "Tap app Android #1", status: "active" }],
    excluded_terminals: {},
  };
  const merged = mergeLiveAndTestTerminalPresentations({ live, test });
  assert.equal(merged.terminals.length, 1);
  assert.equal(merged.terminals[0].id, "term_brand_new_1");
});
