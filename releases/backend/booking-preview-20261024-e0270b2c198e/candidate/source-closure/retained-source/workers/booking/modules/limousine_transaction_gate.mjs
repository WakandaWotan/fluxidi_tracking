// P3D — fail-closed limousine transaction gate resolver.
//
// Quote / manual-quote / book stay on the existing Fluxidi routes. This helper
// only answers whether a server-resolved company may start a limousine
// transaction in the current test-preview phase.
//
// Hard rules:
//   * the matching global gate must be on;
//   * company id must come from the public partner or a matching session,
//     never from a client tenant/company/partner claim;
//   * test-preview requires exact membership of LIMOUSINE_TEST_COMPANY_ALLOWLIST;
//   * missing/empty/wildcard allowlist denies every company;
//   * unpublished providers are denied when the caller already knows that;
//   * no KV, fetch, cron, or secret logging.

import { canonicalizeLimousineTestCompanyId } from "./limousine_test_company_allowlist.mjs";
import { LIMOUSINE_DISCOVERY_LISTING_MODE_TEST_PREVIEW } from "./limousine_discovery_preview.mjs";

export const LIMOUSINE_TRANSACTION_GATE_KIND = Object.freeze({
  QUOTE: "quote",
  BOOK: "book",
  MANUAL_QUOTE: "manual_quote",
});

export const LIMOUSINE_TRANSACTION_GATE_REASON = Object.freeze({
  GATE_OFF: "gate_off",
  COMPANY_UNTRUSTED: "company_untrusted",
  NOT_ALLOWLISTED: "not_allowlisted",
  NOT_PUBLISHED: "not_published",
});

export function limousineTransactionGateErrorFor({ kind, reason } = {}) {
  if (reason === LIMOUSINE_TRANSACTION_GATE_REASON.GATE_OFF) {
    if (kind === LIMOUSINE_TRANSACTION_GATE_KIND.BOOK) {
      return "limousine_book_disabled";
    }
    if (kind === LIMOUSINE_TRANSACTION_GATE_KIND.MANUAL_QUOTE) {
      return "manual_quote_gate_off";
    }
    return "gate_off";
  }
  if (kind === LIMOUSINE_TRANSACTION_GATE_KIND.BOOK) return "limousine_unavailable";
  if (kind === LIMOUSINE_TRANSACTION_GATE_KIND.MANUAL_QUOTE) return "not_found";
  return "unavailable";
}

function isTestPreviewListingMode(listingMode) {
  if (listingMode == null || listingMode === "") return true;
  return listingMode === LIMOUSINE_DISCOVERY_LISTING_MODE_TEST_PREVIEW;
}

export function resolveLimousineTransactionGate({
  kind,
  globalGateEnabled,
  companyId,
  allowlisted,
  allowlistConfigured,
  listingMode = LIMOUSINE_DISCOVERY_LISTING_MODE_TEST_PREVIEW,
  publishedLimousine,
} = {}) {
  if (globalGateEnabled !== true) {
    return {
      ok: false,
      reason: LIMOUSINE_TRANSACTION_GATE_REASON.GATE_OFF,
      error: limousineTransactionGateErrorFor({
        kind,
        reason: LIMOUSINE_TRANSACTION_GATE_REASON.GATE_OFF,
      }),
    };
  }

  const company = canonicalizeLimousineTestCompanyId(companyId);
  if (!company) {
    return {
      ok: false,
      reason: LIMOUSINE_TRANSACTION_GATE_REASON.COMPANY_UNTRUSTED,
      error: limousineTransactionGateErrorFor({
        kind,
        reason: LIMOUSINE_TRANSACTION_GATE_REASON.COMPANY_UNTRUSTED,
      }),
    };
  }

  // Test-preview (current public listing) and an explicit allowlist both
  // require exact membership. An empty/misconfigured allowlist stays deny-all.
  // Production listing is not a bypass: transactions stay allowlist-scoped.
  const mustAllowlist =
    isTestPreviewListingMode(listingMode) || allowlistConfigured === true;
  if (mustAllowlist && allowlisted !== true) {
    return {
      ok: false,
      reason: LIMOUSINE_TRANSACTION_GATE_REASON.NOT_ALLOWLISTED,
      error: limousineTransactionGateErrorFor({
        kind,
        reason: LIMOUSINE_TRANSACTION_GATE_REASON.NOT_ALLOWLISTED,
      }),
    };
  }
  if (allowlisted !== true) {
    return {
      ok: false,
      reason: LIMOUSINE_TRANSACTION_GATE_REASON.NOT_ALLOWLISTED,
      error: limousineTransactionGateErrorFor({
        kind,
        reason: LIMOUSINE_TRANSACTION_GATE_REASON.NOT_ALLOWLISTED,
      }),
    };
  }

  if (publishedLimousine === false) {
    return {
      ok: false,
      reason: LIMOUSINE_TRANSACTION_GATE_REASON.NOT_PUBLISHED,
      error: limousineTransactionGateErrorFor({
        kind,
        reason: LIMOUSINE_TRANSACTION_GATE_REASON.NOT_PUBLISHED,
      }),
    };
  }

  return { ok: true, company_id: company };
}
