import 'package:fluxidi_tracking/customer_bookings_store.dart';

class CustomerSavedBooking {
  const CustomerSavedBooking({
    required this.bookingId,
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

  Future<void> clear() async {
    await CustomerBookingsStore.instance.clear();
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
      'public_booking_id': item.publicBookingId,
      'payment_booking_id': item.paymentBookingId,
      'payment_status': item.paymentStatus,
      'status': item.status,
      'price': item.price,
      'currency': item.currency,
      'quote': item.quote,
      'updated_at': item.updatedAt,
    };
    return CustomerSavedBooking(
      bookingId: item.bookingId,
      customerId: '',
      createdAt: item.createdAt,
      pickupIso: item.pickupIso,
      from: item.from,
      to: item.to,
      price: item.price,
      currency: item.currency,
      paymentStatus: item.paymentStatus,
      bookingStatus: item.status,
      publicReference: item.publicBookingId,
      rawSnapshot: raw,
    );
  }

  StoredCustomerBooking _toCanonical(CustomerSavedBooking booking) {
    return StoredCustomerBooking(
      bookingId: booking.bookingId,
      publicBookingId: booking.publicReference,
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
      paymentStatus: booking.paymentStatus,
      status: booking.bookingStatus,
      createdAt: booking.createdAt,
      updatedAt: DateTime.now().toIso8601String(),
      quote: booking.rawSnapshot['quote'] is Map
          ? Map<String, dynamic>.from(booking.rawSnapshot['quote'] as Map)
          : const <String, dynamic>{},
    );
  }
}
