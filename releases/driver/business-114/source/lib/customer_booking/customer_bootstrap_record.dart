import 'package:fluxidi_tracking/customer_booking/customer_booking_references.dart';
import 'package:fluxidi_tracking/customer_booking/customer_payment_display.dart';
import 'package:fluxidi_tracking/customer_bookings_store.dart';

dynamic customerBootstrapValueAtPath(Map<String, dynamic> source, String path) {
  dynamic current = source;
  for (final segment in path.split('.')) {
    if (current is Map && current.containsKey(segment)) {
      current = current[segment];
    } else {
      return null;
    }
  }
  return current;
}

String customerBootstrapText(Map<String, dynamic> source, List<String> paths) {
  for (final path in paths) {
    final value = customerBootstrapValueAtPath(source, path);
    final text = (value ?? '').toString().trim();
    if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
  }
  return '';
}

double? customerBootstrapDouble(Map<String, dynamic> source, List<String> paths) {
  for (final path in paths) {
    final value = customerBootstrapValueAtPath(source, path);
    if (value is num) return value.toDouble();
    final text = (value ?? '').toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') continue;
    final parsed = double.tryParse(text.replaceAll(',', '.'));
    if (parsed != null) return parsed;
  }
  return null;
}

Map<String, dynamic> customerBootstrapQuoteMap(Map<String, dynamic> item) {
  final raw = customerBootstrapValueAtPath(item, 'quote');
  final quote = raw is Map
      ? Map<String, dynamic>.from(raw)
      : <String, dynamic>{};
  final legs = item['operational_legs'] ?? item['operationalLegs'];
  if (legs is List && !quote.containsKey('operational_legs')) {
    quote['operational_legs'] = legs;
  }
  return quote;
}

/// Maps one bootstrap list item onto the same stored booking the list cards use.
///
/// The list no longer waits for GET /bookings/{id} or the tracking-trips
/// overlay. Parent ride status, payment fields and the public customer
/// reference must therefore already be present on this item.
StoredCustomerBooking? storedCustomerBookingFromBootstrapItem({
  required Map<String, dynamic> item,
  String fallbackTenantId = '',
  String fallbackCompanyId = '',
}) {
  final bookingId = customerBootstrapText(item, const [
    'booking_id',
    'bookingId',
    'id',
    'public_booking_id',
    'publicBookingId',
  ]);
  if (bookingId.isEmpty) return null;
  final paymentChannel = extractCustomerPaymentChannel(<Map<String, dynamic>>[
    item,
    customerBootstrapQuoteMap(item),
  ]);
  final nowIso = DateTime.now().toIso8601String();
  final tenantId = customerBootstrapText(item, const [
    'tenant_id',
    'tenantId',
  ]);
  final companyId = customerBootstrapText(item, const [
    'company_id',
    'companyId',
  ]);
  final publicReference = distinctPublicCustomerReference(
    bookingId: bookingId,
    candidates: <String>[
      customerBootstrapText(item, const [
        'public_booking_reference',
        'publicBookingReference',
        'booking_reference',
        'bookingReference',
        'public_reference',
        'publicReference',
      ]),
    ],
  );
  return StoredCustomerBooking(
    bookingId: bookingId,
    tenantId: tenantId.isNotEmpty ? tenantId : fallbackTenantId.trim(),
    companyId: companyId.isNotEmpty ? companyId : fallbackCompanyId.trim(),
    publicBookingId: publicReference,
    planningReference: customerBootstrapText(item, const [
      'planning_reference',
      'planningReference',
    ]),
    bookingReference: distinctPublicCustomerReference(
      bookingId: bookingId,
      candidates: <String>[
        customerBootstrapText(item, const [
          'booking_reference',
          'bookingReference',
          'public_booking_reference',
          'publicBookingReference',
        ]),
      ],
    ),
    publicReference: publicReference,
    receiptReference: customerBootstrapText(item, const [
      'receipt_reference',
      'receiptReference',
    ]),
    paymentBookingId: customerBootstrapText(item, const [
      'payment_booking_id',
      'paymentBookingId',
    ]),
    customerName: customerBootstrapText(item, const [
      'customer_name',
      'customerName',
    ]),
    customerPhone: customerBootstrapText(item, const [
      'customer_phone',
      'customerPhone',
    ]),
    customerEmail: customerBootstrapText(item, const [
      'customer_email',
      'customerEmail',
    ]),
    from: customerBootstrapText(item, const [
      'from',
      'pickup_address',
      'pickupAddress',
    ]),
    to: customerBootstrapText(item, const [
      'to',
      'dropoff_address',
      'dropoffAddress',
    ]),
    pickupIso: customerBootstrapText(item, const ['pickup_iso', 'pickupIso']),
    price: customerBootstrapDouble(item, const [
      'price',
      'quoted_price',
      'quotedPrice',
    ]),
    currency: customerBootstrapText(item, const [
      'currency',
      'quote.currency',
    ]),
    paymentStatus: customerBootstrapText(item, const [
      'payment_status',
      'paymentStatus',
    ]),
    paymentMethod: paymentChannel.method,
    paymentMode: paymentChannel.mode,
    paymentProvider: paymentChannel.provider,
    status: customerBootstrapText(item, const [
      'status',
      'stage',
      'booking_status',
      'bookingStatus',
      'lifecycle_status',
      'lifecycleStatus',
    ]).toUpperCase(),
    service: customerBootstrapText(item, const [
      'service_type',
      'serviceType',
      'service',
    ]),
    tier: customerBootstrapText(item, const [
      'tier',
      'vehicle_tier',
      'vehicleTier',
    ]),
    pax: customerBootstrapText(item, const [
      'passenger_count',
      'passengerCount',
      'pax',
    ]),
    bags: customerBootstrapText(item, const [
      'luggage_count',
      'luggageCount',
      'bags',
    ]),
    createdAt: customerBootstrapText(item, const ['created_at', 'createdAt'])
            .isNotEmpty
        ? customerBootstrapText(item, const ['created_at', 'createdAt'])
        : nowIso,
    updatedAt: customerBootstrapText(item, const ['updated_at', 'updatedAt'])
            .isNotEmpty
        ? customerBootstrapText(item, const ['updated_at', 'updatedAt'])
        : nowIso,
    companyName: customerBootstrapText(item, const [
      'company_name',
      'companyName',
    ]),
    vatNumber: customerBootstrapText(item, const ['vat_number', 'vatNumber']),
    invoiceEmail: customerBootstrapText(item, const [
      'invoice_email',
      'invoiceEmail',
    ]),
    invoiceAddress: customerBootstrapText(item, const [
      'invoice_address',
      'invoiceAddress',
    ]),
    quote: mergeCustomerPaymentChannelIntoQuote(
      customerBootstrapQuoteMap(item),
      paymentChannel,
    ),
  );
}
