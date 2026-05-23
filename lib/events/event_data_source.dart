import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'event_models.dart';
import 'event_seed_data.dart';

abstract class EventDataSource {
  List<EventDetailData>? getInitialEvents() => null;

  Future<List<EventDetailData>> loadEvents();

  Future<EventFeedResult> loadEventFeed({
    EventFeedQuery query = const EventFeedQuery(),
  }) async {
    final events = await loadEvents();
    return EventFeedResult(
      events: events,
      source: 'load_events',
      receivedAtUtc: DateTime.now().toUtc(),
      isFromCache: false,
      warnings: const <String>[],
    );
  }
}

class LocalSeedEventDataSource implements EventDataSource {
  const LocalSeedEventDataSource();

  @override
  List<EventDetailData> getInitialEvents() {
    return kEventSeedData;
  }

  @override
  Future<List<EventDetailData>> loadEvents() async {
    return kEventSeedData;
  }

  @override
  Future<EventFeedResult> loadEventFeed({
    EventFeedQuery query = const EventFeedQuery(),
  }) async {
    return EventFeedResult(
      events: kEventSeedData,
      source: 'local_seed',
      receivedAtUtc: DateTime.now().toUtc(),
      isFromCache: false,
      warnings: const <String>[],
    );
  }
}

class RemoteEventDataSource implements EventDataSource {
  const RemoteEventDataSource({
    this.baseUrl = '',
    this.endpointUrl,
    this.fallbackDataSource = const LocalSeedEventDataSource(),
    this.timeout = const Duration(seconds: 8),
    this.client,
  });

  final String baseUrl;
  final String? endpointUrl;
  final EventDataSource fallbackDataSource;
  final Duration timeout;
  final http.Client? client;

  @override
  List<EventDetailData>? getInitialEvents() {
    return fallbackDataSource.getInitialEvents();
  }

  @override
  Future<List<EventDetailData>> loadEvents() async {
    final feed = await loadEventFeed();
    return feed.events;
  }

  @override
  Future<EventFeedResult> loadEventFeed({
    EventFeedQuery query = const EventFeedQuery(),
  }) async {
    final fallback = await fallbackDataSource.loadEventFeed(query: query);
    try {
      final uri = _buildPublicEventsUri(query);
      final ownedClient = client == null ? http.Client() : null;
      final activeClient = client ?? ownedClient!;
      http.Response response;
      try {
        response = await activeClient
            .get(
              uri,
              headers: const <String, String>{'Accept': 'application/json'},
            )
            .timeout(timeout);
      } finally {
        ownedClient?.close();
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _fallbackWithWarning(fallback, 'http_${response.statusCode}');
      }
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return _fallbackWithWarning(fallback, 'invalid_json_shape');
      }
      final payload = Map<String, dynamic>.from(decoded);
      if (_asBool(payload['ok']) != true) {
        return _fallbackWithWarning(
          fallback,
          _readString(payload, const <String>['error_code', 'error']) ??
              'remote_not_ok',
        );
      }
      final rawEvents = payload['events'];
      if (rawEvents is! List) {
        return _fallbackWithWarning(fallback, 'events_missing');
      }
      final mapped = rawEvents
          .whereType<Map>()
          .map((eventMap) => _mapEvent(Map<String, dynamic>.from(eventMap)))
          .whereType<EventDetailData>()
          .toList(growable: false);
      if (mapped.isEmpty) {
        return _fallbackWithWarning(fallback, 'empty_events');
      }
      return EventFeedResult(
        events: mapped,
        source:
            _readString(payload, const <String>['source']) ??
            'remote_public_events',
        receivedAtUtc: _readDateTime(payload, const <String>[
          'received_at_utc',
          'receivedAtUtc',
        ]),
        isFromCache:
            _asBool(payload['is_from_cache']) ??
            _asBool(payload['isFromCache']) ??
            false,
        errorCode: _readString(payload, const <String>[
          'error_code',
          'errorCode',
        ]),
        warnings: _readStringList(payload['warnings']),
      );
    } catch (_) {
      return _fallbackWithWarning(fallback, 'remote_fetch_failed');
    }
  }

  EventFeedResult _fallbackWithWarning(
    EventFeedResult fallback,
    String warning,
  ) {
    final warnings = <String>[...fallback.warnings];
    if (warning.trim().isNotEmpty && !warnings.contains(warning)) {
      warnings.add(warning);
    }
    return EventFeedResult(
      events: fallback.events,
      source: fallback.source,
      receivedAtUtc: fallback.receivedAtUtc,
      isFromCache: fallback.isFromCache,
      errorCode: fallback.errorCode,
      warnings: warnings,
    );
  }

  Uri _buildPublicEventsUri(EventFeedQuery query) {
    final explicit = (endpointUrl ?? '').trim();
    final base = baseUrl.trim();
    final raw = explicit.isNotEmpty
        ? explicit
        : '${base.replaceAll(RegExp(r'/+$'), '')}/public/events';
    final uri = Uri.parse(raw);
    final qp = <String, String>{...uri.queryParameters};
    _putIfNotEmpty(qp, 'country', query.countryCode?.toUpperCase());
    _putIfNotEmpty(qp, 'market', query.marketCode?.toLowerCase());
    _putIfNotEmpty(qp, 'category', query.categoryKey?.toLowerCase());
    final normalizedDateMode = query.dateMode?.trim().toLowerCase();
    if (normalizedDateMode == EventDateMode.today) {
      qp['date'] = 'today';
    } else if (normalizedDateMode == EventDateMode.weekend) {
      qp['date'] = 'weekend';
    } else if (normalizedDateMode == EventDateMode.month ||
        normalizedDateMode == EventDateMode.all ||
        normalizedDateMode == 'year' ||
        normalizedDateMode == 'upcoming') {
      qp['date'] = 'year';
    } else if ((normalizedDateMode ?? '').isNotEmpty) {
      qp['date'] = normalizedDateMode!;
    }
    _putIfNotEmpty(qp, 'q', query.searchQuery);
    if (query.startAtUtc != null) {
      qp['start_at'] = query.startAtUtc!.toUtc().toIso8601String();
    }
    if (query.endAtUtc != null) {
      qp['end_at'] = query.endAtUtc!.toUtc().toIso8601String();
    }
    if (query.limit != null && query.limit! > 0)
      qp['limit'] = query.limit.toString();
    if (query.latitude != null && query.latitude!.isFinite) {
      qp['lat'] = query.latitude!.toStringAsFixed(6);
    }
    if (query.longitude != null && query.longitude!.isFinite) {
      qp['lng'] = query.longitude!.toStringAsFixed(6);
    }
    if (query.radiusKm != null &&
        query.radiusKm!.isFinite &&
        query.radiusKm! >= 0) {
      qp['radius_km'] = query.radiusKm!.toStringAsFixed(2);
    }
    return uri.replace(queryParameters: qp);
  }

  static void _putIfNotEmpty(
    Map<String, String> target,
    String key,
    String? value,
  ) {
    final normalized = (value ?? '').trim();
    if (normalized.isNotEmpty) target[key] = normalized;
  }

  EventDetailData? _mapEvent(Map<String, dynamic> event) {
    final id =
        _readString(event, const <String>[
          'id',
          'source_event_id',
          'sourceEventId',
        ]) ??
        '';
    if (id.isEmpty) return null;
    final lat = _readDouble(event, const <String>[
      'latitude',
      'lat',
      'to_lat',
      'toLat',
    ]);
    final lng = _readDouble(event, const <String>[
      'longitude',
      'lng',
      'to_lng',
      'toLng',
    ]);
    if (lat == null || lng == null) return null;
    final categoryKey = _readString(event, const <String>[
      'category_key',
      'categoryKey',
    ]);
    final category =
        _readString(event, const <String>[
          'category',
          'category_label',
          'categoryLabel',
        ]) ??
        categoryKey ??
        'other';
    final startsAtUtc = _readDateTime(event, const <String>[
      'starts_at_utc',
      'startAtUtc',
    ]);
    final dateTimeLabel =
        _readString(event, const <String>[
          'date_time_label',
          'dateTimeLabel',
        ]) ??
        _dateTimeLabelFromUtc(startsAtUtc) ??
        _readString(event, const <String>['starts_at_utc', 'startAtUtc']) ??
        'Gepland';

    final resolvedCategoryKey = resolveEventCategoryKey(
      explicitKey: categoryKey,
      fallbackLabel: category,
    );
    final distanceLabel = _readString(event, const <String>[
      'distance_label',
      'distanceLabel',
    ]);
    final isDistanceLabelTrusted = (distanceLabel ?? '').trim().isNotEmpty;
    final resolvedLocationName =
        _readString(event, const <String>[
          'location_name',
          'locationName',
          'venue_name',
          'venueName',
          'venue',
        ]) ??
        (_readString(event, const <String>['city']) ?? '');
    final imageUrl = _readString(event, const <String>[
      'image_url',
      'imageUrl',
    ]);
    final heroImageUrl = _readString(event, const <String>[
      'hero_image_url',
      'heroImageUrl',
    ]);
    final thumbnailUrl = _readString(event, const <String>[
      'thumbnail_url',
      'thumbnailUrl',
    ]);
    return EventDetailData(
      id: id,
      title: _readString(event, const <String>['title']) ?? 'Event',
      category: category,
      categoryKey: resolvedCategoryKey,
      dateTimeLabel: dateTimeLabel,
      locationName: resolvedLocationName,
      city: _readString(event, const <String>['city']) ?? '',
      address: _readString(event, const <String>['address']) ?? '',
      lat: lat,
      lng: lng,
      distanceOrStatus: distanceLabel ?? '',
      distanceLabel: distanceLabel,
      isDistanceLabelTrusted: isDistanceLabelTrusted,
      description: _readString(event, const <String>[
        'description',
        'subtitle',
      ]),
      imageUrl: imageUrl,
      heroImageUrl: heroImageUrl,
      thumbnailUrl: thumbnailUrl,
      gradient: _gradientForCategory(resolvedCategoryKey),
      sourceLabel: _readString(event, const <String>['provider', 'source']),
      marketCode: _readString(event, const <String>[
        'market_code',
        'marketCode',
      ]),
      countryCode: _readString(event, const <String>[
        'country_code',
        'countryCode',
      ]),
      startAtUtc: startsAtUtc,
      endAtUtc: _readDateTime(event, const <String>['ends_at_utc', 'endAtUtc']),
      timeZone: _readString(event, const <String>['time_zone', 'timeZone']),
      sourceEventId: _readString(event, const <String>[
        'source_event_id',
        'sourceEventId',
      ]),
      provider: _readString(event, const <String>['provider']),
      status: _readString(event, const <String>['status']),
      sourceUrl: _readString(event, const <String>['source_url', 'sourceUrl']),
      updatedAtUtc: _readDateTime(event, const <String>[
        'updated_at_utc',
        'updatedAtUtc',
      ]),
    );
  }

  static List<Color> _gradientForCategory(String categoryKey) {
    switch (categoryKey) {
      case EventCategoryKey.music:
        return const <Color>[Color(0xFF2A1F08), Color(0xFF15120A)];
      case EventCategoryKey.business:
        return const <Color>[Color(0xFF2A260E), Color(0xFF12110A)];
      case EventCategoryKey.sport:
        return const <Color>[Color(0xFF1F1A0C), Color(0xFF100F0A)];
      case EventCategoryKey.food:
        return const <Color>[Color(0xFF2E220B), Color(0xFF141108)];
      default:
        return const <Color>[Color(0xFF1D1A12), Color(0xFF0F0D08)];
    }
  }

  static String? _dateTimeLabelFromUtc(DateTime? utc) {
    if (utc == null) return null;
    final local = utc.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString().padLeft(4, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day-$month-$year • $hour:$minute';
  }

  static String? _readString(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static double? _readDouble(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value == null) continue;
      final number = value is num
          ? value.toDouble()
          : double.tryParse(value.toString());
      if (number != null && number.isFinite) return number;
    }
    return null;
  }

  static DateTime? _readDateTime(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value == null) continue;
      if (value is DateTime) return value.toUtc();
      final parsed = DateTime.tryParse(value.toString());
      if (parsed != null) return parsed.toUtc();
    }
    return null;
  }

  static bool? _asBool(dynamic value) {
    if (value is bool) return value;
    if (value == null) return null;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
    return null;
  }

  static List<String> _readStringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}

class FallbackEventDataSource implements EventDataSource {
  const FallbackEventDataSource({
    required this.primary,
    this.fallback = const LocalSeedEventDataSource(),
  });

  final EventDataSource primary;
  final EventDataSource fallback;

  @override
  List<EventDetailData>? getInitialEvents() {
    return primary.getInitialEvents() ?? fallback.getInitialEvents();
  }

  @override
  Future<List<EventDetailData>> loadEvents() async {
    final feed = await loadEventFeed();
    return feed.events;
  }

  @override
  Future<EventFeedResult> loadEventFeed({
    EventFeedQuery query = const EventFeedQuery(),
  }) async {
    try {
      final result = await primary.loadEventFeed(query: query);
      if (result.events.isNotEmpty) return result;
      final fb = await fallback.loadEventFeed(query: query);
      return EventFeedResult(
        events: fb.events,
        source: fb.source,
        receivedAtUtc: fb.receivedAtUtc,
        isFromCache: fb.isFromCache,
        errorCode: fb.errorCode,
        warnings: <String>[
          ...result.warnings,
          if (!result.warnings.contains('empty_primary_result'))
            'empty_primary_result',
        ],
      );
    } catch (_) {
      return fallback.loadEventFeed(query: query);
    }
  }
}
