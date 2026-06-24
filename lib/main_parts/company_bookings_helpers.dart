part of '../main.dart';

enum _AdminCancelPaidScope { singleLeg, fullRoundtrip }

enum _AdminCreditScope { legOnly, fullParent }

enum _CompanyBookingsFilter {
  open,
  completed,
  cancelled,
  toCredit,
  refundPending,
  refunded,
  refundFailed,
}

class _CompanyBookingsLoadException implements Exception {
  final String code;
  _CompanyBookingsLoadException(this.code);
}

class _CompanyBookingOverviewItem {
  final String bookingId;
  final String parentBookingId;
  final String legId;
  final String legType;
  final bool isOperationalLeg;
  final bool isRoundtripParent;
  final String referenceText;
  final String parentReferenceText;
  final String pickupIso;
  final String fromAddress;
  final String toAddress;
  final String customerName;
  final String assignedDriverText;
  final String assignedVehicleText;
  final String statusText;
  final String paymentStatus;
  final String paymentProvider;
  final String creditStatus;
  final String refundStatus;
  final bool refundRequired;
  final String creditDecision;
  final int? creditedAmountCents;
  final String creditedAt;
  final String mollieRefundId;
  final String mollieRefundStatus;
  final int? refundedAmountCents;
  final String refundedAt;
  final String refundProvider;
  final String complianceMollieRefundEmittedAt;
  final String complianceMollieRefundFinalEmittedAt;
  final bool isPendingCredit;
  final num? amount;
  final num? parentAmount;
  final String currency;
  final _CompanyBookingsFilter bucket;

  const _CompanyBookingOverviewItem({
    required this.bookingId,
    required this.parentBookingId,
    required this.legId,
    required this.legType,
    required this.isOperationalLeg,
    required this.isRoundtripParent,
    required this.referenceText,
    required this.parentReferenceText,
    required this.pickupIso,
    required this.fromAddress,
    required this.toAddress,
    required this.customerName,
    required this.assignedDriverText,
    required this.assignedVehicleText,
    required this.statusText,
    required this.paymentStatus,
    required this.paymentProvider,
    required this.creditStatus,
    required this.refundStatus,
    required this.refundRequired,
    required this.creditDecision,
    required this.creditedAmountCents,
    required this.creditedAt,
    required this.mollieRefundId,
    required this.mollieRefundStatus,
    required this.refundedAmountCents,
    required this.refundedAt,
    required this.refundProvider,
    required this.complianceMollieRefundEmittedAt,
    required this.complianceMollieRefundFinalEmittedAt,
    required this.isPendingCredit,
    required this.amount,
    required this.parentAmount,
    required this.currency,
    required this.bucket,
  });

  static dynamic _path(Map<String, dynamic> root, String path) {
    dynamic cursor = root;
    for (final rawPart in path.split('.')) {
      final part = rawPart.trim();
      if (part.isEmpty) continue;
      if (cursor is Map && cursor.containsKey(part)) {
        cursor = cursor[part];
      } else {
        return null;
      }
    }
    return cursor;
  }

  static String _text(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return '';
    return text;
  }

  static String _firstText(Map<String, dynamic> root, List<String> paths) {
    for (final path in paths) {
      final value = _text(_path(root, path));
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static num? _firstNum(Map<String, dynamic> root, List<String> paths) {
    for (final path in paths) {
      final value = _path(root, path);
      if (value is num) return value;
      if (value is String) {
        final parsed = num.tryParse(value.trim().replaceAll(',', '.'));
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static String _normStatus(String raw) {
    return raw.trim().toUpperCase().replaceAll('-', '_').replaceAll(' ', '_');
  }

  static bool _firstBool(Map<String, dynamic> root, List<String> paths) {
    for (final path in paths) {
      final value = _path(root, path);
      if (value == true) return true;
      if (value == false) return false;
      final text = _text(value).toLowerCase();
      if (text == 'true' || text == '1' || text == 'yes') return true;
    }
    return false;
  }

  static bool _isCancelledStatus(String statusRaw) {
    final normalized = _normStatus(statusRaw);
    return normalized.contains('CANCEL') || normalized == 'DELETED';
  }

  static bool isExplicitNotPaidPaymentStatus(String paymentStatus) {
    final normalized = _normStatus(paymentStatus);
    if (normalized.isEmpty) return false;
    return normalized == 'PENDING' ||
        normalized == 'OPEN' ||
        normalized == 'CHECKOUT_OPEN' ||
        normalized == 'ONLINE_PENDING' ||
        normalized == 'CREATED' ||
        normalized == 'WAITING' ||
        normalized == 'FAILED' ||
        normalized == 'CANCELLED' ||
        normalized == 'CANCELED' ||
        normalized == 'EXPIRED' ||
        normalized == 'ABANDONED' ||
        normalized == 'NOT_CONFIRMED' ||
        normalized == 'UNKNOWN' ||
        normalized == 'UNPAID' ||
        normalized == 'NOT_PAID' ||
        normalized == 'INITIALIZING' ||
        normalized == 'PAYMENT_CHECKOUT_FAILED' ||
        normalized == 'PROCESSING' ||
        normalized == 'AUTHORIZED';
  }

  static bool isPaidPaymentStatus(String paymentStatus) {
    if (isExplicitNotPaidPaymentStatus(paymentStatus)) return false;
    final normalized = _normStatus(paymentStatus);
    return normalized == 'PAID' ||
        normalized == 'SUCCESS' ||
        normalized == 'CONFIRMED' ||
        normalized == 'COMPLETED' ||
        normalized == 'SETTLED' ||
        normalized == 'SUCCEEDED' ||
        normalized == 'CAPTURED';
  }

  static const List<String> _paymentStatusFieldPaths = <String>[
    'payment_status',
    'paymentStatus',
    'record.payment_status',
    'record.paymentStatus',
    'booking.payment_status',
    'booking.paymentStatus',
    'record.booking.payment_status',
    'record.booking.paymentStatus',
    'quote.payment_status',
    'quote.paymentStatus',
    'record.quote.payment_status',
    'record.quote.paymentStatus',
    'payload.payment_status',
    'payload.paymentStatus',
    'record.payload.payment_status',
    'record.payload.paymentStatus',
    'mollie.status',
    'record.mollie.status',
    'booking.mollie.status',
    'payload.mollie.status',
  ];

  static String _safeBookingRefForDiag(String value) {
    final text = value.trim();
    if (text.isEmpty) return '-';
    if (text.length <= 8) return text;
    return '${text.substring(0, 4)}…${text.substring(text.length - 2)}';
  }

  static void _logBookingPaymentClassify({
    required Map<String, dynamic> raw,
    required String bookingRef,
    required String parentRef,
    required String legType,
    required String rawPaymentStatus,
    required String normalizedPaymentStatus,
    required bool isPaid,
    required bool isCreditEligible,
  }) {
    debugPrint(
      '[BOOKING_PAYMENT_CLASSIFY] booking=${_safeBookingRefForDiag(bookingRef)} '
      'parent=${_safeBookingRefForDiag(parentRef)} leg=${legType.isEmpty ? "-" : legType} '
      'raw_status=${rawPaymentStatus.isEmpty ? "-" : rawPaymentStatus} '
      'normalized_status=${normalizedPaymentStatus.isEmpty ? "-" : normalizedPaymentStatus} '
      'isPaid=$isPaid isCreditEligible=$isCreditEligible',
    );
  }

  static void _logCreditClassify({
    required String bookingRef,
    required String parentRef,
    required String legType,
    required bool isPaid,
    required bool isCreditEligible,
    required String reason,
  }) {
    debugPrint(
      '[CREDIT_CLASSIFY] booking=${_safeBookingRefForDiag(bookingRef)} '
      'parent=${_safeBookingRefForDiag(parentRef)} leg=${legType.isEmpty ? "-" : legType} '
      'isPaid=$isPaid isCreditEligible=$isCreditEligible reason=$reason',
    );
    if (!isPaid && reason == 'skip_unpaid') {
      debugPrint(
        '[CREDIT_CLASSIFY][SKIP_UNPAID] booking=${_safeBookingRefForDiag(bookingRef)} '
        'parent=${_safeBookingRefForDiag(parentRef)} leg=${legType.isEmpty ? "-" : legType}',
      );
    }
  }

  static bool _inferPaidFromRawMap(Map<String, dynamic> raw) {
    final status = _firstText(raw, _paymentStatusFieldPaths);
    if (status.isNotEmpty) {
      if (isExplicitNotPaidPaymentStatus(status)) return false;
      if (isPaidPaymentStatus(status)) return true;
    }
    final molliePaid = _firstBool(raw, const <String>[
      '__mollie_paid',
      'record.__mollie_paid',
      'booking.__mollie_paid',
      'payload.__mollie_paid',
    ]);
    if (molliePaid == true) return true;
    return false;
  }

  static bool _isPaidPaymentStatus(String paymentStatus) =>
      isPaidPaymentStatus(paymentStatus);

  static bool isManualPaymentProvider(String paymentProvider) {
    final normalized = _normStatus(paymentProvider);
    return normalized == 'MANUAL' ||
        normalized == 'CASH' ||
        normalized == 'OFFLINE' ||
        normalized == 'INVOICE';
  }

  static bool isMolliePaymentProvider(String paymentProvider) {
    final normalized = _normStatus(paymentProvider);
    return normalized == 'MOLLIE' ||
        normalized == 'ONLINE' ||
        normalized == 'ONLINE_PAYMENT' ||
        normalized == 'ONLINE_PAYMENTS' ||
        normalized == 'PREPAID';
  }

  static bool isMollieRefundStatusRefunded(String mollieRefundStatus) {
    final normalized = _normStatus(mollieRefundStatus);
    return normalized == 'REFUNDED' ||
        normalized == 'SUCCEEDED' ||
        normalized == 'COMPLETED' ||
        normalized == 'SUCCESS' ||
        normalized == 'PAID' ||
        normalized == 'PAID_OUT' ||
        normalized == 'SETTLED';
  }

  static bool isMollieRefundStatusPending(String mollieRefundStatus) {
    final normalized = _normStatus(mollieRefundStatus);
    return normalized == 'QUEUED' ||
        normalized == 'PENDING' ||
        normalized == 'IN_PROGRESS' ||
        normalized == 'PROCESSING' ||
        normalized == 'OPEN' ||
        normalized == 'REQUESTED' ||
        normalized == 'CREATED' ||
        normalized == 'UNKNOWN' ||
        normalized == 'IN_BEHANDELING' ||
        normalized == 'MOLLIE_REFUND_PENDING';
  }

  static bool isMollieRefundStatusFailed(String mollieRefundStatus) {
    final normalized = _normStatus(mollieRefundStatus);
    return normalized == 'FAILED' ||
        normalized == 'FAILURE' ||
        normalized == 'CANCELLED' ||
        normalized == 'CANCELED' ||
        normalized == 'EXPIRED' ||
        normalized == 'REJECTED' ||
        normalized == 'REQUIRES_ACTION' ||
        normalized == 'ERROR';
  }

  static bool isRefundStatusRefundedOrComplete(String refundStatus) {
    final normalized = _normStatus(refundStatus);
    return normalized == 'REFUNDED' ||
        normalized == 'SUCCEEDED' ||
        normalized == 'COMPLETED' ||
        normalized == 'SUCCESS' ||
        normalized == 'PAID' ||
        normalized == 'PAID_OUT' ||
        normalized == 'SETTLED';
  }

  static bool isRefundStatusPending(String refundStatus) {
    final normalized = _normStatus(refundStatus);
    return normalized == 'MOLLIE_REFUND_PENDING' ||
        normalized == 'REFUNDED_PENDING' ||
        normalized == 'QUEUED' ||
        normalized == 'PENDING' ||
        normalized == 'IN_PROGRESS' ||
        normalized == 'OPEN' ||
        normalized == 'REQUESTED' ||
        normalized == 'CREATED' ||
        normalized == 'UNKNOWN' ||
        normalized == 'IN_BEHANDELING' ||
        normalized == 'PROCESSING';
  }

  static bool isRefundStatusFailed(String refundStatus) {
    final normalized = _normStatus(refundStatus);
    return normalized == 'FAILED' ||
        normalized == 'FAILURE' ||
        normalized == 'CANCELLED' ||
        normalized == 'CANCELED' ||
        normalized == 'EXPIRED' ||
        normalized == 'REJECTED' ||
        normalized == 'REQUIRES_ACTION' ||
        normalized == 'ERROR';
  }

  static bool hasMollieRefundAlreadyApplied(_CompanyBookingOverviewItem item) {
    if (item.mollieRefundId.trim().isNotEmpty) return true;
    if (isMollieRefundStatusRefunded(item.mollieRefundStatus)) return true;
    if (isMollieRefundStatusPending(item.mollieRefundStatus)) return true;
    if (isRefundStatusRefundedOrComplete(item.refundStatus)) return true;
    if (isRefundStatusPending(item.refundStatus)) return true;
    if ((item.refundedAmountCents ?? 0) > 0) return true;
    if (item.complianceMollieRefundEmittedAt.trim().isNotEmpty) return true;
    return false;
  }

  static bool hasMollieRefundAuditResyncSignal(
    _CompanyBookingOverviewItem item,
  ) {
    if (item.mollieRefundId.trim().isNotEmpty) return true;
    if (isMollieRefundStatusRefunded(item.mollieRefundStatus)) return true;
    if (isMollieRefundStatusPending(item.mollieRefundStatus)) return true;
    if (isRefundStatusRefundedOrComplete(item.refundStatus)) return true;
    if (isRefundStatusPending(item.refundStatus)) return true;
    if ((item.refundedAmountCents ?? 0) > 0) return true;
    return false;
  }

  static bool isMollieRefundDisplayRefunded(_CompanyBookingOverviewItem item) {
    if (isMollieRefundStatusRefunded(item.mollieRefundStatus)) return true;
    if (isRefundStatusRefundedOrComplete(item.refundStatus)) return true;
    return false;
  }

  static bool isMollieRefundDisplayPending(_CompanyBookingOverviewItem item) {
    if (isMollieRefundStatusPending(item.mollieRefundStatus)) return true;
    if (isRefundStatusPending(item.refundStatus)) return true;
    return false;
  }

  static bool isRefundLifecycleCandidate(_CompanyBookingOverviewItem item) {
    if (item.bucket != _CompanyBookingsFilter.cancelled) return false;
    if (!isPaidPaymentStatus(item.paymentStatus)) return false;
    return item.mollieRefundId.trim().isNotEmpty ||
        item.mollieRefundStatus.trim().isNotEmpty ||
        item.refundStatus.trim().isNotEmpty ||
        (item.refundedAmountCents ?? 0) > 0 ||
        item.refundedAt.trim().isNotEmpty ||
        item.complianceMollieRefundEmittedAt.trim().isNotEmpty ||
        item.complianceMollieRefundFinalEmittedAt.trim().isNotEmpty;
  }

  // Refund identifiers, requested/emitted timestamps, and amount fields only
  // prove a refund was requested. They are not final provider settlement.
  static bool hasRefundLifecycleRequestSignal(
    _CompanyBookingOverviewItem item,
  ) {
    return item.mollieRefundId.trim().isNotEmpty ||
        (item.refundedAmountCents ?? 0) > 0 ||
        item.refundedAt.trim().isNotEmpty ||
        item.complianceMollieRefundEmittedAt.trim().isNotEmpty ||
        item.complianceMollieRefundFinalEmittedAt.trim().isNotEmpty;
  }

  static bool isRefundLifecycleRefunded(_CompanyBookingOverviewItem item) {
    if (!isRefundLifecycleCandidate(item)) return false;
    // "Terugbetaald" requires explicit final success from refund/provider
    // status. A refund id, timestamp, or amount alone remains pending.
    return isMollieRefundStatusRefunded(item.mollieRefundStatus) ||
        isRefundStatusRefundedOrComplete(item.refundStatus);
  }

  static bool isRefundLifecycleFailed(_CompanyBookingOverviewItem item) {
    if (!isRefundLifecycleCandidate(item)) return false;
    if (isRefundLifecycleRefunded(item)) return false;
    return isMollieRefundStatusFailed(item.mollieRefundStatus) ||
        isRefundStatusFailed(item.refundStatus);
  }

  static bool isRefundLifecyclePending(_CompanyBookingOverviewItem item) {
    if (!isRefundLifecycleCandidate(item)) return false;
    if (isRefundLifecycleRefunded(item)) return false;
    if (isRefundLifecycleFailed(item)) return false;
    if (isMollieRefundDisplayPending(item)) return true;
    if (hasRefundLifecycleRequestSignal(item)) return true;
    return false;
  }

  static void logRefundStateDiagnostic(_CompanyBookingOverviewItem item) {
    final bookingLabel = item.referenceText.trim().isNotEmpty
        ? item.referenceText.trim()
        : item.bookingId.trim();
    if (bookingLabel.isEmpty) return;
    final canRefund = canShowMollieRefundAction(item);
    final canSyncAudit = canShowMollieRefundAuditResyncAction(item);
    final canRefreshStatus = canShowMollieRefundStatusRefreshAction(item);
    debugPrint(
      '[COMPANY_BOOKINGS][REFUND_STATE] booking=$bookingLabel '
      'mollie_refund_id_present=${item.mollieRefundId.trim().isNotEmpty} '
      'refund_status=${item.refundStatus.isEmpty ? "-" : item.refundStatus} '
      'mollie_refund_status=${item.mollieRefundStatus.isEmpty ? "-" : item.mollieRefundStatus} '
      'refunded_amount_cents=${item.refundedAmountCents ?? "-"} '
      'can_refund=$canRefund can_sync_audit=$canSyncAudit can_refresh_status=$canRefreshStatus',
    );
  }

  static bool hasMollieRefundEligibleCreditStatus(String creditStatus) {
    final normalized = _normStatus(creditStatus);
    return normalized == 'CREDITED' || normalized == 'PARTIAL_CREDIT';
  }

  static bool _looksLikeUuidIdentity(String value) {
    final text = value.trim();
    if (text.length < 24) return false;
    return RegExp(
      r'^[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}$',
    ).hasMatch(text);
  }

  static bool _looksLikeFluxidiCanonicalBookingId(String value) {
    final text = value.trim();
    if (text.isEmpty) return false;
    return RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{3,}$').hasMatch(text);
  }

  /// True when the row references a human/canonical booking, not a bare UUID shadow.
  static bool hasCanonicalBookingIdentity(_CompanyBookingOverviewItem item) {
    final bookingId = item.bookingId.trim();
    if (_looksLikeFluxidiCanonicalBookingId(bookingId)) return true;
    final ref = item.referenceText.trim();
    if (ref.isEmpty) return false;
    if (_looksLikeUuidIdentity(ref)) return false;
    if (ref.startsWith('…') && ref.length <= 8) return false;
    return true;
  }

  /// True when pickup and route fields are present for operational display.
  static bool hasMinimumOperationalContext(_CompanyBookingOverviewItem item) {
    if (item.pickupIso.trim().isEmpty) return false;
    final from = item.fromAddress.trim();
    final to = item.toAddress.trim();
    if (from.isEmpty || from == '—') return false;
    if (to.isEmpty || to == '—') return false;
    return true;
  }

  static bool isRoundtripOperationalLegRow(_CompanyBookingOverviewItem item) {
    return item.isOperationalLeg &&
        item.isRoundtripParent &&
        item.legId.trim().isNotEmpty;
  }

  static _AdminCreditScope creditScopeForItem(
    _CompanyBookingOverviewItem item,
  ) {
    if (isRoundtripOperationalLegRow(item)) {
      return _AdminCreditScope.legOnly;
    }
    return _AdminCreditScope.fullParent;
  }

  static num? creditDecisionMaxAmount(_CompanyBookingOverviewItem item) {
    if (isRoundtripOperationalLegRow(item)) {
      return item.amount;
    }
    return item.parentAmount ?? item.amount;
  }

  static String creditDecisionBusyKey(_CompanyBookingOverviewItem item) {
    final bookingId = item.parentBookingId.trim().isNotEmpty
        ? item.parentBookingId.trim()
        : item.bookingId.trim();
    final legId = item.legId.trim();
    if (legId.isEmpty) return bookingId;
    return '$bookingId::$legId';
  }

  /// Gate for credit decisions and Mollie refund/money actions in Company Bookings.
  static bool canExecuteCompanyBookingMoneyAction(
    _CompanyBookingOverviewItem item,
  ) => hasCanonicalBookingIdentity(item) && hasMinimumOperationalContext(item);

  static bool hasCreditDecisionRecorded(_CompanyBookingOverviewItem item) {
    final decision = _normStatus(item.creditDecision);
    if (decision == 'FULL_CREDIT' ||
        decision == 'PARTIAL_CREDIT' ||
        decision == 'NO_REFUND' ||
        decision == 'HANDLED_MANUALLY') {
      return true;
    }
    final creditStatus = _normStatus(item.creditStatus);
    return creditStatus == 'CREDITED' ||
        creditStatus == 'PARTIAL_CREDIT' ||
        creditStatus == 'NO_REFUND' ||
        creditStatus == 'HANDLED_MANUALLY';
  }

  static bool canShowCreditDecisionActions(_CompanyBookingOverviewItem item) {
    if (!canExecuteCompanyBookingMoneyAction(item)) return false;
    if (!_isCancelledStatus(item.statusText)) return false;
    if (!isPaidPaymentStatus(item.paymentStatus)) return false;
    if (hasCreditDecisionRecorded(item)) return false;
    final pendingDecision =
        _isPendingCreditToken(item.creditStatus) ||
        _isPendingCreditToken(item.refundStatus) ||
        item.refundRequired;
    final visible = pendingDecision;
    debugPrint(
      '[CREDIT_DECISION][ACTION_VISIBILITY] booking=${_safeBookingRefForDiag(item.referenceText.isEmpty ? item.bookingId : item.referenceText)} '
      'leg=${item.legId.trim().isEmpty ? "-" : _safeBookingRefForDiag(item.legId)} '
      'show_decision_actions=$visible credit_decision=${item.creditDecision.isEmpty ? "-" : item.creditDecision}',
    );
    return visible;
  }

  static bool isMollieRefundEligibleCreditDecision(String creditDecision) {
    final normalized = _normStatus(creditDecision);
    return normalized == 'FULL_CREDIT' || normalized == 'PARTIAL_CREDIT';
  }

  static bool shouldShowMollieRefundStatus(_CompanyBookingOverviewItem item) {
    if (canShowCreditDecisionActions(item)) return false;
    if (!_isCancelledStatus(item.statusText)) return false;
    if (!isPaidPaymentStatus(item.paymentStatus)) return false;
    if (isManualPaymentProvider(item.paymentProvider)) return false;
    if (!isMolliePaymentProvider(item.paymentProvider)) return false;
    final decision = _normStatus(item.creditDecision);
    if (decision == 'NO_REFUND' || decision == 'HANDLED_MANUALLY') {
      return false;
    }
    if (hasMollieRefundEligibleCreditStatus(item.creditStatus)) return true;
    return isMollieRefundEligibleCreditDecision(item.creditDecision);
  }

  static bool canShowMollieRefundAction(_CompanyBookingOverviewItem item) {
    if (!canExecuteCompanyBookingMoneyAction(item)) return false;
    if (!shouldShowMollieRefundStatus(item)) return false;
    if (item.refundRequired && !hasCreditDecisionRecorded(item)) return false;
    if (item.creditDecision == 'NO_REFUND' ||
        item.creditDecision == 'HANDLED_MANUALLY') {
      return false;
    }
    if (hasMollieRefundAlreadyApplied(item)) return false;
    return true;
  }

  /// Patch-1 gate: local "Creditnota" (credit note) PDF document action.
  ///
  /// A credit note is a local correction document for a cancelled/credited
  /// booking or leg. It is only shown once a credit decision has been recorded
  /// ([hasCreditDecisionRecorded]) or a refund has reached a final refunded
  /// state ([isRefundLifecycleRefunded], which implies a credit correction
  /// exists). Leg-first: on a roundtrip booking the credit/refund belongs to a
  /// leg row, so the action is suppressed on the (non-leg) roundtrip parent
  /// row and surfaced on the operational leg row instead.
  static bool canShowCreditNotePdfAction(_CompanyBookingOverviewItem item) {
    if (!hasCanonicalBookingIdentity(item)) return false;
    if (!_isCancelledStatus(item.statusText)) return false;
    if (!isPaidPaymentStatus(item.paymentStatus)) return false;
    final hasCorrection =
        hasCreditDecisionRecorded(item) || isRefundLifecycleRefunded(item);
    if (!hasCorrection) return false;
    if (item.isRoundtripParent && !isRoundtripOperationalLegRow(item)) {
      return false;
    }
    return true;
  }

  /// Patch-1 gate: local "Terugbetalingsbewijs" (refund proof) PDF action.
  ///
  /// Shown only for a final refunded lifecycle row ([isRefundLifecycleRefunded]);
  /// never for refund pending or refund failed. Mirrors the leg-first
  /// suppression of [canShowCreditNotePdfAction].
  static bool canShowRefundProofPdfAction(_CompanyBookingOverviewItem item) {
    if (!hasCanonicalBookingIdentity(item)) return false;
    if (!isRefundLifecycleRefunded(item)) return false;
    if (item.isRoundtripParent && !isRoundtripOperationalLegRow(item)) {
      return false;
    }
    return true;
  }

  static ({
    String bookingId,
    String legId,
    String legType,
    String refundScope,
    bool blocked,
    String blockReason,
  })
  resolveMollieRefundTarget(_CompanyBookingOverviewItem item) {
    final parentId = item.parentBookingId.trim().isNotEmpty
        ? item.parentBookingId.trim()
        : item.bookingId.trim();
    final legId = item.legId.trim();
    if (isRoundtripOperationalLegRow(item) && legId.isNotEmpty) {
      final target = (
        bookingId: parentId,
        legId: legId,
        legType: item.legType.trim(),
        refundScope: 'leg_only',
        blocked: false,
        blockReason: '',
      );
      debugPrint(
        '[LEG_REFUND][TARGET] booking=$parentId leg=$legId scope=leg_only '
        'ref=${_safeBookingRefForDiag(item.referenceText.isEmpty ? item.bookingId : item.referenceText)}',
      );
      return target;
    }
    debugPrint(
      '[LEG_REFUND][TARGET] booking=$parentId leg=- scope=full_parent '
      'ref=${_safeBookingRefForDiag(item.referenceText.isEmpty ? item.bookingId : item.referenceText)}',
    );
    return (
      bookingId: parentId,
      legId: '',
      legType: '',
      refundScope: 'full_parent',
      blocked: false,
      blockReason: '',
    );
  }

  static bool canShowMollieRefundAuditResyncAction(
    _CompanyBookingOverviewItem item,
  ) {
    if (!canExecuteCompanyBookingMoneyAction(item)) return false;
    if (!shouldShowMollieRefundStatus(item)) return false;
    if (item.creditDecision == 'NO_REFUND' ||
        item.creditDecision == 'HANDLED_MANUALLY') {
      return false;
    }
    // Leg-only refunds intentionally never emit a parent-level compliance
    // final event from the status-refresh path. Surfacing the audit-resync
    // CTA on a refunded leg row would only re-trigger that suppressed parent
    // emission and confuse operators ("the leg is refunded, why does it
    // still want resync?"). Operator-level resync of parent compliance
    // belongs on the parent booking detail, not on a leg row.
    if (isRoundtripOperationalLegRow(item) &&
        isMollieRefundDisplayRefunded(item)) {
      return false;
    }
    if (item.complianceMollieRefundFinalEmittedAt.trim().isEmpty &&
        isMollieRefundDisplayRefunded(item) &&
        hasMollieRefundAuditResyncSignal(item)) {
      return true;
    }
    if (item.complianceMollieRefundEmittedAt.trim().isNotEmpty) return false;
    if (canShowMollieRefundStatusRefreshAction(item)) return false;
    return hasMollieRefundAuditResyncSignal(item);
  }

  static bool canShowMollieRefundStatusRefreshAction(
    _CompanyBookingOverviewItem item,
  ) {
    final bookingRef = item.referenceText.trim().isNotEmpty
        ? item.referenceText.trim()
        : item.bookingId.trim();
    final legLabel = item.legId.trim().isEmpty ? '-' : item.legId.trim();
    if (!canExecuteCompanyBookingMoneyAction(item)) return false;
    if (!shouldShowMollieRefundStatus(item)) return false;
    // Hard guard: never expose the "Controleer terugbetalingsstatus" button when
    // the row does not carry a refund id we can actually refresh. This is the
    // primary protection against backend missing_mollie_refund_id.
    if (item.mollieRefundId.trim().isEmpty) {
      debugPrint(
        '[REFUND_STATUS_BUTTON][HIDDEN_NO_REFUND_ID] booking=${_safeBookingRefForDiag(bookingRef)} '
        'leg=$legLabel mollie_refund_id=empty',
      );
      return false;
    }
    // Final refunded display = settled from the row's perspective.
    //
    // The previous gate kept the button visible while the parent record's
    // `compliance_mollie_refund_final_emitted_at` was empty so an operator
    // could nudge compliance forward. That worked for full-parent refunds,
    // but for **leg-only** refunds the worker intentionally skips parent
    // compliance final emit (the leg-refund apply path owns it). As a
    // result a fully refunded leg row kept showing "Check refund status"
    // forever. Final refund state on the leg's own fields is the source of
    // truth here, so we hide the button as soon as the row reports
    // refunded/completed/success on either `mollie_refund_status` or
    // `refund_status`.
    if (isMollieRefundDisplayRefunded(item)) {
      debugPrint(
        '[REFUND_STATUS_BUTTON][HIDDEN_FINAL_REFUND] booking=${_safeBookingRefForDiag(bookingRef)} '
        'leg=$legLabel mollie_refund_status=${item.mollieRefundStatus.isEmpty ? "-" : item.mollieRefundStatus} '
        'refund_status=${item.refundStatus.isEmpty ? "-" : item.refundStatus} '
        'compliance_final_emitted_at=${item.complianceMollieRefundFinalEmittedAt.trim().isEmpty ? "empty" : "present"}',
      );
      return false;
    }
    if (isMollieRefundStatusFailed(item.mollieRefundStatus)) return false;
    final pending =
        isMollieRefundDisplayPending(item) ||
        isRefundStatusPending(item.refundStatus);
    if (pending) {
      debugPrint(
        '[REFUND_STATUS_BUTTON][VISIBLE] booking=${_safeBookingRefForDiag(bookingRef)} '
        'leg=$legLabel reason=refund_pending '
        'mollie_refund_status=${item.mollieRefundStatus.isEmpty ? "-" : item.mollieRefundStatus} '
        'refund_status=${item.refundStatus.isEmpty ? "-" : item.refundStatus}',
      );
    }
    return pending;
  }

  static bool _isPendingCreditToken(String raw) {
    return _normStatus(raw) == 'PENDING_CREDIT';
  }

  static bool _isRefundBucketSettledFromRaw(Map<String, dynamic> raw) {
    final mollieRefundStatus = _firstText(raw, const <String>[
      'mollie_refund_status',
      'mollieRefundStatus',
      'record.mollie_refund_status',
      'record.mollieRefundStatus',
      'booking.mollie_refund_status',
      'booking.mollieRefundStatus',
      'record.booking.mollie_refund_status',
      'record.booking.mollieRefundStatus',
      'payload.mollie_refund_status',
      'payload.mollieRefundStatus',
      'record.payload.mollie_refund_status',
      'record.payload.mollieRefundStatus',
    ]);
    final refundStatus = _firstText(raw, const <String>[
      'refund_status',
      'refundStatus',
      'record.refund_status',
      'record.refundStatus',
      'booking.refund_status',
      'booking.refundStatus',
      'record.booking.refund_status',
      'record.booking.refundStatus',
      'payload.refund_status',
      'payload.refundStatus',
      'record.payload.refund_status',
      'record.payload.refundStatus',
    ]);
    final mollieRefundId = _firstText(raw, const <String>[
      'mollie_refund_id',
      'mollieRefundId',
      'refund_id',
      'refundId',
      'record.mollie_refund_id',
      'record.mollieRefundId',
      'record.refund_id',
      'record.refundId',
      'booking.mollie_refund_id',
      'booking.mollieRefundId',
      'booking.refund_id',
      'booking.refundId',
      'record.booking.mollie_refund_id',
      'record.booking.mollieRefundId',
      'record.booking.refund_id',
      'record.booking.refundId',
      'payload.mollie_refund_id',
      'payload.mollieRefundId',
      'payload.refund_id',
      'payload.refundId',
      'record.payload.mollie_refund_id',
      'record.payload.mollieRefundId',
      'record.payload.refund_id',
      'record.payload.refundId',
    ]);
    final refundedAmountRaw = _firstNum(raw, const <String>[
      'refunded_amount_cents',
      'refundedAmountCents',
      'record.refunded_amount_cents',
      'record.refundedAmountCents',
      'booking.refunded_amount_cents',
      'booking.refundedAmountCents',
      'record.booking.refunded_amount_cents',
      'record.booking.refundedAmountCents',
      'payload.refunded_amount_cents',
      'payload.refundedAmountCents',
      'record.payload.refunded_amount_cents',
      'record.payload.refundedAmountCents',
    ]);
    final complianceFinal = _firstText(raw, const <String>[
      'compliance_mollie_refund_final_emitted_at',
      'complianceMollieRefundFinalEmittedAt',
      'record.compliance_mollie_refund_final_emitted_at',
      'record.complianceMollieRefundFinalEmittedAt',
      'booking.compliance_mollie_refund_final_emitted_at',
      'booking.complianceMollieRefundFinalEmittedAt',
      'record.booking.compliance_mollie_refund_final_emitted_at',
      'record.booking.complianceMollieRefundFinalEmittedAt',
      'payload.compliance_mollie_refund_final_emitted_at',
      'payload.complianceMollieRefundFinalEmittedAt',
      'record.payload.compliance_mollie_refund_final_emitted_at',
      'record.payload.complianceMollieRefundFinalEmittedAt',
    ]);
    if (isMollieRefundStatusRefunded(mollieRefundStatus)) return true;
    if (isRefundStatusRefundedOrComplete(refundStatus)) return true;
    if (complianceFinal.trim().isNotEmpty && mollieRefundId.trim().isNotEmpty) {
      return true;
    }
    if ((refundedAmountRaw ?? 0) > 0 &&
        !isRefundStatusPending(refundStatus) &&
        !isMollieRefundStatusPending(mollieRefundStatus)) {
      return true;
    }
    return false;
  }

  /// True when this row should be visible inside the **Geannuleerd** tab.
  ///
  /// Mutually exclusive with [isPendingCredit]: a paid cancelled leg that still
  /// requires an administrator credit decision belongs in **Te crediteren**.
  /// Refund lifecycle follow-up is exposed by separate refund status filters.
  static bool isCancelledBucketVisible(_CompanyBookingOverviewItem item) {
    if (item.bucket != _CompanyBookingsFilter.cancelled) return false;
    return !item.isPendingCredit;
  }

  /// True when this row should be visible inside the **Te crediteren** tab.
  static bool isToCreditBucketVisible(_CompanyBookingOverviewItem item) {
    return item.isPendingCredit;
  }

  /// Settlement label for a paid cancelled row that no longer needs refund
  /// follow-up. Used by the Cancelled tab to render a clear status chip.
  /// Returns an empty string when no settlement state is applicable yet.
  static String settledRefundChipToken(_CompanyBookingOverviewItem item) {
    if (item.bucket != _CompanyBookingsFilter.cancelled) return '';
    if (item.isPendingCredit) return '';
    if (!isPaidPaymentStatus(item.paymentStatus)) return '';
    final decision = _normStatus(item.creditDecision);
    if (decision == 'NO_REFUND') return 'NO_REFUND';
    if (decision == 'HANDLED_MANUALLY') return 'HANDLED_MANUALLY';
    if (isMollieRefundDisplayRefunded(item)) {
      if (decision == 'PARTIAL_CREDIT') return 'PARTIAL_REFUNDED';
      return 'REFUNDED';
    }
    if (decision == 'FULL_CREDIT') return 'REFUNDED';
    if (decision == 'PARTIAL_CREDIT') return 'PARTIAL_REFUNDED';
    final creditStatus = _normStatus(item.creditStatus);
    if (creditStatus == 'NO_REFUND') return 'NO_REFUND';
    if (creditStatus == 'HANDLED_MANUALLY') return 'HANDLED_MANUALLY';
    return '';
  }

  static void logRefundQueueDiagnostic(_CompanyBookingOverviewItem item) {
    final bookingLabel = item.referenceText.trim().isNotEmpty
        ? item.referenceText.trim()
        : item.bookingId.trim();
    if (bookingLabel.isEmpty) return;
    final legLabel = item.legId.trim().isEmpty ? '-' : item.legId.trim();
    final inCancelled = isCancelledBucketVisible(item);
    final inToCredit = isToCreditBucketVisible(item);
    debugPrint(
      '[REFUND_BUCKET][QUEUE] booking=${_safeBookingRefForDiag(bookingLabel)} '
      'leg=$legLabel cancelled_visible=$inCancelled to_credit=$inToCredit '
      'status=${item.statusText.isEmpty ? "-" : item.statusText} '
      'payment=${item.paymentStatus.isEmpty ? "-" : item.paymentStatus} '
      'credit_decision=${item.creditDecision.isEmpty ? "-" : item.creditDecision} '
      'mollie_refund_id=${item.mollieRefundId.trim().isEmpty ? "empty" : "present"} '
      'mollie_refund_status=${item.mollieRefundStatus.isEmpty ? "-" : item.mollieRefundStatus}',
    );
    if (inCancelled &&
        isPaidPaymentStatus(item.paymentStatus) &&
        settledRefundChipToken(item).isNotEmpty) {
      debugPrint(
        '[REFUND_BUCKET][CANCELLED_VISIBLE] booking=${_safeBookingRefForDiag(bookingLabel)} '
        'leg=$legLabel settlement=${settledRefundChipToken(item)}',
      );
    }
  }

  static void logRefundBucketStateDiagnostic(_CompanyBookingOverviewItem item) {
    final bookingLabel = item.referenceText.trim().isNotEmpty
        ? item.referenceText.trim()
        : item.bookingId.trim();
    if (bookingLabel.isEmpty) return;
    final inCancelled = item.bucket == _CompanyBookingsFilter.cancelled;
    final inToCredit = item.isPendingCredit;
    final refundSettled =
        isMollieRefundDisplayRefunded(item) ||
        (hasMollieRefundAlreadyApplied(item) &&
            !isMollieRefundDisplayPending(item));
    debugPrint(
      '[REFUND_BUCKET][STATE] booking=$bookingLabel '
      'cancelled_bucket=$inCancelled to_credit=$inToCredit '
      'refund_settled=$refundSettled refund_status=${item.refundStatus.isEmpty ? "-" : item.refundStatus} '
      'mollie_refund_status=${item.mollieRefundStatus.isEmpty ? "-" : item.mollieRefundStatus} '
      'can_refund=${canShowMollieRefundAction(item)}',
    );
  }

  static bool _deriveIsPendingCredit({
    required Map<String, dynamic> raw,
    required String statusRaw,
    required String paymentStatus,
    required String creditStatus,
    required String refundStatus,
    required bool refundRequired,
    required String creditDecision,
    required String paymentProvider,
    required String bookingRef,
    required String parentRef,
    required String legType,
  }) {
    if (!_isCancelledStatus(statusRaw)) return false;
    final isPaid =
        isPaidPaymentStatus(paymentStatus) || _inferPaidFromRawMap(raw);
    if (!isPaid) {
      _logCreditClassify(
        bookingRef: bookingRef,
        parentRef: parentRef,
        legType: legType,
        isPaid: false,
        isCreditEligible: false,
        reason: 'skip_unpaid',
      );
      return false;
    }
    if (_isRefundBucketSettledFromRaw(raw)) {
      debugPrint(
        '[REFUND_BUCKET][SETTLED] booking=${_safeBookingRefForDiag(bookingRef)} '
        'leg=${legType.isEmpty ? "-" : legType} reason=mollie_refund_complete',
      );
      _logCreditClassify(
        bookingRef: bookingRef,
        parentRef: parentRef,
        legType: legType,
        isPaid: true,
        isCreditEligible: false,
        reason: 'refund_settled',
      );
      return false;
    }
    final decision = _normStatus(creditDecision);
    if (decision == 'NO_REFUND' || decision == 'HANDLED_MANUALLY') {
      debugPrint(
        '[CREDIT_DECISION][STATE] booking=${_safeBookingRefForDiag(bookingRef)} '
        'leg=${legType.isEmpty ? "-" : legType} decision=$decision to_credit=false reason=settled_manual',
      );
      return false;
    }
    if (decision == 'FULL_CREDIT' || decision == 'PARTIAL_CREDIT') {
      debugPrint(
        '[CREDIT_DECISION][STATE] booking=${_safeBookingRefForDiag(bookingRef)} '
        'leg=${legType.isEmpty ? "-" : legType} decision=$decision to_credit=false reason=decision_recorded',
      );
      return false;
    }
    final resolvedCreditStatus = _normStatus(creditStatus);
    if (resolvedCreditStatus == 'NO_REFUND' ||
        resolvedCreditStatus == 'HANDLED_MANUALLY') {
      return false;
    }
    if (resolvedCreditStatus == 'CREDITED' ||
        resolvedCreditStatus == 'PARTIAL_CREDIT') {
      return false;
    }
    final needsDecision =
        _isPendingCreditToken(creditStatus) ||
        _isPendingCreditToken(refundStatus) ||
        refundRequired;
    debugPrint(
      '[CREDIT_DECISION][STATE] booking=${_safeBookingRefForDiag(bookingRef)} '
      'leg=${legType.isEmpty ? "-" : legType} to_credit=$needsDecision reason=${needsDecision ? "pending_decision" : "paid_not_creditable"}',
    );
    _logCreditClassify(
      bookingRef: bookingRef,
      parentRef: parentRef,
      legType: legType,
      isPaid: true,
      isCreditEligible: needsDecision,
      reason: needsDecision ? 'pending_credit' : 'paid_not_creditable',
    );
    return needsDecision;
  }

  static _CompanyBookingsFilter _bucketFromStatus({required String statusRaw}) {
    final normalized = _normStatus(statusRaw);
    if (normalized.contains('CANCEL')) return _CompanyBookingsFilter.cancelled;
    if (normalized == 'DELETED') return _CompanyBookingsFilter.cancelled;
    if (normalized.contains('COMPLETE') ||
        normalized == 'DONE' ||
        normalized == 'FINISHED') {
      return _CompanyBookingsFilter.completed;
    }
    return _CompanyBookingsFilter.open;
  }

  factory _CompanyBookingOverviewItem.fromMap(Map<String, dynamic> raw) {
    final bookingId = _firstText(raw, const <String>[
      'booking_id',
      'bookingId',
      'id',
      'record.booking_id',
      'record.bookingId',
      'record.booking.id',
      'booking.id',
    ]);
    final parentBookingId = _firstText(raw, const <String>[
      'parent_booking_id',
      'parentBookingId',
      'booking_id',
      'bookingId',
      'id',
      'record.parent_booking_id',
      'record.parentBookingId',
      'record.booking_id',
      'record.bookingId',
      'record.booking.parent_booking_id',
      'record.booking.parentBookingId',
    ]);
    final legId = _firstText(raw, const <String>[
      'leg_id',
      'legId',
      'record.leg_id',
      'record.legId',
      'booking.leg_id',
      'booking.legId',
    ]);
    final legType = _firstText(raw, const <String>[
      'leg_type',
      'legType',
      'record.leg_type',
      'record.legType',
      'booking.leg_type',
      'booking.legType',
    ]);
    final isOperationalLegToken = _firstText(raw, const <String>[
      'is_operational_leg',
      'isOperationalLeg',
      'record.is_operational_leg',
      'record.isOperationalLeg',
      'booking.is_operational_leg',
      'booking.isOperationalLeg',
    ]).toLowerCase();
    final isOperationalLeg =
        isOperationalLegToken == 'true' ||
        isOperationalLegToken == '1' ||
        legId.isNotEmpty;
    final isRoundtripToken = _firstText(raw, const <String>[
      'is_roundtrip_parent',
      'isRoundtripParent',
      'record.is_roundtrip_parent',
      'record.isRoundtripParent',
      'booking.is_roundtrip_parent',
      'booking.isRoundtripParent',
    ]).toLowerCase();
    final isRoundtripParent =
        isRoundtripToken == 'true' || isRoundtripToken == '1';
    final planningRef = _firstText(raw, const <String>[
      'planning_reference',
      'planningReference',
      'record.planning_reference',
      'record.planningReference',
      'booking.planning_reference',
      'booking.planningReference',
    ]);
    final publicRef = _firstText(raw, const <String>[
      'public_booking_reference',
      'publicBookingReference',
      'booking_reference',
      'bookingReference',
      'record.public_booking_reference',
      'record.publicBookingReference',
      'record.booking_reference',
      'record.bookingReference',
      'booking.public_booking_reference',
      'booking.publicBookingReference',
      'booking.booking_reference',
      'booking.bookingReference',
    ]);
    final referenceText = planningRef.isNotEmpty
        ? planningRef
        : (publicRef.isNotEmpty ? publicRef : bookingId);
    final parentRef = _firstText(raw, const <String>[
      'parent_booking_reference',
      'parentBookingReference',
      'linked_order_reference',
      'linkedOrderReference',
      'planning_reference',
      'planningReference',
      'public_booking_reference',
      'publicBookingReference',
      'booking_reference',
      'bookingReference',
      'record.parent_booking_reference',
      'record.parentBookingReference',
      'record.linked_order_reference',
      'record.linkedOrderReference',
      'record.planning_reference',
      'record.planningReference',
      'record.public_booking_reference',
      'record.publicBookingReference',
      'record.booking_reference',
      'record.bookingReference',
      'booking.parent_booking_reference',
      'booking.parentBookingReference',
      'booking.linked_order_reference',
      'booking.linkedOrderReference',
      'booking.planning_reference',
      'booking.planningReference',
      'booking.public_booking_reference',
      'booking.publicBookingReference',
      'booking.booking_reference',
      'booking.bookingReference',
    ]);
    final pickupIso = _firstText(raw, const <String>[
      'pickup_iso',
      'pickupIso',
      'booking.pickup_iso',
      'booking.pickupIso',
      'quote.pickup_iso',
      'record.pickup_iso',
      'record.pickupIso',
      'record.booking.pickup_iso',
      'record.booking.pickupIso',
      'record.quote.pickup_iso',
    ]);
    final fromAddress = _firstText(raw, const <String>[
      'from',
      'pickup',
      'pickup_address',
      'booking.pickup.address',
      'booking.pickup_address',
      'quote.pickup.address',
      'quote.pickup_address',
      'record.from',
      'record.booking.pickup.address',
      'record.booking.pickup_address',
      'record.quote.pickup.address',
      'record.quote.pickup_address',
    ]);
    final toAddress = _firstText(raw, const <String>[
      'to',
      'dropoff',
      'dropoff_address',
      'booking.dropoff.address',
      'booking.dropoff_address',
      'quote.dropoff.address',
      'quote.dropoff_address',
      'record.to',
      'record.booking.dropoff.address',
      'record.booking.dropoff_address',
      'record.quote.dropoff.address',
      'record.quote.dropoff_address',
    ]);
    final customerName = _firstText(raw, const <String>[
      'customer_name',
      'customerName',
      'booking.customer_name',
      'booking.customerName',
      'record.customer_name',
      'record.customerName',
      'record.booking.customer_name',
      'record.booking.customerName',
      'record.booking.customer.name',
      'booking.customer.name',
    ]);
    final assignedDriver = _firstText(raw, const <String>[
      'assigned_driver_name',
      'assignedDriverName',
      'assigned_driver_id',
      'assignedDriverId',
      'driver_id',
      'driverId',
      'booking.assigned_driver_name',
      'booking.assignedDriverName',
      'booking.assigned_driver_id',
      'booking.assignedDriverId',
      'record.booking.assigned_driver_name',
      'record.booking.assignedDriverName',
      'record.booking.assigned_driver_id',
      'record.booking.assignedDriverId',
      'record.booking.driver_id',
      'record.booking.driverId',
    ]);
    final assignedVehicle = _firstText(raw, const <String>[
      'assigned_vehicle_id',
      'assignedVehicleId',
      'vehicle_id',
      'vehicleId',
      'booking.assigned_vehicle_id',
      'booking.assignedVehicleId',
      'booking.vehicle_id',
      'booking.vehicleId',
      'record.booking.assigned_vehicle_id',
      'record.booking.assignedVehicleId',
      'record.booking.vehicle_id',
      'record.booking.vehicleId',
    ]);
    final statusRaw = _firstText(raw, const <String>[
      'status',
      'lifecycle',
      'lifecycle_status',
      'stage',
      'booking.status',
      'booking.lifecycle',
      'booking.lifecycle_status',
      'record.status',
      'record.lifecycle',
      'record.lifecycle_status',
      'record.booking.status',
      'record.booking.lifecycle',
      'record.booking.lifecycle_status',
      'record.booking.stage',
    ]);
    final paymentStatus = _firstText(raw, const <String>[
      'payment_status',
      'paymentStatus',
      'record.payment_status',
      'record.paymentStatus',
      'booking.payment_status',
      'booking.paymentStatus',
      'record.booking.payment_status',
      'record.booking.paymentStatus',
      'quote.payment_status',
      'quote.paymentStatus',
      'record.quote.payment_status',
      'record.quote.paymentStatus',
      'payload.payment_status',
      'payload.paymentStatus',
      'record.payload.payment_status',
      'record.payload.paymentStatus',
      'mollie.status',
      'record.mollie.status',
      'booking.mollie.status',
    ]);
    final paymentProvider = _firstText(raw, const <String>[
      'payment_provider',
      'paymentProvider',
      'payment_mode',
      'paymentMode',
      'record.payment_provider',
      'record.paymentProvider',
      'record.payment_mode',
      'record.paymentMode',
      'booking.payment_provider',
      'booking.paymentProvider',
      'booking.payment_mode',
      'booking.paymentMode',
      'record.booking.payment_provider',
      'record.booking.paymentProvider',
      'payload.payment_provider',
      'payload.paymentProvider',
    ]);
    final creditStatus = _firstText(raw, const <String>[
      'credit_status',
      'creditStatus',
      'record.credit_status',
      'record.creditStatus',
      'booking.credit_status',
      'booking.creditStatus',
      'record.booking.credit_status',
      'record.booking.creditStatus',
      'payload.credit_status',
      'payload.creditStatus',
      'record.payload.credit_status',
      'record.payload.creditStatus',
    ]);
    final refundStatus = _firstText(raw, const <String>[
      'refund_status',
      'refundStatus',
      'record.refund_status',
      'record.refundStatus',
      'booking.refund_status',
      'booking.refundStatus',
      'record.booking.refund_status',
      'record.booking.refundStatus',
      'payload.refund_status',
      'payload.refundStatus',
      'record.payload.refund_status',
      'record.payload.refundStatus',
    ]);
    final refundRequired = _firstBool(raw, const <String>[
      'refund_required',
      'refundRequired',
      'record.refund_required',
      'record.refundRequired',
      'booking.refund_required',
      'booking.refundRequired',
      'record.booking.refund_required',
      'record.booking.refundRequired',
      'payload.refund_required',
      'payload.refundRequired',
      'record.payload.refund_required',
      'record.payload.refundRequired',
    ]);
    final creditDecision = _firstText(raw, const <String>[
      'credit_decision',
      'creditDecision',
      'record.credit_decision',
      'record.creditDecision',
      'booking.credit_decision',
      'booking.creditDecision',
      'record.booking.credit_decision',
      'record.booking.creditDecision',
      'payload.credit_decision',
      'payload.creditDecision',
      'record.payload.credit_decision',
      'record.payload.creditDecision',
    ]);
    final creditedAmountRaw = _firstNum(raw, const <String>[
      'credited_amount_cents',
      'creditedAmountCents',
      'record.credited_amount_cents',
      'record.creditedAmountCents',
      'booking.credited_amount_cents',
      'booking.creditedAmountCents',
      'record.booking.credited_amount_cents',
      'record.booking.creditedAmountCents',
      'payload.credited_amount_cents',
      'payload.creditedAmountCents',
      'record.payload.credited_amount_cents',
      'record.payload.creditedAmountCents',
    ]);
    final creditedAt = _firstText(raw, const <String>[
      'credited_at',
      'creditedAt',
      'record.credited_at',
      'record.creditedAt',
      'booking.credited_at',
      'booking.creditedAt',
      'record.booking.credited_at',
      'record.booking.creditedAt',
      'payload.credited_at',
      'payload.creditedAt',
      'record.payload.credited_at',
      'record.payload.creditedAt',
    ]);
    final mollieRefundId = _firstText(raw, const <String>[
      'mollie_refund_id',
      'mollieRefundId',
      'refund_id',
      'refundId',
      'record.mollie_refund_id',
      'record.mollieRefundId',
      'record.refund_id',
      'record.refundId',
      'booking.mollie_refund_id',
      'booking.mollieRefundId',
      'booking.refund_id',
      'booking.refundId',
      'record.booking.mollie_refund_id',
      'record.booking.mollieRefundId',
      'record.booking.refund_id',
      'record.booking.refundId',
      'payload.mollie_refund_id',
      'payload.mollieRefundId',
      'payload.refund_id',
      'payload.refundId',
      'record.payload.mollie_refund_id',
      'record.payload.mollieRefundId',
      'record.payload.refund_id',
      'record.payload.refundId',
    ]);
    final mollieRefundStatus = _firstText(raw, const <String>[
      'mollie_refund_status',
      'mollieRefundStatus',
      'record.mollie_refund_status',
      'record.mollieRefundStatus',
      'booking.mollie_refund_status',
      'booking.mollieRefundStatus',
      'record.booking.mollie_refund_status',
      'record.booking.mollieRefundStatus',
      'payload.mollie_refund_status',
      'payload.mollieRefundStatus',
      'record.payload.mollie_refund_status',
      'record.payload.mollieRefundStatus',
    ]);
    final refundedAmountRaw = _firstNum(raw, const <String>[
      'refunded_amount_cents',
      'refundedAmountCents',
      'record.refunded_amount_cents',
      'record.refundedAmountCents',
      'booking.refunded_amount_cents',
      'booking.refundedAmountCents',
      'record.booking.refunded_amount_cents',
      'record.booking.refundedAmountCents',
      'payload.refunded_amount_cents',
      'payload.refundedAmountCents',
      'record.payload.refunded_amount_cents',
      'record.payload.refundedAmountCents',
    ]);
    final refundedAt = _firstText(raw, const <String>[
      'refunded_at',
      'refundedAt',
      'record.refunded_at',
      'record.refundedAt',
      'booking.refunded_at',
      'booking.refundedAt',
      'record.booking.refunded_at',
      'record.booking.refundedAt',
      'payload.refunded_at',
      'payload.refundedAt',
      'record.payload.refunded_at',
      'record.payload.refundedAt',
    ]);
    final refundProvider = _firstText(raw, const <String>[
      'refund_provider',
      'refundProvider',
      'record.refund_provider',
      'record.refundProvider',
      'booking.refund_provider',
      'booking.refundProvider',
      'record.booking.refund_provider',
      'record.booking.refundProvider',
      'payload.refund_provider',
      'payload.refundProvider',
      'record.payload.refund_provider',
      'record.payload.refundProvider',
    ]);
    final complianceMollieRefundFinalEmittedAt = _firstText(raw, const <String>[
      'compliance_mollie_refund_final_emitted_at',
      'complianceMollieRefundFinalEmittedAt',
      'record.compliance_mollie_refund_final_emitted_at',
      'record.complianceMollieRefundFinalEmittedAt',
      'booking.compliance_mollie_refund_final_emitted_at',
      'booking.complianceMollieRefundFinalEmittedAt',
      'record.booking.compliance_mollie_refund_final_emitted_at',
      'record.booking.complianceMollieRefundFinalEmittedAt',
      'payload.compliance_mollie_refund_final_emitted_at',
      'payload.complianceMollieRefundFinalEmittedAt',
      'record.payload.compliance_mollie_refund_final_emitted_at',
      'record.payload.complianceMollieRefundFinalEmittedAt',
    ]);
    final complianceMollieRefundEmittedAt = _firstText(raw, const <String>[
      'compliance_mollie_refund_emitted_at',
      'complianceMollieRefundEmittedAt',
      'record.compliance_mollie_refund_emitted_at',
      'record.complianceMollieRefundEmittedAt',
      'booking.compliance_mollie_refund_emitted_at',
      'booking.complianceMollieRefundEmittedAt',
      'record.booking.compliance_mollie_refund_emitted_at',
      'record.booking.complianceMollieRefundEmittedAt',
      'payload.compliance_mollie_refund_emitted_at',
      'payload.complianceMollieRefundEmittedAt',
      'record.payload.compliance_mollie_refund_emitted_at',
      'record.payload.complianceMollieRefundEmittedAt',
    ]);
    final amount = _firstNum(raw, const <String>[
      'leg_price_incl_vat',
      'legPriceInclVat',
      'price',
      'total_price',
      'total',
      'amount',
      'eur',
      'quote.price',
      'quote.total_price',
      'quote.total',
      'quote.amount',
      'quote.eur',
      'quote.pricing.price_incl_vat',
      'quote.pricing.total_price',
      'quote.pricing.total',
      'quote.pricing.price',
      'quote.pricing.amount',
      'quote.pricing.eur',
      'record.price',
      'record.total_price',
      'record.total',
      'record.amount',
      'record.quote.price',
      'record.quote.total_price',
      'record.quote.total',
      'record.quote.amount',
      'record.quote.eur',
      'record.quote.pricing.price_incl_vat',
      'record.quote.pricing.total_price',
      'record.quote.pricing.total',
      'record.quote.pricing.price',
      'record.quote.pricing.amount',
      'record.quote.pricing.eur',
      'booking.total_price',
      'booking.price',
      'booking.amount',
      'record.booking.total_price',
      'record.booking.price',
      'record.booking.amount',
    ]);
    final parentAmount = _firstNum(raw, const <String>[
      'parent_total_price',
      'parentTotalPrice',
      'parent_price_incl_vat',
      'parentPriceInclVat',
      'booking.price_incl_vat',
      'booking.total_price',
      'record.booking.price_incl_vat',
      'record.booking.total_price',
      'price',
      'total_price',
      'total',
      'amount',
    ]);
    final currency = _firstText(raw, const <String>[
      'currency',
      'quote.currency',
      'quote.pricing.currency',
      'record.currency',
      'record.quote.currency',
      'record.quote.pricing.currency',
      'booking.currency',
      'record.booking.currency',
    ]);
    final isPendingCredit = _deriveIsPendingCredit(
      raw: raw,
      statusRaw: statusRaw,
      paymentStatus: paymentStatus,
      creditStatus: creditStatus,
      refundStatus: refundStatus,
      refundRequired: refundRequired,
      creditDecision: creditDecision,
      paymentProvider: paymentProvider,
      bookingRef: referenceText.isEmpty ? bookingId : referenceText,
      parentRef: parentRef.isEmpty ? referenceText : parentRef,
      legType: legType,
    );
    final isPaid =
        isPaidPaymentStatus(paymentStatus) || _inferPaidFromRawMap(raw);
    final normalizedPaymentStatus = isPaid
        ? 'PAID'
        : (_normStatus(paymentStatus).isNotEmpty
              ? _normStatus(paymentStatus)
              : 'UNPAID');
    _logBookingPaymentClassify(
      raw: raw,
      bookingRef: referenceText.isEmpty ? bookingId : referenceText,
      parentRef: parentRef.isEmpty ? referenceText : parentRef,
      legType: legType,
      rawPaymentStatus: paymentStatus,
      normalizedPaymentStatus: normalizedPaymentStatus,
      isPaid: isPaid,
      isCreditEligible: isPendingCredit,
    );
    final bucket = _bucketFromStatus(statusRaw: statusRaw);
    if (isOperationalLeg) {
      debugPrint(
        '[ROUNDTRIP_LEG_UI][COMPANY_FILTER] parent=${_safeBookingRefForDiag(parentBookingId.isEmpty ? bookingId : parentBookingId)} leg=${_safeBookingRefForDiag(legId)} type=${legType.isEmpty ? "-" : legType} status=${_normStatus(statusRaw)} bucket=${bucket.name} parentStatus=${_firstText(raw, const <String>['parent_status', 'parentStatus', 'record.parent_status', 'record.parentStatus']).trim().isEmpty ? "-" : _firstText(raw, const <String>['parent_status', 'parentStatus', 'record.parent_status', 'record.parentStatus'])}',
      );
    }
    return _CompanyBookingOverviewItem(
      bookingId: bookingId,
      parentBookingId: parentBookingId.isEmpty ? bookingId : parentBookingId,
      legId: legId,
      legType: legType,
      isOperationalLeg: isOperationalLeg,
      isRoundtripParent: isRoundtripParent,
      referenceText: referenceText.isEmpty ? bookingId : referenceText,
      parentReferenceText: parentRef.isEmpty ? referenceText : parentRef,
      pickupIso: pickupIso,
      fromAddress: fromAddress.isEmpty ? '—' : fromAddress,
      toAddress: toAddress.isEmpty ? '—' : toAddress,
      customerName: customerName,
      assignedDriverText: assignedDriver.isEmpty ? '—' : assignedDriver,
      assignedVehicleText: assignedVehicle.isEmpty ? '—' : assignedVehicle,
      statusText: _normStatus(statusRaw),
      paymentStatus: normalizedPaymentStatus,
      paymentProvider: _normStatus(paymentProvider),
      creditStatus: _normStatus(creditStatus),
      refundStatus: _normStatus(refundStatus),
      refundRequired: refundRequired,
      creditDecision: _normStatus(creditDecision),
      creditedAmountCents: creditedAmountRaw?.round(),
      creditedAt: creditedAt,
      mollieRefundId: mollieRefundId,
      mollieRefundStatus: _normStatus(mollieRefundStatus),
      refundedAmountCents: refundedAmountRaw?.round(),
      refundedAt: refundedAt,
      refundProvider: _normStatus(refundProvider),
      complianceMollieRefundEmittedAt: complianceMollieRefundEmittedAt,
      complianceMollieRefundFinalEmittedAt:
          complianceMollieRefundFinalEmittedAt,
      isPendingCredit: isPendingCredit,
      amount: amount,
      parentAmount: parentAmount,
      currency: currency,
      bucket: bucket,
    );
  }
}
