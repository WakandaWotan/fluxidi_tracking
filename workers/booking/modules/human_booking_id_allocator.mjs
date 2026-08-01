// RELEASE-P0 — Atomic human booking ID allocator (Option A′).
//
// Global month-scoped Durable Object counter for planned booking IDs
// shaped as YYYY-MM-NNN. Does NOT change `booking:{id}` key shape or
// the public ID format. Street rides / payment shadows / Chiron are out of scope.

export const HUMAN_BOOKING_ID_DO_FLAG = "HUMAN_BOOKING_ID_DO_ALLOCATOR";
export const HUMAN_BOOKING_ID_DO_BINDING = "HUMAN_BOOKING_ID_SEQUENCE";
export const HUMAN_BOOKING_ID_MAX_ALLOCATE_ATTEMPTS = 12;
export const HUMAN_BOOKING_ID_SEED_LIST_PAGE_LIMIT = 1000;
export const HUMAN_BOOKING_ID_SEED_MAX_PAGES = 50;

export function humanBookingIdDoEnabled(env, envFlagFn) {
  if (typeof envFlagFn !== "function") return false;
  return envFlagFn(env?.[HUMAN_BOOKING_ID_DO_FLAG]);
}

export function normalizeHumanBookingYearMonth(value) {
  const raw = String(value ?? "").trim();
  const m = raw.match(/^([0-9]{4})-([0-9]{2})$/);
  if (!m) return "";
  const month = Number(m[2]);
  if (!Number.isFinite(month) || month < 1 || month > 12) return "";
  return `${m[1]}-${m[2]}`;
}

export function formatHumanBookingId(yearMonth, seq) {
  const ym = normalizeHumanBookingYearMonth(yearMonth);
  const n = Math.trunc(Number(seq));
  if (!ym || !Number.isFinite(n) || n < 1) return "";
  // Preserve 3-digit padding; continue naturally beyond three digits.
  return `${ym}-${String(n).padStart(3, "0")}`;
}

export function parseHumanBookingIdSuffix(bookingKeyOrId, yearMonth) {
  const ym = normalizeHumanBookingYearMonth(yearMonth);
  if (!ym) return null;
  const raw = String(bookingKeyOrId ?? "").trim();
  const id = raw.startsWith("booking:") ? raw.slice("booking:".length) : raw;
  const m = id.match(new RegExp(`^${ym}-(\\d+)$`));
  if (!m) return null;
  const n = Number(m[1]);
  return Number.isFinite(n) && n > 0 ? Math.trunc(n) : null;
}

export function computeSeedFloor({ legacySeq = 0, maxExistingSuffix = 0 } = {}) {
  const a = Math.max(0, Math.trunc(Number(legacySeq) || 0));
  const b = Math.max(0, Math.trunc(Number(maxExistingSuffix) || 0));
  return Math.max(a, b);
}

/** Monotonic seed: never move the allocator backward. */
export function applySeedFloor(currentNext, seedFloor) {
  const cur = Math.max(0, Math.trunc(Number(currentNext) || 0));
  const floor = Math.max(0, Math.trunc(Number(seedFloor) || 0));
  return Math.max(cur, floor);
}

/**
 * Rollback KV sequence target = max(DO next, legacy seq, max booking suffix).
 * DO `next` is the last allocated value (not "next to allocate").
 */
export function computeRollbackSeqValue({
  doNext = 0,
  legacySeq = 0,
  maxExistingSuffix = 0,
} = {}) {
  return Math.max(
    0,
    Math.trunc(Number(doNext) || 0),
    Math.trunc(Number(legacySeq) || 0),
    Math.trunc(Number(maxExistingSuffix) || 0),
  );
}

export function humanBookingIdDoInstanceName(yearMonth) {
  return normalizeHumanBookingYearMonth(yearMonth);
}

export async function scanMaxHumanBookingSuffix(bookingKv, yearMonth, opts = {}) {
  const ym = normalizeHumanBookingYearMonth(yearMonth);
  if (!ym || !bookingKv?.list) return 0;
  const pageLimit = Math.max(
    1,
    Math.trunc(Number(opts.pageLimit) || HUMAN_BOOKING_ID_SEED_LIST_PAGE_LIMIT),
  );
  const maxPages = Math.max(
    1,
    Math.trunc(Number(opts.maxPages) || HUMAN_BOOKING_ID_SEED_MAX_PAGES),
  );
  let maxSuffix = 0;
  let cursor;
  let pages = 0;
  do {
    pages += 1;
    if (pages > maxPages) break;
    const page = await bookingKv.list({
      prefix: `booking:${ym}-`,
      limit: pageLimit,
      cursor,
    });
    for (const item of page?.keys || []) {
      const suffix = parseHumanBookingIdSuffix(item?.name, ym);
      if (suffix != null) maxSuffix = Math.max(maxSuffix, suffix);
    }
    cursor = page?.list_complete === false ? page?.cursor : null;
  } while (cursor);
  return maxSuffix;
}

export async function readLegacySeq(bookingKv, yearMonth) {
  const ym = normalizeHumanBookingYearMonth(yearMonth);
  if (!ym || !bookingKv?.get) return 0;
  const raw = await bookingKv.get(`seq:${ym}`);
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? Math.trunc(n) : 0;
}

export async function computeHumanBookingIdSeedFloor(bookingKv, yearMonth, opts = {}) {
  const ym = normalizeHumanBookingYearMonth(yearMonth);
  if (!ym) throw new Error("invalid_year_month");
  const legacySeq = await readLegacySeq(bookingKv, ym);
  const maxExistingSuffix = await scanMaxHumanBookingSuffix(bookingKv, ym, opts);
  return {
    yearMonth: ym,
    legacySeq,
    maxExistingSuffix,
    seedFloor: computeSeedFloor({ legacySeq, maxExistingSuffix }),
  };
}

/**
 * Create-if-absent for planned booking records.
 * Returns { ok:true, created:true } on first write.
 * Returns { ok:true, created:false, existing } when the same logical write is
 * allowed (upsert_same) or the existing payload matches.
 * Returns { ok:false, collision:true } when a foreign record would be overwritten.
 */
export async function putBookingCreateIfAbsent(bookingKv, bookingId, recordJson, opts = {}) {
  const id = String(bookingId ?? "").trim();
  if (!id) return { ok: false, error: "missing_booking_id" };
  if (!bookingKv?.get || !bookingKv?.put) {
    return { ok: false, error: "missing_booking_kv" };
  }
  const key = `booking:${id}`;
  const mode = String(opts.mode || "create").trim().toLowerCase();
  const existing = await bookingKv.get(key);
  if (existing != null && existing !== "") {
    if (mode === "upsert_same") {
      await bookingKv.put(key, recordJson);
      return { ok: true, created: false, updated: true, key };
    }
    if (mode === "create" && existing === recordJson) {
      return { ok: true, created: false, existing: true, key };
    }
    return {
      ok: false,
      collision: true,
      error: "booking_id_collision",
      bookingId: id,
      key,
    };
  }
  await bookingKv.put(key, recordJson);
  // Best-effort re-read race detection (KV has no CAS).
  if (opts.verifyReadback) {
    const readback = await bookingKv.get(key);
    if (readback != null && readback !== recordJson && mode === "create") {
      return {
        ok: false,
        collision: true,
        error: "booking_id_collision_race",
        bookingId: id,
        key,
      };
    }
  }
  return { ok: true, created: true, key };
}

/** In-memory DO storage used by unit tests. */
export function createMemoryDoStorage(seed = {}) {
  const store = new Map(Object.entries(seed));
  return {
    async get(key) {
      return store.has(key) ? store.get(key) : undefined;
    },
    async put(key, value) {
      store.set(key, value);
    },
    async transaction(fn) {
      // Single-threaded fake: run closure with txn API bound to same store.
      const storage = this;
      const txn = {
        get: (k) => storage.get(k),
        put: (k, v) => storage.put(k, v),
      };
      return fn(txn);
    },
    _store: store,
  };
}

export class HumanBookingIdSequenceDO {
  constructor(stateOrCtx, env) {
    this.state = stateOrCtx;
    this.env = env;
  }

  async fetch(request, init) {
    const req =
      request instanceof Request ? request : new Request(String(request), init);
    let body = {};
    try {
      body = await req.json();
    } catch (_) {
      body = {};
    }
    const action = String(body?.action || "").trim().toLowerCase();
    if (action === "allocate") return this._allocate(body);
    if (action === "seed") return this._seed(body);
    if (action === "status") return this._status(body);
    return this._json({ ok: false, error: "unknown_action" }, 400);
  }

  async _allocate(body) {
    const yearMonth =
      normalizeHumanBookingYearMonth(body?.year_month || body?.yearMonth) || "";
    if (!yearMonth) {
      return this._json({ ok: false, error: "invalid_year_month" }, 400);
    }

    // Optional one-time lazy seed supplied by the worker (never decreases).
    const seedFloorRaw = body?.seed_floor ?? body?.seedFloor;
    if (seedFloorRaw != null && seedFloorRaw !== "") {
      await this._seedInternal(yearMonth, seedFloorRaw);
    }

    const next = await this.state.storage.transaction(async (txn) => {
      const current = Math.max(0, Math.trunc(Number(await txn.get("next")) || 0));
      const nextValue = current + 1;
      await txn.put("next", nextValue);
      await txn.put("seeded", true);
      await txn.put("year_month", yearMonth);
      return nextValue;
    });

    const bookingId = formatHumanBookingId(yearMonth, next);
    return this._json({
      ok: true,
      year_month: yearMonth,
      seq: next,
      booking_id: bookingId,
      bookingId,
    });
  }

  async _seed(body) {
    const yearMonth =
      normalizeHumanBookingYearMonth(body?.year_month || body?.yearMonth) || "";
    if (!yearMonth) {
      return this._json({ ok: false, error: "invalid_year_month" }, 400);
    }
    const seedFloor = body?.seed_floor ?? body?.seedFloor ?? body?.floor;
    const result = await this._seedInternal(yearMonth, seedFloor);
    return this._json({ ok: true, ...result });
  }

  async _seedInternal(yearMonth, seedFloorRaw) {
    const floor = Math.max(0, Math.trunc(Number(seedFloorRaw) || 0));
    return this.state.storage.transaction(async (txn) => {
      const current = Math.max(0, Math.trunc(Number(await txn.get("next")) || 0));
      const next = applySeedFloor(current, floor);
      await txn.put("next", next);
      await txn.put("seeded", true);
      await txn.put("year_month", yearMonth);
      await txn.put("seed_floor_applied", floor);
      return {
        year_month: yearMonth,
        previous_next: current,
        next,
        seed_floor: floor,
        moved: next > current,
      };
    });
  }

  async _status(body) {
    const yearMonth =
      normalizeHumanBookingYearMonth(body?.year_month || body?.yearMonth) ||
      normalizeHumanBookingYearMonth(await this.state.storage.get("year_month")) ||
      "";
    const next = Math.max(0, Math.trunc(Number(await this.state.storage.get("next")) || 0));
    const seeded = (await this.state.storage.get("seeded")) === true;
    const seedFloorApplied = Math.max(
      0,
      Math.trunc(Number(await this.state.storage.get("seed_floor_applied")) || 0),
    );
    return this._json({
      ok: true,
      year_month: yearMonth,
      next,
      seeded,
      seed_floor_applied: seedFloorApplied,
    });
  }

  _json(obj, status = 200) {
    return new Response(JSON.stringify(obj), {
      status,
      headers: { "content-type": "application/json" },
    });
  }
}

/** Test helper: namespace binding that routes idFromName → DO instance. */
export function createMemoryHumanBookingIdSequenceBinding() {
  const instances = new Map();
  return {
    idFromName(name) {
      return { name: String(name || "") };
    },
    get(id) {
      const name = String(id?.name || "");
      if (!instances.has(name)) {
        const storage = createMemoryDoStorage();
        const dob = new HumanBookingIdSequenceDO({ storage }, {});
        // Real Durable Objects serialize requests per instance; mimic that
        // so parallel Promise.all allocates distinct sequences in tests.
        let chain = Promise.resolve();
        const originalFetch = dob.fetch.bind(dob);
        dob.fetch = (req, init) => {
          const run = chain.then(() => originalFetch(req, init));
          chain = run.then(
            () => undefined,
            () => undefined,
          );
          return run;
        };
        instances.set(name, dob);
      }
      return instances.get(name);
    },
    _instances: instances,
  };
}

export async function callHumanBookingIdDo(env, yearMonth, body) {
  const binding = env?.[HUMAN_BOOKING_ID_DO_BINDING];
  if (!binding?.idFromName || !binding?.get) {
    throw new Error("missing_human_booking_id_sequence_binding");
  }
  const ym = normalizeHumanBookingYearMonth(yearMonth);
  if (!ym) throw new Error("invalid_year_month");
  const stub = binding.get(binding.idFromName(humanBookingIdDoInstanceName(ym)));
  const resp = await stub.fetch(
    new Request("https://do/human-booking-id", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ...body, year_month: ym }),
    }),
  );
  const json = await resp.json().catch(() => ({}));
  if (!resp.ok || json?.ok === false) {
    const err = new Error(
      String(json?.error || `human_booking_id_do_failed_${resp.status}`),
    );
    err.status = resp.status;
    err.body = json;
    throw err;
  }
  return json;
}
