part of '../main.dart';

class _TripHistoryItem {
  final String tripId;
  final String kind;
  final String? bookingId;
  final String driverId;
  final String? vehicleId;
  final String? startedAt;
  final String? stoppedAt;
  final String origin;
  final String destination;
  final double? kmTotal;
  final int waitSecondsTotal;
  final double? totalEur;
  final String status;
  final String currency;
  final Map<String, dynamic> bookingDetails;
  final Map<String, dynamic> rawSource;
  final String? customerName;
  final String? customerPhone;
  final String? customerEmail;

  const _TripHistoryItem({
    required this.tripId,
    required this.kind,
    required this.bookingId,
    required this.driverId,
    required this.vehicleId,
    required this.startedAt,
    required this.stoppedAt,
    required this.origin,
    required this.destination,
    required this.kmTotal,
    required this.waitSecondsTotal,
    required this.totalEur,
    required this.status,
    required this.currency,
    required this.bookingDetails,
    required this.rawSource,
    required this.customerName,
    required this.customerPhone,
    required this.customerEmail,
  });

  _TripHistoryItem copyWith({
    Map<String, dynamic>? bookingDetails,
    Map<String, dynamic>? rawSource,
  }) {
    return _TripHistoryItem(
      tripId: tripId,
      kind: kind,
      bookingId: bookingId,
      driverId: driverId,
      vehicleId: vehicleId,
      startedAt: startedAt,
      stoppedAt: stoppedAt,
      origin: origin,
      destination: destination,
      kmTotal: kmTotal,
      waitSecondsTotal: waitSecondsTotal,
      totalEur: totalEur,
      status: status,
      currency: currency,
      bookingDetails: bookingDetails ?? this.bookingDetails,
      rawSource: rawSource ?? this.rawSource,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
    );
  }

  // STREET-RIDE-HISTORY-DUPLICATE-ZERO-BOOKING-1A: canonical relation accessors
  // used by the defensive client-side dedupe (canonicalizeStreetHistory).
  /// Parent booking id of an operational leg (`planned` shadow). Falls back to
  /// the raw/booking-details variants; empty when not an operational leg.
  String get parentBookingId {
    return (rawSource['parent_booking_id'] ??
            rawSource['parentBookingId'] ??
            bookingDetails['parent_booking_id'] ??
            bookingDetails['parentBookingId'] ??
            '')
        .toString()
        .trim();
  }

  /// True when this history row is a synthesized operational leg (leg_id /
  /// leg_type / is_operational_leg present in booking_details).
  bool get isOperationalLeg {
    final flag =
        bookingDetails['is_operational_leg'] ??
        bookingDetails['isOperationalLeg'];
    if (flag == true) return true;
    if (flag is String) {
      final s = flag.toLowerCase();
      if (s == 'true' || s == '1') return true;
    }
    final legId = (bookingDetails['leg_id'] ?? bookingDetails['legId'] ?? '')
        .toString()
        .trim();
    final legType =
        (bookingDetails['leg_type'] ?? bookingDetails['legType'] ?? '')
            .toString()
            .trim();
    return legId.isNotEmpty || legType.isNotEmpty;
  }

  /// Explicit/resolved tracking-trip relation (canonical contract 1B). Empty
  /// when the worker did not expose it.
  String get linkedTrackingTripId {
    return (rawSource['linked_tracking_trip_id'] ??
            rawSource['linkedTrackingTripId'] ??
            bookingDetails['linked_tracking_trip_id'] ??
            bookingDetails['linkedTrackingTripId'] ??
            '')
        .toString()
        .trim();
  }

  /// Authoritative worker hint (canonical contract 1A/1B). Null when the worker
  /// did not annotate the row (stale worker) — the client then re-derives.
  bool? get workerOperationalShadowHint {
    final v = rawSource['is_operational_shadow'];
    if (v is bool) return v;
    if (v is String) {
      final s = v.toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    return null;
  }

  factory _TripHistoryItem.fromJson(Map<String, dynamic> json) {
    final origin = json['origin'];
    final destination = json['destination'];
    final originLabel = origin is Map ? origin['label']?.toString() : null;
    final label = destination is Map ? destination['label']?.toString() : null;
    final bookingDetails = json['booking_details'] is Map
        ? Map<String, dynamic>.from(json['booking_details'] as Map)
        : <String, dynamic>{};
    if (bookingDetails.isEmpty) {
      final fallbackBookingDetails =
          _pathValue(json, 'record.booking_details') ??
          _pathValue(json, 'record.bookingDetails') ??
          _pathValue(json, 'record.payload.booking_details') ??
          _pathValue(json, 'record.payload.bookingDetails');
      if (fallbackBookingDetails is Map) {
        bookingDetails.addAll(
          Map<String, dynamic>.from(fallbackBookingDetails),
        );
      }
    }
    final rawSource = Map<String, dynamic>.from(json);
    void copyRootDetail(String rootKey, String detailKey) {
      final value = json[rootKey];
      if (value == null) return;
      final text = value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') return;
      bookingDetails.putIfAbsent(detailKey, () => value);
    }

    copyRootDetail('payment_status', 'payment_status');
    copyRootDetail('paymentStatus', 'paymentStatus');
    copyRootDetail('paid_at', 'paid_at');
    copyRootDetail('paidAt', 'paidAt');
    copyRootDetail('payment_provider', 'payment_provider');
    copyRootDetail('paymentProvider', 'paymentProvider');
    copyRootDetail('payment_id', 'payment_id');
    copyRootDetail('paymentId', 'paymentId');
    if (mapLooksCanonicallyPaid(json)) {
      final paidFields = extractCanonicalPaymentFields(json);
      if (paidFields.isNotEmpty) {
        final merged = overlayCanonicalPaymentFields(
          bookingDetails,
          paidFields,
        );
        bookingDetails
          ..clear()
          ..addAll(merged);
      }
    }
    final tripIdRaw = (json['trip_id'] ?? '').toString().trim();
    String? resolveReference(List<String> paths) {
      return _resolveScalarLabel(json, paths);
    }

    void setIfMeaningful(
      Map<String, dynamic> target,
      String key,
      String? value,
    ) {
      final text = _cleanBusinessReferenceText(value);
      if (text == null) return;
      target[key] = text;
    }

    bool shouldAcceptReceiptReference(
      String? candidate, {
      required String? bookingId,
      required String? planningReference,
      required String? publicBookingReference,
    }) {
      final normalized = _cleanBusinessReferenceText(candidate);
      if (normalized == null) return false;
      return _isRealReceiptReference(
        candidate: normalized,
        canonicalBookingId: bookingId,
        tripId: tripIdRaw.isEmpty ? null : tripIdRaw,
        planningReference: planningReference,
        publicBookingReference: publicBookingReference,
        legacyTripReceiptNumber: tripIdRaw.isEmpty
            ? null
            : _legacyTripReceiptNumber(tripIdRaw),
      );
    }

    final resolvedBookingId = _resolveScalarLabel(json, const <String>[
      'booking_id',
      'bookingId',
      'id',
      'booking.booking_id',
      'booking.bookingId',
      'booking.id',
      'record.booking_id',
      'record.bookingId',
      'record.booking.booking_id',
      'record.booking.bookingId',
      'record.booking.id',
      'payload.booking_id',
      'payload.bookingId',
      'payload.booking.booking_id',
      'payload.booking.bookingId',
      'data.record.booking_id',
      'data.record.bookingId',
      'data.record.booking.booking_id',
      'data.record.booking.bookingId',
      'data.booking.booking_id',
      'data.booking.bookingId',
      'response.record.booking_id',
      'response.record.bookingId',
      'response.record.booking.booking_id',
      'response.record.booking.bookingId',
      'response.booking.booking_id',
      'response.booking.bookingId',
      'public_reference',
      'publicReference',
      'receipt_reference',
      'receiptReference',
      'booking.public_reference',
      'booking.publicReference',
      'booking.receipt_reference',
      'booking.receiptReference',
    ]);
    final planningReference = resolveReference(const <String>[
      'planning_reference',
      'planningReference',
      'references.planning_reference',
      'references.planningReference',
      'booking.planning_reference',
      'booking.planningReference',
      'record.planning_reference',
      'record.planningReference',
      'record.references.planning_reference',
      'record.references.planningReference',
      'record.booking.planning_reference',
      'record.booking.planningReference',
      'payload.planning_reference',
      'payload.planningReference',
      'payload.references.planning_reference',
      'payload.references.planningReference',
      'payload.booking.planning_reference',
      'payload.booking.planningReference',
      'data.record.planning_reference',
      'data.record.planningReference',
      'data.record.references.planning_reference',
      'data.record.references.planningReference',
      'data.booking.planning_reference',
      'data.booking.planningReference',
      'response.record.planning_reference',
      'response.record.planningReference',
      'response.record.references.planning_reference',
      'response.record.references.planningReference',
      'response.booking.planning_reference',
      'response.booking.planningReference',
    ]);
    final publicBookingReference = resolveReference(const <String>[
      'public_booking_reference',
      'publicBookingReference',
      'booking_reference',
      'bookingReference',
      'public_reference',
      'publicReference',
      'references.public_booking_reference',
      'references.publicBookingReference',
      'references.booking_reference',
      'references.bookingReference',
      'references.public_reference',
      'references.publicReference',
      'booking.public_booking_reference',
      'booking.publicBookingReference',
      'booking.booking_reference',
      'booking.bookingReference',
      'booking.public_reference',
      'booking.publicReference',
      'record.public_booking_reference',
      'record.publicBookingReference',
      'record.booking_reference',
      'record.bookingReference',
      'record.public_reference',
      'record.publicReference',
      'record.references.public_booking_reference',
      'record.references.publicBookingReference',
      'record.references.booking_reference',
      'record.references.bookingReference',
      'record.references.public_reference',
      'record.references.publicReference',
      'record.booking.public_booking_reference',
      'record.booking.publicBookingReference',
      'record.booking.booking_reference',
      'record.booking.bookingReference',
      'record.booking.public_reference',
      'record.booking.publicReference',
      'payload.public_booking_reference',
      'payload.publicBookingReference',
      'payload.booking_reference',
      'payload.bookingReference',
      'payload.public_reference',
      'payload.publicReference',
      'payload.references.public_booking_reference',
      'payload.references.publicBookingReference',
      'payload.references.booking_reference',
      'payload.references.bookingReference',
      'payload.references.public_reference',
      'payload.references.publicReference',
      'payload.booking.public_booking_reference',
      'payload.booking.publicBookingReference',
      'payload.booking.booking_reference',
      'payload.booking.bookingReference',
      'payload.booking.public_reference',
      'payload.booking.publicReference',
      'data.record.public_booking_reference',
      'data.record.publicBookingReference',
      'data.record.booking_reference',
      'data.record.bookingReference',
      'data.record.public_reference',
      'data.record.publicReference',
      'data.booking.public_booking_reference',
      'data.booking.publicBookingReference',
      'data.booking.booking_reference',
      'data.booking.bookingReference',
      'data.booking.public_reference',
      'data.booking.publicReference',
      'response.record.public_booking_reference',
      'response.record.publicBookingReference',
      'response.record.booking_reference',
      'response.record.bookingReference',
      'response.record.public_reference',
      'response.record.publicReference',
      'response.booking.public_booking_reference',
      'response.booking.publicBookingReference',
      'response.booking.booking_reference',
      'response.booking.bookingReference',
      'response.booking.public_reference',
      'response.booking.publicReference',
    ]);
    final bookingReference = resolveReference(const <String>[
      'booking_reference',
      'bookingReference',
      'references.booking_reference',
      'references.bookingReference',
      'booking.booking_reference',
      'booking.bookingReference',
      'record.booking_reference',
      'record.bookingReference',
      'record.references.booking_reference',
      'record.references.bookingReference',
      'record.booking.booking_reference',
      'record.booking.bookingReference',
      'payload.booking_reference',
      'payload.bookingReference',
      'payload.references.booking_reference',
      'payload.references.bookingReference',
      'payload.booking.booking_reference',
      'payload.booking.bookingReference',
      'data.record.booking_reference',
      'data.record.bookingReference',
      'data.booking.booking_reference',
      'data.booking.bookingReference',
      'response.record.booking_reference',
      'response.record.bookingReference',
      'response.booking.booking_reference',
      'response.booking.bookingReference',
    ]);
    final publicReference = resolveReference(const <String>[
      'public_reference',
      'publicReference',
      'references.public_reference',
      'references.publicReference',
      'booking.public_reference',
      'booking.publicReference',
      'record.public_reference',
      'record.publicReference',
      'record.references.public_reference',
      'record.references.publicReference',
      'record.booking.public_reference',
      'record.booking.publicReference',
      'payload.public_reference',
      'payload.publicReference',
      'payload.references.public_reference',
      'payload.references.publicReference',
      'payload.booking.public_reference',
      'payload.booking.publicReference',
      'data.record.public_reference',
      'data.record.publicReference',
      'data.booking.public_reference',
      'data.booking.publicReference',
      'response.record.public_reference',
      'response.record.publicReference',
      'response.booking.public_reference',
      'response.booking.publicReference',
    ]);
    final receiptReference = resolveReference(const <String>[
      'receipt_reference',
      'receiptReference',
      'references.receipt_reference',
      'references.receiptReference',
      'booking.receipt_reference',
      'booking.receiptReference',
      'record.receipt_reference',
      'record.receiptReference',
      'record.references.receipt_reference',
      'record.references.receiptReference',
      'record.booking.receipt_reference',
      'record.booking.receiptReference',
      'payload.receipt_reference',
      'payload.receiptReference',
      'payload.references.receipt_reference',
      'payload.references.receiptReference',
      'payload.booking.receipt_reference',
      'payload.booking.receiptReference',
      'data.record.receipt_reference',
      'data.record.receiptReference',
      'data.booking.receipt_reference',
      'data.booking.receiptReference',
      'response.record.receipt_reference',
      'response.record.receiptReference',
      'response.booking.receipt_reference',
      'response.booking.receiptReference',
    ]);
    setIfMeaningful(bookingDetails, 'planning_reference', planningReference);
    setIfMeaningful(bookingDetails, 'planningReference', planningReference);
    setIfMeaningful(
      bookingDetails,
      'public_booking_reference',
      publicBookingReference,
    );
    setIfMeaningful(
      bookingDetails,
      'publicBookingReference',
      publicBookingReference,
    );
    setIfMeaningful(bookingDetails, 'booking_reference', bookingReference);
    setIfMeaningful(bookingDetails, 'bookingReference', bookingReference);
    setIfMeaningful(bookingDetails, 'public_reference', publicReference);
    setIfMeaningful(bookingDetails, 'publicReference', publicReference);
    if (shouldAcceptReceiptReference(
      receiptReference,
      bookingId: resolvedBookingId,
      planningReference: planningReference,
      publicBookingReference: publicBookingReference,
    )) {
      setIfMeaningful(bookingDetails, 'receipt_reference', receiptReference);
      setIfMeaningful(bookingDetails, 'receiptReference', receiptReference);
    }
    final referencesMap = bookingDetails['references'] is Map
        ? Map<String, dynamic>.from(bookingDetails['references'] as Map)
        : <String, dynamic>{};
    setIfMeaningful(referencesMap, 'planning_reference', planningReference);
    setIfMeaningful(referencesMap, 'planningReference', planningReference);
    setIfMeaningful(
      referencesMap,
      'public_booking_reference',
      publicBookingReference,
    );
    setIfMeaningful(
      referencesMap,
      'publicBookingReference',
      publicBookingReference,
    );
    setIfMeaningful(referencesMap, 'booking_reference', bookingReference);
    setIfMeaningful(referencesMap, 'bookingReference', bookingReference);
    setIfMeaningful(referencesMap, 'public_reference', publicReference);
    setIfMeaningful(referencesMap, 'publicReference', publicReference);
    if (shouldAcceptReceiptReference(
      receiptReference,
      bookingId: resolvedBookingId,
      planningReference: planningReference,
      publicBookingReference: publicBookingReference,
    )) {
      setIfMeaningful(referencesMap, 'receipt_reference', receiptReference);
      setIfMeaningful(referencesMap, 'receiptReference', receiptReference);
    }
    if (referencesMap.isNotEmpty) {
      bookingDetails['references'] = referencesMap;
    }
    setIfMeaningful(rawSource, 'planning_reference', planningReference);
    setIfMeaningful(rawSource, 'planningReference', planningReference);
    setIfMeaningful(
      rawSource,
      'public_booking_reference',
      publicBookingReference,
    );
    setIfMeaningful(
      rawSource,
      'publicBookingReference',
      publicBookingReference,
    );
    setIfMeaningful(rawSource, 'booking_reference', bookingReference);
    setIfMeaningful(rawSource, 'bookingReference', bookingReference);
    setIfMeaningful(rawSource, 'public_reference', publicReference);
    setIfMeaningful(rawSource, 'publicReference', publicReference);
    if (shouldAcceptReceiptReference(
      receiptReference,
      bookingId: resolvedBookingId,
      planningReference: planningReference,
      publicBookingReference: publicBookingReference,
    )) {
      setIfMeaningful(rawSource, 'receipt_reference', receiptReference);
      setIfMeaningful(rawSource, 'receiptReference', receiptReference);
    }
    final customerName = _resolveScalarLabel(json, const <String>[
      'customer.name',
      'customer_name',
      'customerName',
      'custName',
      'name',
      'booking.customer.name',
      'booking.customer_name',
      'booking.customerName',
      'booking.custName',
      'booking.name',
      'record.customer_name',
      'record.booking.customer_name',
      'record.booking.customerName',
      'record.booking.custName',
      'payload.customer_name',
      'payload.booking.customer_name',
      'booking_details.customer_name',
      'booking_details.customerName',
      'booking_details.custName',
    ]);
    final customerPhone = _resolveScalarLabel(json, const <String>[
      'customer.phone',
      'customer_phone',
      'customerPhone',
      'custPhone',
      'phone',
      'tel',
      'mobile',
      'booking.customer.phone',
      'booking.customer_phone',
      'booking.customerPhone',
      'booking.custPhone',
      'booking.phone',
      'record.customer_phone',
      'record.booking.customer_phone',
      'record.booking.customerPhone',
      'record.booking.custPhone',
      'payload.customer_phone',
      'payload.booking.customer_phone',
      'booking_details.customer_phone',
      'booking_details.customerPhone',
      'booking_details.custPhone',
      'booking_details.phone',
      'booking_details.tel',
      'booking_details.mobile',
    ]);
    final customerEmail = _resolveEmailLabel(json, const <String>[
      'customer.email',
      'customer_email',
      'customerEmail',
      'custEmail',
      'email',
      'invoiceEmail',
      'invoice_email',
      'booking.customer.email',
      'booking.customer_email',
      'booking.customerEmail',
      'booking.custEmail',
      'booking.email',
      'record.customer_email',
      'record.booking.customer_email',
      'record.booking.customerEmail',
      'record.booking.custEmail',
      'payload.customer_email',
      'payload.booking.customer_email',
      'booking_details.customer_email',
      'booking_details.customerEmail',
      'booking_details.custEmail',
      'booking_details.email',
      'booking_details.invoice_email',
      'booking_details.invoiceEmail',
    ]);
    final fromResolved = _resolveRouteLabel(json, const <String>[
      'route_address_snapshot.from_address',
      'route_address_snapshot.invoice_from_address',
      'invoice_from_address',
      'from_full_address',
      'from_label',
      'from',
      'pickup',
      'pickup_address',
      'pickupAddress',
      'pickupLocation',
      'pickup_location',
      'origin',
      'start_address',
      'startAddress',
      'booking.route_address_snapshot.from_address',
      'booking.invoice_from_address',
      'booking.from_full_address',
      'booking.from_label',
      'booking.from',
      'booking.pickup',
      'booking.pickup_address',
      'booking.pickupAddress',
      'record.invoice_from_address',
      'record.from_full_address',
      'record.from_label',
      'record.from',
      'record.booking.invoice_from_address',
      'record.booking.from_full_address',
      'record.booking.from_label',
      'record.booking.from',
      'record.booking.pickup',
      'payload.from',
      'payload.booking.from',
      'quote.inputs.from',
      'booking_details.invoice_from_address',
      'booking_details.from_full_address',
      'booking_details.from_label',
      'booking_details.from',
      'booking_details.pickup',
      'booking_details.pickup_address',
      'booking_details.pickupAddress',
    ]);
    final toResolved = _resolveRouteLabel(json, const <String>[
      'route_address_snapshot.to_address',
      'route_address_snapshot.invoice_to_address',
      'invoice_to_address',
      'to_full_address',
      'to_label',
      'to',
      'destination',
      'destination_address',
      'destinationAddress',
      'dropoff',
      'dropoff_address',
      'dropoffAddress',
      'end_address',
      'endAddress',
      'booking.route_address_snapshot.to_address',
      'booking.invoice_to_address',
      'booking.to_full_address',
      'booking.to_label',
      'booking.to',
      'booking.destination',
      'booking.destination_address',
      'booking.destinationAddress',
      'record.invoice_to_address',
      'record.to_full_address',
      'record.to_label',
      'record.to',
      'record.booking.invoice_to_address',
      'record.booking.to_full_address',
      'record.booking.to_label',
      'record.booking.to',
      'record.booking.destination',
      'payload.to',
      'payload.booking.to',
      'quote.inputs.to',
      'booking_details.invoice_to_address',
      'booking_details.to_full_address',
      'booking_details.to_label',
      'booking_details.to',
      'booking_details.destination',
      'booking_details.destination_address',
      'booking_details.destinationAddress',
    ]);
    double? asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse((value ?? '').toString().replaceAll(',', '.'));
    }

    int asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.round();
      return int.tryParse((value ?? '').toString()) ?? 0;
    }

    final rootKmTotal = asDouble(json['km_total']);

    return _TripHistoryItem(
      tripId: (json['trip_id'] ?? '').toString(),
      kind: (json['kind'] ?? 'direct').toString(),
      bookingId: resolvedBookingId,
      driverId: (json['driver_id'] ?? '').toString(),
      vehicleId: json['vehicle_id']?.toString(),
      startedAt: json['started_at']?.toString(),
      stoppedAt: json['stopped_at']?.toString(),
      origin:
          fromResolved.value ??
          _placeLabel(origin, originLabel ?? _receiptText('currentLocation')),
      destination:
          toResolved.value ??
          ((label == null || label.trim().isEmpty) ? '—' : label.trim()),
      kmTotal:
          rootKmTotal ??
          asDouble(bookingDetails['km_total']) ??
          asDouble(bookingDetails['distance_km']),
      waitSecondsTotal: asInt(json['wait_seconds_total']),
      totalEur: asDouble(json['total_eur']),
      status: (json['status'] ?? '—').toString(),
      currency: (json['currency'] ?? 'EUR').toString(),
      bookingDetails: bookingDetails,
      rawSource: rawSource,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
    );
  }

  static String _placeLabel(dynamic value, String fallback) {
    if (value is Map) {
      final label = value['label']?.toString().trim();
      if (label != null &&
          label.isNotEmpty &&
          !receiptIsNonAddressRoutePlaceholder(label)) {
        return label;
      }
      // Never synthesize raw coordinates as a customer-facing place label.
      return fallback;
    }
    final text = value?.toString().trim();
    if (text != null &&
        text.isNotEmpty &&
        !receiptIsNonAddressRoutePlaceholder(text)) {
      return text;
    }
    return fallback;
  }

  static ({String? value, String? key}) _resolveRouteLabel(
    Map<String, dynamic> root,
    List<String> paths,
  ) {
    for (final path in paths) {
      final value = _pathValue(root, path);
      final label = _extractRouteLabel(value);
      if (label != null && label.isNotEmpty) {
        return (value: label, key: path);
      }
    }
    return (value: null, key: null);
  }

  static String? _resolveScalarLabel(
    Map<String, dynamic> root,
    List<String> paths,
  ) {
    for (final path in paths) {
      final value = _pathValue(root, path);
      final text = _cleanText(value);
      if (text != null) return text;
    }
    return null;
  }

  static String? _resolveEmailLabel(
    Map<String, dynamic> root,
    List<String> paths,
  ) {
    for (final path in paths) {
      final value = _pathValue(root, path);
      final text = _cleanText(value);
      if (text == null) continue;
      if (_looksLikeEmail(text)) return text;
    }
    return null;
  }

  static String? _cleanText(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text == '—' || text.toLowerCase() == 'null')
      return null;
    return text;
  }

  static bool _looksLikeEmail(String value) {
    final at = value.indexOf('@');
    if (at <= 0 || at >= value.length - 1) return false;
    final dotAfterAt = value.indexOf('.', at + 1);
    if (dotAfterAt <= at + 1 || dotAfterAt >= value.length - 1) return false;
    return !value.contains(RegExp(r'\s'));
  }

  static dynamic _pathValue(Map<String, dynamic> root, String path) {
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

  static String? _extractRouteLabel(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty || text == '—') return null;
      if (receiptIsNonAddressRoutePlaceholder(text)) return null;
      return text;
    }
    if (value is Map) {
      for (final key in const <String>[
        'label',
        'address',
        'formatted_address',
        'formattedAddress',
        'full_address',
        'fullAddress',
        'name',
        'text',
        'value',
      ]) {
        final inner = value[key]?.toString().trim();
        if (inner == null || inner.isEmpty || inner == '—') continue;
        if (receiptIsNonAddressRoutePlaceholder(inner)) continue;
        return inner;
      }
      return null;
    }
    if (value is Iterable) return null;
    final fallback = value.toString().trim();
    if (fallback.isEmpty || fallback == '—') return null;
    if (receiptIsNonAddressRoutePlaceholder(fallback)) return null;
    return fallback;
  }

  bool get isCompletedForReceipt {
    final s = status.toLowerCase().trim();
    return s == 'stopped' || s == 'completed';
  }

  bool get isLocalOnlyDirectFallback {
    final source = (rawSource['history_source'] ?? '').toString().trim();
    final detailsSource = (bookingDetails['history_source'] ?? '')
        .toString()
        .trim();
    return source == 'local_only_direct_fallback' ||
        detailsSource == 'local_only_direct_fallback';
  }

  // SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Commit 5):
  // explicit `backend_confirmed=false` in either the root record or the
  // nested booking_details map. Broader safe rule approved for Commit 5 —
  // a ride that the server did not acknowledge must never render as an
  // ordinary Completed ride even when the fallback source marker is absent.
  bool get isBackendConfirmedFalse {
    bool? readBool(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.trim().toLowerCase();
        if (s == 'true' || s == '1') return true;
        if (s == 'false' || s == '0') return false;
      }
      return null;
    }

    final bcRoot = readBool(rawSource['backend_confirmed']);
    final bcDetails = readBool(bookingDetails['backend_confirmed']);
    return bcRoot == false || bcDetails == false;
  }

  /// Truthful gate used by every UI surface (`_statusChipText`,
  /// `_statusChipColor`, the history-tile description row and the receipt
  /// `Rit status` row). A ride qualifies for the local/unconfirmed
  /// presentation if EITHER the explicit fallback source marker is set OR
  /// `backend_confirmed=false` is present.
  bool get shouldRenderAsLocalOnlyUnconfirmed =>
      isLocalOnlyDirectFallback || isBackendConfirmedFalse;

  String get receiptNumber {
    return _businessReferenceDisplayForItem(
      this,
      source: 'trip_item_receipt_number',
    ).value;
  }

  String get kindLabel {
    return _localizedRideKind(kind);
  }

  String? detail(String key) {
    final value = bookingDetails[key];
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

String? _paymentUpdateText(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
    return null;
  }
  return text;
}

String _normalizePaymentUpdateStatus(dynamic value) {
  final raw = _paymentUpdateText(value);
  if (raw == null) return 'unknown';
  final normalized = raw
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_')
      .trim();
  switch (normalized) {
    case 'paid':
    case 'succeeded':
    case 'success':
    case 'completed':
    case 'settled':
    case 'confirmed':
      return 'paid';
    case 'pending':
    case 'open':
    case 'authorized':
    case 'authorised':
    case 'processing':
      return 'pending';
    case 'failed':
    case 'error':
    case 'declined':
      return 'failed';
    case 'cancelled':
    case 'canceled':
      return 'cancelled';
    case 'unpaid':
    case 'not_paid':
      return 'unpaid';
    default:
      return 'unknown';
  }
}

String _normalizePaymentUpdateMethod(dynamic value) {
  final raw = _paymentUpdateText(value);
  if (raw == null) return 'unknown';
  final normalized = raw
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_')
      .trim();
  switch (normalized) {
    case 'cash':
    case 'contant':
      return 'cash';
    case 'qr':
    case 'qr_code':
      return 'qr';
    case 'bancontact':
      return 'bancontact';
    case 'card':
    case 'terminal':
    case 'card_terminal':
      return 'card_terminal';
    case 'payment_link':
    case 'link':
    case 'online':
      return 'payment_link';
    case 'mollie':
      return 'mollie';
    default:
      return 'unknown';
  }
}

String? _paymentUpdateField(Map<String, dynamic> fields, List<String> keys) {
  for (final key in keys) {
    final text = _paymentUpdateText(fields[key]);
    if (text != null) return text;
  }
  return null;
}

String? _cleanBusinessReferenceText(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  final token = text.toLowerCase();
  if (token == 'null' ||
      token == 'undefined' ||
      token == 'unknown' ||
      token == '-' ||
      token == '—') {
    return null;
  }
  return text;
}

String? _businessReferenceAtPath(Map<String, dynamic> root, List<String> path) {
  dynamic current = root;
  for (final key in path) {
    if (current is Map && current.containsKey(key)) {
      current = current[key];
    } else {
      return null;
    }
  }
  return _cleanBusinessReferenceText(current);
}

String? _pickReferenceAliasFromMaps(
  List<Map<String, dynamic>> maps,
  List<List<String>> paths,
) {
  for (final map in maps) {
    if (map.isEmpty) continue;
    for (final path in paths) {
      final value = _businessReferenceAtPath(map, path);
      if (value != null) return value;
    }
  }
  return null;
}

Map<String, dynamic>? _referenceMapAtPath(
  Map<String, dynamic> root,
  List<String> path,
) {
  dynamic current = root;
  for (final key in path) {
    if (current is Map && current.containsKey(key)) {
      current = current[key];
    } else {
      return null;
    }
  }
  if (current is Map) {
    return Map<String, dynamic>.from(current);
  }
  return null;
}

List<Map<String, dynamic>> _referenceMapsFromRoot(Map<String, dynamic> root) {
  const nestedPaths = <List<String>>[
    <String>['references'],
    <String>['booking'],
    <String>['record'],
    <String>['record', 'references'],
    <String>['record', 'booking'],
    <String>['record', 'payload'],
    <String>['record', 'payload', 'references'],
    <String>['record', 'payload', 'booking'],
    <String>['payload'],
    <String>['payload', 'references'],
    <String>['payload', 'booking'],
    <String>['data'],
    <String>['data', 'record'],
    <String>['data', 'record', 'references'],
    <String>['data', 'record', 'booking'],
    <String>['data', 'booking'],
    <String>['data', 'booking', 'references'],
    <String>['response'],
    <String>['response', 'record'],
    <String>['response', 'record', 'references'],
    <String>['response', 'record', 'booking'],
    <String>['response', 'booking'],
    <String>['response', 'booking', 'references'],
  ];
  final out = <Map<String, dynamic>>[root];
  for (final path in nestedPaths) {
    final map = _referenceMapAtPath(root, path);
    if (map != null && map.isNotEmpty) out.add(map);
  }
  return out;
}

List<Map<String, dynamic>> _referenceLookupMaps(
  List<Map<String, dynamic>> roots,
) {
  final out = <Map<String, dynamic>>[];
  for (final root in roots) {
    if (root.isEmpty) continue;
    out.addAll(_referenceMapsFromRoot(root));
  }
  return out;
}

const List<List<String>> _receiptReferenceAliasPaths = <List<String>>[
  <String>['receipt_reference'],
  <String>['receiptReference'],
];

const List<List<String>> _planningReferenceAliasPaths = <List<String>>[
  <String>['planning_reference'],
  <String>['planningReference'],
];

const List<List<String>> _publicBookingReferenceAliasPaths = <List<String>>[
  <String>['public_booking_reference'],
  <String>['publicBookingReference'],
  <String>['booking_reference'],
  <String>['bookingReference'],
  <String>['public_reference'],
  <String>['publicReference'],
];

const List<List<String>> _bookingReferenceAliasPaths = <List<String>>[
  <String>['booking_reference'],
  <String>['bookingReference'],
];

const List<List<String>> _publicReferenceAliasPaths = <List<String>>[
  <String>['public_reference'],
  <String>['publicReference'],
];

({
  String? receipt,
  String? planning,
  String? publicBooking,
  String? booking,
  String? publicRef,
})
_extractBusinessReferenceAliasesFromMaps(List<Map<String, dynamic>> maps) {
  final receipt = _pickReferenceAliasFromMaps(
    maps,
    _receiptReferenceAliasPaths,
  );
  final planning = _pickReferenceAliasFromMaps(
    maps,
    _planningReferenceAliasPaths,
  );
  final publicBooking = _pickReferenceAliasFromMaps(
    maps,
    _publicBookingReferenceAliasPaths,
  );
  final bookingRef = _pickReferenceAliasFromMaps(
    maps,
    _bookingReferenceAliasPaths,
  );
  final publicRef = _pickReferenceAliasFromMaps(
    maps,
    _publicReferenceAliasPaths,
  );
  return (
    receipt: receipt,
    planning: planning,
    publicBooking: publicBooking,
    booking: bookingRef,
    publicRef: publicRef,
  );
}

Map<String, dynamic> _mergeBusinessReferencesIntoSource({
  required Map<String, dynamic> source,
  required Map<String, dynamic> authoritative,
  String? canonicalBookingId,
  String? tripId,
  required String sourceTag,
}) {
  final merged = Map<String, dynamic>.from(source);
  final sourceMaps = _referenceLookupMaps(<Map<String, dynamic>>[merged]);
  final authoritativeMaps = _referenceLookupMaps(<Map<String, dynamic>>[
    authoritative,
  ]);
  final existing = _extractBusinessReferenceAliasesFromMaps(sourceMaps);
  final incoming = _extractBusinessReferenceAliasesFromMaps(authoritativeMaps);
  final selectedPlanning = incoming.planning ?? existing.planning;
  final selectedPublicBooking =
      incoming.publicBooking ?? existing.publicBooking;
  final selectedBooking = incoming.booking ?? existing.booking;
  final selectedPublic = incoming.publicRef ?? existing.publicRef;
  final existingReceipt = existing.receipt;
  final incomingReceipt = incoming.receipt;
  final resolvedReceipt =
      (incomingReceipt != null &&
          _isRealReceiptReference(
            candidate: incomingReceipt,
            canonicalBookingId: canonicalBookingId,
            tripId: tripId,
            planningReference: selectedPlanning,
            publicBookingReference: selectedPublicBooking,
            legacyTripReceiptNumber: tripId == null
                ? null
                : _legacyTripReceiptNumber(tripId),
          ))
      ? incomingReceipt
      : existingReceipt;

  void setIfMeaningful(Map<String, dynamic> target, String key, String? value) {
    final text = _cleanBusinessReferenceText(value);
    if (text == null) return;
    target[key] = text;
  }

  final references = merged['references'] is Map
      ? Map<String, dynamic>.from(merged['references'] as Map)
      : <String, dynamic>{};
  final booking = merged['booking'] is Map
      ? Map<String, dynamic>.from(merged['booking'] as Map)
      : <String, dynamic>{};

  setIfMeaningful(merged, 'planning_reference', selectedPlanning);
  setIfMeaningful(merged, 'planningReference', selectedPlanning);
  setIfMeaningful(merged, 'public_booking_reference', selectedPublicBooking);
  setIfMeaningful(merged, 'publicBookingReference', selectedPublicBooking);
  setIfMeaningful(merged, 'booking_reference', selectedBooking);
  setIfMeaningful(merged, 'bookingReference', selectedBooking);
  setIfMeaningful(merged, 'public_reference', selectedPublic);
  setIfMeaningful(merged, 'publicReference', selectedPublic);
  setIfMeaningful(merged, 'receipt_reference', resolvedReceipt);
  setIfMeaningful(merged, 'receiptReference', resolvedReceipt);

  setIfMeaningful(references, 'planning_reference', selectedPlanning);
  setIfMeaningful(references, 'planningReference', selectedPlanning);
  setIfMeaningful(
    references,
    'public_booking_reference',
    selectedPublicBooking,
  );
  setIfMeaningful(references, 'publicBookingReference', selectedPublicBooking);
  setIfMeaningful(references, 'booking_reference', selectedBooking);
  setIfMeaningful(references, 'bookingReference', selectedBooking);
  setIfMeaningful(references, 'public_reference', selectedPublic);
  setIfMeaningful(references, 'publicReference', selectedPublic);
  setIfMeaningful(references, 'receipt_reference', resolvedReceipt);
  setIfMeaningful(references, 'receiptReference', resolvedReceipt);

  setIfMeaningful(booking, 'planning_reference', selectedPlanning);
  setIfMeaningful(booking, 'planningReference', selectedPlanning);
  setIfMeaningful(booking, 'public_booking_reference', selectedPublicBooking);
  setIfMeaningful(booking, 'publicBookingReference', selectedPublicBooking);
  setIfMeaningful(booking, 'booking_reference', selectedBooking);
  setIfMeaningful(booking, 'bookingReference', selectedBooking);
  setIfMeaningful(booking, 'public_reference', selectedPublic);
  setIfMeaningful(booking, 'publicReference', selectedPublic);
  setIfMeaningful(booking, 'receipt_reference', resolvedReceipt);
  setIfMeaningful(booking, 'receiptReference', resolvedReceipt);

  if (references.isNotEmpty) merged['references'] = references;
  if (booking.isNotEmpty) merged['booking'] = booking;

  debugPrint(
    '[RECEIPT][REF_ENRICH] source=$sourceTag booking=${_safeRefPreview(canonicalBookingId ?? '')} planning=${selectedPlanning ?? ''} public=${selectedPublicBooking ?? ''} receipt=${resolvedReceipt ?? ''}',
  );
  return merged;
}

String _safeRefPreview(String value) {
  final text = value.trim();
  if (text.isEmpty) return '';
  if (text.length <= 10) return text;
  return '${text.substring(0, 4)}…${text.substring(text.length - 4)}';
}

Future<void> _agentDebugLog({
  required String runId,
  required String hypothesisId,
  required String location,
  required String message,
  required Map<String, dynamic> data,
}) async {
  try {
    final payload = <String, dynamic>{
      'sessionId': '59ce83',
      'runId': runId,
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await File('debug-59ce83.log').writeAsString(
      '${jsonEncode(payload)}\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {
    // Keep debug logging non-blocking.
  }
}

void _debugReceiptReferenceSelection({
  required String source,
  required _TripHistoryItem item,
  required String selected,
}) {
  final maps = _referenceLookupMaps(<Map<String, dynamic>>[
    item.rawSource,
    item.bookingDetails,
  ]);
  final refs = _extractBusinessReferenceAliasesFromMaps(maps);
  debugPrint(
    '[RECEIPT][REF_SELECTED] booking=${_safeRefPreview(item.bookingId ?? '')} receipt=${refs.receipt ?? ''} planning=${refs.planning ?? ''} public=${refs.publicBooking ?? ''} selected=$selected source=$source',
  );
}

String _legacyTripReceiptNumber(String tripId) {
  final normalized = tripId.trim();
  if (normalized.length <= 10) return normalized;
  return '${normalized.substring(0, 6)}-${normalized.substring(normalized.length - 4)}';
}

bool _sameReference(String? a, String? b) {
  final left = _cleanBusinessReferenceText(a);
  final right = _cleanBusinessReferenceText(b);
  if (left == null || right == null) return false;
  return left.trim().toLowerCase() == right.trim().toLowerCase();
}

bool _isLegacyTripReceiptNumber(String? value) {
  final text = _cleanBusinessReferenceText(value);
  if (text == null) return false;
  final lower = text.toLowerCase();
  if (lower.startsWith('planne-')) return true;
  return RegExp(r'^planne-[a-z0-9]{3,}$').hasMatch(lower);
}

bool _isDerivedPlannedTripReference({
  required String candidate,
  String? canonicalBookingId,
  String? tripId,
}) {
  final lower = candidate.trim().toLowerCase();
  if (lower.startsWith('planned_')) return true;
  final canonical = _cleanBusinessReferenceText(canonicalBookingId);
  if (canonical != null && _sameReference(candidate, 'planned_$canonical')) {
    return true;
  }
  if (tripId != null &&
      _sameReference(candidate, tripId) &&
      lower.startsWith('planned_')) {
    return true;
  }
  return false;
}

bool _isRealReceiptReference({
  required String candidate,
  String? canonicalBookingId,
  String? tripId,
  String? planningReference,
  String? publicBookingReference,
  String? legacyTripReceiptNumber,
}) {
  final normalized = _cleanBusinessReferenceText(candidate);
  if (normalized == null) return false;
  if (_sameReference(normalized, canonicalBookingId)) return false;
  if (_sameReference(normalized, tripId)) return false;
  if (_sameReference(normalized, planningReference)) return false;
  if (_sameReference(normalized, publicBookingReference)) return false;
  if (_sameReference(normalized, legacyTripReceiptNumber)) return false;
  if (_isLegacyTripReceiptNumber(normalized)) return false;
  if (_isDerivedPlannedTripReference(
    candidate: normalized,
    canonicalBookingId: canonicalBookingId,
    tripId: tripId,
  )) {
    return false;
  }
  return true;
}

String _pickBusinessReference({
  required Map<String, dynamic> rawSource,
  Map<String, dynamic> details = const <String, dynamic>{},
  String? bookingId,
  String? tripId,
  String? legacyFallback,
}) {
  final maps = _referenceLookupMaps(<Map<String, dynamic>>[rawSource, details]);

  const receiptPaths = <List<String>>[
    <String>['receipt_reference'],
    <String>['receiptReference'],
    <String>['references', 'receipt_reference'],
    <String>['references', 'receiptReference'],
    <String>['booking', 'receipt_reference'],
    <String>['booking', 'receiptReference'],
  ];
  const planningPaths = <List<String>>[
    <String>['planning_reference'],
    <String>['planningReference'],
    <String>['references', 'planning_reference'],
    <String>['references', 'planningReference'],
    <String>['booking', 'planning_reference'],
    <String>['booking', 'planningReference'],
  ];
  const publicBookingPaths = <List<String>>[
    <String>['public_booking_reference'],
    <String>['publicBookingReference'],
    <String>['booking_reference'],
    <String>['bookingReference'],
    <String>['public_reference'],
    <String>['publicReference'],
    <String>['references', 'public_booking_reference'],
    <String>['references', 'publicBookingReference'],
    <String>['references', 'booking_reference'],
    <String>['references', 'bookingReference'],
    <String>['references', 'public_reference'],
    <String>['references', 'publicReference'],
    <String>['booking', 'public_booking_reference'],
    <String>['booking', 'publicBookingReference'],
    <String>['booking', 'booking_reference'],
    <String>['booking', 'bookingReference'],
    <String>['booking', 'public_reference'],
    <String>['booking', 'publicReference'],
  ];
  const canonicalBookingPaths = <List<String>>[
    <String>['booking_id'],
    <String>['bookingId'],
    <String>['references', 'booking_id'],
    <String>['references', 'bookingId'],
    <String>['booking', 'booking_id'],
    <String>['booking', 'bookingId'],
    <String>['id'],
  ];
  const tripPaths = <List<String>>[
    <String>['trip_id'],
    <String>['tripId'],
    <String>['references', 'trip_id'],
    <String>['references', 'tripId'],
    <String>['booking', 'trip_id'],
    <String>['booking', 'tripId'],
  ];

  final canonicalBookingId =
      _cleanBusinessReferenceText(bookingId) ??
      _pickReferenceAliasFromMaps(maps, canonicalBookingPaths);
  final effectiveTripId =
      _cleanBusinessReferenceText(tripId) ??
      _pickReferenceAliasFromMaps(maps, tripPaths);
  final planningRef = _pickReferenceAliasFromMaps(maps, planningPaths);
  final publicBookingRef = _pickReferenceAliasFromMaps(
    maps,
    publicBookingPaths,
  );
  final receiptRef = _pickReferenceAliasFromMaps(maps, receiptPaths);
  final legacyTripReceiptNumber =
      _cleanBusinessReferenceText(legacyFallback) ??
      (effectiveTripId == null
          ? null
          : _legacyTripReceiptNumber(effectiveTripId));
  if (receiptRef != null &&
      _isRealReceiptReference(
        candidate: receiptRef,
        canonicalBookingId: canonicalBookingId,
        tripId: effectiveTripId,
        planningReference: planningRef,
        publicBookingReference: publicBookingRef,
        legacyTripReceiptNumber: legacyTripReceiptNumber,
      )) {
    return receiptRef;
  }

  if (planningRef != null) return planningRef;
  if (publicBookingRef != null) return publicBookingRef;
  if (canonicalBookingId != null) return canonicalBookingId;
  if (effectiveTripId != null) return effectiveTripId;

  final fallback = _cleanBusinessReferenceText(legacyTripReceiptNumber);
  return fallback ?? '—';
}

enum _BusinessReferenceKind {
  receipt,
  planning,
  publicBooking,
  canonicalBooking,
  internalTrip,
  unknown,
}

_BusinessReferenceKind _classifyBusinessReferenceSelection({
  required String selectedValue,
  required Map<String, dynamic> rawSource,
  required Map<String, dynamic> details,
  String? bookingId,
  String? tripId,
}) {
  final selected = _cleanBusinessReferenceText(selectedValue);
  if (selected == null) return _BusinessReferenceKind.unknown;
  final maps = _referenceLookupMaps(<Map<String, dynamic>>[rawSource, details]);
  final refs = _extractBusinessReferenceAliasesFromMaps(maps);
  final canonicalBookingId =
      _cleanBusinessReferenceText(bookingId) ??
      _pickReferenceAliasFromMaps(maps, const [
        ['booking_id'],
        ['bookingId'],
        ['id'],
      ]);
  final effectiveTripId =
      _cleanBusinessReferenceText(tripId) ??
      _pickReferenceAliasFromMaps(maps, const [
        ['trip_id'],
        ['tripId'],
      ]);
  if (_sameReference(selected, refs.receipt) &&
      _isRealReceiptReference(
        candidate: selected,
        canonicalBookingId: canonicalBookingId,
        tripId: effectiveTripId,
        planningReference: refs.planning,
        publicBookingReference: refs.publicBooking,
        legacyTripReceiptNumber: effectiveTripId == null
            ? null
            : _legacyTripReceiptNumber(effectiveTripId),
      )) {
    return _BusinessReferenceKind.receipt;
  }
  if (_sameReference(selected, refs.planning)) {
    return _BusinessReferenceKind.planning;
  }
  if (_sameReference(selected, refs.publicBooking) ||
      _sameReference(selected, refs.booking) ||
      _sameReference(selected, refs.publicRef)) {
    return _BusinessReferenceKind.publicBooking;
  }
  if (_sameReference(selected, canonicalBookingId)) {
    return _BusinessReferenceKind.canonicalBooking;
  }
  if (_sameReference(selected, effectiveTripId) ||
      _isLegacyTripReceiptNumber(selected) ||
      _isDerivedPlannedTripReference(
        candidate: selected,
        canonicalBookingId: canonicalBookingId,
        tripId: effectiveTripId,
      )) {
    return _BusinessReferenceKind.internalTrip;
  }
  return _BusinessReferenceKind.unknown;
}

String _receiptReferenceLabelForKind(_BusinessReferenceKind kind) {
  switch (kind) {
    case _BusinessReferenceKind.receipt:
      return _receiptText('receiptNumber');
    case _BusinessReferenceKind.planning:
      return _receiptText('planningNumber');
    case _BusinessReferenceKind.publicBooking:
      return _receiptText('bookingNumber');
    case _BusinessReferenceKind.canonicalBooking:
      return _receiptText('internalBooking');
    case _BusinessReferenceKind.internalTrip:
      return _receiptText('internalTrip');
    case _BusinessReferenceKind.unknown:
      return _receiptText('reference');
  }
}

({String label, String value, _BusinessReferenceKind kind})
_businessReferenceDisplayForItem(
  _TripHistoryItem item, {
  required String source,
}) {
  final selected = _pickBusinessReference(
    rawSource: item.rawSource,
    details: item.bookingDetails,
    bookingId: item.bookingId,
    tripId: item.tripId,
    legacyFallback: _legacyTripReceiptNumber(item.tripId),
  );
  final kind = _classifyBusinessReferenceSelection(
    selectedValue: selected,
    rawSource: item.rawSource,
    details: item.bookingDetails,
    bookingId: item.bookingId,
    tripId: item.tripId,
  );
  _debugReceiptReferenceSelection(
    source: source,
    item: item,
    selected: selected,
  );
  return (
    label: _receiptReferenceLabelForKind(kind),
    value: selected,
    kind: kind,
  );
}

String? _paymentUpdatePaidAtUtc(Map<String, dynamic> fields) {
  final raw = _paymentUpdateField(fields, const [
    'paid_at_utc',
    'paidAtUtc',
    'paid_at',
    'paidAt',
  ]);
  if (raw == null) return null;
  final parsed = DateTime.tryParse(raw);
  return parsed == null ? raw : parsed.toUtc().toIso8601String();
}

bool _isPaidPaymentUpdate(Map<String, dynamic> fields) {
  return _normalizePaymentUpdateStatus(
        _paymentUpdateField(fields, const ['payment_status', 'paymentStatus']),
      ) ==
      'paid';
}

Map<String, dynamic> _buildCompliancePaymentUpdateLedgerRecord({
  required _TripHistoryItem item,
  required Map<String, dynamic> paymentFields,
  required String method,
  required String source,
  required DateTime eventAt,
  bool? backendConfirmed,
}) {
  final bookingId = (item.bookingId ?? '').trim();
  final tripId = item.tripId.trim();
  final normalizedRideType = item.kind.trim().toLowerCase();
  final rideType =
      normalizedRideType == 'direct' || normalizedRideType == 'planned'
      ? normalizedRideType
      : (bookingId.isNotEmpty
            ? 'planned'
            : (tripId.isNotEmpty ? 'direct' : 'unknown'));
  final paidAtUtc =
      _paymentUpdatePaidAtUtc(paymentFields) ??
      eventAt.toUtc().toIso8601String();
  final status = _normalizePaymentUpdateStatus(
    _paymentUpdateField(paymentFields, const [
      'payment_status',
      'paymentStatus',
    ]),
  );
  final normalizedMethod = _normalizePaymentUpdateMethod(
    _paymentUpdateField(paymentFields, const [
          'payment_method',
          'paymentMethod',
        ]) ??
        method,
  );
  final paymentSource =
      _paymentUpdateField(paymentFields, const [
        'payment_source',
        'paymentSource',
      ]) ??
      source;
  final provider = _paymentUpdateField(paymentFields, const [
    'payment_provider',
    'paymentProvider',
  ]);
  final paymentId = _paymentUpdateField(paymentFields, const [
    'payment_id',
    'paymentId',
  ]);
  final maps = _referenceLookupMaps(<Map<String, dynamic>>[
    paymentFields,
    item.bookingDetails,
    item.rawSource,
  ]);
  final receiptReference = _pickReferenceAliasFromMaps(maps, const [
    ['receipt_reference'],
    ['receiptReference'],
  ]);
  final planningReference = _pickReferenceAliasFromMaps(maps, const [
    ['planning_reference'],
    ['planningReference'],
  ]);
  final publicBookingReference = _pickReferenceAliasFromMaps(maps, const [
    ['public_booking_reference'],
    ['publicBookingReference'],
    ['booking_reference'],
    ['bookingReference'],
    ['public_reference'],
    ['publicReference'],
  ]);
  final bookingReference = _pickReferenceAliasFromMaps(maps, const [
    ['booking_reference'],
    ['bookingReference'],
  ]);
  final publicReference = _pickReferenceAliasFromMaps(maps, const [
    ['public_reference'],
    ['publicReference'],
  ]);
  final reference = _pickBusinessReference(
    rawSource: item.rawSource,
    details: item.bookingDetails,
    bookingId: bookingId,
    tripId: tripId,
    legacyFallback: _legacyTripReceiptNumber(item.tripId),
  );
  final effectiveReceiptReference =
      (receiptReference != null &&
          _isRealReceiptReference(
            candidate: receiptReference,
            canonicalBookingId: bookingId,
            tripId: tripId,
            planningReference: planningReference,
            publicBookingReference: publicBookingReference,
            legacyTripReceiptNumber: _legacyTripReceiptNumber(item.tripId),
          ))
      ? receiptReference
      : reference;
  final eventKey = reference.isEmpty
      ? eventAt.toUtc().millisecondsSinceEpoch
      : reference;
  final strictScope = _strictComplianceScopeFromValues(
    tenantCandidates: <dynamic>[
      paymentFields['tenant_id'],
      paymentFields['tenantId'],
      item.bookingDetails['tenant_id'],
      item.bookingDetails['tenantId'],
      item.rawSource['tenant_id'],
      item.rawSource['tenantId'],
      activeDriverSessionNotifier.value?.tenantId,
    ],
    companyCandidates: <dynamic>[
      paymentFields['company_id'],
      paymentFields['companyId'],
      item.bookingDetails['company_id'],
      item.bookingDetails['companyId'],
      item.rawSource['company_id'],
      item.rawSource['companyId'],
      activeDriverSessionNotifier.value?.companyId,
      companyProfileNotifier.value?.companyId,
      activeCompanySessionNotifier.value?.companyId,
    ],
  );

  return <String, dynamic>{
    'ledger_version': '1.0',
    'event_type': 'payment_update',
    'event_id': 'payment_update_${eventKey}_${normalizedMethod}_$paidAtUtc',
    'ride_id': null,
    'ride_type': rideType,
    'lifecycle_status': 'payment_updated',
    'tenant_id': strictScope?.tenantId ?? '',
    'company_id': strictScope?.companyId ?? '',
    'driver_id': item.driverId.trim().isNotEmpty
        ? item.driverId.trim()
        : kDriverId,
    'vehicle_id': (item.vehicleId ?? '').trim().isEmpty
        ? null
        : item.vehicleId!.trim(),
    'booking_id': bookingId.isEmpty ? null : bookingId,
    'trip_id': tripId.isEmpty ? null : tripId,
    'session_id': null,
    'payment': <String, dynamic>{
      'status': status,
      if (normalizedMethod != 'unknown') 'method': normalizedMethod,
      if (paymentSource.trim().isNotEmpty) 'source': paymentSource.trim(),
      if (provider != null) 'provider': provider,
      if (paymentId != null) 'payment_id': paymentId,
      'paid_at_utc': paidAtUtc,
    },
    'references': <String, dynamic>{
      'receipt_reference': effectiveReceiptReference.isEmpty
          ? null
          : effectiveReceiptReference,
      'planning_reference': planningReference,
      'public_booking_reference': publicBookingReference,
      'booking_reference': bookingReference,
      'public_reference': publicReference,
      'invoice_reference': null,
    },
    'provenance': <String, dynamic>{
      'backend_confirmed': backendConfirmed,
      'validation_state': 'payment_update',
      'source': 'in_car_payment_mark',
    },
    'created_at_utc': eventAt.toUtc().toIso8601String(),
    'finalized_at_utc': eventAt.toUtc().toIso8601String(),
  };
}

bool _isPaidForReceiptPaymentFallback(String? rawStatus) {
  final normalized = (rawStatus ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
  return normalized == 'paid' ||
      normalized == 'settled' ||
      normalized == 'confirmed' ||
      normalized == 'completed' ||
      normalized == 'succeeded' ||
      normalized == 'success';
}

bool _isMissingOrUnknownReceiptPaymentField(String? value) {
  final normalized = (value ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
  return normalized.isEmpty || normalized == 'unknown';
}

String? _paymentFieldWithMolliePaidFallback({
  required String? value,
  required String? paymentStatus,
  required String? paymentProvider,
}) {
  if (!_isMissingOrUnknownReceiptPaymentField(value)) {
    return value?.trim();
  }
  final providerNormalized = (paymentProvider ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
  if (providerNormalized == 'mollie' &&
      _isPaidForReceiptPaymentFallback(paymentStatus)) {
    return 'mollie';
  }
  return value?.trim();
}
