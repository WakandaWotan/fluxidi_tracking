// Pure cancel/refund UI rules for the company bookings overview.
//
// Credit registration is not a Mollie refund. A ride is only "Terugbetaald"
// after Mollie confirms a refund. Missing `refunds.write` must not be retried
// until the company re-authorizes Mollie.

const String kCompanyMollieRefundsWriteMissing = 'mollie_refunds_write_missing';

bool companyBookingCancelShouldStart({
  required bool alreadyBusy,
  required bool bulkArchiving,
}) {
  return !alreadyBusy && !bulkArchiving;
}

bool companyBookingMollieRefundsWriteMissing(String error) {
  final text = error.trim().toLowerCase();
  if (text.isEmpty) return false;
  return text.contains('refunds.write') ||
      text.contains(kCompanyMollieRefundsWriteMissing) ||
      (text.contains('insufficient_scope') && text.contains('refund'));
}

bool companyBookingShouldRetryMollieRefund({
  required String lastError,
  required bool writeGrantConfirmed,
}) {
  if (companyBookingMollieRefundsWriteMissing(lastError) &&
      !writeGrantConfirmed) {
    return false;
  }
  return true;
}

bool companyBookingCreditAlreadyRecorded(String creditDecision) {
  switch (creditDecision.trim().toUpperCase()) {
    case 'FULL_CREDIT':
    case 'PARTIAL_CREDIT':
    case 'NO_REFUND':
    case 'HANDLED_MANUALLY':
      return true;
    default:
      return false;
  }
}

enum CompanyBookingRefundUiKind { none, pending, refunded, failed }

String _companyRefundStatusToken(String raw) {
  return raw.trim().toUpperCase().replaceAll('-', '_');
}

bool companyBookingRefundStatusIsCreditOnly(String refundStatus) {
  switch (_companyRefundStatusToken(refundStatus)) {
    case 'PENDING_CREDIT':
    case 'FULL_CREDIT':
    case 'PARTIAL_CREDIT':
    case 'CREDITED':
    case 'NO_REFUND':
    case 'HANDLED_MANUALLY':
      return true;
    default:
      return false;
  }
}

bool companyBookingHasRefundRequestSignal({
  String mollieRefundId = '',
  int? refundedAmountCents,
  String refundedAt = '',
  String complianceEmittedAt = '',
}) {
  return mollieRefundId.trim().isNotEmpty ||
      (refundedAmountCents ?? 0) > 0 ||
      refundedAt.trim().isNotEmpty ||
      complianceEmittedAt.trim().isNotEmpty;
}

bool companyBookingRefundStatusIsPendingToken(String raw) {
  if (companyBookingRefundStatusIsCreditOnly(raw)) return false;
  switch (_companyRefundStatusToken(raw)) {
    case 'QUEUED':
    case 'PENDING':
    case 'IN_PROGRESS':
    case 'PROCESSING':
    case 'OPEN':
    case 'REQUESTED':
    case 'CREATED':
    case 'UNKNOWN':
    case 'IN_BEHANDELING':
    case 'MOLLIE_REFUND_PENDING':
    case 'REFUNDED_PENDING':
      return true;
    default:
      return false;
  }
}

/// Shared tab / card / snackbar classification. A credit is never a refund.
CompanyBookingRefundUiKind companyBookingRefundUiKind({
  required bool cancelled,
  required bool paid,
  String mollieRefundStatus = '',
  String refundStatus = '',
  String mollieRefundId = '',
  int? refundedAmountCents,
  String refundedAt = '',
  String lastError = '',
  String complianceEmittedAt = '',
}) {
  if (!cancelled || !paid) return CompanyBookingRefundUiKind.none;
  if (companyBookingIsMollieRefundConfirmed(
    mollieRefundStatus: mollieRefundStatus,
    refundStatus: companyBookingRefundStatusIsCreditOnly(refundStatus)
        ? ''
        : refundStatus,
    mollieRefundId: mollieRefundId,
  )) {
    return CompanyBookingRefundUiKind.refunded;
  }
  if (companyBookingIsMollieRefundFailed(
    mollieRefundStatus: mollieRefundStatus,
    refundStatus: companyBookingRefundStatusIsCreditOnly(refundStatus)
        ? ''
        : refundStatus,
    lastError: lastError,
  )) {
    return CompanyBookingRefundUiKind.failed;
  }
  if (companyBookingRefundStatusIsPendingToken(mollieRefundStatus) ||
      companyBookingRefundStatusIsPendingToken(refundStatus) ||
      companyBookingHasRefundRequestSignal(
        mollieRefundId: mollieRefundId,
        refundedAmountCents: refundedAmountCents,
        refundedAt: refundedAt,
        complianceEmittedAt: complianceEmittedAt,
      )) {
    return CompanyBookingRefundUiKind.pending;
  }
  return CompanyBookingRefundUiKind.none;
}

/// Apply accepted by Mollie: pending until provider status is refunded.
CompanyBookingRefundUiKind companyBookingRefundApplySnackKind({
  required bool ok,
  String refundStatus = '',
  String mollieRefundStatus = '',
}) {
  if (!ok) return CompanyBookingRefundUiKind.failed;
  return companyBookingRefundUiKind(
    cancelled: true,
    paid: true,
    mollieRefundStatus: mollieRefundStatus,
    refundStatus: refundStatus,
    mollieRefundId: ok ? 're_accepted' : '',
  );
}

/// Credit and refund stay independent: a recorded credit is never a refund.
bool companyBookingIsMollieRefundConfirmed({
  required String mollieRefundStatus,
  required String refundStatus,
  required String mollieRefundId,
}) {
  final mollie = mollieRefundStatus.trim().toUpperCase();
  final refund = refundStatus.trim().toUpperCase();
  const settled = <String>{
    'REFUNDED',
    'SUCCEEDED',
    'COMPLETED',
    'SUCCESS',
    'PAID',
    'PAID_OUT',
    'SETTLED',
  };
  if (settled.contains(mollie) || settled.contains(refund)) return true;
  return false;
}

bool companyBookingIsMollieRefundFailed({
  required String mollieRefundStatus,
  required String refundStatus,
  String lastError = '',
}) {
  if (companyBookingMollieRefundsWriteMissing(lastError)) return true;
  final mollie = mollieRefundStatus.trim().toUpperCase();
  final refund = refundStatus.trim().toUpperCase();
  const failed = <String>{
    'FAILED',
    'FAILURE',
    'CANCELLED',
    'CANCELED',
    'EXPIRED',
    'REJECTED',
    'ERROR',
    'REQUIRES_ACTION',
  };
  return failed.contains(mollie) || failed.contains(refund);
}

/// Tab counts must include a failed refund even when credit is already recorded.
bool companyBookingCountsAsFailedRefundTab({
  required bool cancelled,
  required bool paid,
  required String mollieRefundStatus,
  required String refundStatus,
  String lastError = '',
}) {
  if (!cancelled || !paid) return false;
  return companyBookingIsMollieRefundFailed(
    mollieRefundStatus: mollieRefundStatus,
    refundStatus: refundStatus,
    lastError: lastError,
  );
}

String companyBookingSettledChipToken({
  required String creditDecision,
  required String mollieRefundStatus,
  required String refundStatus,
  required String mollieRefundId,
}) {
  final decision = creditDecision.trim().toUpperCase();
  if (decision == 'NO_REFUND') return 'NO_REFUND';
  if (decision == 'HANDLED_MANUALLY') return 'HANDLED_MANUALLY';
  if (companyBookingIsMollieRefundConfirmed(
    mollieRefundStatus: mollieRefundStatus,
    refundStatus: refundStatus,
    mollieRefundId: mollieRefundId,
  )) {
    return decision == 'PARTIAL_CREDIT' ? 'PARTIAL_REFUNDED' : 'REFUNDED';
  }
  if (decision == 'FULL_CREDIT' || decision == 'PARTIAL_CREDIT') {
    return 'CREDITED_NOT_REFUNDED';
  }
  return '';
}

class CompanyBookingCancelTiming {
  const CompanyBookingCancelTiming({
    required this.requestMs,
    required this.reloadMs,
  });

  final int requestMs;
  final int reloadMs;

  bool get requestWasTheSlowPart => requestMs >= reloadMs;
}
