// BOOKINGS-LIST-PAGINATION-CLIENT-P0C
//
// Process-wide company/chauffeur booking-list cache + single-flight.
//
// Feature-detects Worker P0C pagination (`next_cursor` + `has_more`). Never
// fabricates a cursor and never infers `has_more` from `items.length`.
// Legacy Workers (those keys absent) get at most one compatible larger
// request per screen/TTL. Failures are never cached as healthy empty data.
// Tokens and auth objects are never stored.

/// 45 s — documented short TTL (30–60 s band).
const Duration kBookingListPageTtl = Duration(seconds: 45);

/// First-page size once the Worker advertises P0C pagination.
const int kBookingListProjectedPageSize = 25;

/// Current company overview request when pagination fields are absent.
const int kBookingListLegacyCompanyLimit = 200;

/// Current chauffeur list request when pagination fields are absent.
const int kBookingListLegacyDriverLimit = 50;

const String kBookingListCompanyPath = '/bookings';
const String kBookingListDriverPath = '/driver/bookings';

/// QA-only request observability. Default false.
const bool kBookingListQaRequestLogging = bool.fromEnvironment(
  'FLUXIDI_QA_REQUEST_LOGGING',
  defaultValue: false,
);

/// Identifier-free booking-page QA events.
abstract final class BookingPageQaEvent {
  static const networkFetch = 'booking_page_network_fetch';
  static const cacheHit = 'booking_page_cache_hit';
  static const coalesced = 'booking_page_coalesced';
  static const manualRefresh = 'booking_page_manual_refresh';
  static const nextPage = 'booking_page_next_page';
  static const legacyContract = 'booking_page_legacy_contract';
  static const invalidated = 'booking_page_invalidated';
}

const Set<String> kBookingPageQaEvents = <String>{
  BookingPageQaEvent.networkFetch,
  BookingPageQaEvent.cacheHit,
  BookingPageQaEvent.coalesced,
  BookingPageQaEvent.manualRefresh,
  BookingPageQaEvent.nextPage,
  BookingPageQaEvent.legacyContract,
  BookingPageQaEvent.invalidated,
};

String formatBookingPageQaLog(String event) {
  final safe = kBookingPageQaEvents.contains(event)
      ? event
      : BookingPageQaEvent.networkFetch;
  return '[BOOKING_PAGE] $safe';
}

void logBookingPageQa(
  String event, {
  bool enabled = kBookingListQaRequestLogging,
  void Function(String line)? sink,
}) {
  if (!enabled) return;
  final line = formatBookingPageQaLog(event);
  if (sink != null) {
    sink(line);
    return;
  }
  // ignore: avoid_print
  print(line);
}

enum BookingListActor { company, driver }

enum BookingListHistoryMode { active, history }

enum BookingListContractKind { projected, legacy }

enum BookingListPageReason { opportunistic, manualRefresh, nextPage, mutation }

/// Bounded GET outcome. [transport] never receives tokens from the cache.
typedef BookingListPageTransport =
    Future<Map<String, dynamic>> Function({
      required BookingListPageRequest request,
      required int limit,
      required Future<Map<String, String>> Function() headers,
    });

class BookingListPageException implements Exception {
  BookingListPageException(this.code);
  final String code;

  @override
  String toString() => code;
}

class BookingListPageRequest {
  const BookingListPageRequest({
    required this.actor,
    required this.tenantId,
    required this.companyId,
    this.driverId = '',
    this.historyMode = BookingListHistoryMode.history,
    this.cursor = '',
    this.scopeQuery = const <String, String>{},
    this.filterFingerprint = '',
  });

  final BookingListActor actor;
  final String tenantId;
  final String companyId;
  final String driverId;
  final BookingListHistoryMode historyMode;
  final String cursor;
  final Map<String, String> scopeQuery;
  final String filterFingerprint;

  bool get isFirstPage => cursor.trim().isEmpty;

  String get path => actor == BookingListActor.company
      ? kBookingListCompanyPath
      : kBookingListDriverPath;

  int get legacyLimit => actor == BookingListActor.company
      ? kBookingListLegacyCompanyLimit
      : kBookingListLegacyDriverLimit;

  String get scopeKey {
    return [
      actor.name,
      tenantId.trim(),
      companyId.trim(),
      driverId.trim(),
      historyMode.name,
      filterFingerprint.trim(),
    ].join('|');
  }

  String get cacheKey => '$scopeKey|${cursor.trim()}';

  BookingListPageRequest copyWith({String? cursor}) {
    return BookingListPageRequest(
      actor: actor,
      tenantId: tenantId,
      companyId: companyId,
      driverId: driverId,
      historyMode: historyMode,
      cursor: cursor ?? this.cursor,
      scopeQuery: scopeQuery,
      filterFingerprint: filterFingerprint,
    );
  }
}

class BookingListPageResult {
  const BookingListPageResult({
    required this.scopeKey,
    required this.cacheKey,
    required this.contract,
    required this.items,
    required this.count,
    required this.hasMore,
    this.nextCursor,
    this.degraded = false,
    this.limitUsed = kBookingListProjectedPageSize,
  });

  final String scopeKey;
  final String cacheKey;
  final BookingListContractKind contract;
  final List<Map<String, dynamic>> items;
  final int count;
  final bool hasMore;
  final String? nextCursor;
  final bool degraded;
  final int limitUsed;

  bool get isLegacy => contract == BookingListContractKind.legacy;
  bool get isProjected => contract == BookingListContractKind.projected;
}

class _CachedBookingListPage {
  const _CachedBookingListPage({required this.result, required this.fetchedAt});

  final BookingListPageResult result;
  final DateTime fetchedAt;
}

/// Whether a decoded map advertises P0C pagination. Both keys must be present.
/// Values are not inferred from [items] length.
bool bookingListPayloadAdvertisesPagination(Map<dynamic, dynamic> decoded) {
  return decoded.containsKey('next_cursor') && decoded.containsKey('has_more');
}

/// Parses `{ ok, items, count }` plus optional P0C fields.
///
/// [hasMore] is true only when the Worker sent `has_more: true` together with
/// a non-empty opaque `next_cursor`. A missing cursor disables further
/// loading instead of inventing one.
BookingListPageResult parseBookingListPagePayload(
  Map<dynamic, dynamic> decoded, {
  required BookingListPageRequest request,
  required int limitUsed,
}) {
  if (decoded['ok'] != true) {
    final apiError = (decoded['error']?.toString().trim() ?? '').isNotEmpty
        ? decoded['error'].toString().trim()
        : 'bookings_not_ok';
    throw BookingListPageException(apiError);
  }
  final raw =
      (decoded['items'] as List<dynamic>? ??
      decoded['bookings'] as List<dynamic>? ??
      const <dynamic>[]);
  final items = raw
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList(growable: false);
  final advertised = bookingListPayloadAdvertisesPagination(decoded);
  final contract = advertised
      ? BookingListContractKind.projected
      : BookingListContractKind.legacy;
  var hasMore = false;
  String? nextCursor;
  if (advertised) {
    final cursor = (decoded['next_cursor'] ?? '').toString().trim();
    if (decoded['has_more'] == true && cursor.isNotEmpty) {
      hasMore = true;
      nextCursor = cursor;
    }
  }
  final countRaw = decoded['count'];
  final count = countRaw is int
      ? countRaw
      : (countRaw is num ? countRaw.toInt() : items.length);
  return BookingListPageResult(
    scopeKey: request.scopeKey,
    cacheKey: request.cacheKey,
    contract: contract,
    items: items,
    count: count,
    hasMore: hasMore,
    nextCursor: nextCursor,
    degraded: advertised && decoded['degraded'] == true,
    limitUsed: limitUsed,
  );
}

/// Deterministic row identity: booking + optional operational leg.
String bookingListRowDedupeKey(Map<String, dynamic> row) {
  final id = (row['booking_id'] ?? row['id'] ?? '').toString().trim();
  if (id.isEmpty) return '';
  final leg = (row['leg_id'] ?? row['legId'] ?? '').toString().trim();
  return leg.isEmpty ? id : '$id:$leg';
}

/// Concatenate pages, keep first occurrence, preserve incoming order.
List<Map<String, dynamic>> mergeBookingListPages({
  required List<Map<String, dynamic>> previous,
  required List<Map<String, dynamic>> incoming,
}) {
  final seen = <String>{};
  final out = <Map<String, dynamic>>[];
  for (final row in <Map<String, dynamic>>[...previous, ...incoming]) {
    final key = bookingListRowDedupeKey(row);
    if (key.isEmpty) continue;
    if (!seen.add(key)) continue;
    out.add(row);
  }
  return List<Map<String, dynamic>>.unmodifiable(out);
}

/// Load-more is Worker-advertised only. Never auto-drain.
bool bookingListShowsLoadMore({
  required BookingListContractKind contract,
  required bool hasMore,
  required String? nextCursor,
}) {
  if (contract != BookingListContractKind.projected) return false;
  if (hasMore != true) return false;
  return (nextCursor ?? '').trim().isNotEmpty;
}

/// Explicit user action is required for the next projected page.
bool bookingListAllowsAutomaticDrain() => false;

/// Query used by the production transport. Identifier values come from the
/// already-authenticated scope; the cache never logs them.
Map<String, String> buildBookingListPageQuery({
  required BookingListPageRequest request,
  required int limit,
}) {
  final query = <String, String>{...request.scopeQuery, 'limit': '$limit'};
  if (request.historyMode == BookingListHistoryMode.history) {
    query['include_history'] = '1';
  }
  final cursor = request.cursor.trim();
  if (cursor.isNotEmpty) {
    query['cursor'] = cursor;
  }
  return query;
}

class BookingListPageRepository {
  BookingListPageRepository({
    required BookingListPageTransport transport,
    this.ttl = kBookingListPageTtl,
    DateTime Function()? clock,
    this.qaLogEnabled = kBookingListQaRequestLogging,
    void Function(String event)? qaLog,
  }) : _transport = transport,
       _clock = clock ?? DateTime.now,
       _qaLog = qaLog;

  final BookingListPageTransport _transport;
  final Duration ttl;
  final DateTime Function() _clock;
  final bool qaLogEnabled;
  final void Function(String event)? _qaLog;

  final Map<String, _CachedBookingListPage> _cache =
      <String, _CachedBookingListPage>{};
  final Map<String, Future<BookingListPageResult>> _inFlight =
      <String, Future<BookingListPageResult>>{};
  final Map<String, BookingListContractKind> _contractByScope =
      <String, BookingListContractKind>{};

  DateTime now() => _clock();

  void _emitQa(String event) {
    if (_qaLog != null) {
      if (qaLogEnabled) _qaLog(event);
      return;
    }
    logBookingPageQa(event, enabled: qaLogEnabled);
  }

  Future<BookingListPageResult> fetch({
    required BookingListPageRequest request,
    required Future<Map<String, String>> Function() headers,
    bool forceRefresh = false,
    BookingListPageReason reason = BookingListPageReason.opportunistic,
  }) {
    final key = request.cacheKey;
    if (forceRefresh && request.isFirstPage) {
      _contractByScope.remove(request.scopeKey);
      _cache.remove(key);
    }
    if (!forceRefresh) {
      final cached = _cache[key];
      if (cached != null && now().difference(cached.fetchedAt) < ttl) {
        _emitQa(BookingPageQaEvent.cacheHit);
        return Future<BookingListPageResult>.value(cached.result);
      }
    }
    final existing = _inFlight[key];
    if (existing != null) {
      _emitQa(BookingPageQaEvent.coalesced);
      return existing;
    }
    if (reason == BookingListPageReason.manualRefresh) {
      _emitQa(BookingPageQaEvent.manualRefresh);
    } else if (reason == BookingListPageReason.nextPage ||
        !request.isFirstPage) {
      _emitQa(BookingPageQaEvent.nextPage);
    }
    late final Future<BookingListPageResult> future;
    future = Future<BookingListPageResult>(() async {
      try {
        final result = await _load(request: request, headers: headers);
        if (identical(_inFlight[key], future)) {
          _cache[key] = _CachedBookingListPage(
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

  Future<BookingListPageResult> _load({
    required BookingListPageRequest request,
    required Future<Map<String, String>> Function() headers,
  }) async {
    final known = _contractByScope[request.scopeKey];
    late final BookingListPageResult result;
    if (known == BookingListContractKind.legacy && request.isFirstPage) {
      result = await _loadOnce(
        request: request,
        headers: headers,
        limit: request.legacyLimit,
        expectLegacy: true,
      );
    } else if (!request.isFirstPage) {
      result = await _loadOnce(
        request: request,
        headers: headers,
        limit: kBookingListProjectedPageSize,
        expectLegacy: false,
      );
    } else {
      final probed = await _loadOnce(
        request: request,
        headers: headers,
        limit: kBookingListProjectedPageSize,
        expectLegacy: false,
      );
      if (probed.contract == BookingListContractKind.projected) {
        result = probed;
      } else {
        result = await _loadOnce(
          request: request,
          headers: headers,
          limit: request.legacyLimit,
          expectLegacy: true,
        );
      }
    }
    // Always adopt the payload we just parsed. A later projected Worker must
    // stop the sticky legacy request path without waiting for a manual refresh.
    _contractByScope[request.scopeKey] = result.contract;
    return result;
  }

  Future<BookingListPageResult> _loadOnce({
    required BookingListPageRequest request,
    required Future<Map<String, String>> Function() headers,
    required int limit,
    required bool expectLegacy,
  }) async {
    _emitQa(BookingPageQaEvent.networkFetch);
    if (expectLegacy) {
      _emitQa(BookingPageQaEvent.legacyContract);
    }
    final decoded = await _transport(
      request: request,
      limit: limit,
      headers: headers,
    );
    return parseBookingListPagePayload(
      decoded,
      request: request,
      limitUsed: limit,
    );
  }

  void invalidate({
    String? tenantId,
    String? companyId,
    String? driverId,
    BookingListActor? actor,
  }) {
    _emitQa(BookingPageQaEvent.invalidated);
    final tenant = (tenantId ?? '').trim();
    final company = (companyId ?? '').trim();
    final driver = (driverId ?? '').trim();
    if (tenant.isEmpty && company.isEmpty && driver.isEmpty && actor == null) {
      invalidateAll(emitQa: false);
      return;
    }
    bool matches(String key) {
      final parts = key.split('|');
      if (parts.length < 5) return false;
      if (actor != null && parts[0] != actor.name) return false;
      if (tenant.isNotEmpty && parts[1] != tenant) return false;
      if (company.isNotEmpty && parts[2] != company) return false;
      if (driver.isNotEmpty && parts[3] != driver) return false;
      return true;
    }

    _cache.removeWhere((key, _) => matches(key));
    _inFlight.removeWhere((key, _) => matches(key));
    _contractByScope.removeWhere((key, _) => matches(key));
  }

  void invalidateAll({bool emitQa = true}) {
    if (emitQa) _emitQa(BookingPageQaEvent.invalidated);
    _cache.clear();
    _inFlight.clear();
    _contractByScope.clear();
  }

  void resetForTest() {
    _cache.clear();
    _inFlight.clear();
    _contractByScope.clear();
  }

  bool hasFreshCache(BookingListPageRequest request, {DateTime? now}) {
    final cached = _cache[request.cacheKey];
    if (cached == null) return false;
    return (now ?? this.now()).difference(cached.fetchedAt) < ttl;
  }

  BookingListContractKind? cachedContract(BookingListPageRequest request) {
    return _contractByScope[request.scopeKey];
  }
}

BookingListPageRepository? _bookingListPageRepository;

/// Process-wide repository. Transport is bound lazily so library init cannot
/// cycle through `app_config.dart`.
BookingListPageRepository get bookingListPageRepository {
  return _bookingListPageRepository ??= BookingListPageRepository(
    transport: loadBookingListPageUncached,
  );
}

void bindBookingListPageRepositoryForTest(BookingListPageRepository repo) {
  _bookingListPageRepository = repo;
}

void resetBookingListPageRepositoryForTest() {
  _bookingListPageRepository?.resetForTest();
}

/// Set by [booking_list_page_http.dart] to avoid importing HTTP from tests
/// that only exercise the cache.
BookingListPageTransport loadBookingListPageUncached =
    _missingBookingListPageTransport;

Future<Map<String, dynamic>> _missingBookingListPageTransport({
  required BookingListPageRequest request,
  required int limit,
  required Future<Map<String, String>> Function() headers,
}) {
  throw BookingListPageException('booking_list_transport_unbound');
}
