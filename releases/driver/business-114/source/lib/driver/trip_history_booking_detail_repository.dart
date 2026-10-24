// TRIP-HISTORY-DETAIL-BOUND-CLIENT-P0C
//
// Process-wide booking-detail cache for explicit trip-history opens only.
// History/list rendering must not call this automatically.

const Duration kTripHistoryBookingDetailTtl = Duration(seconds: 45);

const bool kTripHistoryDetailQaRequestLogging = bool.fromEnvironment(
  'FLUXIDI_QA_REQUEST_LOGGING',
  defaultValue: false,
);

abstract final class TripHistoryDetailQaEvent {
  static const networkFetch = 'trip_history_detail_network_fetch';
  static const cacheHit = 'trip_history_detail_cache_hit';
  static const coalesced = 'trip_history_detail_coalesced';
  static const invalidated = 'trip_history_detail_invalidated';
  static const scopeDropped = 'trip_history_detail_scope_dropped';
}

enum TripHistoryDetailReason { open, retry }

typedef TripHistoryBookingDetailTransport =
    Future<Map<String, dynamic>> Function({
      required TripHistoryBookingDetailRequest request,
      required Future<Map<String, String>> Function() headers,
    });

class TripHistoryBookingDetailException implements Exception {
  TripHistoryBookingDetailException(this.code);
  final String code;

  @override
  String toString() => code;
}

class TripHistoryBookingDetailRequest {
  const TripHistoryBookingDetailRequest({
    required this.tenantId,
    required this.companyId,
    required this.driverId,
    required this.bookingId,
    this.scopeQuery = const <String, String>{},
  });

  final String tenantId;
  final String companyId;
  final String driverId;
  final String bookingId;
  final Map<String, String> scopeQuery;

  String get scopeKey =>
      '${tenantId.trim()}|${companyId.trim()}|${driverId.trim()}';

  String get cacheKey => '$scopeKey|${bookingId.trim()}';

  String get path => '/bookings/${Uri.encodeComponent(bookingId.trim())}';
}

class TripHistoryBookingDetailResult {
  const TripHistoryBookingDetailResult({
    required this.cacheKey,
    required this.scopeKey,
    required this.payload,
  });

  final String cacheKey;
  final String scopeKey;
  final Map<String, dynamic> payload;
}

class _CachedTripHistoryDetail {
  const _CachedTripHistoryDetail({
    required this.result,
    required this.fetchedAt,
  });

  final TripHistoryBookingDetailResult result;
  final DateTime fetchedAt;
}

/// History sync never hydrates booking detail automatically.
bool tripHistoryAllowsAutomaticDetailHydration() => false;

class TripHistoryBookingDetailRepository {
  TripHistoryBookingDetailRepository({
    required TripHistoryBookingDetailTransport transport,
    this.ttl = kTripHistoryBookingDetailTtl,
    DateTime Function()? clock,
    this.qaLogEnabled = kTripHistoryDetailQaRequestLogging,
    void Function(String event)? qaLog,
  }) : _transport = transport,
       _clock = clock ?? DateTime.now,
       _qaLog = qaLog;

  final TripHistoryBookingDetailTransport _transport;
  final Duration ttl;
  final DateTime Function() _clock;
  final bool qaLogEnabled;
  final void Function(String event)? _qaLog;

  final Map<String, _CachedTripHistoryDetail> _cache =
      <String, _CachedTripHistoryDetail>{};
  final Map<String, Future<TripHistoryBookingDetailResult>> _inFlight =
      <String, Future<TripHistoryBookingDetailResult>>{};
  String _activeScopeKey = '';

  DateTime now() => _clock();

  void _emitQa(String event) {
    if (!qaLogEnabled) return;
    final safe = event;
    final line = '[TRIP_HISTORY_DETAIL] $safe';
    if (_qaLog != null) {
      _qaLog(line);
      return;
    }
    // ignore: avoid_print
    print(line);
  }

  void applyScope({
    required String tenantId,
    required String companyId,
    required String driverId,
  }) {
    final next = TripHistoryBookingDetailRequest(
      tenantId: tenantId,
      companyId: companyId,
      driverId: driverId,
      bookingId: '_',
    ).scopeKey;
    if (next == _activeScopeKey) return;
    _activeScopeKey = next;
    invalidateAll(emitQa: false);
  }

  Future<TripHistoryBookingDetailResult> fetch({
    required TripHistoryBookingDetailRequest request,
    required Future<Map<String, String>> Function() headers,
    bool forceRefresh = false,
  }) {
    applyScope(
      tenantId: request.tenantId,
      companyId: request.companyId,
      driverId: request.driverId,
    );
    final key = request.cacheKey;
    final scopeAtStart = _activeScopeKey;
    if (!forceRefresh) {
      final cached = _cache[key];
      if (cached != null && now().difference(cached.fetchedAt) < ttl) {
        _emitQa(TripHistoryDetailQaEvent.cacheHit);
        return Future<TripHistoryBookingDetailResult>.value(cached.result);
      }
    }
    final existing = _inFlight[key];
    if (existing != null) {
      _emitQa(TripHistoryDetailQaEvent.coalesced);
      return existing;
    }
    late final Future<TripHistoryBookingDetailResult> future;
    future = Future<TripHistoryBookingDetailResult>(() async {
      try {
        _emitQa(TripHistoryDetailQaEvent.networkFetch);
        final decoded = await _transport(request: request, headers: headers);
        if (scopeAtStart != _activeScopeKey) {
          _emitQa(TripHistoryDetailQaEvent.scopeDropped);
          throw TripHistoryBookingDetailException('scope_changed');
        }
        final result = TripHistoryBookingDetailResult(
          cacheKey: key,
          scopeKey: request.scopeKey,
          payload: Map<String, dynamic>.from(decoded),
        );
        if (identical(_inFlight[key], future) &&
            scopeAtStart == _activeScopeKey) {
          _cache[key] = _CachedTripHistoryDetail(
            result: result,
            fetchedAt: now(),
          );
        }
        return result;
      } finally {
        if (identical(_inFlight[key], future)) {
          _inFlight.remove(key);
        }
      }
    });
    _inFlight[key] = future;
    return future;
  }

  void invalidate({
    String? tenantId,
    String? companyId,
    String? driverId,
    String? bookingId,
  }) {
    _emitQa(TripHistoryDetailQaEvent.invalidated);
    final tenant = (tenantId ?? '').trim();
    final company = (companyId ?? '').trim();
    final driver = (driverId ?? '').trim();
    final booking = (bookingId ?? '').trim();
    bool matches(String key) {
      final parts = key.split('|');
      if (parts.length < 4) return false;
      if (tenant.isNotEmpty && parts[0] != tenant) return false;
      if (company.isNotEmpty && parts[1] != company) return false;
      if (driver.isNotEmpty && parts[2] != driver) return false;
      if (booking.isNotEmpty && parts[3] != booking) return false;
      return true;
    }

    _cache.removeWhere((key, _) => matches(key));
    _inFlight.removeWhere((key, _) => matches(key));
  }

  void invalidateAll({bool emitQa = true}) {
    if (emitQa) _emitQa(TripHistoryDetailQaEvent.invalidated);
    _cache.clear();
    _inFlight.clear();
  }

  void resetForTest() {
    _cache.clear();
    _inFlight.clear();
    _activeScopeKey = '';
  }

  bool hasFreshCache(TripHistoryBookingDetailRequest request, {DateTime? now}) {
    final cached = _cache[request.cacheKey];
    if (cached == null) return false;
    return (now ?? this.now()).difference(cached.fetchedAt) < ttl;
  }
}

TripHistoryBookingDetailRepository? _tripHistoryBookingDetailRepository;

TripHistoryBookingDetailRepository get tripHistoryBookingDetailRepository {
  return _tripHistoryBookingDetailRepository ??=
      TripHistoryBookingDetailRepository(
        transport: loadTripHistoryBookingDetailUncached,
      );
}

void bindTripHistoryBookingDetailRepositoryForTest(
  TripHistoryBookingDetailRepository repo,
) {
  _tripHistoryBookingDetailRepository = repo;
}

void resetTripHistoryBookingDetailRepositoryForTest() {
  _tripHistoryBookingDetailRepository?.resetForTest();
}

TripHistoryBookingDetailTransport loadTripHistoryBookingDetailUncached =
    _missingTripHistoryBookingDetailTransport;

Future<Map<String, dynamic>> _missingTripHistoryBookingDetailTransport({
  required TripHistoryBookingDetailRequest request,
  required Future<Map<String, String>> Function() headers,
}) {
  throw TripHistoryBookingDetailException('transport_unbound');
}
