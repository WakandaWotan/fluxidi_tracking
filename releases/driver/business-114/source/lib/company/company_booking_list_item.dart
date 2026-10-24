// COMPANY-CUSTOMER-OPS-P0 — same list fields and buckets as the company overview.

import 'package:fluxidi_tracking/company/company_booking_created_sort.dart';
import 'package:fluxidi_tracking/main_parts/direct_ride_booking_link.dart';

enum CompanyBookingListBucket {
  open,
  completed,
  cancelled,
  toCredit,
  refundPending,
  refunded,
  refundFailed,
}

class CompanyBookingListItem {
  const CompanyBookingListItem({
    required this.bookingId,
    required this.customerName,
    required this.fromAddress,
    required this.toAddress,
    required this.pickupIso,
    required this.statusText,
    required this.paymentStatus,
    required this.quoteId,
    required this.createdAtIso,
    required this.assignedDriverText,
    required this.assignedVehicleText,
    required this.amount,
    required this.currency,
    required this.bucket,
    this.refundRequired = false,
    this.refundStatus = '',
    this.creditStatus = '',
  });

  final String bookingId;
  final String customerName;
  final String fromAddress;
  final String toAddress;
  final String pickupIso;
  final String statusText;
  final String paymentStatus;
  final String quoteId;
  final String createdAtIso;
  final String assignedDriverText;
  final String assignedVehicleText;
  final num? amount;
  final String currency;
  final CompanyBookingListBucket bucket;
  final bool refundRequired;
  final String refundStatus;
  final String creditStatus;

  String get routeLabel {
    if (fromAddress.isEmpty && toAddress.isEmpty) return bookingId;
    return '$fromAddress → $toAddress';
  }

  factory CompanyBookingListItem.fromMap(Map<String, dynamic> raw) {
    String first(List<String> keys) {
      for (final key in keys) {
        final value = _pathText(raw, key);
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    final bookingId = first(const <String>[
      'booking_id',
      'bookingId',
      'id',
      'record.booking_id',
      'record.booking.id',
    ]);
    final statusText = first(const <String>[
      'status',
      'lifecycle',
      'lifecycle_status',
      'booking.status',
      'record.status',
      'record.booking.status',
    ]);
    final paymentStatus = first(const <String>[
      'payment_status',
      'paymentStatus',
      'record.payment_status',
      'booking.payment_status',
    ]);
    final refundStatus = first(const <String>[
      'refund_status',
      'refundStatus',
      'mollie_refund_status',
    ]);
    final creditStatus = first(const <String>[
      'credit_status',
      'creditStatus',
      'credit_decision',
    ]);
    final refundRequiredRaw = first(const <String>[
      'refund_required',
      'refundRequired',
    ]).toLowerCase();
    final refundRequired =
        refundRequiredRaw == 'true' || refundRequiredRaw == '1';
    final streetBucket = streetRideCompanyBucket(statusText);
    var bucket = switch (streetBucket) {
      StreetRideCompanyBucket.open => CompanyBookingListBucket.open,
      StreetRideCompanyBucket.completed => CompanyBookingListBucket.completed,
      StreetRideCompanyBucket.cancelled => CompanyBookingListBucket.cancelled,
    };
    final paid = paymentStatus.toLowerCase().contains('paid');
    if (bucket == CompanyBookingListBucket.cancelled &&
        paid &&
        (refundRequired || creditStatus.toLowerCase().contains('pending'))) {
      bucket = CompanyBookingListBucket.toCredit;
    }
    final refundNorm = refundStatus.toLowerCase();
    if (refundNorm.contains('fail')) {
      bucket = CompanyBookingListBucket.refundFailed;
    } else if (refundNorm.contains('refunded') || refundNorm.contains('complete')) {
      bucket = CompanyBookingListBucket.refunded;
    } else if (refundNorm.contains('pending')) {
      bucket = CompanyBookingListBucket.refundPending;
    }
    num? amount;
    final amountRaw = raw['price'] ??
        raw['amount'] ??
        raw['price_incl_vat'] ??
        (raw['booking'] is Map
            ? (raw['booking'] as Map)['price_incl_vat']
            : null);
    if (amountRaw is num) amount = amountRaw;
    if (amountRaw is String) amount = num.tryParse(amountRaw);
    return CompanyBookingListItem(
      bookingId: bookingId,
      customerName: first(const <String>[
        'customer_name',
        'customerName',
        'booking.customer_name',
        'record.customer_name',
      ]),
      fromAddress: first(const <String>[
        'from',
        'pickup',
        'pickup_address',
        'record.from',
      ]),
      toAddress: first(const <String>[
        'to',
        'dropoff',
        'dropoff_address',
        'record.to',
      ]),
      pickupIso: first(const <String>[
        'pickup_iso',
        'pickupIso',
        'start_at',
        'record.pickup_iso',
      ]),
      statusText: statusText,
      paymentStatus: paymentStatus,
      quoteId: first(const <String>[
        'quote_id',
        'quoteId',
        'planning_reference',
        'record.quote_id',
      ]),
      createdAtIso: extractCompanyBookingCreatedAtIso(raw),
      assignedDriverText: first(const <String>[
        'assigned_driver_name',
        'assignedDriverName',
        'assigned_driver_id',
      ]),
      assignedVehicleText: first(const <String>[
        'assigned_vehicle_id',
        'assignedVehicleId',
        'vehicle_id',
      ]),
      amount: amount,
      currency: first(const <String>['currency']).isEmpty
          ? 'EUR'
          : first(const <String>['currency']),
      bucket: bucket,
      refundRequired: refundRequired,
      refundStatus: refundStatus,
      creditStatus: creditStatus,
    );
  }
}

String _pathText(Map<String, dynamic> raw, String path) {
  dynamic current = raw;
  for (final part in path.split('.')) {
    if (current is! Map) return '';
    current = current[part];
  }
  return current?.toString().trim() ?? '';
}

List<CompanyBookingListItem> sortCompanyBookingListItems(
  Iterable<CompanyBookingListItem> items,
) {
  return sortCompanyBookingsNewestCreatedFirst(
    items.where((item) => item.bookingId.trim().isNotEmpty),
    (item) => CompanyBookingCreatedSortFields(
      bookingId: item.bookingId,
      createdAtIso: item.createdAtIso,
    ),
  );
}
