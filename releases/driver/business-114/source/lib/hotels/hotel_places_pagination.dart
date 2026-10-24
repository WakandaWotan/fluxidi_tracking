/// Client-side gate for one explicit Google Places page-2 request.
enum HotelPlacesPage2Phase {
  hidden,
  waitingActivation,
  available,
  loading,
  retryable,
  complete,
}

class HotelPlacesPaginationMeta {
  const HotelPlacesPaginationMeta({
    required this.page,
    required this.hasMore,
    required this.maxPages,
    this.nextCursor,
    this.availableAt,
  });

  final int page;
  final bool hasMore;
  final int maxPages;
  final String? nextCursor;
  final DateTime? availableAt;

  static HotelPlacesPaginationMeta? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final cursor = (json['next_cursor'] ?? json['nextCursor'] ?? '')
        .toString()
        .trim();
    final page = _asInt(json['page']) ?? 1;
    final hasMore = json['has_more'] == true || json['hasMore'] == true;
    final maxPages = _asInt(json['max_pages'] ?? json['maxPages']) ?? 2;
    DateTime? availableAt;
    final rawAvailable = json['available_at'] ?? json['availableAt'];
    if (rawAvailable is num) {
      availableAt = DateTime.fromMillisecondsSinceEpoch(
        rawAvailable.round(),
        isUtc: true,
      );
    } else if (rawAvailable is String && rawAvailable.trim().isNotEmpty) {
      availableAt = DateTime.tryParse(rawAvailable.trim())?.toUtc();
    }
    if (!hasMore || cursor.isEmpty || page >= maxPages) {
      return HotelPlacesPaginationMeta(
        page: page,
        hasMore: false,
        maxPages: maxPages,
      );
    }
    return HotelPlacesPaginationMeta(
      page: page,
      hasMore: true,
      maxPages: maxPages,
      nextCursor: cursor,
      availableAt: availableAt,
    );
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse((value ?? '').toString().trim());
  }
}

class HotelPlacesPage2Snapshot {
  const HotelPlacesPage2Snapshot({
    required this.phase,
    this.cursor,
    this.queryGeneration,
    this.availableAt,
    this.retryAfter,
  });

  final HotelPlacesPage2Phase phase;
  final String? cursor;
  final int? queryGeneration;
  final DateTime? availableAt;
  final Duration? retryAfter;

  bool get showAction =>
      phase == HotelPlacesPage2Phase.available ||
      phase == HotelPlacesPage2Phase.waitingActivation ||
      phase == HotelPlacesPage2Phase.loading ||
      phase == HotelPlacesPage2Phase.retryable;

  bool get canRequest => phase == HotelPlacesPage2Phase.available;

  bool get isRetryable => phase == HotelPlacesPage2Phase.retryable;
}

class HotelPlacesPage2Controller {
  HotelPlacesPage2Snapshot _snapshot = const HotelPlacesPage2Snapshot(
    phase: HotelPlacesPage2Phase.hidden,
  );

  HotelPlacesPage2Snapshot get snapshot => _snapshot;

  void reset() {
    _snapshot = const HotelPlacesPage2Snapshot(
      phase: HotelPlacesPage2Phase.hidden,
    );
  }

  void applyFirstPage({
    required HotelPlacesPaginationMeta? pagination,
    required int queryGeneration,
    DateTime? now,
  }) {
    final cursor = pagination?.nextCursor?.trim() ?? '';
    if (pagination == null ||
        pagination.hasMore != true ||
        cursor.isEmpty ||
        pagination.page >= pagination.maxPages) {
      _snapshot = const HotelPlacesPage2Snapshot(
        phase: HotelPlacesPage2Phase.hidden,
      );
      return;
    }
    final clock = now ?? DateTime.now().toUtc();
    final availableAt = pagination.availableAt?.toUtc();
    final waiting =
        availableAt != null && availableAt.isAfter(clock);
    _snapshot = HotelPlacesPage2Snapshot(
      phase: waiting
          ? HotelPlacesPage2Phase.waitingActivation
          : HotelPlacesPage2Phase.available,
      cursor: cursor,
      queryGeneration: queryGeneration,
      availableAt: availableAt,
    );
  }

  bool activateIfReady({DateTime? now}) {
    if (_snapshot.phase != HotelPlacesPage2Phase.waitingActivation) {
      return false;
    }
    final availableAt = _snapshot.availableAt;
    final clock = now ?? DateTime.now().toUtc();
    if (availableAt != null && availableAt.isAfter(clock)) {
      return false;
    }
    _snapshot = HotelPlacesPage2Snapshot(
      phase: HotelPlacesPage2Phase.available,
      cursor: _snapshot.cursor,
      queryGeneration: _snapshot.queryGeneration,
      availableAt: _snapshot.availableAt,
    );
    return true;
  }

  bool beginRequest({required int queryGeneration}) {
    if (_snapshot.phase != HotelPlacesPage2Phase.available &&
        _snapshot.phase != HotelPlacesPage2Phase.retryable) {
      return false;
    }
    if (_snapshot.queryGeneration != queryGeneration) return false;
    if ((_snapshot.cursor ?? '').trim().isEmpty) return false;
    _snapshot = HotelPlacesPage2Snapshot(
      phase: HotelPlacesPage2Phase.loading,
      cursor: _snapshot.cursor,
      queryGeneration: queryGeneration,
      availableAt: _snapshot.availableAt,
    );
    return true;
  }

  bool shouldApply({required int queryGeneration}) {
    return _snapshot.queryGeneration == queryGeneration &&
        (_snapshot.phase == HotelPlacesPage2Phase.loading ||
            _snapshot.phase == HotelPlacesPage2Phase.retryable ||
            _snapshot.phase == HotelPlacesPage2Phase.available);
  }

  void completeSuccess({required int queryGeneration}) {
    if (!shouldApply(queryGeneration: queryGeneration)) return;
    _snapshot = HotelPlacesPage2Snapshot(
      phase: HotelPlacesPage2Phase.complete,
      queryGeneration: queryGeneration,
    );
  }

  void completeRetryable({
    required int queryGeneration,
    Duration? retryAfter,
    DateTime? availableAt,
  }) {
    if (_snapshot.queryGeneration != queryGeneration) return;
    _snapshot = HotelPlacesPage2Snapshot(
      phase: HotelPlacesPage2Phase.retryable,
      cursor: _snapshot.cursor,
      queryGeneration: queryGeneration,
      availableAt: availableAt ?? _snapshot.availableAt,
      retryAfter: retryAfter,
    );
  }

  void completeFailure({required int queryGeneration}) {
    if (_snapshot.queryGeneration != queryGeneration) return;
    _snapshot = HotelPlacesPage2Snapshot(
      phase: HotelPlacesPage2Phase.retryable,
      cursor: _snapshot.cursor,
      queryGeneration: queryGeneration,
      availableAt: _snapshot.availableAt,
    );
  }
}

String? hotelStayStablePlaceId(String stayId) {
  final value = stayId.trim();
  if (value.isEmpty) return null;
  const prefix = 'google_places:';
  if (value.startsWith(prefix) && value.length > prefix.length) {
    return value.substring(prefix.length);
  }
  return value;
}

List<T> dedupeHotelStaysByPlaceId<T>(
  Iterable<T> stays, {
  required String Function(T stay) idOf,
}) {
  final out = <T>[];
  final seen = <String>{};
  for (final stay in stays) {
    final id = hotelStayStablePlaceId(idOf(stay));
    if (id == null || !seen.add(id)) continue;
    out.add(stay);
  }
  return out;
}
