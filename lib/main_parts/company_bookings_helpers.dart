part of '../main.dart';

enum _CompanyBookingsFilter { open, completed, cancelled, toCredit }

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
  final String creditStatus;
  final String refundStatus;
  final bool refundRequired;
  final String creditDecision;
  final int? creditedAmountCents;
  final String creditedAt;
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
    required this.creditStatus,
    required this.refundStatus,
    required this.refundRequired,
    required this.creditDecision,
    required this.creditedAmountCents,
    required this.creditedAt,
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

  static bool isPaidPaymentStatus(String paymentStatus) {
    final normalized = _normStatus(paymentStatus);
    return normalized == 'PAID' ||
        normalized == 'SUCCESS' ||
        normalized == 'CONFIRMED' ||
        normalized == 'COMPLETED' ||
        normalized == 'SETTLED';
  }

  static bool _inferPaidFromRawMap(Map<String, dynamic> raw) {
    if (isPaidPaymentStatus(
      _firstText(raw, const <String>[
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
      ]),
    )) {
      return true;
    }
    final paidAt = _firstText(raw, const <String>[
      'paid_at',
      'paidAt',
      'record.paid_at',
      'record.paidAt',
      'booking.paid_at',
      'booking.paidAt',
      'record.booking.paid_at',
      'record.booking.paidAt',
      'payload.paid_at',
      'payload.paidAt',
      'record.payload.paid_at',
      'record.payload.paidAt',
    ]);
    if (paidAt.isEmpty) return false;
    final provider = _normStatus(
      _firstText(raw, const <String>[
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
      ]),
    );
    return provider == 'MOLLIE' ||
        provider == 'ONLINE' ||
        provider == 'ONLINE_PAYMENT' ||
        provider == 'ONLINE_PAYMENTS' ||
        provider == 'PREPAID' ||
        _firstText(raw, const <String>[
          'payment_id',
          'paymentId',
          'record.payment_id',
          'record.paymentId',
          'booking.payment_id',
          'booking.paymentId',
          'record.booking.payment_id',
          'record.booking.paymentId',
        ]).isNotEmpty;
  }

  static bool _isPaidPaymentStatus(String paymentStatus) =>
      isPaidPaymentStatus(paymentStatus);

  static bool _isPendingCreditToken(String raw) {
    return _normStatus(raw) == 'PENDING_CREDIT';
  }

  static bool _deriveIsPendingCredit({
    required Map<String, dynamic> raw,
    required String statusRaw,
    required String paymentStatus,
    required String creditStatus,
    required String refundStatus,
    required bool refundRequired,
  }) {
    if (!_isCancelledStatus(statusRaw)) return false;
    if (!_isPaidPaymentStatus(paymentStatus) && !_inferPaidFromRawMap(raw)) {
      return false;
    }
    return _isPendingCreditToken(creditStatus) ||
        _isPendingCreditToken(refundStatus) ||
        refundRequired;
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
    );
    final normalizedPaymentStatus =
        isPaidPaymentStatus(paymentStatus) || _inferPaidFromRawMap(raw)
        ? 'PAID'
        : _normStatus(paymentStatus);
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
      creditStatus: _normStatus(creditStatus),
      refundStatus: _normStatus(refundStatus),
      refundRequired: refundRequired,
      creditDecision: _normStatus(creditDecision),
      creditedAmountCents: creditedAmountRaw?.round(),
      creditedAt: creditedAt,
      isPendingCredit: isPendingCredit,
      amount: amount,
      parentAmount: parentAmount,
      currency: currency,
      bucket: _bucketFromStatus(statusRaw: statusRaw),
    );
  }
}
