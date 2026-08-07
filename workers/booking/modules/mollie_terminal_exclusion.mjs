// MOLLIE-TERMINAL-UNLINK-AND-EXCLUSION-P1
//
// Pure Fluxidi-side Mollie terminal unlink/exclusion helpers.
// Never deletes or deactivates terminals at the Mollie provider.

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
  const excluded = obj.excluded === undefined ? true : _bool(obj.excluded);
  return {
    provider_terminal_id: id,
    linked: excluded ? false : obj.linked === false ? false : true,
    excluded,
    excluded_at: _str(obj.excluded_at ?? obj.excludedAt, 40) || null,
    updated_at: _str(obj.updated_at ?? obj.updatedAt, 40) || null,
  };
}

export function normalizeExcludedTerminalsMap(raw = null) {
  const src = _asObject(raw);
  const out = {};
  for (const [key, value] of Object.entries(src)) {
    const rec = normalizeExcludedTerminalRecord(value, key);
    if (!rec || !rec.excluded) continue;
    out[rec.provider_terminal_id] = rec;
  }
  return out;
}

/**
 * Merge provider-discovered terminals with durable Fluxidi exclusion state.
 * Exclusions survive sync; never invent provider DELETE.
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
    const excluded = !!(ex && ex.excluded === true);
    terminals.push({
      ...raw,
      id,
      linked: !excluded,
      excluded,
      excluded_at: excluded ? ex.excluded_at || null : null,
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
  if (act !== "unlink" && act !== "relink" && act !== "exclude" && act !== "include") {
    return { ok: false, error: "invalid_link_action" };
  }
  const next = { ...normalizeExcludedTerminalsMap(excludedMap) };
  if (act === "unlink" || act === "exclude") {
    next[id] = {
      provider_terminal_id: id,
      linked: false,
      excluded: true,
      excluded_at: next[id]?.excluded_at || now,
      updated_at: now,
    };
    return { ok: true, excluded_terminals: next, excluded: true, linked: false };
  }
  // relink / include
  delete next[id];
  return { ok: true, excluded_terminals: next, excluded: false, linked: true };
}

export function isTerminalExcluded(terminalOrId, excludedMap = null) {
  if (terminalOrId && typeof terminalOrId === "object") {
    if (terminalOrId.excluded === true) return true;
    const id = _str(terminalOrId.id ?? terminalOrId.provider_terminal_id, 120);
    const map = normalizeExcludedTerminalsMap(excludedMap);
    return !!(map[id] && map[id].excluded === true);
  }
  const id = _str(terminalOrId, 120);
  const map = normalizeExcludedTerminalsMap(excludedMap);
  return !!(map[id] && map[id].excluded === true);
}

/** Terminals eligible for Tap to Pay / active payment selection. */
export function filterSelectablePosTerminals(terminals = [], excludedMap = null) {
  const list = Array.isArray(terminals) ? terminals : [];
  const map = normalizeExcludedTerminalsMap(excludedMap);
  return list.filter((t) => {
    if (!t || typeof t !== "object") return false;
    const id = _str(t.id, 120);
    if (!id) return false;
    if (t.excluded === true) return false;
    if (map[id]?.excluded === true) return false;
    if (t.linked === false) return false;
    return true;
  });
}

export function partitionTerminalsForPresentation(terminals = []) {
  const list = Array.isArray(terminals) ? terminals : [];
  const active = [];
  const excluded = [];
  for (const t of list) {
    if (!t || typeof t !== "object") continue;
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
