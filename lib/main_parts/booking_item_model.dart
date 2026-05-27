part of '../main.dart';

class BookingItem {
  final String bookingId;
  final String? pickupIso;
  final String? from;
  final String? to;
  final String? tier;
  final int? pax;
  final int? bags;
  final String? status;
  final num? price; // optional
  final String? currency; // optional
  final Map<String, dynamic> details;

  // Tracking API (fluxidi-tracking-api)
  final String? sessionId;
  final String? createdAtIso;
  final double? lastLat;
  final double? lastLon;
  final String? lastPingTs;
  final num? lastSpeed;
  final num? lastHeading;

  BookingItem({
    required this.bookingId,
    this.sessionId,
    this.pickupIso,
    this.from,
    this.to,
    this.tier,
    this.pax,
    this.bags,
    this.status,
    this.price,
    this.currency,
    this.details = const <String, dynamic>{},
    this.createdAtIso,
    this.lastLat,
    this.lastLon,
    this.lastPingTs,
    this.lastSpeed,
    this.lastHeading,
  });

  String get shortId {
    if (bookingId.length <= 12) return bookingId;
    return '${bookingId.substring(0, 4)}…${bookingId.substring(bookingId.length - 4)}';
  }

  String get legId {
    final raw = (details['leg_id'] ?? details['legId'] ?? '').toString().trim();
    return raw;
  }

  bool get isOperationalLeg {
    final token =
        (details['is_operational_leg'] ?? details['isOperationalLeg'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    if (token == 'true' || token == '1') return true;
    return legId.isNotEmpty;
  }

  String get rowKey {
    final leg = legId;
    if (isOperationalLeg && leg.isNotEmpty) return '$bookingId:$leg';
    return bookingId;
  }

  static String? _extractPlaceLabel(dynamic v) {
    if (v == null) return null;
    if (v is String) {
      final s = v.trim();
      return s.isEmpty ? null : s;
    }
    if (v is Map<String, dynamic>) {
      // Common shapes: {address: "..."} or {label:"..."} or {text:"..."} etc.
      const keys = [
        'address',
        'label',
        'text',
        'name',
        'formatted',
        'display',
        'place_name',
        'full_address',
      ];
      for (final k in keys) {
        final vv = v[k];
        if (vv is String && vv.trim().isNotEmpty) return vv.trim();
      }

      // Sometimes nested like {pickup:{address:"..."}} already handled upstream,
      // but also allow {location:{address:"..."}} style.
      for (final nestedKey in ['location', 'place', 'geo', 'data']) {
        final nested = v[nestedKey];
        if (nested is Map<String, dynamic>) {
          for (final k in keys) {
            final vv = nested[k];
            if (vv is String && vv.trim().isNotEmpty) return vv.trim();
          }
        }
      }
    }
    return null;
  }

  BookingItem copyWith({
    String? bookingId,
    String? pickupIso,
    String? from,
    String? to,
    String? tier,
    int? pax,
    int? bags,
    String? status,
    num? price,
    String? currency,
    Map<String, dynamic>? details,
    String? sessionId,
    String? createdAtIso,
    double? lastLat,
    double? lastLon,
    String? lastPingTs,
    num? lastSpeed,
    num? lastHeading,
  }) {
    return BookingItem(
      bookingId: bookingId ?? this.bookingId,
      pickupIso: pickupIso ?? this.pickupIso,
      from: from ?? this.from,
      to: to ?? this.to,
      tier: tier ?? this.tier,
      pax: pax ?? this.pax,
      bags: bags ?? this.bags,
      status: status ?? this.status,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      details: details ?? this.details,
      sessionId: sessionId ?? this.sessionId,
      createdAtIso: createdAtIso ?? this.createdAtIso,
      lastLat: lastLat ?? this.lastLat,
      lastLon: lastLon ?? this.lastLon,
      lastPingTs: lastPingTs ?? this.lastPingTs,
      lastSpeed: lastSpeed ?? this.lastSpeed,
      lastHeading: lastHeading ?? this.lastHeading,
    );
  }

  factory BookingItem.fromJson(Map<String, dynamic> j) {
    // Support both booking-api payloads and tracking-api payloads.
    final lastPing = (j['last_ping'] is Map<String, dynamic>)
        ? (j['last_ping'] as Map<String, dynamic>)
        : null;

    String? pickLabel = _extractPlaceLabel(j['pickup'] ?? j['from']);
    String? dropLabel = _extractPlaceLabel(j['dropoff'] ?? j['to']);

    // Extra common field names across versions/backends
    pickLabel ??= _extractPlaceLabel(
      j['pickup_address'] ?? j['pickup_label'] ?? j['from_address'],
    );
    dropLabel ??= _extractPlaceLabel(
      j['dropoff_address'] ?? j['dropoff_label'] ?? j['to_address'],
    );

    // If backend already provides plain strings, prefer those
    final fromStr = (j['from'] is String) ? (j['from'] as String) : null;
    final toStr = (j['to'] is String) ? (j['to'] as String) : null;

    return BookingItem(
      bookingId: (j['booking_id'] ?? j['id'] ?? '').toString(),
      pickupIso: j['pickup_iso']?.toString(),
      from: (fromStr?.trim().isNotEmpty ?? false)
          ? fromStr!.trim()
          : (pickLabel?.trim().isNotEmpty ?? false ? pickLabel!.trim() : null),
      to: (toStr?.trim().isNotEmpty ?? false)
          ? toStr!.trim()
          : (dropLabel?.trim().isNotEmpty ?? false ? dropLabel!.trim() : null),
      tier: j['tier']?.toString(),
      pax: _toIntOrNull(
        j['pax'] ??
            j['passengers'] ??
            j['persons'] ??
            j['pax_count'] ??
            j['paxCount'],
      ),
      bags: _toIntOrNull(
        j['bags'] ?? j['luggage'] ?? j['bags_count'] ?? j['bagsCount'],
      ),
      status: (j['status'] ?? j['stage'])?.toString(),
      price: _toNumOrNull(
        j['price'] ??
            j['total_price'] ??
            j['total'] ??
            j['amount'] ??
            j['eur'] ??
            ((j['quote'] is Map) ? (j['quote'] as Map)['price'] : null) ??
            ((j['quote'] is Map) ? (j['quote'] as Map)['total_price'] : null) ??
            ((j['quote'] is Map) ? (j['quote'] as Map)['total'] : null) ??
            ((j['quote'] is Map) ? (j['quote'] as Map)['amount'] : null) ??
            ((j['quote'] is Map) ? (j['quote'] as Map)['eur'] : null) ??
            (((j['quote'] is Map) && ((j['quote'] as Map)['pricing'] is Map))
                ? ((j['quote'] as Map)['pricing'] as Map)['price_incl_vat']
                : null) ??
            (((j['quote'] is Map) && ((j['quote'] as Map)['pricing'] is Map))
                ? ((j['quote'] as Map)['pricing'] as Map)['total_price']
                : null) ??
            (((j['quote'] is Map) && ((j['quote'] as Map)['pricing'] is Map))
                ? ((j['quote'] as Map)['pricing'] as Map)['total']
                : null) ??
            (((j['quote'] is Map) && ((j['quote'] as Map)['pricing'] is Map))
                ? ((j['quote'] as Map)['pricing'] as Map)['price']
                : null) ??
            (((j['quote'] is Map) && ((j['quote'] as Map)['pricing'] is Map))
                ? ((j['quote'] as Map)['pricing'] as Map)['amount']
                : null) ??
            (((j['quote'] is Map) && ((j['quote'] as Map)['pricing'] is Map))
                ? ((j['quote'] as Map)['pricing'] as Map)['eur']
                : null),
      ),
      currency: (j['currency'] ?? 'EUR')?.toString(),
      details: Map<String, dynamic>.from(j),
      sessionId: j['session_id']?.toString(),
      createdAtIso: j['created_at']?.toString(),
      lastLat: _toDoubleOrNull(lastPing?['lat']),
      lastLon: _toDoubleOrNull(lastPing?['lon']),
      lastPingTs: lastPing?['ts']?.toString(),
      lastSpeed: _toNumOrNull(lastPing?['speed']),
      lastHeading: _toNumOrNull(lastPing?['heading']),
    );
  }

  static int? _toIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  static num? _toNumOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  static double? _toDoubleOrNull(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
