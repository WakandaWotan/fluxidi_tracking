// KV-CRON-AMPLIFIERS-P0 — per-invocation operation budget.
//
// Wraps a Workers KV namespace and counts billable ops. Throws
// KvBudgetExceededError when a cap is crossed so a scheduled job cannot
// silently resume the 3,280-read amplifier. HTTP fetch paths must NOT use
// this wrapper.

export class KvBudgetExceededError extends Error {
  constructor(kind, used, max) {
    super(`kv_budget_${kind}:${used}/${max}`);
    this.name = "KvBudgetExceededError";
    this.kind = kind;
    this.used = used;
    this.max = max;
  }
}

export function envFlagOn(value) {
  return ["1", "true", "yes", "on"].includes(String(value ?? "").trim().toLowerCase());
}

function isolateState() {
  if (!globalThis.__fluxidiKvIsolateBudget) {
    globalThis.__fluxidiKvIsolateBudget = {
      hour: "",
      day: "",
      hourReads: 0,
      dayReads: 0,
      killed: false,
      reason: null,
    };
  }
  return globalThis.__fluxidiKvIsolateBudget;
}

export function resetIsolateKvBudgetForTests() {
  const state = isolateState();
  state.hour = "";
  state.day = "";
  state.hourReads = 0;
  state.dayReads = 0;
  state.killed = false;
  state.reason = null;
}

export function noteIsolateReads(reads, options = {}) {
  const n = Math.max(0, Math.floor(Number(reads) || 0));
  const hourly = Math.max(0, Math.floor(Number(options.hourlyLimit) || 0));
  const daily = Math.max(0, Math.floor(Number(options.dailyLimit) || 0));
  const state = isolateState();
  if (options.killSwitch === true || state.killed) {
    state.killed = true;
    state.reason = state.reason || "kill_switch";
    throw new KvBudgetExceededError("kill_switch", state.hourReads, 0);
  }
  const hour = new Date().toISOString().slice(0, 13);
  const day = hour.slice(0, 10);
  if (state.hour !== hour) {
    state.hour = hour;
    state.hourReads = 0;
  }
  if (state.day !== day) {
    state.day = day;
    state.dayReads = 0;
  }
  state.hourReads += n;
  state.dayReads += n;
  if (hourly && state.hourReads > hourly) {
    state.killed = true;
    state.reason = "hourly_budget";
    throw new KvBudgetExceededError("hourly", state.hourReads, hourly);
  }
  if (daily && state.dayReads > daily) {
    state.killed = true;
    state.reason = "daily_budget";
    throw new KvBudgetExceededError("daily", state.dayReads, daily);
  }
  return { hourReads: state.hourReads, dayReads: state.dayReads };
}

export function logKvPass(label, payload) {
  try {
    console.log(`[${label}] ${JSON.stringify(payload)}`);
  } catch (_) {
    // best-effort observability
  }
}

export function wrapKvBudget(ns, options = {}) {
  const maxReads = Math.max(0, Number(options.maxReads) || 0);
  const maxLists = Math.max(0, Number(options.maxLists) || 0);
  const maxWrites = Math.max(0, Number(options.maxWrites) || 0);
  const counts = { read: 0, list: 0, write: 0, delete: 0 };
  if (!ns || typeof ns !== "object") {
    return { counts, namespace: ns };
  }

  const charge = (kind, max) => {
    counts[kind] += 1;
    if (counts[kind] > max) {
      throw new KvBudgetExceededError(kind, counts[kind], max);
    }
  };

  return {
    counts,
    get: async (...args) => {
      charge("read", maxReads);
      return ns.get(...args);
    },
    getWithMetadata: async (...args) => {
      charge("read", maxReads);
      if (typeof ns.getWithMetadata !== "function") return { value: null, metadata: null };
      return ns.getWithMetadata(...args);
    },
    list: async (...args) => {
      charge("list", maxLists);
      return ns.list(...args);
    },
    put: async (...args) => {
      charge("write", maxWrites);
      return ns.put(...args);
    },
    delete: async (...args) => {
      counts.delete += 1;
      charge("write", maxWrites);
      return ns.delete(...args);
    },
  };
}
