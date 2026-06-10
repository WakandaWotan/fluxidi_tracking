import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/compliance_ledger_reader.dart';

enum ComplianceRegisterReceiptAction {
  viewDetails,
  downloadReceipt,
  downloadInvoice,
  shareReceipt,
}

/// Keys we accept inside a backend / compliance "location" Map when extracting
/// a single human-readable address String. Mirrors the keys used by the
/// existing route resolvers in `_TripHistoryItem.fromJson`,
/// `_RideReceiptBodyState._resolvedRouteForPdf` and
/// `_ReceiptPdfActionRunner._resolveRoute`.
const List<String> _kComplianceRouteLabelKeys = <String>[
  'label',
  'address',
  'formatted_address',
  'formattedAddress',
  'name',
  'text',
  'value',
];

/// Returns `true` when [text] is a stringified Map/List literal like `{}`,
/// `{label: }`, `{label: , lat: 50.8}` or `[]`. Such strings can sneak in
/// when raw compliance Maps are passed through Dart's default `toString()`
/// (e.g. by upstream resolvers that fall back to `value.toString()`). They
/// must never reach the receipt UI / PDF as address text.
bool isComplianceMapLiteralText(String? text) {
  if (text == null) return false;
  final trimmed = text.trim();
  if (trimmed.length < 2) return false;
  final start = trimmed[0];
  final end = trimmed[trimmed.length - 1];
  return (start == '{' && end == '}') || (start == '[' && end == ']');
}

/// Resolves a clean route-display String from a value that may be a String,
/// a Map (`{label,address,formatted_address,name,...}`), or `null`. Returns
/// `null` for empty Strings, placeholders, Iterables, and Maps whose route
/// keys are all empty. Never calls `toString()` on a Map / Iterable.
String? extractComplianceRouteScalar(Object? value) {
  if (value == null) return null;
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '—' || trimmed == '-') return null;
    if (isComplianceMapLiteralText(trimmed)) return null;
    return trimmed;
  }
  if (value is Map) {
    for (final key in _kComplianceRouteLabelKeys) {
      final inner = value[key];
      if (inner is String) {
        final trimmed = inner.trim();
        if (trimmed.isEmpty || trimmed == '—' || trimmed == '-') continue;
        if (isComplianceMapLiteralText(trimmed)) continue;
        return trimmed;
      }
    }
    return null;
  }
  if (value is Iterable) return null;
  // Numbers / bools etc. — accept their textual form when non-empty and not a
  // map-literal shape.
  final fallback = value.toString().trim();
  if (fallback.isEmpty || fallback == '—' || fallback == '-') return null;
  if (isComplianceMapLiteralText(fallback)) return null;
  return fallback;
}

/// Returns `true` when [value] indicates a confirmed paid state.
///
/// Used by the receipt-hydration merge helpers to ensure compliance / local
/// ride register payment authority is preserved: once any of the layers
/// (compliance, tracking trip, booking record) signals "paid", later layers
/// must never downgrade it to unpaid/pending/unknown. Accepts the common
/// string aliases the backends use plus the `paid: true` boolean form.
bool isComplianceReceiptPaidStatus(Object? value) {
  if (value == null) return false;
  if (value is bool) return value;
  final text = value.toString().trim().toLowerCase();
  if (text.isEmpty) return false;
  return text == 'paid' ||
      text == 'settled' ||
      text == 'confirmed' ||
      text == 'completed' ||
      text == 'success';
}

/// Aliases that carry a payment status. Used to detect / preserve a
/// pre-existing paid state across merge layers.
const List<String> _kCompliancePaymentStatusAliases = <String>[
  'payment_status',
  'paymentStatus',
  'payment_state',
  'paymentState',
  'paid',
  'is_paid',
  'isPaid',
];

/// Aliases that carry payment metadata (method / source / provider / id /
/// timestamp / amount). When the base layer already has these from
/// compliance, downstream layers must not silently overwrite them.
const List<String> _kCompliancePaymentMetadataKeys = <String>[
  'payment_method',
  'paymentMethod',
  'payment_source',
  'paymentSource',
  'payment_provider',
  'paymentProvider',
  'payment_id',
  'paymentId',
  'paid_at',
  'paidAt',
  'payment_amount',
  'paymentAmount',
];

/// Computes whether the base trip-history JSON (root + booking_details +
/// booking + payment subtree) already carries a confirmed paid state. When
/// `true`, subsequent enrichment from the tracking worker or booking worker
/// must not overwrite payment status / method / source / provider with
/// non-paid values.
bool baseTripHistoryJsonHasPaidStatus(Map<String, dynamic> json) {
  Map<String, dynamic> asMap(Object? value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};
  final bookingDetails = asMap(json['booking_details']);
  final booking = asMap(json['booking']);
  final record = asMap(json['record']);
  final recordBooking = asMap(record['booking']);
  final payment = asMap(json['payment']);
  final bookingDetailsPayment = asMap(bookingDetails['payment']);
  final scopes = <Map<String, dynamic>>[
    json,
    bookingDetails,
    booking,
    record,
    recordBooking,
    payment,
    bookingDetailsPayment,
  ];
  for (final scope in scopes) {
    if (scope.isEmpty) continue;
    for (final alias in _kCompliancePaymentStatusAliases) {
      if (!scope.containsKey(alias)) continue;
      if (isComplianceReceiptPaidStatus(scope[alias])) return true;
    }
  }
  return false;
}

typedef ComplianceRegisterReceiptHandler =
    Future<void> Function(
      BuildContext context,
      ComplianceLedgerEntry entry, {
      required ComplianceRegisterReceiptAction action,
    });

ComplianceRegisterReceiptHandler? complianceRegisterReceiptHandler;

void registerComplianceRegisterReceiptHandler(
  ComplianceRegisterReceiptHandler handler,
) {
  complianceRegisterReceiptHandler = handler;
}

/// Builds a trip-history shaped JSON payload from a compliance ledger entry.
/// Used by the main app receipt/PDF pipeline via [registerComplianceRegisterReceiptHandler].
Map<String, dynamic> tripHistoryJsonFromLedgerEntry(
  ComplianceLedgerEntry entry,
) {
  Map<String, dynamic> asMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  String text(Object? value) => (value ?? '').toString().trim();
  String? nullableText(Object? value) {
    final out = text(value);
    return out.isEmpty ? null : out;
  }

  final raw = entry.raw;
  final payment = asMap(raw['payment']);
  final fare = asMap(raw['fare']);
  final references = asMap(raw['references']);
  final bookingId = entry.bookingId.trim();
  final tripId = entry.tripId.trim();
  final rideType = entry.rideType.trim().isEmpty
      ? 'planned'
      : entry.rideType.trim();
  final kind = rideType.toLowerCase() == 'direct' ? 'direct' : 'planned';

  final bookingDetails = <String, dynamic>{
    if (bookingId.isNotEmpty) 'booking_id': bookingId,
    if (tripId.isNotEmpty) 'trip_id': tripId,
    'payment_status': entry.paymentStatus.isNotEmpty
        ? entry.paymentStatus
        : payment['status'],
    'payment_method': entry.paymentMethod.isNotEmpty
        ? entry.paymentMethod
        : payment['method'],
    'payment_source': entry.paymentSource.isNotEmpty
        ? entry.paymentSource
        : payment['source'],
    'payment_provider': entry.paymentProvider.isNotEmpty
        ? entry.paymentProvider
        : payment['provider'],
    if (entry.paymentId.isNotEmpty) 'payment_id': entry.paymentId,
    if (entry.paidAtUtc != null)
      'paid_at': entry.paidAtUtc!.toUtc().toIso8601String(),
    if (entry.receiptReference.isNotEmpty)
      'receipt_reference': entry.receiptReference,
    if (entry.planningReference.isNotEmpty)
      'planning_reference': entry.planningReference,
    if (entry.publicBookingReference.isNotEmpty)
      'public_booking_reference': entry.publicBookingReference,
    if (entry.invoiceReference.isNotEmpty)
      'invoice_reference': entry.invoiceReference,
    if (entry.tenantId.isNotEmpty) 'tenant_id': entry.tenantId,
    if (entry.companyId.isNotEmpty) 'company_id': entry.companyId,
    if (entry.fareTotalEur != null) 'total_eur': entry.fareTotalEur,
    if (entry.distanceKm != null) 'km_total': entry.distanceKm,
    if (entry.distanceKm != null) 'distance_km': entry.distanceKm,
    if (entry.waitSecondsTotal != null)
      'wait_seconds_total': entry.waitSecondsTotal,
    if (entry.currency.isNotEmpty) 'currency': entry.currency,
  };

  for (final key in references.keys) {
    final value = references[key];
    if (value == null) continue;
    final asText = text(value);
    if (asText.isEmpty) continue;
    bookingDetails.putIfAbsent(key, () => value);
  }

  final startedAt =
      entry.startedAtUtc?.toUtc().toIso8601String() ??
      nullableText(raw['started_at_utc']) ??
      nullableText(asMap(raw['timestamps'])['started_at_utc']);
  final stoppedAt =
      entry.endedAtUtc?.toUtc().toIso8601String() ??
      entry.finalizedAtUtc?.toUtc().toIso8601String() ??
      nullableText(raw['ended_at_utc']) ??
      nullableText(asMap(raw['timestamps'])['stopped_at_utc']) ??
      nullableText(asMap(raw['timestamps'])['event_at_utc']);

  // Compliance pickup/dropoff labels are frequently empty (especially for
  // backend-restored events and payment_update rows). Emit the `origin` /
  // `destination` keys ONLY when they actually carry a non-placeholder label;
  // otherwise leave them out so downstream resolvers (`_extractRouteLabel`,
  // `_resolveRouteLabel`) don't fall through to `value.toString()` on the
  // empty Map and surface "{}" / "{label: }" into the UI/PDF.
  final pickupLabelClean = extractComplianceRouteScalar(entry.pickupLabel);
  final dropoffLabelClean = extractComplianceRouteScalar(entry.dropoffLabel);

  // Strip raw pickup/dropoff Maps from the spread so the same fallback can't
  // re-introduce empty Maps via rawSource. The merge below repopulates these
  // keys with backend-authoritative values when hydration succeeds.
  final rawSanitized = <String, dynamic>{};
  for (final entryKv in raw.entries) {
    if (entryKv.key == 'pickup' || entryKv.key == 'dropoff') {
      final scalar = extractComplianceRouteScalar(entryKv.value);
      if (scalar == null) continue;
      rawSanitized[entryKv.key] = scalar;
      continue;
    }
    rawSanitized[entryKv.key] = entryKv.value;
  }

  // Mirror compliance payment status / metadata to ROOT in addition to
  // `booking_details`. This is the compliance ledger's authoritative payment
  // signal for the Local Ride Register, and surfacing it at root lets the
  // `overlayRoot` guard in `mergeBookingRecordIntoTripHistoryJson` (which
  // skips overlay when `existing` is non-empty) preserve it instead of being
  // silently downgraded by a booking-worker record that hasn't caught up to
  // an in-vehicle cash payment. The empty-string filters keep the spread
  // safe when compliance has no payment data.
  final paymentStatusRoot = entry.paymentStatus.isNotEmpty
      ? entry.paymentStatus
      : (text(payment['status']).isEmpty ? null : text(payment['status']));
  final paymentMethodRoot = entry.paymentMethod.isNotEmpty
      ? entry.paymentMethod
      : (text(payment['method']).isEmpty ? null : text(payment['method']));
  final paymentSourceRoot = entry.paymentSource.isNotEmpty
      ? entry.paymentSource
      : (text(payment['source']).isEmpty ? null : text(payment['source']));
  final paymentProviderRoot = entry.paymentProvider.isNotEmpty
      ? entry.paymentProvider
      : (text(payment['provider']).isEmpty ? null : text(payment['provider']));
  final paidAtRoot = entry.paidAtUtc?.toUtc().toIso8601String();

  return <String, dynamic>{
    'trip_id': tripId,
    'kind': kind,
    if (bookingId.isNotEmpty) 'booking_id': bookingId,
    'driver_id': entry.driverId,
    if (entry.vehicleId.isNotEmpty) 'vehicle_id': entry.vehicleId,
    if (startedAt != null) 'started_at': startedAt,
    if (stoppedAt != null) 'stopped_at': stoppedAt,
    if (pickupLabelClean != null)
      'origin': <String, dynamic>{'label': pickupLabelClean},
    if (dropoffLabelClean != null)
      'destination': <String, dynamic>{'label': dropoffLabelClean},
    if (pickupLabelClean != null) 'from': pickupLabelClean,
    if (dropoffLabelClean != null) 'to': dropoffLabelClean,
    if (entry.distanceKm != null) 'km_total': entry.distanceKm,
    if (entry.waitSecondsTotal != null)
      'wait_seconds_total': entry.waitSecondsTotal,
    if (entry.fareTotalEur != null) 'total_eur': entry.fareTotalEur,
    'status': entry.lifecycleStatus.isNotEmpty
        ? entry.lifecycleStatus
        : 'completed',
    'currency': entry.currency.isNotEmpty
        ? entry.currency
        : text(fare['currency']).isEmpty
        ? 'EUR'
        : text(fare['currency']),
    'booking_details': bookingDetails,
    ...rawSanitized,
    // Placed AFTER `...rawSanitized` so the compliance-derived payment
    // authority always wins over any stale `payment_status` that might
    // survive inside `entry.raw`.
    if (paymentStatusRoot != null) 'payment_status': paymentStatusRoot,
    if (paymentMethodRoot != null) 'payment_method': paymentMethodRoot,
    if (paymentSourceRoot != null) 'payment_source': paymentSourceRoot,
    if (paymentProviderRoot != null) 'payment_provider': paymentProviderRoot,
    if (entry.paymentId.isNotEmpty) 'payment_id': entry.paymentId,
    if (paidAtRoot != null) 'paid_at': paidAtRoot,
  };
}

/// Overlays an authoritative booking record (typically the body of
/// `GET /bookings/{bookingId}` from the booking worker) onto the
/// trip-history JSON built by [tripHistoryJsonFromLedgerEntry].
///
/// Compliance ledger entries are intentionally minimal (no PII, often empty
/// pickup/dropoff labels, no service_type/tier, partial fare). When the
/// register row has a `booking_id`, the backend can supply the full record;
/// this helper exposes it under the keys the existing receipt / PDF
/// resolvers already probe: `record`, `booking`, `booking_details`, and a
/// small set of root-level mirrors (`from`/`to`/`origin`/`destination`/
/// `customer_*`/`payment_*`/`total_eur`/`service_type`/`tier`/
/// `scheduled_pickup_at`). Backend non-empty values take precedence;
/// compliance-derived values survive when the backend has none. Pure
/// function — kept in this file so hydration callers (e.g. `main.dart`) can
/// merge without depending on receipt internals.
Map<String, dynamic> mergeBookingRecordIntoTripHistoryJson({
  required Map<String, dynamic> tripHistoryJson,
  required Map<String, dynamic> decodedResponse,
}) {
  Map<String, dynamic> asMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  bool nonEmpty(Object? value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is num || value is bool) return true;
    if (value is Map) return value.isNotEmpty;
    if (value is Iterable) return value.isNotEmpty;
    return value.toString().trim().isNotEmpty;
  }

  final record = asMap(decodedResponse['record']);
  if (record.isEmpty) return tripHistoryJson;
  final booking = asMap(record['booking']);
  final source = booking.isNotEmpty ? booking : record;

  final merged = Map<String, dynamic>.from(tripHistoryJson);

  // Payment authority guard:
  //   - The compliance ledger is authoritative for in-vehicle / cash / manual
  //     payments (the booking worker may still show `pending` while the
  //     driver-app marked the ride paid). Never downgrade a confirmed paid
  //     base state to unpaid/pending/unknown.
  //   - Booking-worker is allowed to UPGRADE unpaid → paid (e.g. Mollie
  //     settlement landed on the record after the ledger row was written).
  final basePaid = baseTripHistoryJsonHasPaidStatus(tripHistoryJson);

  // Expose the full authoritative subtrees so existing path-based lookups
  // (record.*, record.booking.*, booking.*) succeed without extra plumbing.
  merged['record'] = record;
  if (booking.isNotEmpty) {
    final existingBooking = asMap(merged['booking']);
    for (final entry in booking.entries) {
      if (nonEmpty(entry.value)) {
        existingBooking[entry.key] = entry.value;
      } else {
        existingBooking.putIfAbsent(entry.key, () => entry.value);
      }
    }
    merged['booking'] = existingBooking;
  }

  bool isPaymentStatusKey(String key) =>
      _kCompliancePaymentStatusAliases.contains(key);
  bool isPaymentMetadataKey(String key) =>
      _kCompliancePaymentMetadataKeys.contains(key);

  void overlayRoot(String key, Object? value) {
    if (!nonEmpty(value)) return;

    // Never downgrade a paid status. Allow upgrading unpaid → paid.
    if (isPaymentStatusKey(key)) {
      final existing = merged[key];
      if (isComplianceReceiptPaidStatus(existing) &&
          !isComplianceReceiptPaidStatus(value)) {
        return;
      }
      merged[key] = value;
      return;
    }

    // Preserve compliance payment metadata (method / source / provider /
    // paid_at / amount) when the base layer is already paid. The compliance
    // values are the truth for in-vehicle settlements.
    if (isPaymentMetadataKey(key) && basePaid && nonEmpty(merged[key])) {
      return;
    }

    final existing = merged[key];
    if (!nonEmpty(existing)) {
      merged[key] = value;
      return;
    }
    // Prefer richer Map values when the existing one was a compliance
    // placeholder like {} or {label: ''} but the backend supplies real data.
    if (existing is Map && value is Map) {
      final existingLabel = existing['label']?.toString().trim() ?? '';
      final incomingLabel = value['label']?.toString().trim() ?? '';
      if (existingLabel.isEmpty && incomingLabel.isNotEmpty) {
        merged[key] = value;
      } else if (existing.length <= 1 && value.length > existing.length) {
        merged[key] = value;
      }
    }
  }

  // Route keys are handled separately below with strict String coercion so
  // empty backend Maps (`{lat,lon,label:''}`) can never leak as
  // `value.toString()` into the receipt UI / PDF. Non-route keys keep the
  // existing overlay semantics.
  const overlayKeys = <String>[
    'customer',
    'customer_name',
    'customer_phone',
    'customer_email',
    'invoice_email',
    'service_type',
    'tier',
    'scheduled_pickup_at',
    'total',
    'total_eur',
    'subtotal_ex_vat',
    'vat_amount',
    'vat_rate',
    'fare',
    'km_total',
    'distance_km',
    'payment',
    'payment_method',
    'payment_source',
    'payment_provider',
    'payment_status',
    'payment_id',
    'paid_at',
    'references',
    'public_reference',
    'publicReference',
    'planning_reference',
    'planningReference',
    'public_booking_reference',
    'publicBookingReference',
    'booking_reference',
    'bookingReference',
    'receipt_reference',
    'receiptReference',
  ];
  for (final key in overlayKeys) {
    overlayRoot(key, source[key]);
  }

  // Mirror authoritative fields into booking_details so the broadest
  // resolvers (`_detailAt(['customer_name'])`, `_detailAt(['from'])`, etc.)
  // hit them without depending on rawSource Map fallbacks. Same payment
  // authority guard as `overlayRoot`: never downgrade paid → unpaid, and
  // preserve compliance payment metadata when the base layer is paid.
  final bookingDetails = asMap(merged['booking_details']);
  for (final key in overlayKeys) {
    final v = source[key];
    if (!nonEmpty(v)) continue;
    if (isPaymentStatusKey(key)) {
      final existing = bookingDetails[key];
      if (isComplianceReceiptPaidStatus(existing) &&
          !isComplianceReceiptPaidStatus(v)) {
        continue;
      }
      bookingDetails[key] = v;
      continue;
    }
    if (isPaymentMetadataKey(key) &&
        basePaid &&
        nonEmpty(bookingDetails[key])) {
      continue;
    }
    bookingDetails[key] = v;
  }

  // -------------------------------------------------------------------------
  // Route normalization (strict).
  //
  // Booking records may carry route data under many different keys depending
  // on the source (planned online booking / driver street ride / company
  // admin preview / etc.). The receipt must show the REQUESTED booking route
  // for planned bookings, falling back to actual driven route only when the
  // requested one is missing. We resolve a single clean String per side from
  // a wide priority list, then force-mirror it to every key the downstream
  // resolvers probe. When no clean value is available we REMOVE the offending
  // keys at root + booking_details so empty Maps cannot leak through
  // `_extractRouteLabel`'s default `toString()` fallback in
  // `_TripHistoryItem.fromJson`.
  // -------------------------------------------------------------------------
  Object? walkPath(List<String> probe) {
    Object? current;
    Map<String, dynamic>? scope;
    for (var i = 0; i < probe.length; i++) {
      final key = probe[i];
      if (i == 0) {
        switch (key) {
          case 'record':
            current = record;
            break;
          case 'booking':
            current = booking.isNotEmpty ? booking : merged['booking'];
            break;
          case 'merged':
            current = merged;
            break;
          default:
            current = null;
        }
        scope = current is Map ? Map<String, dynamic>.from(current) : null;
      } else {
        if (scope == null) {
          current = null;
          break;
        }
        current = scope[key];
        scope = current is Map ? Map<String, dynamic>.from(current) : null;
      }
    }
    return current;
  }

  bool pathYieldsScalar(List<String> probe) =>
      extractComplianceRouteScalar(walkPath(probe)) != null;

  String? pickRouteSide(List<List<String>> probes) {
    for (final probe in probes) {
      final scalar = extractComplianceRouteScalar(walkPath(probe));
      if (scalar != null) return scalar;
    }
    return null;
  }

  // Strict priority: REQUESTED booking route first (planned/online), then
  // actual driven route, then compliance fallbacks. Every key the receipt
  // body / PDF runner probes is mirrored below so the choice taken here is
  // authoritative.
  const fromProbes = <List<String>>[
    // Requested booking route — strongest signal for planned/online bookings.
    ['record', 'booking', 'from'],
    ['booking', 'from'],
    ['record', 'from'],
    ['record', 'booking', 'pickup'],
    ['booking', 'pickup'],
    ['record', 'pickup'],
    ['record', 'booking', 'origin'],
    ['booking', 'origin'],
    ['record', 'origin'],
    ['record', 'booking', 'pickup_address'],
    ['booking', 'pickup_address'],
    ['record', 'pickup_address'],
    ['record', 'booking', 'pickupAddress'],
    ['booking', 'pickupAddress'],
    ['record', 'pickupAddress'],
    ['record', 'booking', 'pickup_from'],
    ['booking', 'pickup_from'],
    ['record', 'pickup_from'],
    ['record', 'booking', 'pickupFrom'],
    ['booking', 'pickupFrom'],
    ['record', 'pickupFrom'],
    ['record', 'booking_details', 'from'],
    ['record', 'booking_details', 'pickup'],
    ['record', 'booking_details', 'origin'],
    ['record', 'booking_details', 'pickup_address'],
    ['record', 'booking', 'booking_details', 'from'],
    ['record', 'booking', 'booking_details', 'pickup'],
    ['record', 'quote', 'inputs', 'from'],
    ['record', 'quote', 'inputs', 'pickup'],
    ['booking', 'quote', 'inputs', 'from'],
    ['record', 'payload', 'from'],
    ['record', 'payload', 'pickup'],
    ['record', 'payload', 'pickup_address'],
    ['booking', 'payload', 'from'],
    ['record', 'requested_from'],
    ['record', 'requestedFrom'],
    ['booking', 'requested_from'],
    ['booking', 'requestedFrom'],
    ['record', 'pickup_label'],
    ['record', 'pickupLabel'],
    ['booking', 'pickup_label'],
    ['booking', 'pickupLabel'],
    // Last resort: whatever survived in the merged JSON from compliance.
    ['merged', 'from'],
    ['merged', 'pickup'],
    ['merged', 'origin'],
  ];

  const toProbes = <List<String>>[
    ['record', 'booking', 'to'],
    ['booking', 'to'],
    ['record', 'to'],
    ['record', 'booking', 'destination'],
    ['booking', 'destination'],
    ['record', 'destination'],
    ['record', 'booking', 'dropoff'],
    ['booking', 'dropoff'],
    ['record', 'dropoff'],
    ['record', 'booking', 'destination_address'],
    ['booking', 'destination_address'],
    ['record', 'destination_address'],
    ['record', 'booking', 'destinationAddress'],
    ['booking', 'destinationAddress'],
    ['record', 'destinationAddress'],
    ['record', 'booking', 'dropoff_address'],
    ['booking', 'dropoff_address'],
    ['record', 'dropoff_address'],
    ['record', 'booking', 'dropoffAddress'],
    ['booking', 'dropoffAddress'],
    ['record', 'dropoffAddress'],
    ['record', 'booking', 'dropoff_to'],
    ['booking', 'dropoff_to'],
    ['record', 'dropoff_to'],
    ['record', 'booking', 'dropoffTo'],
    ['booking', 'dropoffTo'],
    ['record', 'dropoffTo'],
    ['record', 'booking_details', 'to'],
    ['record', 'booking_details', 'destination'],
    ['record', 'booking_details', 'dropoff'],
    ['record', 'booking_details', 'destination_address'],
    ['record', 'booking', 'booking_details', 'to'],
    ['record', 'booking', 'booking_details', 'destination'],
    ['record', 'quote', 'inputs', 'to'],
    ['record', 'quote', 'inputs', 'destination'],
    ['booking', 'quote', 'inputs', 'to'],
    ['record', 'payload', 'to'],
    ['record', 'payload', 'destination'],
    ['record', 'payload', 'destination_address'],
    ['booking', 'payload', 'to'],
    ['record', 'requested_to'],
    ['record', 'requestedTo'],
    ['booking', 'requested_to'],
    ['booking', 'requestedTo'],
    ['record', 'dropoff_label'],
    ['record', 'dropoffLabel'],
    ['booking', 'dropoff_label'],
    ['booking', 'dropoffLabel'],
    ['merged', 'to'],
    ['merged', 'destination'],
    ['merged', 'dropoff'],
  ];

  final routeFrom = pickRouteSide(fromProbes);
  final routeTo = pickRouteSide(toProbes);

  // -------------------------------------------------------------------------
  // ROUTE_KEYS diagnostic — boolean presence only. No raw addresses, phone,
  // email, tokens, or payload bodies are logged. Helps verify which paths
  // exist on a real GET /bookings/{id} response without dumping the body.
  // -------------------------------------------------------------------------
  debugPrint(
    '[LOCAL_RIDE_REGISTER][ROUTE_KEYS]'
    ' record_booking_from=${pathYieldsScalar(const ['record', 'booking', 'from'])}'
    ' record_booking_to=${pathYieldsScalar(const ['record', 'booking', 'to'])}'
    ' booking_from=${pathYieldsScalar(const ['booking', 'from'])}'
    ' booking_to=${pathYieldsScalar(const ['booking', 'to'])}'
    ' booking_details_from=${pathYieldsScalar(const ['record', 'booking_details', 'from'])}'
    ' booking_details_to=${pathYieldsScalar(const ['record', 'booking_details', 'to'])}'
    ' quote_inputs_from=${pathYieldsScalar(const ['record', 'quote', 'inputs', 'from'])}'
    ' quote_inputs_to=${pathYieldsScalar(const ['record', 'quote', 'inputs', 'to'])}'
    ' pickup_label=${pathYieldsScalar(const ['record', 'pickup_label']) || pathYieldsScalar(const ['booking', 'pickup_label'])}'
    ' dropoff_label=${pathYieldsScalar(const ['record', 'dropoff_label']) || pathYieldsScalar(const ['booking', 'dropoff_label'])}'
    ' requested_route_present=${pathYieldsScalar(const ['record', 'requested_from']) || pathYieldsScalar(const ['record', 'requestedFrom']) || pathYieldsScalar(const ['booking', 'requested_from']) || pathYieldsScalar(const ['booking', 'requestedFrom'])}'
    ' actual_route_present=${pathYieldsScalar(const ['merged', 'from']) || pathYieldsScalar(const ['merged', 'pickup']) || pathYieldsScalar(const ['merged', 'origin'])}',
  );

  const routeMirrorFromKeys = <String>['from', 'origin', 'pickup'];
  const routeMirrorToKeys = <String>['to', 'destination', 'dropoff'];

  void applyRouteSide({required bool isFrom, required String? value}) {
    final mirrorKeys = isFrom ? routeMirrorFromKeys : routeMirrorToKeys;
    if (value != null) {
      // Force-mirror to root + booking_details + booking (in-memory merged JSON
      // only — we do not mutate any backend record).
      for (final key in mirrorKeys) {
        merged[key] = value;
        bookingDetails[key] = value;
      }
      final mergedBooking = asMap(merged['booking']);
      for (final key in mirrorKeys) {
        mergedBooking[key] = value;
      }
      if (mergedBooking.isNotEmpty) merged['booking'] = mergedBooking;
    } else {
      // Drop any compliance / partial backend Maps that would otherwise be
      // stringified by `_extractRouteLabel`'s fallback path.
      for (final key in mirrorKeys) {
        merged.remove(key);
        bookingDetails.remove(key);
      }
    }
  }

  applyRouteSide(isFrom: true, value: routeFrom);
  applyRouteSide(isFrom: false, value: routeTo);

  // Reassert mirrored keys (in case a foreign type slipped in via a different
  // overlayRoot path earlier in this function).
  const routeMirrorAllKeys = <String>[
    'from',
    'to',
    'origin',
    'destination',
    'pickup',
    'dropoff',
  ];
  for (final key in routeMirrorAllKeys) {
    final v = merged[key];
    if (v is! String) {
      if (v == null) continue;
      final scalar = extractComplianceRouteScalar(v);
      if (scalar == null) {
        merged.remove(key);
        bookingDetails.remove(key);
      } else {
        merged[key] = scalar;
        bookingDetails[key] = scalar;
      }
    }
  }

  if (bookingDetails.isNotEmpty) merged['booking_details'] = bookingDetails;

  // Short, masked diagnostic only — no raw addresses.
  String shortSource;
  if (routeFrom != null || routeTo != null) {
    if (pathYieldsScalar(const ['record', 'booking', 'from']) ||
        pathYieldsScalar(const ['record', 'booking', 'to']) ||
        pathYieldsScalar(const ['record', 'booking', 'pickup']) ||
        pathYieldsScalar(const ['record', 'booking', 'destination'])) {
      shortSource = 'record.booking';
    } else if (pathYieldsScalar(const ['record', 'booking_details', 'from']) ||
        pathYieldsScalar(const ['record', 'booking_details', 'to'])) {
      shortSource = 'booking_details';
    } else if (pathYieldsScalar(const ['record', 'quote', 'inputs', 'from']) ||
        pathYieldsScalar(const ['record', 'quote', 'inputs', 'to'])) {
      shortSource = 'quote.inputs';
    } else if (pathYieldsScalar(const ['record', 'payload', 'from']) ||
        pathYieldsScalar(const ['record', 'payload', 'to'])) {
      shortSource = 'payload';
    } else if (pathYieldsScalar(const ['record', 'pickup_label']) ||
        pathYieldsScalar(const ['record', 'dropoff_label'])) {
      shortSource = 'pickup_label';
    } else {
      shortSource = booking.isNotEmpty ? 'booking' : 'record';
    }
  } else {
    shortSource = 'none';
  }
  debugPrint(
    '[LOCAL_RIDE_REGISTER][HYDRATE_ROUTE] from_present=${routeFrom != null} to_present=${routeTo != null} source=$shortSource',
  );

  return merged;
}

/// Overlays a Tracking Worker `/trips/history` trip projection (as produced by
/// `summarizeTrip` + `normalizeBookingDetails`) into the trip-history JSON the
/// Local Ride Register receipt path consumes.
///
/// This is the SAME shape the chauffeur History page feeds into
/// `_TripHistoryItem.fromJson`, so opening the receipt from the Local Ride
/// Register reuses the authoritative route + planned booking details that the
/// chauffeur recorded at trip stop (`origin.label`, `destination.label`,
/// `booking_details.pickup_address/destination_address/scheduled_pickup_at/
/// service_type/tier/passengers/luggage_count/...`).
///
/// Semantics:
/// - Backend trip values WIN over the compliance / empty placeholders already
///   in [baseJson] when they're non-empty. Empty / placeholder values from the
///   trip are silently ignored.
/// - `origin` / `destination` Maps are only written when their label is a
///   clean non-empty String (via [extractComplianceRouteScalar]); otherwise
///   the existing route normalization in [mergeBookingRecordIntoTripHistoryJson]
///   handles fallback.
/// - Route Strings (`pickup_address` / `destination_address`) are mirrored to
///   root `from/to/origin/destination/pickup/dropoff` so the downstream route
///   resolvers in `_TripHistoryItem.fromJson`, `_RideReceiptBodyState._resolvedRouteForPdf`
///   and `_ReceiptPdfActionRunner._resolveRoute` pick them up.
/// - `booking_details` is merged per-key (backend non-empty wins; pre-existing
///   keys preserved when backend is empty).
Map<String, dynamic> mergeTrackingTripIntoTripHistoryJson({
  required Map<String, dynamic> tripJson,
  required Map<String, dynamic> baseJson,
}) {
  Map<String, dynamic> asMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  bool nonEmpty(Object? value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is num || value is bool) return true;
    if (value is Map) return value.isNotEmpty;
    if (value is Iterable) return value.isNotEmpty;
    return value.toString().trim().isNotEmpty;
  }

  final merged = Map<String, dynamic>.from(baseJson);

  // Payment authority guard:
  //   - For Local Ride Register hydration, the compliance ledger / base
  //     payment fields are authoritative. The tracking worker's
  //     `/trips/history` projection may still reflect a stale `pending` /
  //     `unknown` while the driver-app already marked the ride paid via an
  //     in-vehicle cash / Bancontact settlement. Treat trip payment fields
  //     as fill-only: overlay only when the base has no value. Paid status
  //     is additionally protected against downgrade.
  bool isPaymentStatusKey(String key) =>
      _kCompliancePaymentStatusAliases.contains(key);
  bool isPaymentMetadataKey(String key) =>
      _kCompliancePaymentMetadataKeys.contains(key);

  // ---------------------------------------------------------------------------
  // Route Maps (`origin`, `destination`).
  //
  // `summarizeTrip` projects these as `{label,lat,lon}`. For direct/street
  // rides `label` may be empty (coordinate-only). In that case we DO NOT
  // overwrite the existing baseJson values — the existing route normalization
  // will fall back to localized "Street ride start point" / "Start location"
  // labels, which is correct for those rides.
  // ---------------------------------------------------------------------------
  void overlayRouteMap(String key) {
    final incoming = tripJson[key];
    if (incoming is! Map) return;
    final labelScalar = extractComplianceRouteScalar(incoming['label']);
    if (labelScalar == null) return;
    final next = <String, dynamic>{'label': labelScalar};
    final lat = incoming['lat'];
    final lon = incoming['lon'];
    if (lat is num) next['lat'] = lat;
    if (lon is num) next['lon'] = lon;
    merged[key] = next;
  }

  overlayRouteMap('origin');
  overlayRouteMap('destination');

  // ---------------------------------------------------------------------------
  // booking_details overlay (per-key, backend wins when non-empty).
  // ---------------------------------------------------------------------------
  final incomingDetails = asMap(tripJson['booking_details']);
  final mergedDetails = asMap(merged['booking_details']);
  const detailsKeys = <String>[
    'pickup_address',
    'destination_address',
    'scheduled_pickup_at',
    'subtype',
    'service_type',
    'serviceType',
    'service',
    'tier',
    'vehicle_tier',
    'vehicleTier',
    'passengers',
    'luggage_count',
    'booked_wait_minutes',
    'customer_name',
    'customerName',
    'customer_phone',
    'customerPhone',
    'customer_email',
    'customerEmail',
    'booking_total_eur',
    'segment_price_eur',
    'leg_price_incl_vat',
    'legPriceInclVat',
    'outbound_price_eur',
    'return_price_eur',
    'booking_status',
    'payment_status',
    'paymentStatus',
    'payment_method',
    'paymentMethod',
    'payment_source',
    'paymentSource',
    'payment_provider',
    'paymentProvider',
    'currency',
  ];
  for (final key in detailsKeys) {
    final v = incomingDetails[key];
    if (!nonEmpty(v)) continue;
    if (isPaymentStatusKey(key)) {
      // Never downgrade paid → unpaid.
      final existing = mergedDetails[key];
      if (isComplianceReceiptPaidStatus(existing) &&
          !isComplianceReceiptPaidStatus(v)) {
        continue;
      }
      // For tracking trips, even an "upgrade" to paid is suspect (tracking is
      // typically the LEAST authoritative source for in-vehicle payments).
      // Fill-only: keep base value when present, only fill missing.
      if (nonEmpty(existing)) continue;
      mergedDetails[key] = v;
      continue;
    }
    if (isPaymentMetadataKey(key)) {
      // Tracking trip payment metadata fills missing only — never replace
      // compliance values that already wrote method / source / provider.
      if (nonEmpty(mergedDetails[key])) continue;
      mergedDetails[key] = v;
      continue;
    }
    mergedDetails[key] = v;
  }
  if (mergedDetails.isNotEmpty) merged['booking_details'] = mergedDetails;

  // ---------------------------------------------------------------------------
  // Top-level overlay (only when backend value is non-empty).
  // ---------------------------------------------------------------------------
  const topLevelKeys = <String>[
    'kind',
    'started_at',
    'stopped_at',
    'km_total',
    'wait_seconds_total',
    'total_eur',
    'currency',
    'payment_status',
    'paymentStatus',
    'payment_method',
    'paymentMethod',
    'payment_source',
    'paymentSource',
    'paid_at',
    'paidAt',
    'payment_amount',
    'paymentAmount',
  ];
  for (final key in topLevelKeys) {
    final v = tripJson[key];
    if (!nonEmpty(v)) continue;
    if (isPaymentStatusKey(key)) {
      final existing = merged[key];
      if (isComplianceReceiptPaidStatus(existing) &&
          !isComplianceReceiptPaidStatus(v)) {
        continue;
      }
      if (nonEmpty(existing)) continue;
      merged[key] = v;
      continue;
    }
    if (isPaymentMetadataKey(key)) {
      if (nonEmpty(merged[key])) continue;
      merged[key] = v;
      continue;
    }
    merged[key] = v;
  }

  // ---------------------------------------------------------------------------
  // Mirror authoritative route addresses to the canonical route keys so the
  // downstream resolvers (`_TripHistoryItem.fromJson::_resolveRouteLabel`,
  // `_RideReceiptBodyState._resolvedRouteForPdf`,
  // `_ReceiptPdfActionRunner._resolveRoute`) all surface the same value.
  // ---------------------------------------------------------------------------
  final pickupScalar = extractComplianceRouteScalar(
    incomingDetails['pickup_address'] ??
        (tripJson['origin'] is Map
            ? (tripJson['origin'] as Map)['label']
            : null),
  );
  final dropoffScalar = extractComplianceRouteScalar(
    incomingDetails['destination_address'] ??
        (tripJson['destination'] is Map
            ? (tripJson['destination'] as Map)['label']
            : null),
  );
  if (pickupScalar != null) {
    // Skip 'origin' here so the `{label,lat,lon}` Map written above keeps its
    // coordinates for any downstream code that uses them.
    for (final key in const ['from', 'pickup']) {
      merged[key] = pickupScalar;
    }
    for (final key in const ['from', 'origin', 'pickup']) {
      mergedDetails[key] = pickupScalar;
    }
  }
  if (dropoffScalar != null) {
    for (final key in const ['to', 'dropoff']) {
      merged[key] = dropoffScalar;
    }
    for (final key in const ['to', 'destination', 'dropoff']) {
      mergedDetails[key] = dropoffScalar;
    }
  }
  if (mergedDetails.isNotEmpty) merged['booking_details'] = mergedDetails;

  return merged;
}

Future<void> runComplianceRegisterReceiptAction({
  required BuildContext context,
  required ComplianceLedgerEntry entry,
  required ComplianceRegisterReceiptAction action,
}) async {
  final handler = complianceRegisterReceiptHandler;
  if (handler == null) {
    debugPrint(
      '[LOCAL_RIDE_REGISTER][EXPORT_RECEIPT] key=${ComplianceLedgerReader.groupKeyFor(entry)} source=register status=handler_missing',
    );
    return;
  }
  await handler(context, entry, action: action);
}
