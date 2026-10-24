import 'package:fluxidi_tracking/customer_booking/customer_booking_references.dart';
import 'package:fluxidi_tracking/customer_booking/customer_payment_display.dart';
import 'package:fluxidi_tracking/customer_bookings_store.dart';

class CustomerSavedBooking {
  const CustomerSavedBooking({
    required this.bookingId,
    required this.tenantId,
    required this.companyId,
    required this.customerId,
    required this.createdAt,
    required this.pickupIso,
    required this.from,
    required this.to,
    required this.price,
    required this.currency,
    required this.paymentStatus,
    required this.bookingStatus,
    required this.publicReference,
    required this.rawSnapshot,
  });

  final String bookingId;
  final String tenantId;
  final String companyId;
  final String customerId;
  final String createdAt;
  final String pickupIso;
  final String from;
  final String to;
  final double? price;
  final String currency;
  final String paymentStatus;
  final String bookingStatus;
  final String publicReference;
  final Map<String, dynamic> rawSnapshot;

  factory CustomerSavedBooking.fromJson(Map<String, dynamic> json) {
    String read(String key) => (json[key] ?? '').toString().trim();
    double? readNum(String key) {
      final value = json[key];
      if (value is num) return value.toDouble();
      final parsed = double.tryParse(
        (value ?? '').toString().trim().replaceAll(',', '.'),
      );
      return parsed;
    }

    final raw = json['rawSnapshot'];
    final rawMap = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    return CustomerSavedBooking(
      bookingId: read('bookingId'),
      tenantId: read('tenantId'),
      companyId: read('companyId'),
      customerId: read('customerId'),
      createdAt: read('createdAt'),
      pickupIso: read('pickupIso'),
      from: read('from'),
      to: read('to'),
      price: readNum('price'),
      currency: read('currency'),
      paymentStatus: read('paymentStatus'),
      bookingStatus: read('bookingStatus'),
      publicReference: read('publicReference'),
      rawSnapshot: rawMap,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'bookingId': bookingId,
      'tenantId': tenantId,
      'companyId': companyId,
      'customerId': customerId,
      'createdAt': createdAt,
      'pickupIso': pickupIso,
      'from': from,
      'to': to,
      'price': price,
      'currency': currency,
      'paymentStatus': paymentStatus,
      'bookingStatus': bookingStatus,
      'publicReference': publicReference,
      'rawSnapshot': rawSnapshot,
    };
  }

  CustomerSavedBooking copyWith({
    String? bookingId,
    String? tenantId,
    String? companyId,
    String? customerId,
    String? createdAt,
    String? pickupIso,
    String? from,
    String? to,
    double? price,
    bool clearPrice = false,
    String? currency,
    String? paymentStatus,
    String? bookingStatus,
    String? publicReference,
    Map<String, dynamic>? rawSnapshot,
  }) {
    return CustomerSavedBooking(
      bookingId: bookingId ?? this.bookingId,
      tenantId: tenantId ?? this.tenantId,
      companyId: companyId ?? this.companyId,
      customerId: customerId ?? this.customerId,
      createdAt: createdAt ?? this.createdAt,
      pickupIso: pickupIso ?? this.pickupIso,
      from: from ?? this.from,
      to: to ?? this.to,
      price: clearPrice ? null : (price ?? this.price),
      currency: currency ?? this.currency,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      bookingStatus: bookingStatus ?? this.bookingStatus,
      publicReference: publicReference ?? this.publicReference,
      rawSnapshot: rawSnapshot ?? this.rawSnapshot,
    );
  }
}

class CustomerBookingStore {
  CustomerBookingStore._();

  static final CustomerBookingStore instance = CustomerBookingStore._();

  Future<List<CustomerSavedBooking>> loadAll() async {
    final canonical = await CustomerBookingsStore.instance.loadAll();
    return canonical
        .map(_fromCanonical)
        .where((entry) => entry.bookingId.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<void> upsert(CustomerSavedBooking booking) async {
    final id = booking.bookingId.trim();
    if (id.isEmpty) return;
    await CustomerBookingsStore.instance.upsert(_toCanonical(booking));
  }

  Future<void> remove(String bookingId) async {
    final id = bookingId.trim();
    if (id.isEmpty) return;
    await CustomerBookingsStore.instance.remove(id);
  }

  Future<({bool removed, bool storeA, bool storeB, int remaining})>
  removeLocalBookingByAnyReference(Set<String> aliases) async {
    final normalizedAliases = aliases
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    final result = await CustomerBookingsStore.instance
        .removeByAnyReferenceAliases(normalizedAliases);
    return (
      removed: result.removed,
      storeA: result.removed,
      storeB: result.removed,
      remaining: result.remaining,
    );
  }

  Future<void> clear() async {
    await CustomerBookingsStore.instance.clear();
  }

  Future<void> clearLocalTestData() async {
    await CustomerBookingsStore.instance.clearLocalTestData();
  }

  Future<void> markPaid({
    required String bookingId,
    String? bookingStatus,
  }) async {
    final id = bookingId.trim();
    if (id.isEmpty) return;
    await CustomerBookingsStore.instance.markPaid(
      bookingId: id,
      bookingStatus: bookingStatus,
    );
  }

  CustomerSavedBooking _fromCanonical(StoredCustomerBooking item) {
    final raw = <String, dynamic>{
      'booking_id': item.bookingId,
      'tenant_id': item.tenantId,
      'tenantId': item.tenantId,
      'company_id': item.companyId,
      'companyId': item.companyId,
      'public_booking_id': item.publicBookingId,
      'public_booking_reference': distinctPublicCustomerReference(
        bookingId: item.bookingId,
        candidates: <String>[
          item.publicBookingId,
          item.publicReference,
          item.bookingReference,
        ],
      ),
      'publicBookingReference': distinctPublicCustomerReference(
        bookingId: item.bookingId,
        candidates: <String>[
          item.publicBookingId,
          item.publicReference,
          item.bookingReference,
        ],
      ),
      'planning_reference': item.planningReference,
      'planningReference': item.planningReference,
      'booking_reference': item.bookingReference,
      'bookingReference': item.bookingReference,
      'public_reference': item.publicReference,
      'publicReference': item.publicReference,
      'receipt_reference': item.receiptReference,
      'receiptReference': item.receiptReference,
      'payment_booking_id': item.paymentBookingId,
      'payment_status': item.paymentStatus,
      'payment_method': item.paymentMethod,
      'paymentMethod': item.paymentMethod,
      'payment_mode': item.paymentMode,
      'paymentMode': item.paymentMode,
      'payment_provider': item.paymentProvider,
      'paymentProvider': item.paymentProvider,
      'status': item.status,
      'price': item.price,
      'currency': item.currency,
      'customer_name': item.customerName,
      'customer_phone': item.customerPhone,
      'customer_email': item.customerEmail,
      'pax': item.pax,
      'bags': item.bags,
      'quote': mergeCustomerPaymentChannelIntoQuote(
        item.quote,
        CustomerPaymentChannel(
          method: item.paymentMethod,
          mode: item.paymentMode,
          provider: item.paymentProvider,
        ),
      ),
      'updated_at': item.updatedAt,
    };
    return CustomerSavedBooking(
      bookingId: item.bookingId,
      tenantId: item.tenantId,
      companyId: item.companyId,
      customerId: '',
      createdAt: item.createdAt,
      pickupIso: item.pickupIso,
      from: item.from,
      to: item.to,
      price: item.price,
      currency: item.currency,
      paymentStatus: item.paymentStatus,
      bookingStatus: item.status,
      publicReference: distinctPublicCustomerReference(
        bookingId: item.bookingId,
        candidates: <String>[
          item.publicBookingId,
          item.publicReference,
          item.bookingReference,
        ],
      ),
      rawSnapshot: raw,
    );
  }

  StoredCustomerBooking _toCanonical(CustomerSavedBooking booking) {
    String firstNonEmpty(List<dynamic> values) {
      for (final value in values) {
        final text = (value ?? '').toString().trim();
        if (text.isNotEmpty) return text;
      }
      return '';
    }

    final paymentChannel = extractCustomerPaymentChannel(<Map<String, dynamic>>[
      booking.rawSnapshot,
    ]);
    return StoredCustomerBooking(
      bookingId: booking.bookingId,
      tenantId: firstNonEmpty([
        booking.tenantId,
        booking.rawSnapshot['tenant_id'],
        booking.rawSnapshot['tenantId'],
      ]),
      companyId: firstNonEmpty([
        booking.companyId,
        booking.rawSnapshot['company_id'],
        booking.rawSnapshot['companyId'],
      ]),
      publicBookingId: distinctPublicCustomerReference(
        bookingId: booking.bookingId,
        candidates: <String?>[
          booking.rawSnapshot['public_booking_id']?.toString(),
          booking.rawSnapshot['public_booking_reference']?.toString(),
          booking.rawSnapshot['publicBookingReference']?.toString(),
          booking.rawSnapshot['booking_reference']?.toString(),
          booking.rawSnapshot['bookingReference']?.toString(),
          booking.rawSnapshot['public_reference']?.toString(),
          booking.rawSnapshot['publicReference']?.toString(),
          booking.publicReference,
        ],
      ),
      planningReference: firstNonEmpty([
        booking.rawSnapshot['planning_reference'],
        booking.rawSnapshot['planningReference'],
      ]),
      bookingReference: distinctPublicCustomerReference(
        bookingId: booking.bookingId,
        candidates: <String?>[
          booking.rawSnapshot['booking_reference']?.toString(),
          booking.rawSnapshot['bookingReference']?.toString(),
          booking.publicReference,
        ],
      ),
      publicReference: distinctPublicCustomerReference(
        bookingId: booking.bookingId,
        candidates: <String?>[
          booking.rawSnapshot['public_reference']?.toString(),
          booking.rawSnapshot['publicReference']?.toString(),
          booking.publicReference,
        ],
      ),
      receiptReference: firstNonEmpty([
        booking.rawSnapshot['receipt_reference'],
        booking.rawSnapshot['receiptReference'],
      ]),
      paymentBookingId: (booking.rawSnapshot['payment_booking_id'] ?? '')
          .toString()
          .trim(),
      customerName: (booking.rawSnapshot['customer_name'] ?? '')
          .toString()
          .trim(),
      customerPhone: (booking.rawSnapshot['customer_phone'] ?? '')
          .toString()
          .trim(),
      customerEmail: (booking.rawSnapshot['customer_email'] ?? '')
          .toString()
          .trim(),
      from: booking.from,
      to: booking.to,
      pickupIso: booking.pickupIso,
      price: booking.price,
      currency: booking.currency,
      pax: firstNonEmpty([
        booking.rawSnapshot['pax'],
        booking.rawSnapshot['passengers'],
      ]),
      bags: firstNonEmpty([
        booking.rawSnapshot['bags'],
      ]),
      paymentStatus: booking.paymentStatus,
      paymentMethod: paymentChannel.method,
      paymentMode: paymentChannel.mode,
      paymentProvider: paymentChannel.provider,
      status: booking.bookingStatus,
      createdAt: booking.createdAt,
      updatedAt: DateTime.now().toIso8601String(),
      quote: mergeCustomerPaymentChannelIntoQuote(
        booking.rawSnapshot['quote'] is Map
            ? Map<String, dynamic>.from(booking.rawSnapshot['quote'] as Map)
            : const <String, dynamic>{},
        paymentChannel,
      ),
    );
  }
}
