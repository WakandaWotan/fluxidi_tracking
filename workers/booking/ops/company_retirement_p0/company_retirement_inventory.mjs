import { createHash } from "node:crypto";
import {
  COMPANY_REGISTRY_MANIFEST_KEY,
  registryPageKey,
} from "../../modules/company_registry_index.mjs";
import {
  isHardProtectedCompanyCode,
} from "../../modules/company_registry_tombstone_guard.mjs";
import {
  OBSERVED_ID_MISMATCH_CODES,
  RISK_GROUPS,
  isSecretBearingKey,
} from "./company_retirement_policy.mjs";
import {
  billitOauthKey,
  bookingRecordKey,
  companyDriverActiveLinkKey,
  companyLinkCodeKey,
  companyLinkScopeKey,
  companyLogoR2Key,
  registryKeysForCode,
  scopedKeys,
} from "./company_retirement_keys.mjs";

export function sha256Hex(value) {
  return createHash("sha256").update(String(value ?? "")).digest("hex");
}

export function maskScopePart(value) {
  const text = String(value || "");
  if (!text) return null;
  return `sha256:${sha256Hex(text).slice(0, 16)}`;
}

function asObject(value) {
  if (!value) return null;
  if (typeof value === "object" && !Array.isArray(value)) return value;
  if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value);
      return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null;
    } catch {
      return null;
    }
  }
  return null;
}

export function redactValue(key, raw) {
  if (raw == null) return { present: false, sha256: null, redacted: null };
  const text = typeof raw === "string" ? raw : JSON.stringify(raw);
  const digest = sha256Hex(text);
  if (isSecretBearingKey(key)) {
    return {
      present: true,
      sha256: digest,
      bytes: text.length,
      redacted: { omitted: "secret_bearing_key" },
    };
  }
  const obj = asObject(raw);
  if (!obj) {
    return { present: true, sha256: digest, bytes: text.length, redacted: { type: typeof raw } };
  }
  const redacted = {
    company_code: obj.company_code || obj.companyCode || null,
    source: obj.source || null,
    linking_enabled: obj.linking_enabled ?? obj.linkingEnabled ?? null,
    lifecycle_status: obj.lifecycle_status || null,
    environment_class: obj.environment_class || null,
    has_display_name: Boolean(obj.display_name || obj.displayName || obj.companyName),
    has_tenant: Boolean(obj.tenant_id || obj.tenantId),
    has_company: Boolean(obj.company_id || obj.companyId),
    item_count: Array.isArray(obj.items)
      ? obj.items.length
      : (Array.isArray(obj.booking_ids) ? obj.booking_ids.length : (Array.isArray(obj.vehicles) ? obj.vehicles.length : (Array.isArray(obj.drivers) ? obj.drivers.length : null))),
    updated_at: obj.updated_at || obj.updatedAt || null,
    created_at: obj.created_at || obj.createdAt || null,
  };
  return { present: true, sha256: digest, bytes: text.length, redacted };
}

function bookingIdsFromIndex(raw) {
  const obj = asObject(raw);
  if (!obj) return [];
  const rows = obj.items || obj.bookings || obj.booking_ids || obj.ids || [];
  if (!Array.isArray(rows)) return [];
  return [...new Set(rows.map((row) => {
    if (typeof row === "string") return row;
    return row?.booking_id || row?.bookingId || row?.id || "";
  }).filter(Boolean))].slice(0, 50);
}

function paymentSignals(record) {
  const obj = asObject(record) || {};
  const booking = obj.booking && typeof obj.booking === "object" ? obj.booking : obj;
  const payment = booking.payment || obj.payment || {};
  const status = String(
    payment.status || payment.payment_status || booking.payment_status || obj.payment_status || "",
  ).toLowerCase();
  const providerRef = payment.mollie_payment_id || payment.provider_ref || booking.mollie_payment_id || "";
  const paid = /paid|captured|settled|paid_out|succeeded/.test(status) || Boolean(providerRef);
  const invoice = booking.invoice || obj.invoice || obj.document || {};
  const invoiced = Boolean(
    invoice.invoice_id
    || invoice.document_id
    || invoice.billit_id
    || booking.invoice_id
    || obj.fiscal_document_id
    || obj.document_id,
  );
  const amount = Number(payment.amount_cents ?? booking.price_cents ?? obj.amount_cents ?? 0);
  return {
    paid,
    invoiced,
    has_amount: Number.isFinite(amount) && amount > 0,
    status: status || null,
  };
}

function recentIso(iso, days = 30) {
  if (!iso) return false;
  const ms = Date.parse(iso);
  if (!Number.isFinite(ms)) return false;
  return (Date.now() - ms) < days * 24 * 60 * 60 * 1000;
}

export function classifyRiskGroup(inventory) {
  if (inventory.protected) return RISK_GROUPS.PROTECTED;
  const missing = !inventory.identity?.has_company_link
    && !inventory.identity?.has_registry_code
    && !inventory.identity?.on_registry_page;
  if (missing) return RISK_GROUPS.MISSING_OR_MISMATCH;
  if (
    inventory.counts.payments > 0
    || inventory.counts.invoices > 0
    || (inventory.counts.bookings > 0 && inventory.counts.recent_bookings > 0)
  ) {
    return RISK_GROUPS.PAYMENTS_OR_RECENT;
  }
  if (
    inventory.counts.bookings > 0
    || inventory.counts.drivers > 0
    || inventory.counts.vehicles > 0
    || inventory.counts.customers > 0
    || inventory.integrations.billit_oauth_present
    || inventory.integrations.mollie_status_present
    || inventory.integrations.chiron_present
    || inventory.counts.r2_logo > 0
  ) {
    return RISK_GROUPS.DATA_PRESENT;
  }
  return RISK_GROUPS.EMPTY_LOW;
}

export function classifyCandidate(inventory) {
  const blockers = [];
  const phaseABlockers = [];
  const risks = [];
  if (inventory.protected) {
    blockers.push("protected_company");
    phaseABlockers.push("protected_company");
  }
  if (inventory.counts.payments > 0) blockers.push("has_payments");
  if (inventory.counts.invoices > 0) blockers.push("has_invoices");
  if (inventory.counts.bookings > 0 && inventory.counts.recent_bookings > 0) {
    blockers.push("unexpected_real_usage");
  }
  if (inventory.counts.bookings > 0) risks.push("has_bookings");
  if (inventory.counts.drivers > 0) risks.push("has_drivers");
  if (inventory.counts.vehicles > 0) risks.push("has_vehicles");
  if (inventory.counts.customers > 0) risks.push("has_customers");
  if (inventory.integrations.billit_oauth_present) risks.push("billit_oauth_present_external_untouched");
  if (inventory.integrations.mollie_status_present) risks.push("mollie_status_present_external_untouched");
  if (inventory.integrations.chiron_present) risks.push("chiron_present_external_untouched");
  if (inventory.read_errors.length) {
    blockers.push("partial_failure");
    phaseABlockers.push("partial_failure");
  }
  const riskGroup = classifyRiskGroup({
    ...inventory,
    classification: undefined,
  });
  return {
    eligible: phaseABlockers.length === 0,
    phase_a_eligible: phaseABlockers.length === 0,
    phase_a_blocked: phaseABlockers.length > 0,
    phase_b_eligible: false,
    phase_b_blocked: true,
    blockers: [...new Set(blockers)],
    phase_a_blockers: [...new Set(phaseABlockers)],
    risks: [...new Set(risks)],
    risk_group: riskGroup,
  };
}

export function codesOnRegistryPages(pages = []) {
  const codes = [];
  const seen = new Set();
  for (const page of pages) {
    const pageNo = Number(page?.page || 0);
    for (const row of page?.companies || []) {
      const code = String(row?.company_code || "").trim();
      if (!code || seen.has(code)) continue;
      seen.add(code);
      codes.push({ company_code: code, page: pageNo });
    }
  }
  return codes;
}

export function reconcileObservedCodes(pageCodes, explicitCodes) {
  const explicit = new Set(explicitCodes);
  const observed = pageCodes.map((row) => row.company_code);
  const extraObserved = observed.filter((code) => (
    !explicit.has(code)
    && code !== "FLX-00001"
    && code !== "FLX-00020"
  ));
  const missingExplicit = explicitCodes.filter((code) => !observed.includes(code));
  return {
    observed_on_pages: observed,
    extra_observed_not_added: extraObserved,
    explicit_missing_from_pages: missingExplicit,
    auto_added: [],
  };
}

export async function inventoryCompany(stores, companyCode, options = {}) {
  const {
    nowIso = new Date().toISOString(),
    compact = false,
  } = options;
  const bookingKv = stores.BOOKING_KV;
  const trackingKv = stores.FLUXIDI_TRACKING;
  const invoiceKv = stores.INVOICE_KV;
  const r2 = stores.PUBLIC_MEDIA;
  const readErrors = [];
  const keysTouched = [];

  async function getStore(store, key) {
    if (!store || !key) return null;
    keysTouched.push(key);
    try {
      return await store.get(key);
    } catch (err) {
      readErrors.push({ key_kind: key.split(":")[0], error: "read_failed" });
      return null;
    }
  }

  const registry = registryKeysForCode(companyCode);
  const linkRaw = await getStore(bookingKv, companyLinkCodeKey(companyCode));
  const link = asObject(linkRaw) || {};
  const tenantId = String(link.tenant_id || link.tenantId || "");
  const companyId = String(link.company_id || link.companyId || "");
  const scopeKey = companyLinkScopeKey(tenantId, companyId);
  const scopeRaw = options.registryOnly === true
    ? null
    : (scopeKey ? await getStore(bookingKv, scopeKey) : null);
  const registryCodeRaw = await getStore(bookingKv, registry.code);
  const tombstoneRaw = await getStore(bookingKv, registry.tombstone);
  const pageHint = options.pageMembership?.get(companyCode) || null;

  const useCompact = compact === true;
  const registryOnly = options.registryOnly === true;
  const compactSuffixes = new Set([
    "business_profile:v1",
    "subscription:v1",
    "drivers:index:v1",
    "fleet:vehicles:v1",
    "bookings:list:v1",
    "chiron_connection:v1",
    "integration:mollie:status:v1",
  ]);
  const scoped = {};
  if (!registryOnly) {
    for (const key of scopedKeys(tenantId, companyId)) {
      const suffix = key.split(":").slice(4).join(":");
      if (useCompact && !compactSuffixes.has(suffix)) continue;
      scoped[suffix] = redactValue(key, await getStore(bookingKv, key));
    }
  }
  const billitKey = billitOauthKey(tenantId, companyId);
  const billitRaw = registryOnly ? null : (billitKey ? await getStore(bookingKv, billitKey) : null);
  const driverLinkRaw = registryOnly ? null : await getStore(bookingKv, companyDriverActiveLinkKey(companyCode));

  const bookingsIndex = registryOnly ? null : asObject(await getStore(bookingKv, tenantId && companyId
    ? `tenant:${tenantId}:company:${companyId}:bookings:list:v1`
    : ""));
  const bookingIds = bookingIdsFromIndex(bookingsIndex);
  let payments = 0;
  let invoices = 0;
  let recentBookings = 0;
  const bookingSummaries = [];
  for (const bookingId of bookingIds) {
    const rec = await getStore(bookingKv, bookingRecordKey(bookingId));
    const signals = paymentSignals(rec);
    if (signals.paid) payments += 1;
    if (signals.invoiced) invoices += 1;
    const obj = asObject(rec) || {};
    const created = obj.created_at || obj.createdAt || obj.booking?.created_at;
    if (recentIso(created)) recentBookings += 1;
    if (invoiceKv) {
      const invoiceProbe = await getStore(invoiceKv, `invoice:${bookingId}`);
      if (invoiceProbe) invoices += 1;
    }
    bookingSummaries.push({
      booking_id_fp: maskScopePart(bookingId),
      paid: signals.paid,
      invoiced: signals.invoiced,
      recent: recentIso(created),
    });
  }

  const prior = options.priorCounts?.[companyCode] || null;
  const drivers = registryOnly ? null : asObject(await getStore(bookingKv, tenantId && companyId
    ? `tenant:${tenantId}:company:${companyId}:drivers:index:v1`
    : ""));
  const vehicles = registryOnly ? null : asObject(await getStore(bookingKv, tenantId && companyId
    ? `tenant:${tenantId}:company:${companyId}:fleet:vehicles:v1`
    : ""));
  const driverCount = prior?.drivers ?? (Array.isArray(drivers?.drivers)
    ? drivers.drivers.length
    : (Array.isArray(drivers?.items) ? drivers.items.length : (drivers ? 1 : 0)));
  const vehicleCount = prior?.vehicles ?? (Array.isArray(vehicles?.vehicles)
    ? vehicles.vehicles.length
    : (Array.isArray(vehicles?.items) ? vehicles.items.length : 0));

  let trackingHits = prior?.tracking_hits ?? 0;
  if (!registryOnly && !useCompact && trackingKv && tenantId && companyId) {
    const tripKpi = await getStore(trackingKv, `tenant:${tenantId}:company:${companyId}:dashboard:trip_kpis:v1`);
    if (tripKpi) trackingHits += 1;
  }

  const logoKey = companyLogoR2Key(tenantId, companyId);
  let r2Present = Boolean(prior?.r2_logo);
  if (!registryOnly && !useCompact && r2 && logoKey && typeof r2.head === "function") {
    try {
      const head = await r2.head(logoKey);
      r2Present = Boolean(head);
      keysTouched.push(logoKey);
    } catch {
      readErrors.push({ key_kind: "r2_logo", error: "read_failed" });
    }
  } else if (!registryOnly && r2 && logoKey && typeof r2.get === "function") {
    try {
      const obj = await r2.get(logoKey);
      r2Present = Boolean(obj);
      keysTouched.push(logoKey);
    } catch {
      readErrors.push({ key_kind: "r2_logo", error: "read_failed" });
    }
  }

  const inventory = {
    company_code: companyCode,
    protected: isHardProtectedCompanyCode(companyCode),
    now_iso: nowIso,
    identity: {
      has_company_link: Boolean(linkRaw),
      has_scope_link: Boolean(scopeRaw),
      has_registry_code: Boolean(registryCodeRaw),
      has_tombstone: Boolean(tombstoneRaw),
      on_registry_page: Boolean(pageHint),
      registry_pages: pageHint ? [pageHint] : [],
      tenant_fp: maskScopePart(tenantId),
      company_fp: maskScopePart(companyId),
      source: link.source || null,
      linking_enabled: link.linking_enabled ?? link.linkingEnabled ?? null,
      registry: redactValue(registry.code, registryCodeRaw).redacted,
    },
    registry_membership: {
      pages: pageHint ? [pageHint] : [],
    },
    raw: {
      registry_code: asObject(registryCodeRaw),
      company_link: asObject(linkRaw),
      registry_code_text: typeof registryCodeRaw === "string" ? registryCodeRaw : (registryCodeRaw ? JSON.stringify(registryCodeRaw) : null),
      company_link_text: typeof linkRaw === "string" ? linkRaw : (linkRaw ? JSON.stringify(linkRaw) : null),
    },
    counts: {
      bookings: prior?.bookings ?? bookingIds.length,
      recent_bookings: prior?.recent_bookings ?? recentBookings,
      payments: prior?.payments ?? payments,
      invoices: prior?.invoices ?? invoices,
      drivers: driverCount,
      vehicles: vehicleCount,
      customers: prior?.customers ?? 0,
      tracking_hits: trackingHits,
      r2_logo: r2Present ? 1 : 0,
    },
    integrations: {
      billit_oauth_present: prior?.billit_oauth_present ?? Boolean(billitRaw),
      mollie_status_present: prior?.mollie_status_present ?? Boolean(scoped["integration:mollie:status:v1"]?.present),
      chiron_present: prior?.chiron_present ?? Boolean(scoped["chiron_connection:v1"]?.present),
      driver_link_present: prior?.driver_link_present ?? Boolean(driverLinkRaw),
      external_accounts_unchanged: true,
    },
    scoped,
    bookings: bookingSummaries,
    read_errors: readErrors,
    keys_probed: keysTouched.length,
  };
  inventory.classification = classifyCandidate(inventory);
  inventory.restore_checksums = {
    company_link: redactValue(companyLinkCodeKey(companyCode), linkRaw).sha256,
    registry_code: redactValue(registry.code, registryCodeRaw).sha256,
    scope_link: redactValue(scopeKey || "scope", scopeRaw).sha256,
    registry_page: options.sharedChecksums?.registry_page || null,
    registry_manifest: options.sharedChecksums?.registry_manifest || null,
  };
  return inventory;
}

export async function readRegistryPagesAndManifest(bookingKv) {
  const readErrors = [];
  async function getJson(key) {
    try {
      const raw = await bookingKv.get(key);
      return raw;
    } catch {
      readErrors.push({ key_kind: key.split(":")[0], error: "read_failed" });
      return null;
    }
  }
  const manifestRaw = await getJson(COMPANY_REGISTRY_MANIFEST_KEY);
  const manifest = asObject(manifestRaw);
  const pageCount = Math.max(1, Number(manifest?.page_count) || 1);
  const pages = [];
  for (let i = 1; i <= pageCount; i += 1) {
    const pageRaw = await getJson(registryPageKey(i));
    const page = asObject(pageRaw);
    if (page) pages.push({ ...page, _raw: pageRaw });
  }
  const membership = new Map();
  for (const row of codesOnRegistryPages(pages)) {
    membership.set(row.company_code, row.page);
  }
  return {
    manifest,
    manifest_raw: manifestRaw,
    pages,
    membership,
    read_errors: readErrors,
    checksums: {
      registry_manifest: redactValue(COMPANY_REGISTRY_MANIFEST_KEY, manifestRaw).sha256,
      registry_page: redactValue(registryPageKey(1), pages[0]?._raw || pages[0]).sha256,
    },
  };
}

export async function inventorySelection(stores, codes, options = {}) {
  const companies = [];
  const concurrency = Math.max(1, Math.min(4, Number(options.concurrency) || 1));
  const registrySnapshot = stores.BOOKING_KV
    ? await readRegistryPagesAndManifest(stores.BOOKING_KV)
    : { membership: new Map(), checksums: {}, pages: [], manifest: null, read_errors: [] };
  let index = 0;
  async function worker() {
    while (index < codes.length) {
      const current = index;
      index += 1;
      companies[current] = await inventoryCompany(stores, codes[current], {
        ...options,
        pageMembership: registrySnapshot.membership,
        sharedChecksums: registrySnapshot.checksums,
      });
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, codes.length) }, () => worker()));
  const phaseABlocked = companies.filter((row) => row.classification.phase_a_blocked);
  const reconciliation = reconcileObservedCodes(
    codesOnRegistryPages(registrySnapshot.pages),
    codes,
  );
  return {
    generated_at: options.nowIso || new Date().toISOString(),
    phase: "registry_retirement",
    companies,
    eligible_count: companies.filter((row) => row.classification.phase_a_eligible).length,
    blocked_count: phaseABlocked.length,
    fail_closed: phaseABlocked.length > 0 || registrySnapshot.read_errors.length > 0,
    fail_closed_codes: phaseABlocked.map((row) => row.company_code),
    risk_groups: {
      empty_or_low_risk: companies.filter((row) => row.classification.risk_group === RISK_GROUPS.EMPTY_LOW).map((row) => row.company_code),
      data_present: companies.filter((row) => row.classification.risk_group === RISK_GROUPS.DATA_PRESENT).map((row) => row.company_code),
      payments_or_recent_usage: companies.filter((row) => row.classification.risk_group === RISK_GROUPS.PAYMENTS_OR_RECENT).map((row) => row.company_code),
      missing_or_id_mismatch: companies.filter((row) => row.classification.risk_group === RISK_GROUPS.MISSING_OR_MISMATCH).map((row) => row.company_code),
    },
    registry_snapshot: {
      page_count: registrySnapshot.pages.length,
      manifest_total: registrySnapshot.manifest?.total ?? null,
      observed_codes: codesOnRegistryPages(registrySnapshot.pages).map((row) => row.company_code),
      checksums: registrySnapshot.checksums,
    },
    reconciliation,
    raw_registry: {
      manifest: registrySnapshot.manifest,
      manifest_text: typeof registrySnapshot.manifest_raw === "string"
        ? registrySnapshot.manifest_raw
        : (registrySnapshot.manifest ? JSON.stringify(registrySnapshot.manifest) : null),
      pages: registrySnapshot.pages.map((page) => ({
        page: page.page,
        membership_generation: page.membership_generation,
        companies: page.companies,
        text: typeof page._raw === "string" ? page._raw : JSON.stringify({
          page: page.page,
          membership_generation: page.membership_generation,
          companies: page.companies,
        }),
      })),
    },
  };
}
