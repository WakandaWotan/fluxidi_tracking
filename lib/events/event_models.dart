import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

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
    this.description,
    this.imageUrl,
    this.heroImageUrl,
    this.thumbnailUrl,
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
  final String? description;
  final String? imageUrl;
  final String? heroImageUrl;
  final String? thumbnailUrl;
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

String buildSavedEventIdentityKey(EventDetailData event) {
  return buildSavedEventIdentityKeyFromParts(
    provider: event.provider,
    sourceEventId: event.sourceEventId,
    fallbackId: event.id,
  );
}

String buildSavedEventIdentityKeyFromParts({
  String? provider,
  String? sourceEventId,
  String? fallbackId,
}) {
  final normalizedProvider = (provider ?? '').trim().toLowerCase();
  final normalizedSourceEventId = (sourceEventId ?? '').trim();
  final normalizedFallbackId = (fallbackId ?? '').trim();
  if (normalizedProvider.isNotEmpty && normalizedSourceEventId.isNotEmpty) {
    return '$normalizedProvider::$normalizedSourceEventId';
  }
  if (normalizedSourceEventId.isNotEmpty)
    return 'source::$normalizedSourceEventId';
  if (normalizedFallbackId.isNotEmpty) return 'id::$normalizedFallbackId';
  return 'unknown::${DateTime.now().toUtc().millisecondsSinceEpoch}';
}

class SavedEventRecord {
  const SavedEventRecord({
    required this.storageKey,
    required this.id,
    required this.provider,
    required this.sourceEventId,
    required this.title,
    required this.categoryKey,
    required this.startsAtUtc,
    required this.locationName,
    required this.address,
    required this.city,
    required this.countryCode,
    required this.latitude,
    required this.longitude,
    required this.sourceUrl,
    required this.imageUrl,
    required this.heroImageUrl,
    required this.thumbnailUrl,
    required this.savedAtUtc,
    required this.favorite,
    required this.saved,
  });

  final String storageKey;
  final String id;
  final String provider;
  final String sourceEventId;
  final String title;
  final String categoryKey;
  final String startsAtUtc;
  final String locationName;
  final String address;
  final String city;
  final String countryCode;
  final double? latitude;
  final double? longitude;
  final String sourceUrl;
  final String imageUrl;
  final String heroImageUrl;
  final String thumbnailUrl;
  final String savedAtUtc;
  final bool favorite;
  final bool saved;

  SavedEventRecord copyWith({bool? favorite, bool? saved, String? savedAtUtc}) {
    return SavedEventRecord(
      storageKey: storageKey,
      id: id,
      provider: provider,
      sourceEventId: sourceEventId,
      title: title,
      categoryKey: categoryKey,
      startsAtUtc: startsAtUtc,
      locationName: locationName,
      address: address,
      city: city,
      countryCode: countryCode,
      latitude: latitude,
      longitude: longitude,
      sourceUrl: sourceUrl,
      imageUrl: imageUrl,
      heroImageUrl: heroImageUrl,
      thumbnailUrl: thumbnailUrl,
      savedAtUtc: savedAtUtc ?? this.savedAtUtc,
      favorite: favorite ?? this.favorite,
      saved: saved ?? this.saved,
    );
  }

  static SavedEventRecord fromEvent(
    EventDetailData event, {
    required bool favorite,
    required bool saved,
    String? savedAtUtc,
  }) {
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    return SavedEventRecord(
      storageKey: buildSavedEventIdentityKey(event),
      id: event.id,
      provider: (event.provider ?? '').trim().toLowerCase(),
      sourceEventId: (event.sourceEventId ?? '').trim(),
      title: event.title,
      categoryKey: event.resolvedCategoryKey,
      startsAtUtc: event.startAtUtc?.toUtc().toIso8601String() ?? '',
      locationName: event.locationName,
      address: event.address,
      city: event.city,
      countryCode: (event.countryCode ?? '').trim().toUpperCase(),
      latitude: event.lat.isFinite ? event.lat : null,
      longitude: event.lng.isFinite ? event.lng : null,
      sourceUrl: (event.sourceUrl ?? '').trim(),
      imageUrl: (event.imageUrl ?? '').trim(),
      heroImageUrl: (event.heroImageUrl ?? '').trim(),
      thumbnailUrl: (event.thumbnailUrl ?? '').trim(),
      savedAtUtc: savedAtUtc ?? nowUtc,
      favorite: favorite,
      saved: saved,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'storageKey': storageKey,
      'id': id,
      'provider': provider,
      'sourceEventId': sourceEventId,
      'title': title,
      'categoryKey': categoryKey,
      'startsAtUtc': startsAtUtc,
      'locationName': locationName,
      'address': address,
      'city': city,
      'countryCode': countryCode,
      'latitude': latitude,
      'longitude': longitude,
      'sourceUrl': sourceUrl,
      'imageUrl': imageUrl,
      'heroImageUrl': heroImageUrl,
      'thumbnailUrl': thumbnailUrl,
      'savedAtUtc': savedAtUtc,
      'favorite': favorite,
      'saved': saved,
    };
  }

  static SavedEventRecord? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final source = Map<String, dynamic>.from(raw);
    final id = (source['id'] ?? '').toString().trim();
    if (id.isEmpty) return null;
    final provider = (source['provider'] ?? '').toString().trim().toLowerCase();
    final sourceEventId = (source['sourceEventId'] ?? '').toString().trim();
    final storageKey = (source['storageKey'] ?? '').toString().trim().isNotEmpty
        ? source['storageKey'].toString().trim()
        : buildSavedEventIdentityKeyFromParts(
            provider: provider,
            sourceEventId: sourceEventId,
            fallbackId: id,
          );
    return SavedEventRecord(
      storageKey: storageKey,
      id: id,
      provider: provider,
      sourceEventId: sourceEventId,
      title: (source['title'] ?? '').toString(),
      categoryKey: (source['categoryKey'] ?? '').toString(),
      startsAtUtc: (source['startsAtUtc'] ?? '').toString(),
      locationName: (source['locationName'] ?? '').toString(),
      address: (source['address'] ?? '').toString(),
      city: (source['city'] ?? '').toString(),
      countryCode: (source['countryCode'] ?? '').toString(),
      latitude: _toFiniteDouble(source['latitude']),
      longitude: _toFiniteDouble(source['longitude']),
      sourceUrl: (source['sourceUrl'] ?? '').toString(),
      imageUrl: (source['imageUrl'] ?? '').toString(),
      heroImageUrl: (source['heroImageUrl'] ?? '').toString(),
      thumbnailUrl: (source['thumbnailUrl'] ?? '').toString(),
      savedAtUtc: (source['savedAtUtc'] ?? '').toString(),
      favorite: _toBool(source['favorite']),
      saved: _toBool(source['saved'], fallback: true),
    );
  }

  static double? _toFiniteDouble(dynamic raw) {
    if (raw == null) return null;
    final number = raw is num
        ? raw.toDouble()
        : double.tryParse(raw.toString());
    if (number == null || !number.isFinite) return null;
    return number;
  }

  static bool _toBool(dynamic raw, {bool fallback = false}) {
    if (raw is bool) return raw;
    if (raw == null) return fallback;
    final normalized = raw.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
    return fallback;
  }
}

class EventLocalSavedStore {
  const EventLocalSavedStore();

  static const String _fileName = 'saved_events_v1.json';

  Future<Map<String, SavedEventRecord>> loadAll() async {
    try {
      final file = await _storeFile();
      if (!await file.exists()) return <String, SavedEventRecord>{};
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return <String, SavedEventRecord>{};
      final decoded = jsonDecode(raw);
      return _normalizeDecoded(decoded);
    } catch (_) {
      try {
        final file = await _storeFile();
        if (await file.exists()) await file.delete();
      } catch (_) {}
      return <String, SavedEventRecord>{};
    }
  }

  Future<void> saveAll(Map<String, SavedEventRecord> items) async {
    final file = await _storeFile();
    final payload = <String, dynamic>{
      for (final entry in items.entries) entry.key: entry.value.toJson(),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<Map<String, SavedEventRecord>> toggleFavorite(
    EventDetailData event, {
    required bool favorite,
  }) async {
    final all = await loadAll();
    final key = buildSavedEventIdentityKey(event);
    final existing = all[key];
    if (favorite) {
      all[key] = SavedEventRecord.fromEvent(
        event,
        favorite: true,
        saved: existing?.saved ?? false,
        savedAtUtc: existing?.savedAtUtc,
      );
    } else if (existing != null) {
      if (existing.saved) {
        all[key] = existing.copyWith(favorite: false);
      } else {
        all.remove(key);
      }
    }
    await saveAll(all);
    return all;
  }

  Future<Map<String, SavedEventRecord>> saveEventDetails(
    EventDetailData event,
  ) async {
    final all = await loadAll();
    final key = buildSavedEventIdentityKey(event);
    final existing = all[key];
    all[key] = SavedEventRecord.fromEvent(
      event,
      favorite: existing?.favorite ?? false,
      saved: true,
      savedAtUtc: existing?.savedAtUtc,
    );
    await saveAll(all);
    return all;
  }

  static Map<String, SavedEventRecord> _normalizeDecoded(dynamic decoded) {
    final out = <String, SavedEventRecord>{};
    if (decoded is Map) {
      final source = Map<String, dynamic>.from(decoded);
      for (final entry in source.entries) {
        final parsed = SavedEventRecord.fromJson(entry.value);
        if (parsed == null) continue;
        out[(entry.key).trim().isEmpty ? parsed.storageKey : entry.key] =
            parsed;
      }
      return out;
    }
    if (decoded is List) {
      for (final item in decoded) {
        final parsed = SavedEventRecord.fromJson(item);
        if (parsed == null) continue;
        out[parsed.storageKey] = parsed;
      }
    }
    return out;
  }

  Future<File> _storeFile() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}fluxidi${Platform.pathSeparator}events',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }
}
