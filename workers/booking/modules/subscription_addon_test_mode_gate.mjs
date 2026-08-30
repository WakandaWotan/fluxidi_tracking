/**
 * Fail-closed add-on billing-mode gate.
 * A test-mode Mollie payment must never grant ordinary production entitlements.
 * Never logs or returns API keys / webhook secrets.
 */

export const ADDON_TEST_COMPANY_ALLOWLIST_VAR =
  "FLUXIDI_SUBSCRIPTION_ADDON_TEST_COMPANY_ALLOWLIST";
export const ADDON_TEST_AUTHORIZED_PROFILE_FLAG = "billing_test_authorized";

const COMPANY_CODE_RE = /^FLX-[0-9]{4,12}$/;

function text(value, max = 160) {
  if (value == null) return "";
  const raw = String(value).trim();
  if (!raw) return "";
  return max > 0 && raw.length > max ? raw.slice(0, max) : raw;
}

function normalizeCompanyCode(value) {
  const code = text(value, 32).toUpperCase();
  return COMPANY_CODE_RE.test(code) ? code : "";
}

function normalizeCompanyId(value) {
  return text(value, 80);
}

export function effectiveMollieKeyMode(apiKey) {
  const key = typeof apiKey === "string" ? apiKey : "";
  if (!key) return { ok: false, error: "missing_mollie_api_key" };
  if (key.startsWith("test_")) return { ok: true, mode: "test" };
  if (key.startsWith("live_")) return { ok: true, mode: "live" };
  return { ok: false, error: "unrecognized_mollie_key_mode" };
}

export function declaredSubscriptionMollieMode(raw) {
  const mode = text(raw, 16).toLowerCase();
  if (!mode) return { ok: true, asserted: false, mode: "" };
  if (mode === "test" || mode === "live") return { ok: true, asserted: true, mode };
  return { ok: false, error: "unrecognized_declared_mollie_mode" };
}

export function resolveSubscriptionBillingMode({ apiKey, declaredMode } = {}) {
  const effective = effectiveMollieKeyMode(apiKey);
  if (!effective.ok) {
    return { ok: false, error: effective.error, http_status: 503 };
  }
  const declared = declaredSubscriptionMollieMode(declaredMode);
  if (!declared.ok) {
    return { ok: false, error: declared.error, http_status: 503 };
  }
  if (declared.asserted && declared.mode !== effective.mode) {
    return {
      ok: false,
      error: "mollie_mode_mismatch",
      declared_mode: declared.mode,
      effective_mode: effective.mode,
      http_status: 503,
    };
  }
  return {
    ok: true,
    mode: effective.mode,
    declared_mode: declared.asserted ? declared.mode : "",
    declared_mode_asserted: declared.asserted === true,
    effective_mode: effective.mode,
  };
}

export function parseAddonTestCompanyAllowlist(raw) {
  const textValue = typeof raw === "string" ? raw : "";
  if (!textValue.trim()) return [];
  const tokens = textValue.split(/[,;\s]+/).map((part) => part.trim()).filter(Boolean);
  const out = [];
  const seen = new Set();
  for (const token of tokens) {
    const code = normalizeCompanyCode(token);
    const id = code ? "" : normalizeCompanyId(token);
    const value = code || id;
    if (!value || seen.has(value)) continue;
    // Codes are explicit. Company IDs must look like identifiers, not labels.
    if (!code && !/^[A-Za-z0-9]+(?:[._:-][A-Za-z0-9]+)+$/.test(id)) continue;
    seen.add(value);
    out.push(value);
  }
  return out;
}

export function isAuthorizedAddonTestCompany({
  companyCode,
  companyId,
  allowlistRaw,
  profile,
} = {}) {
  if (profile && profile[ADDON_TEST_AUTHORIZED_PROFILE_FLAG] === true) {
    return { authorized: true, reason: "profile_billing_test_authorized" };
  }
  const allowlist = parseAddonTestCompanyAllowlist(allowlistRaw);
  if (allowlist.length === 0) {
    return { authorized: false, reason: "test_company_allowlist_empty" };
  }
  const code = normalizeCompanyCode(companyCode)
    || normalizeCompanyCode(profile?.public_company_code)
    || normalizeCompanyCode(profile?.company_code);
  const id = normalizeCompanyId(companyId) || normalizeCompanyId(profile?.company_id);
  if (code && allowlist.includes(code)) {
    return { authorized: true, reason: "allowlist_company_code" };
  }
  if (id && allowlist.includes(id)) {
    return { authorized: true, reason: "allowlist_company_id" };
  }
  return { authorized: false, reason: "company_not_on_test_allowlist" };
}

export function authorizeAddonCheckout({
  apiKey,
  declaredMode,
  companyCode,
  companyId,
  allowlistRaw,
  profile,
  displayName,
} = {}) {
  void displayName;
  const billing = resolveSubscriptionBillingMode({ apiKey, declaredMode });
  if (!billing.ok) return billing;
  if (billing.mode === "live") {
    return {
      ok: true,
      billing_mode: "live",
      test_company_authorized: false,
      counts_as_live_revenue: true,
      contributes_mrr: true,
      authorization_reason: "live_billing_mode",
    };
  }
  const decision = isAuthorizedAddonTestCompany({
    companyCode,
    companyId,
    allowlistRaw,
    profile,
  });
  if (!decision.authorized) {
    return {
      ok: false,
      error: "addon_test_mode_not_authorized",
      billing_mode: "test",
      test_company_authorized: false,
      authorization_reason: decision.reason,
      http_status: 403,
    };
  }
  return {
    ok: true,
    billing_mode: "test",
    test_company_authorized: true,
    counts_as_live_revenue: false,
    contributes_mrr: false,
    authorization_reason: decision.reason,
  };
}

export function buildAddonPendingBillingEvidence({
  authorization,
  companyId,
  companyCode,
  addonCode,
  quantity,
  createdAt,
  activationId,
  providerPaymentId,
} = {}) {
  const billingMode = authorization?.billing_mode === "test" ? "test" : "live";
  const testAuthorized = authorization?.test_company_authorized === true;
  return {
    billing_mode: billingMode,
    effective_billing_mode: billingMode,
    test_company_authorized: testAuthorized,
    company_id: normalizeCompanyId(companyId),
    company_code: normalizeCompanyCode(companyCode) || null,
    addon_code: text(addonCode, 64).toLowerCase(),
    quantity: Number(quantity) === 1 ? 1 : 0,
    created_at: text(createdAt, 48) || null,
    activation_id: text(activationId, 160),
    provider_payment_id: text(providerPaymentId, 128),
    counts_as_live_revenue: authorization?.counts_as_live_revenue === true,
    contributes_mrr: authorization?.contributes_mrr === true,
  };
}

export function verifiedMolliePaymentMode(payment) {
  const mode = text(payment?.mode, 16).toLowerCase();
  if (mode === "test" || mode === "live") return { ok: true, mode };
  return { ok: false, error: "unproven_payment_mode" };
}

function sameMeta(left, right) {
  return text(left, 160).toLowerCase() === text(right, 160).toLowerCase();
}

export function pendingMatchesVerifiedPayment(pending, payment) {
  if (!pending || typeof pending !== "object") {
    return { ok: false, error: "pending_activation_missing" };
  }
  const meta = payment?.metadata && typeof payment.metadata === "object" && !Array.isArray(payment.metadata)
    ? payment.metadata
    : {};
  const pendingActivation = text(pending.activation_id, 160);
  const metaActivation = text(meta.activation_id ?? meta.activationId, 160);
  if (pendingActivation && metaActivation && pendingActivation !== metaActivation) {
    return { ok: false, error: "pending_activation_id_mismatch" };
  }
  const pendingCompany = normalizeCompanyId(pending.company_id);
  const metaCompany = normalizeCompanyId(meta.company_id ?? meta.companyId);
  if (pendingCompany && metaCompany && pendingCompany !== metaCompany) {
    return { ok: false, error: "pending_company_mismatch" };
  }
  const pendingAddon = text(pending.addon_code, 64).toLowerCase();
  const metaAddon = text(meta.addon_code ?? meta.addonCode, 64).toLowerCase();
  if (pendingAddon && metaAddon && pendingAddon !== metaAddon) {
    return { ok: false, error: "pending_addon_mismatch" };
  }
  const pendingQty = Number(pending.quantity);
  const metaQty = Number(meta.quantity);
  if (Number.isFinite(pendingQty) && Number.isFinite(metaQty) && pendingQty !== metaQty) {
    return { ok: false, error: "pending_quantity_mismatch" };
  }
  if (pendingActivation && metaActivation) return { ok: true };
  if (!metaActivation && pendingActivation) {
    return { ok: false, error: "payment_activation_id_unproven" };
  }
  return { ok: true };
}

export function authorizeAddonWebhookActivation({
  apiKey,
  declaredMode,
  pending,
  payment,
  companyCode,
  companyId,
  allowlistRaw,
  profile,
} = {}) {
  const billing = resolveSubscriptionBillingMode({ apiKey, declaredMode });
  if (!billing.ok) return billing;
  if (!pending || typeof pending !== "object") {
    return { ok: false, error: "pending_activation_missing", http_status: 200 };
  }
  const paymentStatus = text(payment?.status, 24).toLowerCase();
  if (paymentStatus && paymentStatus !== "paid") {
    return { ok: false, error: "payment_not_paid", http_status: 200 };
  }
  const match = pendingMatchesVerifiedPayment(pending, payment);
  if (!match.ok) return { ...match, http_status: 200 };
  const storedMode = text(pending.billing_mode ?? pending.effective_billing_mode, 8).toLowerCase();
  if (storedMode !== "test" && storedMode !== "live") {
    return {
      ok: false,
      error: "legacy_pending_billing_mode_unproven",
      http_status: 200,
    };
  }
  const paymentMode = verifiedMolliePaymentMode(payment);
  if (!paymentMode.ok) {
    return { ok: false, error: paymentMode.error, http_status: 200 };
  }
  if (storedMode !== paymentMode.mode) {
    return { ok: false, error: "pending_payment_mode_mismatch", http_status: 200 };
  }
  if (storedMode !== billing.mode) {
    return { ok: false, error: "pending_config_mode_mismatch", http_status: 200 };
  }
  if (storedMode === "live") {
    return {
      ok: true,
      billing_mode: "live",
      test_company_authorized: false,
      counts_as_live_revenue: true,
      contributes_mrr: true,
      authorization_reason: "live_billing_mode",
    };
  }
  const decision = isAuthorizedAddonTestCompany({
    companyCode: companyCode || pending.company_code,
    companyId: companyId || pending.company_id,
    allowlistRaw,
    profile,
  });
  if (!decision.authorized) {
    return {
      ok: false,
      error: "legacy_or_unauthorized_test_pending",
      billing_mode: "test",
      test_company_authorized: false,
      authorization_reason: decision.reason,
      http_status: 200,
    };
  }
  return {
    ok: true,
    billing_mode: "test",
    test_company_authorized: true,
    counts_as_live_revenue: false,
    contributes_mrr: false,
    authorization_reason: decision.reason,
  };
}

export function testGrantRevenueAudit(authorization = {}) {
  return {
    billing_mode: authorization.billing_mode || null,
    counts_as_live_revenue: authorization.counts_as_live_revenue === true,
    contributes_mrr: authorization.contributes_mrr === true,
  };
}

export { sameMeta };
