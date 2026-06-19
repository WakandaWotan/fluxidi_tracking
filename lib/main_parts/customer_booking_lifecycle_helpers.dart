part of '../main.dart';

dynamic _customerBookingValueAtPath(Map<String, dynamic> root, String path) {
  dynamic current = root;
  for (final segment in path.split('.')) {
    if (current is Map && current.containsKey(segment)) {
      current = current[segment];
    } else {
      return null;
    }
  }
  return current;
}

Set<String> _customerBookingAliasesFromSource(Map<String, dynamic> source) {
  const aliasPaths = <String>[
    'booking_id',
    'bookingId',
    'id',
    'public_booking_id',
    'publicBookingId',
    'public_booking_reference',
    'publicBookingReference',
    'booking_reference',
    'bookingReference',
    'public_reference',
    'publicReference',
    'planning_reference',
    'planningReference',
    'receipt_reference',
    'receiptReference',
    'payment_booking_id',
    'paymentBookingId',
    'parent_booking_id',
    'parentBookingId',
    'original_booking_id',
    'originalBookingId',
    'booking.booking_id',
    'booking.bookingId',
    'booking.id',
    'booking.public_booking_id',
    'booking.publicBookingId',
    'booking.public_booking_reference',
    'booking.publicBookingReference',
    'booking.booking_reference',
    'booking.bookingReference',
    'booking.public_reference',
    'booking.publicReference',
    'booking.planning_reference',
    'booking.planningReference',
    'booking.receipt_reference',
    'booking.receiptReference',
    'booking.payment_booking_id',
    'booking.paymentBookingId',
    'booking.parent_booking_id',
    'booking.parentBookingId',
    'booking.original_booking_id',
    'booking.originalBookingId',
    'booking_details.booking_id',
    'booking_details.bookingId',
    'booking_details.public_booking_id',
    'booking_details.publicBookingId',
    'booking_details.public_booking_reference',
    'booking_details.publicBookingReference',
    'booking_details.booking_reference',
    'booking_details.bookingReference',
    'booking_details.public_reference',
    'booking_details.publicReference',
    'booking_details.planning_reference',
    'booking_details.planningReference',
    'booking_details.receipt_reference',
    'booking_details.receiptReference',
    'booking_details.payment_booking_id',
    'booking_details.paymentBookingId',
    'booking_details.parent_booking_id',
    'booking_details.parentBookingId',
    'booking_details.original_booking_id',
    'booking_details.originalBookingId',
    'record.booking_id',
    'record.bookingId',
    'record.id',
    'record.public_booking_id',
    'record.publicBookingId',
    'record.parent_booking_id',
    'record.parentBookingId',
    'record.original_booking_id',
    'record.originalBookingId',
    'record.booking.booking_id',
    'record.booking.bookingId',
    'record.booking.id',
    'record.references.public_booking_reference',
    'record.references.publicBookingReference',
    'record.references.booking_reference',
    'record.references.bookingReference',
    'record.references.public_reference',
    'record.references.publicReference',
    'record.references.planning_reference',
    'record.references.planningReference',
    'record.references.receipt_reference',
    'record.references.receiptReference',
    'record.booking_details.booking_id',
    'record.booking_details.bookingId',
    'record.booking_details.public_booking_id',
    'record.booking_details.publicBookingId',
    'record.booking_details.public_booking_reference',
    'record.booking_details.publicBookingReference',
    'record.booking_details.booking_reference',
    'record.booking_details.bookingReference',
    'record.booking_details.public_reference',
    'record.booking_details.publicReference',
    'record.booking_details.planning_reference',
    'record.booking_details.planningReference',
    'record.booking_details.receipt_reference',
    'record.booking_details.receiptReference',
    'record.booking_details.payment_booking_id',
    'record.booking_details.paymentBookingId',
    'record.booking_details.parent_booking_id',
    'record.booking_details.parentBookingId',
    'record.booking_details.original_booking_id',
    'record.booking_details.originalBookingId',
    'payload.booking_id',
    'payload.bookingId',
    'payload.id',
    'payload.public_booking_id',
    'payload.publicBookingId',
    'payload.parent_booking_id',
    'payload.parentBookingId',
    'payload.original_booking_id',
    'payload.originalBookingId',
    'payload.booking.booking_id',
    'payload.booking.bookingId',
    'payload.booking.id',
    'payload.references.public_booking_reference',
    'payload.references.publicBookingReference',
    'payload.references.booking_reference',
    'payload.references.bookingReference',
    'payload.references.public_reference',
    'payload.references.publicReference',
    'payload.references.planning_reference',
    'payload.references.planningReference',
    'payload.references.receipt_reference',
    'payload.references.receiptReference',
    'payload.booking_details.booking_id',
    'payload.booking_details.bookingId',
    'payload.booking_details.public_booking_id',
    'payload.booking_details.publicBookingId',
    'payload.booking_details.public_booking_reference',
    'payload.booking_details.publicBookingReference',
    'payload.booking_details.booking_reference',
    'payload.booking_details.bookingReference',
    'payload.booking_details.public_reference',
    'payload.booking_details.publicReference',
    'payload.booking_details.planning_reference',
    'payload.booking_details.planningReference',
    'payload.booking_details.receipt_reference',
    'payload.booking_details.receiptReference',
    'payload.booking_details.payment_booking_id',
    'payload.booking_details.paymentBookingId',
    'payload.booking_details.parent_booking_id',
    'payload.booking_details.parentBookingId',
    'payload.booking_details.original_booking_id',
    'payload.booking_details.originalBookingId',
    'references.public_booking_reference',
    'references.publicBookingReference',
    'references.booking_reference',
    'references.bookingReference',
    'references.public_reference',
    'references.publicReference',
    'references.planning_reference',
    'references.planningReference',
    'references.receipt_reference',
    'references.receiptReference',
    'references.payment_booking_id',
    'references.paymentBookingId',
    'references.parent_booking_id',
    'references.parentBookingId',
    'references.original_booking_id',
    'references.originalBookingId',
  ];
  final aliases = <String>{};
  void addAlias(dynamic value) {
    final text = _cleanBusinessReferenceText(value?.toString());
    if (text == null) return;
    aliases.add(text.toLowerCase());
  }

  for (final path in aliasPaths) {
    addAlias(_customerBookingValueAtPath(source, path));
  }
  return aliases;
}

Set<String> _customerBookingDeleteAliases({
  String? bookingId,
  String? publicBookingReference,
  String? bookingReference,
  String? publicReference,
  String? planningReference,
  String? receiptReference,
  String? paymentBookingId,
  String? parentBookingId,
  String? originalBookingId,
  Map<String, dynamic>? source,
}) {
  final aliases = <String>{};
  void addAlias(String? value) {
    final text = _cleanBusinessReferenceText(value);
    if (text == null) return;
    aliases.add(text.toLowerCase());
  }

  addAlias(bookingId);
  addAlias(publicBookingReference);
  addAlias(bookingReference);
  addAlias(publicReference);
  addAlias(planningReference);
  addAlias(receiptReference);
  addAlias(paymentBookingId);
  addAlias(parentBookingId);
  addAlias(originalBookingId);
  if (source != null && source.isNotEmpty) {
    aliases.addAll(_customerBookingAliasesFromSource(source));
  }
  return aliases;
}

Set<String> _customerBookingAliasesFromStored(StoredCustomerBooking booking) {
  return _customerBookingDeleteAliases(
    bookingId: booking.bookingId,
    publicBookingReference: booking.publicBookingReference,
    bookingReference: booking.bookingReference,
    publicReference: booking.publicReference,
    planningReference: booking.planningReference,
    receiptReference: booking.receiptReference,
    paymentBookingId: booking.paymentBookingId,
    source: booking.quote,
  );
}

const String _customerDetailResultRemovedLocal = 'removed_local';
const String _customerDetailResultCancelledServer = 'cancelled_server';
const String _customerDetailResultLegCancelledServer = 'leg_cancelled_server';

String? _customerDetailResultAction(dynamic result) {
  if (result == true) return _customerDetailResultRemovedLocal;
  if (result is String && result.trim().isNotEmpty) return result.trim();
  if (result is Map) {
    final action = result['action']?.toString().trim();
    if (action != null && action.isNotEmpty) return action;
  }
  return null;
}

String _normalizeCustomerLifecycleStatus(String raw) {
  final value = raw.trim().toUpperCase();
  if (value.isEmpty) return '';
  switch (value) {
    case 'PENDING':
    case 'IN_REVIEW':
      return 'PENDING';
    case 'CONFIRMED':
    case 'ACCEPTED':
    case 'ASSIGNED':
    case 'ACTIVE':
    case 'IN_PROGRESS':
    case 'ON_ROUTE':
    case 'ARRIVED':
    case 'STARTED':
      return 'CONFIRMED';
    case 'COMPLETED':
    case 'FINISHED':
    case 'DONE':
    case 'CLOSED':
      return 'COMPLETED';
    case 'CANCELLED':
    case 'CANCELED':
      return 'CANCELLED';
    case 'DELETED':
    case 'REMOVED':
      return 'DELETED';
    case 'FAILED':
    case 'ERROR':
      return 'FAILED';
    case 'EXPIRED':
      return 'EXPIRED';
    case 'DECLINED':
    case 'REJECTED':
      return 'DECLINED';
    default:
      return value;
  }
}

bool _isActiveCustomerLifecycleStatus(String status) {
  final s = _normalizeCustomerLifecycleStatus(status);
  if (s.isEmpty) return true;
  return s != 'CANCELLED' &&
      s != 'DELETED' &&
      s != 'FAILED' &&
      s != 'EXPIRED' &&
      s != 'DECLINED';
}

bool _isCustomerBookingTerminalStatus(String? status) {
  final raw = (status ?? '').trim();
  if (raw.isEmpty) return false;
  final normalized = _normalizeCustomerLifecycleStatus(
    raw,
  ).trim().toUpperCase().replaceAll(RegExp(r'[\s-]+'), '_');
  switch (normalized) {
    case 'CANCELLED':
    case 'CANCELED':
    case 'COMPLETED':
    case 'COMPLETE':
    case 'DELETED':
    case 'ARCHIVED':
    case 'CLOSED':
    case 'DONE':
    case 'FAILED':
    case 'EXPIRED':
    case 'DECLINED':
      return true;
    default:
      return false;
  }
}

StoredCustomerBooking _hydrateStoredCustomerBookingFromView({
  required StoredCustomerBooking stored,
  required CustomerBookingView view,
  required String source,
}) {
  final normalizedStatus = _normalizeCustomerLifecycleStatus(
    view.lifecycleStatus,
  );
  final normalizedPayment = view.rawPaymentStatus.trim().toLowerCase();
  // Business/invoice fields must reflect this booking record only. Do not let
  // prior locally stored profile/business values turn a private booking into a
  // business booking during hydration.
  final rawCompanyName = view.companyName.trim();
  final rawVatNumber = view.vatNumber.trim();
  final rawInvoiceEmail = view.invoiceEmail.trim();
  final rawInvoiceAddress = view.invoiceAddress.trim();
  final hasVat = rawVatNumber.isNotEmpty;
  final hasBusinessIntent = view.businessCustomer || view.invoiceRequested;
  final isBusinessBooking = hasVat && hasBusinessIntent;
  final mergedCompanyName = isBusinessBooking ? rawCompanyName : '';
  final mergedVatNumber = isBusinessBooking ? rawVatNumber : '';
  final mergedInvoiceEmail = isBusinessBooking ? rawInvoiceEmail : '';
  final mergedInvoiceAddress = isBusinessBooking ? rawInvoiceAddress : '';
  final mergedBusinessDetected = isBusinessBooking;
  final mergedInvoiceRequested = isBusinessBooking;
  debugPrint(
    '[CUSTOMER_BOOKING][HYDRATE_STATUS] source=$source booking=${_safeRefPreview(view.bookingId)} raw=${view.lifecycleStatus} normalized=$normalizedStatus',
  );
  // #region agent log H2 status normalization result
  unawaited(
    _agentDebugLog(
      runId: 'initial',
      hypothesisId: 'H2',
      location: 'main.dart:_hydrateStoredCustomerBookingFromView',
      message: '[CUSTOMER_BOOKING][HYDRATE_STATUS]',
      data: <String, dynamic>{
        'source': source,
        'booking': _safeRefPreview(view.bookingId),
        'rawStatus': view.lifecycleStatus,
        'normalizedStatus': normalizedStatus,
        'storedStatusBefore': stored.status,
        'storedStatusAfter': normalizedStatus.isNotEmpty
            ? normalizedStatus
            : stored.status,
      },
    ),
  );
  // #endregion
  debugPrint(
    '[CUSTOMER_BOOKING][BUSINESS_FIELDS] source=$source booking=${_safeRefPreview(view.bookingId)} business=$mergedBusinessDetected invoiceRequested=$mergedInvoiceRequested companyFound=${mergedCompanyName.trim().isNotEmpty} vatFound=${mergedVatNumber.trim().isNotEmpty} invoiceEmailFound=${mergedInvoiceEmail.trim().isNotEmpty} invoiceAddressFound=${mergedInvoiceAddress.trim().isNotEmpty}',
  );
  // #region agent log H3 business merge result
  unawaited(
    _agentDebugLog(
      runId: 'initial',
      hypothesisId: 'H3',
      location: 'main.dart:_hydrateStoredCustomerBookingFromView',
      message: '[CUSTOMER_BOOKING][BUSINESS_FIELDS]',
      data: <String, dynamic>{
        'source': source,
        'booking': _safeRefPreview(view.bookingId),
        'viewBusiness': view.businessCustomer,
        'viewInvoiceRequested': view.invoiceRequested,
        'storedBusinessBefore': stored.businessDetected,
        'storedInvoiceRequestedBefore': stored.invoiceRequested,
        'mergedBusiness': mergedBusinessDetected,
        'mergedInvoiceRequested': mergedInvoiceRequested,
        'companyFound': mergedCompanyName.trim().isNotEmpty,
        'vatFound': mergedVatNumber.trim().isNotEmpty,
        'invoiceEmailFound': mergedInvoiceEmail.trim().isNotEmpty,
        'invoiceAddressFound': mergedInvoiceAddress.trim().isNotEmpty,
      },
    ),
  );
  // #endregion
  return stored.copyWith(
    status: normalizedStatus.isNotEmpty ? normalizedStatus : stored.status,
    paymentStatus: normalizedPayment.isNotEmpty
        ? normalizedPayment
        : stored.paymentStatus,
    businessDetected: mergedBusinessDetected,
    invoiceRequested: mergedInvoiceRequested,
    companyName: mergedCompanyName,
    vatNumber: mergedVatNumber,
    invoiceEmail: mergedInvoiceEmail,
    invoiceAddress: mergedInvoiceAddress,
  );
}

bool _customerAliasesIntersect(Set<String> a, Set<String> b) {
  for (final value in a) {
    if (b.contains(value)) return true;
  }
  return false;
}

Future<({bool removed, bool storeA, bool storeB, int remaining})>
_removeLocalCustomerBookingEverywhere({
  required String bookingForLog,
  required Set<String> aliases,
}) async {
  final sortedAliases = aliases.toList(growable: false)..sort();
  debugPrint(
    '[CUSTOMER_BOOKING][DELETE_REQ] booking=${_safeRefPreview(bookingForLog)} aliases=${sortedAliases.join(',')}',
  );
  final hideMarked = await CustomerBookingsStore.instance
      .markHiddenByAnyReferenceAliases(aliases);
  debugPrint(
    '[CUSTOMER_BOOKING][HIDE_MARK] aliases=${sortedAliases.join(',')} ok=$hideMarked',
  );
  final result = await CustomerBookingsStore.instance
      .removeByAnyReferenceAliasesAcrossKnownCustomerScopesForDisplayOnly(
        aliases,
      );
  debugPrint(
    '[CUSTOMER_BOOKING][DELETE_RESULT] removed=${result.removed} storeA=${result.removed} storeB=${result.removed} remaining=${result.remaining}',
  );
  return (
    removed: result.removed,
    storeA: result.removed,
    storeB: result.removed,
    remaining: result.remaining,
  );
}

// Customer-facing refund lifecycle labels for paid roundtrip leg cancellations.
// Mirrors CR-1 provider-status semantics without importing company/admin helpers.

enum CustomerRefundDisplayPhase {
  creditDue,
  refundPending,
  refunded,
  refundFailed,
  noRefundNeeded,
  unknown,
}

String _normCustomerRefundToken(String raw) {
  return raw.trim().toUpperCase().replaceAll('-', '_').replaceAll(' ', '_');
}

bool _customerRefundStatusIsRefunded(String token) {
  switch (_normCustomerRefundToken(token)) {
    case 'REFUNDED':
    case 'SUCCEEDED':
    case 'SUCCESS':
    case 'COMPLETED':
    case 'PAID':
    case 'PAID_OUT':
    case 'SETTLED':
    case 'PAID_BACK':
    case 'RETURNED':
      return true;
    default:
      return false;
  }
}

bool _customerRefundStatusIsPending(String token) {
  switch (_normCustomerRefundToken(token)) {
    case 'QUEUED':
    case 'PENDING':
    case 'PROCESSING':
    case 'IN_PROGRESS':
    case 'OPEN':
    case 'REQUESTED':
    case 'CREATED':
    case 'MOLLIE_REFUND_PENDING':
    case 'IN_BEHANDELING':
      return true;
    default:
      return false;
  }
}

bool _customerRefundStatusIsFailed(String token) {
  switch (_normCustomerRefundToken(token)) {
    case 'FAILED':
    case 'FAILURE':
    case 'ERROR':
    case 'REJECTED':
    case 'CANCELLED':
    case 'CANCELED':
    case 'EXPIRED':
    case 'MOLLIE_REFUND_FAILED':
      return true;
    default:
      return false;
  }
}

bool _customerCreditDecisionIsNoRefund(String creditDecision) {
  switch (_normCustomerRefundToken(creditDecision)) {
    case 'NO_REFUND':
    case 'NONE':
      return true;
    default:
      return false;
  }
}

bool _customerCreditDecisionIsManual(String creditDecision) {
  switch (_normCustomerRefundToken(creditDecision)) {
    case 'HANDLED_MANUALLY':
    case 'MANUALLY_HANDLED':
      return true;
    default:
      return false;
  }
}

/// Classifies the customer-safe refund row in the Prijs card. Refund identifiers
/// and amounts prove a refund was requested; explicit final provider status is
/// required for [CustomerRefundDisplayPhase.refunded].
CustomerRefundDisplayPhase classifyCustomerRefundDisplayPhase({
  required String refundStatus,
  required String mollieRefundStatus,
  required String mollieRefundId,
  required int? refundedAmountCents,
  required String refundedAt,
  required String creditDecision,
  required bool hasCreditDueAmount,
}) {
  if (_customerCreditDecisionIsNoRefund(creditDecision)) {
    return CustomerRefundDisplayPhase.noRefundNeeded;
  }
  if (_customerCreditDecisionIsManual(creditDecision)) {
    return CustomerRefundDisplayPhase.noRefundNeeded;
  }

  final refundTok = refundStatus.trim();
  final mollieTok = mollieRefundStatus.trim();

  if (_customerRefundStatusIsFailed(refundTok) ||
      _customerRefundStatusIsFailed(mollieTok)) {
    return CustomerRefundDisplayPhase.refundFailed;
  }
  if (_customerRefundStatusIsRefunded(refundTok) ||
      _customerRefundStatusIsRefunded(mollieTok)) {
    return CustomerRefundDisplayPhase.refunded;
  }

  final hasRefundRequestSignal =
      mollieRefundId.trim().isNotEmpty ||
      (refundedAmountCents ?? 0) > 0 ||
      refundedAt.trim().isNotEmpty;
  if (hasRefundRequestSignal) {
    return CustomerRefundDisplayPhase.refundPending;
  }

  if (hasCreditDueAmount) {
    return CustomerRefundDisplayPhase.creditDue;
  }
  return CustomerRefundDisplayPhase.unknown;
}

String localizedCustomerRefundPriceLabel(
  CustomerRefundDisplayPhase phase, {
  bool manualHandled = false,
}) {
  switch (phase) {
    case CustomerRefundDisplayPhase.refunded:
      return _tr(
        nl: 'Terugbetaald aan klant',
        en: 'Refunded to customer',
        fr: 'Rembourse au client',
        es: 'Reembolsado al cliente',
      );
    case CustomerRefundDisplayPhase.refundPending:
      return _tr(
        nl: 'Terugbetaling in behandeling',
        en: 'Refund in progress',
        fr: 'Remboursement en cours',
        es: 'Reembolso en curso',
      );
    case CustomerRefundDisplayPhase.refundFailed:
      return _tr(
        nl: 'Terugbetaling mislukt',
        en: 'Refund failed',
        fr: 'Remboursement echoue',
        es: 'Reembolso fallido',
      );
    case CustomerRefundDisplayPhase.noRefundNeeded:
      if (manualHandled) {
        return _tr(
          nl: 'Handmatig afgehandeld',
          en: 'Handled manually',
          fr: 'Traite manuellement',
          es: 'Gestionado manualmente',
        );
      }
      return _tr(
        nl: 'Geen terugbetaling',
        en: 'No refund',
        fr: 'Pas de remboursement',
        es: 'Sin reembolso',
      );
    case CustomerRefundDisplayPhase.creditDue:
    case CustomerRefundDisplayPhase.unknown:
      return _tr(
        nl: 'Te crediteren',
        en: 'Credit due',
        fr: 'A crediter',
        es: 'A acreditar',
      );
  }
}

int? _customerRefundCentsFromDynamic(dynamic raw) {
  if (raw == null) return null;
  final asInt = int.tryParse(raw.toString());
  if (asInt != null && asInt > 0) return asInt;
  final asDouble = double.tryParse(raw.toString().replaceAll(',', '.'));
  if (asDouble != null && asDouble > 0) return asDouble.round();
  return null;
}

String _customerRefundTextFromMap(
  Map<String, dynamic>? map,
  String snakeKey,
  String camelKey,
) {
  if (map == null) return '';
  final raw = map[snakeKey] ?? map[camelKey];
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty || text.toLowerCase() == 'null') return '';
  return text;
}

int? _customerRefundCentsFromMap(
  Map<String, dynamic>? map,
  String snakeKey,
  String camelKey,
) {
  if (map == null) return null;
  return _customerRefundCentsFromDynamic(map[snakeKey] ?? map[camelKey]);
}
