// MOLLIE-TERMINAL-UNLINK-AND-EXCLUSION-P1
// MOLLIE-TERMINAL-FORGET-FROM-FLUXIDI-P1
//
// Pure Fluxidi-side Mollie terminal unlink / forget helpers.
// Never deletes or deactivates terminals at the Mollie provider.
//
// States:
//  - linked: selectable for Tap to Pay (when provider-active)
//  - excluded (unlink): hidden from active list, visible under Ontkoppelde
//  - forgotten (remove from Fluxidi): tombstoned — hidden from all customer UI
//    and Tap to Pay; survives sync/snapshot/restart; provider untouched

function _str(v, max = 160) {
  return String(v ?? "").trim().slice(0, max);
}

function _asObject(v) {
  return v && typeof v === "object" && !Array.isArray(v) ? v : {};
}

function _bool(v) {
  return v === true || v === "true" || v === 1 || v === "1";
}

export function normalizeExcludedTerminalRecord(raw = null, terminalId = "") {
  const obj = _asObject(raw);
  const id = _str(obj.provider_terminal_id ?? obj.terminal_id ?? terminalId, 120);
  if (!id) return null;
  const forgotten =
    _bool(obj.forgotten) ||
    _bool(obj.removed_from_fluxidi) ||
    _bool(obj.removedFromFluxidi);
  const excluded =
    forgotten || (obj.excluded === undefined ? true : _bool(obj.excluded));
  if (!excluded && !forgotten) return null;
  return {
    provider_terminal_id: id,
    linked: false,
    excluded: true,
    forgotten: !!forgotten,
    excluded_at: _str(obj.excluded_at ?? obj.excludedAt, 40) || null,
    forgotten_at: forgotten
      ? _str(obj.forgotten_at ?? obj.forgottenAt, 40) || null
      : null,
    updated_at: _str(obj.updated_at ?? obj.updatedAt, 40) || null,
  };
}

export function normalizeExcludedTerminalsMap(raw = null) {
  const src = _asObject(raw);
  const out = {};
  for (const [key, value] of Object.entries(src)) {
    const rec = normalizeExcludedTerminalRecord(value, key);
    if (!rec) continue;
    out[rec.provider_terminal_id] = rec;
  }
  return out;
}

/**
 * Merge provider-discovered terminals with durable Fluxidi exclusion/forget state.
 * Forgotten tombstones survive sync; never invent provider DELETE.
 */
export function mergeProviderTerminalsWithExclusions({
  providerTerminals = [],
  previousExcluded = null,
  nowIso = null,
} = {}) {
  void nowIso;
  const excludedMap = normalizeExcludedTerminalsMap(previousExcluded);
  const list = Array.isArray(providerTerminals) ? providerTerminals : [];
  const terminals = [];
  for (const raw of list) {
    if (!raw || typeof raw !== "object") continue;
    const id = _str(raw.id, 120);
    if (!id) continue;
    const ex = excludedMap[id] || null;
    const forgotten = !!(ex && ex.forgotten === true);
    const excluded = forgotten || !!(ex && ex.excluded === true);
    terminals.push({
      ...raw,
      id,
      linked: !excluded,
      excluded,
      forgotten,
      excluded_at: excluded ? ex?.excluded_at || null : null,
      forgotten_at: forgotten ? ex?.forgotten_at || null : null,
    });
  }
  return {
    terminals,
    excluded_terminals: excludedMap,
  };
}

export function applyTerminalLinkAction({
  excludedMap = null,
  terminalId = "",
  action = "",
  nowIso = null,
} = {}) {
  const id = _str(terminalId, 120);
  const act = _str(action, 40).toLowerCase();
  const now = _str(nowIso, 40) || new Date().toISOString();
  if (!id) return { ok: false, error: "terminal_id_required" };
  const allowed = new Set([
    "unlink",
    "exclude",
    "relink",
    "include",
    "forget",
    "remove",
    "remove_from_fluxidi",
  ]);
  if (!allowed.has(act)) {
    return { ok: false, error: "invalid_link_action" };
  }
  const next = { ...normalizeExcludedTerminalsMap(excludedMap) };
  const existing = next[id] || null;

  if (act === "forget" || act === "remove" || act === "remove_from_fluxidi") {
    next[id] = {
      provider_terminal_id: id,
      linked: false,
      excluded: true,
      forgotten: true,
      excluded_at: existing?.excluded_at || now,
      forgotten_at: existing?.forgotten_at || now,
      updated_at: now,
    };
    return {
      ok: true,
      excluded_terminals: next,
      excluded: true,
      forgotten: true,
      linked: false,
    };
  }

  if (act === "unlink" || act === "exclude") {
    // Do not downgrade an existing forgotten tombstone back to temporary unlink.
    if (existing?.forgotten === true) {
      return {
        ok: true,
        excluded_terminals: next,
        excluded: true,
        forgotten: true,
        linked: false,
      };
    }
    next[id] = {
      provider_terminal_id: id,
      linked: false,
      excluded: true,
      forgotten: false,
      excluded_at: existing?.excluded_at || now,
      forgotten_at: null,
      updated_at: now,
    };
    return {
      ok: true,
      excluded_terminals: next,
      excluded: true,
      forgotten: false,
      linked: false,
    };
  }

  // relink / include — never clear a forgotten tombstone via reconnect.
  if (existing?.forgotten === true) {
    return { ok: false, error: "terminal_forgotten" };
  }
  delete next[id];
  return {
    ok: true,
    excluded_terminals: next,
    excluded: false,
    forgotten: false,
    linked: true,
  };
}

export function isTerminalForgotten(terminalOrId, excludedMap = null) {
  if (terminalOrId && typeof terminalOrId === "object") {
    if (terminalOrId.forgotten === true) return true;
    const id = _str(terminalOrId.id ?? terminalOrId.provider_terminal_id, 120);
    const map = normalizeExcludedTerminalsMap(excludedMap);
    return !!(map[id] && map[id].forgotten === true);
  }
  const id = _str(terminalOrId, 120);
  const map = normalizeExcludedTerminalsMap(excludedMap);
  return !!(map[id] && map[id].forgotten === true);
}

export function isTerminalExcluded(terminalOrId, excludedMap = null) {
  if (terminalOrId && typeof terminalOrId === "object") {
    if (terminalOrId.excluded === true || terminalOrId.forgotten === true) {
      return true;
    }
    const id = _str(terminalOrId.id ?? terminalOrId.provider_terminal_id, 120);
    const map = normalizeExcludedTerminalsMap(excludedMap);
    return !!(map[id] && (map[id].excluded === true || map[id].forgotten === true));
  }
  const id = _str(terminalOrId, 120);
  const map = normalizeExcludedTerminalsMap(excludedMap);
  return !!(map[id] && (map[id].excluded === true || map[id].forgotten === true));
}

/** Terminals eligible for Tap to Pay / active payment selection. */
export function filterSelectablePosTerminals(terminals = [], excludedMap = null) {
  const list = Array.isArray(terminals) ? terminals : [];
  const map = normalizeExcludedTerminalsMap(excludedMap);
  return list.filter((t) => {
    if (!t || typeof t !== "object") return false;
    const id = _str(t.id, 120);
    if (!id) return false;
    if (t.forgotten === true || t.excluded === true) return false;
    if (map[id]?.forgotten === true || map[id]?.excluded === true) return false;
    if (t.linked === false) return false;
    return true;
  });
}

/** Customer-facing terminal list: hide forgotten tombstones entirely. */
export function filterCustomerVisibleTerminals(terminals = [], excludedMap = null) {
  const list = Array.isArray(terminals) ? terminals : [];
  const map = normalizeExcludedTerminalsMap(excludedMap);
  return list.filter((t) => {
    if (!t || typeof t !== "object") return false;
    if (t.forgotten === true) return false;
    const id = _str(t.id, 120);
    if (id && map[id]?.forgotten === true) return false;
    return true;
  });
}

export function partitionTerminalsForPresentation(terminals = []) {
  const list = Array.isArray(terminals) ? terminals : [];
  const active = [];
  const excluded = [];
  for (const t of list) {
    if (!t || typeof t !== "object") continue;
    if (t.forgotten === true) continue; // removed from Fluxidi UI
    if (t.excluded === true || t.linked === false) excluded.push(t);
    else active.push(t);
  }
  return { active, excluded };
}

/** Open/pending Mollie POS statuses that still may settle. */
export function posIntentStatusBlocksTerminalUnlink(status = "") {
  const s = _str(status, 40).toLowerCase();
  return (
    s === "open" ||
    s === "pending" ||
    s === "authorized" ||
    s === "created" ||
    s === "mollie_open"
  );
}
