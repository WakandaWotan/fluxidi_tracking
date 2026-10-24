const String kRatehawkViewStayContextPrefix = 'rhctx1';
const String kRatehawkOfferRefPrefix = 'rh1';

class RatehawkGuestRoom {
  const RatehawkGuestRoom({
    required this.adults,
    this.children = const <int>[],
  });

  final int adults;
  final List<int> children;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'adults': adults,
      'children': List<int>.from(children),
    };
  }
}

class RatehawkViewStaySnapshot {
  const RatehawkViewStaySnapshot({
    required this.contextToken,
    required this.hid,
    required this.checkin,
    required this.checkout,
    required this.residency,
    required this.currency,
    required this.guests,
    this.expiresAt,
  });

  final String contextToken;
  final int hid;
  final String checkin;
  final String checkout;
  final String residency;
  final String currency;
  final List<RatehawkGuestRoom> guests;
  final DateTime? expiresAt;

  bool get hasServerContextPrefix {
    return contextToken.trim().startsWith('$kRatehawkViewStayContextPrefix.');
  }

  bool isExpired([DateTime? now]) {
    if (expiresAt == null) return false;
    return !expiresAt!.isAfter(now ?? DateTime.now());
  }

  bool get hasCompleteClaims {
    final dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    return hid > 0 &&
        dateRe.hasMatch(checkin) &&
        dateRe.hasMatch(checkout) &&
        checkout.compareTo(checkin) > 0 &&
        RegExp(r'^[a-z]{2}$').hasMatch(residency) &&
        RegExp(r'^[A-Z]{3}$').hasMatch(currency) &&
        guests.isNotEmpty &&
        guests.every((room) => room.adults >= 1);
  }

  int get nightCount {
    final start = DateTime.tryParse(checkin);
    final end = DateTime.tryParse(checkout);
    if (start == null || end == null) return 0;
    return end.difference(start).inDays;
  }
}

bool isRatehawkViewStayContextToken(String? raw) {
  final token = (raw ?? '').trim();
  return token.startsWith('$kRatehawkViewStayContextPrefix.') &&
      token.split('.').length >= 3;
}

bool isRatehawkOfferRef(String? raw) {
  final token = (raw ?? '').trim();
  return token.startsWith('$kRatehawkOfferRefPrefix.') &&
      token.split('.').length >= 3;
}

List<RatehawkGuestRoom> parseRatehawkGuestRooms(dynamic raw) {
  if (raw is! List) return const <RatehawkGuestRoom>[];
  final rooms = <RatehawkGuestRoom>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final adults = int.tryParse('${item['adults'] ?? ''}');
    if (adults == null || adults < 1) continue;
    final childrenRaw = item['children'];
    final children = <int>[];
    if (childrenRaw is List) {
      for (final age in childrenRaw) {
        final parsed = int.tryParse('$age');
        if (parsed != null && parsed >= 0 && parsed <= 17) {
          children.add(parsed);
        }
      }
    }
    rooms.add(RatehawkGuestRoom(adults: adults, children: children));
  }
  return rooms;
}

RatehawkViewStaySnapshot? parseRatehawkViewStaySnapshot(
  Map<String, dynamic> json, {
  int? hid,
}) {
  final token = (json['view_stay_context'] ?? json['viewStayContext'] ?? '')
      .toString()
      .trim();
  if (!isRatehawkViewStayContextToken(token)) return null;

  final stayContext = json['stay_context'] is Map
      ? Map<String, dynamic>.from(json['stay_context'] as Map)
      : json;
  final parsedHid =
      int.tryParse('${stayContext['hid'] ?? json['hid'] ?? hid ?? ''}') ?? hid;
  if (parsedHid == null || parsedHid <= 0) return null;

  final checkin = (stayContext['checkin'] ?? json['checkin'] ?? '')
      .toString()
      .trim();
  final checkout = (stayContext['checkout'] ?? json['checkout'] ?? '')
      .toString()
      .trim();
  final residency = (stayContext['residency'] ?? json['residency'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  final currency = (stayContext['currency'] ?? json['currency'] ?? '')
      .toString()
      .trim()
      .toUpperCase();
  final guests = parseRatehawkGuestRooms(
    stayContext['guests'] ?? json['guests'],
  );
  DateTime? expiresAt;
  final expiresRaw =
      json['view_stay_context_expires_at'] ?? json['viewStayContextExpiresAt'];
  if (expiresRaw is num && expiresRaw.isFinite) {
    expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresRaw.round());
  } else if (expiresRaw is String) {
    expiresAt = DateTime.tryParse(expiresRaw.trim());
  }

  final snapshot = RatehawkViewStaySnapshot(
    contextToken: token,
    hid: parsedHid,
    checkin: checkin,
    checkout: checkout,
    residency: residency,
    currency: currency,
    guests: guests,
    expiresAt: expiresAt,
  );
  if (!snapshot.hasCompleteClaims) return null;
  return snapshot;
}
