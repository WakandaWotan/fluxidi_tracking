part of '../main.dart';

enum _CompanyBookingsFilter { open, completed, cancelled, review }

class _CompanyBookingsLoadException implements Exception {
  final String code;
  _CompanyBookingsLoadException(this.code);
}

class _CompanyBookingOverviewItem {
  final String bookingId;
  final String referenceText;
  final String pickupIso;
  final String fromAddress;
  final String toAddress;
  final String customerName;
  final String assignedDriverText;
  final String assignedVehicleText;
  final String statusText;
  final String paymentStatus;
  final num? amount;
  final String currency;
  final _CompanyBookingsFilter bucket;

  const _CompanyBookingOverviewItem({
    required this.bookingId,
    required this.referenceText,
    required this.pickupIso,
    required this.fromAddress,
    required this.toAddress,
    required this.customerName,
    required this.assignedDriverText,
    required this.assignedVehicleText,
    required this.statusText,
    required this.paymentStatus,
    required this.amount,
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

  static _CompanyBookingsFilter _bucketFromStatus({
    required String statusRaw,
    required String pickupIso,
    required String fromAddress,
    required String toAddress,
  }) {
    final normalized = _normStatus(statusRaw);
    if (normalized.contains('CANCEL')) return _CompanyBookingsFilter.cancelled;
    if (normalized == 'DELETED') return _CompanyBookingsFilter.cancelled;
    if (normalized.contains('COMPLETE') ||
        normalized == 'DONE' ||
        normalized == 'FINISHED') {
      return _CompanyBookingsFilter.completed;
    }
    final hasRoute =
        fromAddress.trim().isNotEmpty &&
        fromAddress.trim() != '—' &&
        toAddress.trim().isNotEmpty &&
        toAddress.trim() != '—';
    final pickupParsed = DateTime.tryParse(pickupIso.trim());
    if (pickupParsed == null) {
      return _CompanyBookingsFilter.review;
    }
    final pickupMs = pickupParsed.toLocal().millisecondsSinceEpoch;
    final cutoffMs = DateTime.now()
        .subtract(const Duration(hours: 6))
        .millisecondsSinceEpoch;
    if (pickupMs < cutoffMs) {
      return _CompanyBookingsFilter.review;
    }
    if (!hasRoute) {
      return _CompanyBookingsFilter.review;
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
    ]);
    final amount = _firstNum(raw, const <String>[
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
    return _CompanyBookingOverviewItem(
      bookingId: bookingId,
      referenceText: referenceText.isEmpty ? bookingId : referenceText,
      pickupIso: pickupIso,
      fromAddress: fromAddress.isEmpty ? '—' : fromAddress,
      toAddress: toAddress.isEmpty ? '—' : toAddress,
      customerName: customerName,
      assignedDriverText: assignedDriver.isEmpty ? '—' : assignedDriver,
      assignedVehicleText: assignedVehicle.isEmpty ? '—' : assignedVehicle,
      statusText: _normStatus(statusRaw),
      paymentStatus: _normStatus(paymentStatus),
      amount: amount,
      currency: currency,
      bucket: _bucketFromStatus(
        statusRaw: statusRaw,
        pickupIso: pickupIso,
        fromAddress: fromAddress,
        toAddress: toAddress,
      ),
    );
  }
}
