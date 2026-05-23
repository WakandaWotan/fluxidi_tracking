import 'package:flutter/material.dart';

typedef EventBookCallback = void Function(EventDetailData event);

class EventCategoryKey {
  static const String music = 'music';
  static const String sport = 'sport';
  static const String food = 'food';
  static const String family = 'family';
  static const String culture = 'culture';
  static const String theater = 'theater';
  static const String comedy = 'comedy';
  static const String business = 'business';
  static const String airport = 'airport';
  static const String other = 'other';

  static const Set<String> values = <String>{
    music,
    sport,
    food,
    family,
    culture,
    theater,
    comedy,
    business,
    airport,
    other,
  };
}

class EventCategoryMeta {
  const EventCategoryMeta({
    required this.key,
    required this.icon,
    this.aliases = const <String>[],
  });

  final String key;
  final IconData icon;
  final List<String> aliases;
}

const List<EventCategoryMeta> kEventCategoryMeta = <EventCategoryMeta>[
  EventCategoryMeta(
    key: EventCategoryKey.music,
    icon: Icons.graphic_eq_rounded,
    aliases: <String>['muziek', 'music', 'musique', 'música'],
  ),
  EventCategoryMeta(
    key: EventCategoryKey.sport,
    icon: Icons.sports_soccer_rounded,
    aliases: <String>['sport', 'deporte'],
  ),
  EventCategoryMeta(
    key: EventCategoryKey.food,
    icon: Icons.restaurant_rounded,
    aliases: <String>['food', 'eten', 'culinary', 'gastronomy', 'gastronomie'],
  ),
  EventCategoryMeta(
    key: EventCategoryKey.family,
    icon: Icons.family_restroom_rounded,
    aliases: <String>['family', 'familie', 'famille'],
  ),
  EventCategoryMeta(
    key: EventCategoryKey.culture,
    icon: Icons.museum_outlined,
    aliases: <String>['culture', 'cultuur'],
  ),
  EventCategoryMeta(
    key: EventCategoryKey.theater,
    icon: Icons.theater_comedy_rounded,
    aliases: <String>[
      'arts & theatre',
      'arts & theater',
      'arts and theatre',
      'arts and theater',
      'theatre',
      'theater',
      'théâtre',
    ],
  ),
  EventCategoryMeta(
    key: EventCategoryKey.comedy,
    icon: Icons.mic_rounded,
    aliases: <String>['comedy', 'comédie', 'stand-up', 'humor', 'humour'],
  ),
  EventCategoryMeta(
    key: EventCategoryKey.business,
    icon: Icons.apartment_rounded,
    aliases: <String>['business', 'zakelijk', 'negocios', 'affaires'],
  ),
  EventCategoryMeta(
    key: EventCategoryKey.airport,
    icon: Icons.flight_takeoff_rounded,
    aliases: <String>['airport', 'luchthaven', 'aéroport', 'aeropuerto'],
  ),
  EventCategoryMeta(
    key: EventCategoryKey.other,
    icon: Icons.event_rounded,
    aliases: <String>['other', 'overig', 'autre', 'otro'],
  ),
];

String resolveEventCategoryKey({
  String? explicitKey,
  required String fallbackLabel,
}) {
  final normalizedExplicit = (explicitKey ?? '').trim().toLowerCase();
  if (EventCategoryKey.values.contains(normalizedExplicit)) {
    return normalizedExplicit;
  }
  final normalizedLabel = fallbackLabel.trim().toLowerCase();
  for (final meta in kEventCategoryMeta) {
    if (meta.aliases.contains(normalizedLabel)) return meta.key;
    for (final alias in meta.aliases) {
      if (alias.isNotEmpty && normalizedLabel.contains(alias)) return meta.key;
    }
  }
  return EventCategoryKey.other;
}

EventCategoryMeta? eventCategoryMetaByKey(String key) {
  for (final meta in kEventCategoryMeta) {
    if (meta.key == key) return meta;
  }
  return null;
}

class EventFeedQuery {
  const EventFeedQuery({
    this.marketCode,
    this.countryCode,
    this.categoryKey,
    this.dateMode,
    this.startAtUtc,
    this.endAtUtc,
    this.searchQuery,
    this.locale,
    this.latitude,
    this.longitude,
    this.radiusKm,
    this.limit,
  });

  final String? marketCode;
  final String? countryCode;
  final String? categoryKey;
  final String? dateMode;
  final DateTime? startAtUtc;
  final DateTime? endAtUtc;
  final String? searchQuery;
  final String? locale;
  final double? latitude;
  final double? longitude;
  final double? radiusKm;
  final int? limit;
}

class EventDateMode {
  static const String all = 'all';
  static const String today = 'today';
  static const String weekend = 'weekend';
  static const String month = 'month';

  static const Set<String> values = <String>{all, today, weekend, month};
}

class EventFeedResult {
  const EventFeedResult({
    this.events = const <EventDetailData>[],
    this.source = 'unknown',
    this.receivedAtUtc,
    this.isFromCache = false,
    this.errorCode,
    this.warnings = const <String>[],
  });

  final List<EventDetailData> events;
  final String source;
  final DateTime? receivedAtUtc;
  final bool isFromCache;
  final String? errorCode;
  final List<String> warnings;
}

class EventDetailData {
  const EventDetailData({
    required this.id,
    required this.title,
    required this.category,
    required this.dateTimeLabel,
    required this.locationName,
    required this.city,
    required this.address,
    required this.lat,
    required this.lng,
    required this.distanceOrStatus,
    required this.gradient,
    this.distanceLabel,
    this.isDistanceLabelTrusted = false,
    this.visualAssetPath,
    this.sourceLabel,
    this.marketCode,
    this.countryCode,
    this.categoryKey,
    this.startAtUtc,
    this.endAtUtc,
    this.timeZone,
    this.sourceEventId,
    this.provider,
    this.status,
    this.sourceUrl,
    this.updatedAtUtc,
  });

  final String id;
  final String title;
  final String category;
  final String dateTimeLabel;
  final String locationName;
  final String city;
  final String address;
  final double lat;
  final double lng;
  final String distanceOrStatus;
  final String? distanceLabel;
  final bool isDistanceLabelTrusted;
  final List<Color> gradient;
  final String? visualAssetPath;
  final String? sourceLabel;

  // Future-feed fields (optional for backward compatibility).
  final String? marketCode;
  final String? countryCode;
  final String? categoryKey;
  final DateTime? startAtUtc;
  final DateTime? endAtUtc;
  final String? timeZone;
  final String? sourceEventId;
  final String? provider;
  final String? status;
  final String? sourceUrl;
  final DateTime? updatedAtUtc;

  String get destinationLabel {
    final location = locationName.trim();
    final destination = address.trim();
    if (location.isEmpty) return destination;
    if (destination.isEmpty) return location;
    return '$location, $destination';
  }

  String get resolvedCategoryKey {
    return resolveEventCategoryKey(
      explicitKey: categoryKey,
      fallbackLabel: category,
    );
  }

  String? get customerTicketStatusLabel {
    return mapEventStatusToCustomerLabel(status);
  }
}

String? mapEventStatusToCustomerLabel(String? rawStatus) {
  final normalized = (rawStatus ?? '').trim().toLowerCase();
  if (normalized.isEmpty || normalized == 'unknown') return null;
  if (normalized.contains('onsale')) return 'Tickets beschikbaar';
  if (normalized.contains('soldout') || normalized.contains('sold out')) {
    return 'Uitverkocht';
  }
  if (normalized.contains('offsale')) return 'Niet beschikbaar';
  if (normalized.contains('cancelled') || normalized.contains('canceled')) {
    return 'Geannuleerd';
  }
  return null;
}
