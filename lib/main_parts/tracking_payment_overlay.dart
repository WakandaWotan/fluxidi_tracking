part of '../main.dart';

Map<String, String> _trackingOverlayHeaders() {
  final headers = <String, String>{};
  final token = kAdminToken.trim();
  if (token.isNotEmpty) {
    headers['x-admin-token'] = token;
  }
  return headers;
}

bool _isPaidTrackingPaymentToken(String? raw) {
  final token = (raw ?? '').trim().toLowerCase().replaceAll('-', '_');
  return token == 'paid' ||
      token == 'settled' ||
      token == 'confirmed' ||
      token == 'completed' ||
      token == 'succeeded' ||
      token == 'success';
}

String _normalizeCustomerPaymentDisplayToken(String? raw) {
  return (raw ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
}

bool _isPaidCustomerPaymentDisplayToken(String token) {
  return token == 'paid' ||
      token == 'confirmed' ||
      token == 'success' ||
      token == 'completed' ||
      token == 'settled' ||
      token == 'succeeded' ||
      token == 'captured';
}

bool _isPartialCustomerPaymentDisplayToken(String token) {
  return token == 'partially_paid' ||
      token == 'partial_paid' ||
      token == 'partial';
}

String _classifyCustomerPaymentDisplayToken({
  required Set<String> aliases,
  required String fallbackToken,
  _TrackingPaymentOverlayMatcher? matcher,
}) {
  final normalizedFallback = _normalizeCustomerPaymentDisplayToken(
    fallbackToken,
  );
  if (matcher != null) {
    final aggregate = matcher.aggregateOperationalLegsForParentAliases(aliases);
    if (aggregate.totalLegs >= 2) {
      if (aggregate.paidLegs == aggregate.totalLegs) return 'paid';
      if (aggregate.paidLegs > 0) return 'partially_paid';
    } else if (matcher.hasAnyPaidForAliases(aliases)) {
      return 'paid';
    }
  }
  if (_isPaidCustomerPaymentDisplayToken(normalizedFallback)) return 'paid';
  if (_isPartialCustomerPaymentDisplayToken(normalizedFallback)) {
    return 'partially_paid';
  }
  return normalizedFallback;
}

String _trackingOverlayCompositeKey(String left, String right) {
  final a = left.trim().toLowerCase();
  final b = right.trim().toLowerCase();
  if (a.isEmpty || b.isEmpty) return '';
  return '$a::$b';
}

class _TrackingTripPaymentEntry {
  const _TrackingTripPaymentEntry({
    required this.tripId,
    required this.bookingId,
    required this.parentBookingId,
    required this.legId,
    required this.legType,
    required this.rowKey,
    required this.paymentStatus,
    required this.isPaid,
    required this.isOperationalLeg,
    required this.aliases,
  });

  final String tripId;
  final String bookingId;
  final String parentBookingId;
  final String legId;
  final String legType;
  final String rowKey;
  final String paymentStatus;
  final bool isPaid;
  final bool isOperationalLeg;
  final Set<String> aliases;

  static String _text(dynamic value) {
    final s = (value ?? '').toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return '';
    return s;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  factory _TrackingTripPaymentEntry.fromJson(Map<String, dynamic> raw) {
    final detail = _asMap(raw['booking_details']);
    final booking = _asMap(raw['booking']);
    final paymentStatus = _text(
      raw['payment_status'] ??
          raw['paymentStatus'] ??
          detail['payment_status'] ??
          detail['paymentStatus'] ??
          booking['payment_status'] ??
          booking['paymentStatus'],
    );
    final bookingId = _text(
      raw['booking_id'] ??
          raw['bookingId'] ??
          detail['booking_id'] ??
          detail['bookingId'] ??
          booking['booking_id'] ??
          booking['bookingId'],
    );
    final parentBookingId = _text(
      raw['parent_booking_id'] ??
          raw['parentBookingId'] ??
          detail['parent_booking_id'] ??
          detail['parentBookingId'],
    );
    final legId = _text(
      raw['leg_id'] ?? raw['legId'] ?? detail['leg_id'] ?? detail['legId'],
    );
    final legType = _text(
      raw['leg_type'] ??
          raw['legType'] ??
          detail['leg_type'] ??
          detail['legType'],
    ).toLowerCase();
    final rowKey = _text(
      raw['row_key'] ?? raw['rowKey'] ?? detail['row_key'] ?? detail['rowKey'],
    );
    final operationalToken = _text(
      raw['is_operational_leg'] ??
          raw['isOperationalLeg'] ??
          detail['is_operational_leg'] ??
          detail['isOperationalLeg'],
    ).toLowerCase();
    final isOperationalLeg =
        operationalToken == 'true' ||
        operationalToken == '1' ||
        legId.isNotEmpty ||
        rowKey.isNotEmpty;
    final aliases = <String>{};
    void addAlias(dynamic value) {
      final token = _text(value).toLowerCase();
      if (token.isEmpty) return;
      aliases.add(token);
    }

    addAlias(raw['trip_id'] ?? raw['tripId']);
    addAlias(raw['booking_id'] ?? raw['bookingId']);
    addAlias(raw['public_booking_id'] ?? raw['publicBookingId']);
    addAlias(raw['public_booking_reference'] ?? raw['publicBookingReference']);
    addAlias(raw['booking_reference'] ?? raw['bookingReference']);
    addAlias(raw['public_reference'] ?? raw['publicReference']);
    addAlias(raw['planning_reference'] ?? raw['planningReference']);
    addAlias(raw['payment_booking_id'] ?? raw['paymentBookingId']);
    addAlias(raw['parent_booking_id'] ?? raw['parentBookingId']);
    addAlias(raw['original_booking_id'] ?? raw['originalBookingId']);
    addAlias(detail['booking_id'] ?? detail['bookingId']);
    addAlias(detail['public_booking_id'] ?? detail['publicBookingId']);
    addAlias(
      detail['public_booking_reference'] ?? detail['publicBookingReference'],
    );
    addAlias(detail['booking_reference'] ?? detail['bookingReference']);
    addAlias(detail['public_reference'] ?? detail['publicReference']);
    addAlias(detail['planning_reference'] ?? detail['planningReference']);
    addAlias(detail['payment_booking_id'] ?? detail['paymentBookingId']);
    addAlias(detail['parent_booking_id'] ?? detail['parentBookingId']);
    addAlias(detail['original_booking_id'] ?? detail['originalBookingId']);
    addAlias(booking['booking_id'] ?? booking['bookingId']);
    addAlias(booking['public_booking_id'] ?? booking['publicBookingId']);
    addAlias(
      booking['public_booking_reference'] ?? booking['publicBookingReference'],
    );
    addAlias(booking['booking_reference'] ?? booking['bookingReference']);
    addAlias(booking['public_reference'] ?? booking['publicReference']);
    addAlias(booking['planning_reference'] ?? booking['planningReference']);
    addAlias(booking['payment_booking_id'] ?? booking['paymentBookingId']);
    addAlias(booking['parent_booking_id'] ?? booking['parentBookingId']);
    addAlias(booking['original_booking_id'] ?? booking['originalBookingId']);

    return _TrackingTripPaymentEntry(
      tripId: _text(raw['trip_id'] ?? raw['tripId']),
      bookingId: bookingId,
      parentBookingId: parentBookingId,
      legId: legId,
      legType: legType,
      rowKey: rowKey,
      paymentStatus: paymentStatus,
      isPaid: _isPaidTrackingPaymentToken(paymentStatus),
      isOperationalLeg: isOperationalLeg,
      aliases: aliases,
    );
  }
}

class _TrackingPaymentOverlayMatcher {
  _TrackingPaymentOverlayMatcher(List<_TrackingTripPaymentEntry> trips)
    : _allTrips = trips {
    for (final entry in trips) {
      for (final alias in entry.aliases) {
        final normalizedAlias = _normalizeAlias(alias);
        if (normalizedAlias.isEmpty) continue;
        _entriesByAlias
            .putIfAbsent(normalizedAlias, () => <_TrackingTripPaymentEntry>[])
            .add(entry);
      }
      if (!entry.isOperationalLeg) continue;
      if (entry.legId.isNotEmpty) {
        _byLegId
            .putIfAbsent(entry.legId, () => <_TrackingTripPaymentEntry>[])
            .add(entry);
      }
      if (entry.bookingId.isNotEmpty && entry.legType.isNotEmpty) {
        final key = _trackingOverlayCompositeKey(
          entry.bookingId,
          entry.legType,
        );
        if (key.isNotEmpty) {
          _byBookingLegType
              .putIfAbsent(key, () => <_TrackingTripPaymentEntry>[])
              .add(entry);
        }
      }
      if (entry.parentBookingId.isNotEmpty && entry.legType.isNotEmpty) {
        final key = _trackingOverlayCompositeKey(
          entry.parentBookingId,
          entry.legType,
        );
        if (key.isNotEmpty) {
          _byParentLegType
              .putIfAbsent(key, () => <_TrackingTripPaymentEntry>[])
              .add(entry);
        }
      }
      final parentKey = entry.parentBookingId.isNotEmpty
          ? entry.parentBookingId
          : entry.bookingId;
      final parentAlias = _normalizeAlias(parentKey);
      if (parentAlias.isNotEmpty) {
        _operationalByParent
            .putIfAbsent(parentAlias, () => <_TrackingTripPaymentEntry>[])
            .add(entry);
      }
    }
  }

  final List<_TrackingTripPaymentEntry> _allTrips;
  final Map<String, List<_TrackingTripPaymentEntry>> _byLegId =
      <String, List<_TrackingTripPaymentEntry>>{};
  final Map<String, List<_TrackingTripPaymentEntry>> _byBookingLegType =
      <String, List<_TrackingTripPaymentEntry>>{};
  final Map<String, List<_TrackingTripPaymentEntry>> _byParentLegType =
      <String, List<_TrackingTripPaymentEntry>>{};
  final Map<String, List<_TrackingTripPaymentEntry>> _operationalByParent =
      <String, List<_TrackingTripPaymentEntry>>{};
  final Map<String, List<_TrackingTripPaymentEntry>> _entriesByAlias =
      <String, List<_TrackingTripPaymentEntry>>{};

  int get totalTrips => _allTrips.length;

  String _normalizeAlias(String value) {
    return value.trim().toLowerCase();
  }

  ({int totalLegs, int paidLegs}) _aggregateFromEntries(
    Iterable<_TrackingTripPaymentEntry> entries,
  ) {
    final paidByLeg = <String, bool>{};
    for (final entry in entries) {
      final legKey = entry.legId.isNotEmpty
          ? 'leg:${entry.legId}'
          : (entry.rowKey.isNotEmpty
                ? 'row:${entry.rowKey}'
                : (entry.legType.isNotEmpty
                      ? 'type:${entry.legType}'
                      : (entry.tripId.isNotEmpty
                            ? 'trip:${entry.tripId}'
                            : '')));
      if (legKey.isEmpty) continue;
      paidByLeg[legKey] = (paidByLeg[legKey] ?? false) || entry.isPaid;
    }
    final total = paidByLeg.length;
    final paid = paidByLeg.values.where((value) => value).length;
    return (totalLegs: total, paidLegs: paid);
  }

  List<_TrackingTripPaymentEntry> matchOperationalLeg({
    required String bookingId,
    required String parentBookingId,
    required String legId,
    required String legType,
  }) {
    final out = <_TrackingTripPaymentEntry>[];
    final seen = <String>{};
    void add(Iterable<_TrackingTripPaymentEntry>? entries) {
      if (entries == null) return;
      for (final entry in entries) {
        final id = entry.tripId.isNotEmpty
            ? entry.tripId
            : '${entry.bookingId}|${entry.parentBookingId}|${entry.legId}|${entry.legType}|${entry.rowKey}';
        if (!seen.add(id)) continue;
        out.add(entry);
      }
    }

    if (legId.trim().isNotEmpty) {
      add(_byLegId[legId.trim()]);
    }
    if (bookingId.trim().isNotEmpty && legType.trim().isNotEmpty) {
      add(
        _byBookingLegType[_trackingOverlayCompositeKey(
          bookingId.trim(),
          legType.trim(),
        )],
      );
    }
    if (parentBookingId.trim().isNotEmpty && legType.trim().isNotEmpty) {
      add(
        _byParentLegType[_trackingOverlayCompositeKey(
          parentBookingId.trim(),
          legType.trim(),
        )],
      );
    }
    return out;
  }

  ({int totalLegs, int paidLegs}) aggregateOperationalLegsForParent(
    String parentBookingId,
  ) {
    final key = _normalizeAlias(parentBookingId);
    if (key.isEmpty) return (totalLegs: 0, paidLegs: 0);
    final entries =
        _operationalByParent[key] ?? const <_TrackingTripPaymentEntry>[];
    return _aggregateFromEntries(entries);
  }

  ({int totalLegs, int paidLegs}) aggregateOperationalLegsForParentAliases(
    Set<String> aliases,
  ) {
    if (aliases.isEmpty) return (totalLegs: 0, paidLegs: 0);
    final seenTripKeys = <String>{};
    final merged = <_TrackingTripPaymentEntry>[];
    for (final alias in aliases) {
      final key = _normalizeAlias(alias);
      if (key.isEmpty) continue;
      final entries = _operationalByParent[key];
      if (entries == null || entries.isEmpty) continue;
      for (final entry in entries) {
        final identity = entry.tripId.isNotEmpty
            ? entry.tripId
            : '${entry.bookingId}|${entry.parentBookingId}|${entry.legId}|${entry.legType}|${entry.rowKey}';
        if (!seenTripKeys.add(identity)) continue;
        merged.add(entry);
      }
    }
    return _aggregateFromEntries(merged);
  }

  bool hasAnyPaidForAliases(Set<String> aliases) {
    if (aliases.isEmpty) return false;
    final seenTripKeys = <String>{};
    for (final alias in aliases) {
      final key = _normalizeAlias(alias);
      if (key.isEmpty) continue;
      final entries = _entriesByAlias[key];
      if (entries == null || entries.isEmpty) continue;
      for (final entry in entries) {
        final identity = entry.tripId.isNotEmpty
            ? entry.tripId
            : '${entry.bookingId}|${entry.parentBookingId}|${entry.legId}|${entry.legType}|${entry.rowKey}|${entry.paymentStatus}';
        if (!seenTripKeys.add(identity)) continue;
        if (entry.isPaid) return true;
      }
    }
    return false;
  }
}

Future<List<_TrackingTripPaymentEntry>> _fetchTrackingOverlayTrips({
  required Map<String, String> scopeQuery,
  required String diagTag,
  int limit = 200,
}) async {
  final scoped = <String, String>{...scopeQuery};
  final tenantId = (scoped['tenant_id'] ?? scoped['tenantId'] ?? '')
      .toString()
      .trim();
  final companyId = (scoped['company_id'] ?? scoped['companyId'] ?? '')
      .toString()
      .trim();
  if (tenantId.isEmpty || companyId.isEmpty) {
    debugPrint(
      '[$diagTag][PAYMENT_OVERLAY][WARN] status=skip reason=missing_scope',
    );
    return const <_TrackingTripPaymentEntry>[];
  }
  scoped['tenant_id'] = tenantId;
  scoped['company_id'] = companyId;
  scoped['tenantId'] = tenantId;
  scoped['companyId'] = companyId;
  scoped['limit'] = '${limit.clamp(1, 500)}';

  final uri = Uri.parse(
    '$kWorkerBaseUrl$kTripsHistoryPath',
  ).replace(queryParameters: scoped);
  try {
    final res = await http
        .get(uri, headers: _trackingOverlayHeaders())
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      debugPrint(
        '[$diagTag][PAYMENT_OVERLAY][WARN] status=${res.statusCode} reason=http_error',
      );
      return const <_TrackingTripPaymentEntry>[];
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
      debugPrint(
        '[$diagTag][PAYMENT_OVERLAY][WARN] status=invalid_payload reason=not_ok',
      );
      return const <_TrackingTripPaymentEntry>[];
    }
    final rawTrips = decoded['trips'] is List
        ? (decoded['trips'] as List)
        : const <dynamic>[];
    return rawTrips
        .whereType<Map>()
        .map(
          (entry) =>
              _TrackingTripPaymentEntry.fromJson(entry.cast<String, dynamic>()),
        )
        .toList(growable: false);
  } catch (err) {
    debugPrint(
      '[$diagTag][PAYMENT_OVERLAY][WARN] status=exception reason=$err',
    );
    return const <_TrackingTripPaymentEntry>[];
  }
}

/// Optional: Worker route endpoint (recommended, avoids exposing Mapbox token)
/// Implement later in Worker: POST { from, to } -> { coords:[[lon,lat],...], distance_m, duration_s }
