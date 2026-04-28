import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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

  static const String _fileName = 'customer_bookings_v1.json';
  List<CustomerSavedBooking>? _cache;

  Future<File> _file() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}customer_state',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  List<CustomerSavedBooking> _sorted(List<CustomerSavedBooking> items) {
    final out = List<CustomerSavedBooking>.from(items);
    out.sort((a, b) {
      final aDt =
          DateTime.tryParse(a.createdAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDt =
          DateTime.tryParse(b.createdAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDt.compareTo(aDt);
    });
    return out;
  }

  Future<List<CustomerSavedBooking>> loadAll() async {
    if (_cache != null) return List<CustomerSavedBooking>.from(_cache!);
    try {
      final file = await _file();
      if (!await file.exists()) {
        _cache = <CustomerSavedBooking>[];
        return const <CustomerSavedBooking>[];
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        _cache = <CustomerSavedBooking>[];
        return const <CustomerSavedBooking>[];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _cache = <CustomerSavedBooking>[];
        return const <CustomerSavedBooking>[];
      }
      final items = decoded
          .whereType<Map>()
          .map(
            (entry) =>
                CustomerSavedBooking.fromJson(Map<String, dynamic>.from(entry)),
          )
          .where((entry) => entry.bookingId.trim().isNotEmpty)
          .toList(growable: false);
      _cache = _sorted(items);
      return List<CustomerSavedBooking>.from(_cache!);
    } catch (err) {
      debugPrint('[CUSTOMER_BOOKINGS][LOAD_ERROR] $err');
      _cache = <CustomerSavedBooking>[];
      return const <CustomerSavedBooking>[];
    }
  }

  Future<void> _saveAll(List<CustomerSavedBooking> items) async {
    final sorted = _sorted(items);
    _cache = sorted;
    try {
      final file = await _file();
      final payload = sorted.map((e) => e.toJson()).toList(growable: false);
      await file.writeAsString(jsonEncode(payload));
    } catch (err) {
      debugPrint('[CUSTOMER_BOOKINGS][SAVE_ERROR] $err');
    }
  }

  Future<void> upsert(CustomerSavedBooking booking) async {
    final id = booking.bookingId.trim();
    if (id.isEmpty) return;
    final list = await loadAll();
    final index = list.indexWhere((item) => item.bookingId.trim() == id);
    if (index >= 0) {
      list[index] = booking;
    } else {
      list.add(booking);
    }
    await _saveAll(list);
  }

  Future<void> remove(String bookingId) async {
    final id = bookingId.trim();
    if (id.isEmpty) return;
    final list = await loadAll();
    list.removeWhere((item) => item.bookingId.trim() == id);
    await _saveAll(list);
  }

  Future<void> clear() async {
    await _saveAll(const <CustomerSavedBooking>[]);
  }

  Future<void> markPaid({
    required String bookingId,
    String? bookingStatus,
  }) async {
    final id = bookingId.trim();
    if (id.isEmpty) return;
    final list = await loadAll();
    final index = list.indexWhere((item) => item.bookingId.trim() == id);
    if (index < 0) return;
    final item = list[index];
    list[index] = item.copyWith(
      paymentStatus: 'paid',
      bookingStatus:
          bookingStatus ??
          (item.bookingStatus.trim().isEmpty
              ? 'CONFIRMED'
              : item.bookingStatus),
    );
    await _saveAll(list);
  }
}
