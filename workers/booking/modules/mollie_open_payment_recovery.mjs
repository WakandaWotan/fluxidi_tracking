// MOLLIE-OPEN-PAYMENT-RECOVERY-P0
//
// Pure decision model for recovering an open Mollie hosted checkout without
// creating a second payment owner. Network / KV I/O lives in the booking worker.

function _str(v, max = 160) {
  return String(v ?? "").trim().slice(0, max);
}

function _lower(v, max = 160) {
  return _str(v, max).toLowerCase();
}

export const MOLLIE_OPEN_PAYMENT_PRESENTATION = Object.freeze({
  CHECKING: "checking",
  PENDING: "pending",
  PAID: "paid",
  FAILED: "failed",
  EXPIRED: "expired",
  CANCELED: "canceled",
  REFRESHING: "refreshing",
  CANCELING: "canceling",
  RECOVERY_ERROR: "recoveryError",
});

export function isMollieProviderStatusPaid(status) {
  const t = _lower(status, 40);
  return (
    t === "paid" ||
    t === "confirmed" ||
    t === "completed" ||
    t === "success" ||
    t === "settled" ||
    t === "succeeded" ||
    t === "captured"
  );
}

export function isMollieProviderStatusReleased(status) {
  const t = _lower(status, 40);
  return (
    t === "failed" ||
    t === "canceled" ||
    t === "cancelled" ||
    t === "expired" ||
    t === "abandoned"
  );
}

export function isMollieProviderStatusPayable(status) {
  const t = _lower(status, 40);
  if (!t) return true; // unknown local marker — treat as still potentially payable
  return (
    t === "open" ||
    t === "pending" ||
    t === "authorized" ||
    t === "mollie_open"
  );
}

/**
 * Cancel gate against authoritative provider status.
 * PAID always wins over cancel (webhook race).
 */
export function resolveMollieOpenPaymentCancelDecision({
  providerStatus = "",
  localPaymentStatus = "",
} = {}) {
  if (
    isMollieProviderStatusPaid(providerStatus) ||
    isMollieProviderStatusPaid(localPaymentStatus)
  ) {
    return {
      action: "reject_paid",
      may_cancel: false,
      reason: "already_paid",
      release_owner: false,
      fallback_allowed: false,
    };
  }
  const released = isMollieProviderStatusReleased(providerStatus);
  if (released) {
    const token = _lower(providerStatus, 40);
    return {
      action: "already_released",
      may_cancel: false,
      reason: token || "released",
      release_owner: true,
      fallback_allowed: true,
      presentation_state:
        token === "expired"
          ? MOLLIE_OPEN_PAYMENT_PRESENTATION.EXPIRED
          : token === "failed"
            ? MOLLIE_OPEN_PAYMENT_PRESENTATION.FAILED
            : MOLLIE_OPEN_PAYMENT_PRESENTATION.CANCELED,
    };
  }
  if (isMollieProviderStatusPayable(providerStatus)) {
    return {
      action: "cancel",
      may_cancel: true,
      reason: "pending_cancelable",
      release_owner: false,
      fallback_allowed: false,
    };
  }
  return {
    action: "reject_unknown",
    may_cancel: false,
    reason: "provider_status_unknown",
    release_owner: false,
    fallback_allowed: false,
  };
}

/**
 * Presentation + allowed recovery actions for an existing open checkout.
 */
export function resolveMollieOpenPaymentPresentation({
  providerStatus = "",
  hasCheckoutUrl = false,
  busy = null,
  recoveryError = false,
} = {}) {
  if (recoveryError === true) {
    return {
      state: MOLLIE_OPEN_PAYMENT_PRESENTATION.RECOVERY_ERROR,
      resumable: !!hasCheckoutUrl,
      cancel_allowed: false,
      fallback_allowed: false,
      actions: ["refresh_status"],
    };
  }
  const busyToken = _lower(busy, 40);
  if (busyToken === "refreshing" || busyToken === "checking") {
    return {
      state:
        busyToken === "checking"
          ? MOLLIE_OPEN_PAYMENT_PRESENTATION.CHECKING
          : MOLLIE_OPEN_PAYMENT_PRESENTATION.REFRESHING,
      resumable: false,
      cancel_allowed: false,
      fallback_allowed: false,
      actions: [],
    };
  }
  if (busyToken === "canceling" || busyToken === "cancelling") {
    return {
      state: MOLLIE_OPEN_PAYMENT_PRESENTATION.CANCELING,
      resumable: false,
      cancel_allowed: false,
      fallback_allowed: false,
      actions: [],
    };
  }
  if (isMollieProviderStatusPaid(providerStatus)) {
    return {
      state: MOLLIE_OPEN_PAYMENT_PRESENTATION.PAID,
      resumable: false,
      cancel_allowed: false,
      fallback_allowed: false,
      actions: [],
    };
  }
  if (isMollieProviderStatusReleased(providerStatus)) {
    const token = _lower(providerStatus, 40);
    const state =
      token === "expired"
        ? MOLLIE_OPEN_PAYMENT_PRESENTATION.EXPIRED
        : token === "failed"
          ? MOLLIE_OPEN_PAYMENT_PRESENTATION.FAILED
          : MOLLIE_OPEN_PAYMENT_PRESENTATION.CANCELED;
    return {
      state,
      resumable: false,
      cancel_allowed: false,
      fallback_allowed: true,
      actions: [],
    };
  }
  const resumable =
    hasCheckoutUrl === true ||
    (typeof hasCheckoutUrl === "string" && !!_str(hasCheckoutUrl, 2000));
  return {
    state: MOLLIE_OPEN_PAYMENT_PRESENTATION.PENDING,
    resumable,
    cancel_allowed: true,
    fallback_allowed: false,
    actions: [
      "refresh_status",
      ...(resumable ? ["resume_checkout"] : []),
      "cancel_open_checkout",
    ],
  };
}

/**
 * Enrich open_mollie_checkout_exists conflict with recovery actions.
 */
export function buildOpenMollieCheckoutRecoveryPayload(openCheckout = null) {
  const open =
    openCheckout && typeof openCheckout === "object" ? openCheckout : null;
  const presentation = resolveMollieOpenPaymentPresentation({
    providerStatus: open?.mollie_status ?? open?.mollieStatus ?? "",
    hasCheckoutUrl: !!(open?.checkout_url || open?.checkoutUrl),
  });
  return {
    error: "open_mollie_checkout_exists",
    status: 409,
    message: "An online Mollie checkout is still open for this ride.",
    open_checkout: open,
    requires_confirm_cancel_open_mollie: true,
    recovery: {
      presentation_state: presentation.state,
      resumable: presentation.resumable === true,
      cancel_allowed: presentation.cancel_allowed === true,
      fallback_allowed: presentation.fallback_allowed === true,
      actions: presentation.actions,
    },
  };
}

/**
 * After cancel attempt: paid race must win; released releases owner.
 */
export function resolveMollieCancelReconcileOutcome({
  providerStatusAfter = "",
  cancelHttpOk = false,
} = {}) {
  if (isMollieProviderStatusPaid(providerStatusAfter)) {
    return {
      action: "project_paid",
      ok: false,
      error: "payment_already_paid",
      release_owner: false,
      fallback_allowed: false,
      may_manual_pay: false,
    };
  }
  if (isMollieProviderStatusReleased(providerStatusAfter)) {
    return {
      action: "release_owner",
      ok: true,
      error: null,
      release_owner: true,
      fallback_allowed: true,
      may_manual_pay: true,
      provider_status: _lower(providerStatusAfter, 40),
    };
  }
  if (cancelHttpOk && isMollieProviderStatusPayable(providerStatusAfter)) {
    // Mollie sometimes lags; treat successful DELETE + still-open as pending
    // cancel — caller must not release fallback yet.
    return {
      action: "cancel_pending",
      ok: false,
      error: "cancel_not_confirmed",
      release_owner: false,
      fallback_allowed: false,
      may_manual_pay: false,
    };
  }
  return {
    action: "recovery_error",
    ok: false,
    error: "cancel_reconcile_failed",
    release_owner: false,
    fallback_allowed: false,
    may_manual_pay: false,
  };
}

export function normalizeMollieRecoveryAction(raw) {
  const t = _lower(raw, 40);
  if (t === "refresh" || t === "refresh_status" || t === "status") {
    return "refresh";
  }
  if (t === "resume" || t === "resume_checkout" || t === "reuse") {
    return "resume";
  }
  if (t === "cancel" || t === "cancel_open_checkout" || t === "cancel_open") {
    return "cancel";
  }
  return "";
}
