// BOOKINGS-DOCUMENTS-BOUND-CLIENT-P0C
//
// Process-wide company booking-documents cache + single-flight.
// Documents are fetched only after an explicit expand/detail/mutation.
// Failures are never cached as healthy empty data. Tokens are never stored.
// QA logs never include tenant/company/booking identifiers.

const Duration kBookingDocumentsPageTtl = Duration(seconds: 45);

const String kBookingDocumentsCompanyPathPrefix = '/company/bookings/';
const String kBookingDocumentsCompanyPathSuffix = '/documents';

const bool kBookingDocumentsQaRequestLogging = bool.fromEnvironment(
  'FLUXIDI_QA_REQUEST_LOGGING',
  defaultValue: false,
);

abstract final class BookingDocumentsQaEvent {
  static const networkFetch = 'booking_documents_network_fetch';
  static const cacheHit = 'booking_documents_cache_hit';
  static const coalesced = 'booking_documents_coalesced';
  static const invalidated = 'booking_documents_invalidated';
}

const Set<String> kBookingDocumentsQaEvents = <String>{
  BookingDocumentsQaEvent.networkFetch,
  BookingDocumentsQaEvent.cacheHit,
  BookingDocumentsQaEvent.coalesced,
  BookingDocumentsQaEvent.invalidated,
};

String formatBookingDocumentsQaLog(String event) {
  final safe = kBookingDocumentsQaEvents.contains(event)
      ? event
      : BookingDocumentsQaEvent.networkFetch;
  return '[BOOKING_DOCUMENTS] $safe';
}

void logBookingDocumentsQa(
  String event, {
  bool enabled = kBookingDocumentsQaRequestLogging,
  void Function(String line)? sink,
}) {
  if (!enabled) return;
  final line = formatBookingDocumentsQaLog(event);
  if (sink != null) {
    sink(line);
    return;
  }
  // ignore: avoid_print
  print(line);
}

enum BookingDocumentsPageReason { expand, detail, mutation, retry }

/// Bounded GET outcome. [transport] never receives tokens from the cache.
typedef BookingDocumentsPageTransport =
    Future<Map<String, dynamic>> Function({
      required BookingDocumentsPageRequest request,
      required Future<Map<String, String>> Function() headers,
    });

class BookingDocumentsPageException implements Exception {
  BookingDocumentsPageException(this.code);
  final String code;

  @override
  String toString() => code;
}

class BookingDocumentsPageRequest {
  const BookingDocumentsPageRequest({
    required this.tenantId,
    required this.companyId,
    required this.bookingId,
    this.scopeQuery = const <String, String>{},
  });

  final String tenantId;
  final String companyId;
  final String bookingId;
  final Map<String, String> scopeQuery;

  String get cacheKey =>
      '${tenantId.trim()}|${companyId.trim()}|${bookingId.trim()}';

  String get path =>
      '$kBookingDocumentsCompanyPathPrefix${Uri.encodeComponent(bookingId.trim())}$kBookingDocumentsCompanyPathSuffix';
}

class BookingDocumentsPageResult {
  const BookingDocumentsPageResult({
    required this.cacheKey,
    required this.documents,
    required this.count,
    this.activePayableCount,
    this.reviewRequired = false,
    this.warnings = const <String>[],
    this.raw = const <String, dynamic>{},
  });

  final String cacheKey;
  final List<Map<String, dynamic>> documents;
  final int count;
  final int? activePayableCount;
  final bool reviewRequired;
  final List<String> warnings;
  final Map<String, dynamic> raw;
}

class _CachedBookingDocumentsPage {
  const _CachedBookingDocumentsPage({
    required this.result,
    required this.fetchedAt,
  });

  final BookingDocumentsPageResult result;
  final DateTime fetchedAt;
}

BookingDocumentsPageResult parseBookingDocumentsPagePayload(
  Map<String, dynamic> decoded, {
  required BookingDocumentsPageRequest request,
}) {
  if (decoded['ok'] != true) {
    throw BookingDocumentsPageException(
      (decoded['error'] ?? 'invalid_payload').toString(),
    );
  }
  final rawDocs = decoded['documents'];
  final documents = <Map<String, dynamic>>[];
  if (rawDocs is List) {
    for (final entry in rawDocs) {
      if (entry is Map) {
        documents.add(Map<String, dynamic>.from(entry));
      }
    }
  }
  final rawCount = decoded['count'];
  final count = rawCount is int ? rawCount : documents.length;
  final rawPayable = decoded['active_payable_count'];
  return BookingDocumentsPageResult(
    cacheKey: request.cacheKey,
    documents: List<Map<String, dynamic>>.unmodifiable(documents),
    count: count,
    activePayableCount: rawPayable is int ? rawPayable : null,
    reviewRequired: decoded['review_required'] == true,
    warnings: decoded['warnings'] is List
        ? decoded['warnings'].map((e) => e.toString()).toList(growable: false)
        : const <String>[],
    raw: Map<String, dynamic>.from(decoded),
  );
}

class BookingDocumentsPageRepository {
  BookingDocumentsPageRepository({
    required BookingDocumentsPageTransport transport,
    this.ttl = kBookingDocumentsPageTtl,
    DateTime Function()? clock,
    this.qaLogEnabled = kBookingDocumentsQaRequestLogging,
    void Function(String event)? qaLog,
  }) : _transport = transport,
       _clock = clock ?? DateTime.now,
       _qaLog = qaLog;

  final BookingDocumentsPageTransport _transport;
  final Duration ttl;
  final DateTime Function() _clock;
  final bool qaLogEnabled;
  final void Function(String event)? _qaLog;

  final Map<String, _CachedBookingDocumentsPage> _cache =
      <String, _CachedBookingDocumentsPage>{};
  final Map<String, Future<BookingDocumentsPageResult>> _inFlight =
      <String, Future<BookingDocumentsPageResult>>{};
  final List<void Function()> _listeners = <void Function()>[];

  DateTime now() => _clock();

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
  }

  void _emitQa(String event) {
    if (_qaLog != null) {
      if (qaLogEnabled) _qaLog(event);
      return;
    }
    logBookingDocumentsQa(event, enabled: qaLogEnabled);
  }

  Future<BookingDocumentsPageResult> fetch({
    required BookingDocumentsPageRequest request,
    required Future<Map<String, String>> Function() headers,
    bool forceRefresh = false,
    BookingDocumentsPageReason reason = BookingDocumentsPageReason.expand,
  }) {
    final key = request.cacheKey;
    if (forceRefresh) {
      _cache.remove(key);
    } else {
      final cached = _cache[key];
      if (cached != null && now().difference(cached.fetchedAt) < ttl) {
        _emitQa(BookingDocumentsQaEvent.cacheHit);
        return Future<BookingDocumentsPageResult>.value(cached.result);
      }
    }
    final existing = _inFlight[key];
    if (existing != null) {
      _emitQa(BookingDocumentsQaEvent.coalesced);
      return existing;
    }
    late final Future<BookingDocumentsPageResult> future;
    future = Future<BookingDocumentsPageResult>(() async {
      try {
        _emitQa(BookingDocumentsQaEvent.networkFetch);
        final decoded = await _transport(request: request, headers: headers);
        final result = parseBookingDocumentsPagePayload(
          decoded,
          request: request,
        );
        if (identical(_inFlight[key], future)) {
          _cache[key] = _CachedBookingDocumentsPage(
            result: result,
            fetchedAt: now(),
          );
          _notify();
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

  BookingDocumentsPageResult? cachedResult(BookingDocumentsPageRequest request) {
    final cached = _cache[request.cacheKey];
    if (cached == null) return null;
    if (now().difference(cached.fetchedAt) >= ttl) return null;
    return cached.result;
  }

  bool hasFreshCache(BookingDocumentsPageRequest request, {DateTime? now}) {
    final cached = _cache[request.cacheKey];
    if (cached == null) return false;
    return (now ?? this.now()).difference(cached.fetchedAt) < ttl;
  }

  void invalidateBookingDocuments({
    required String tenantId,
    required String companyId,
    required String bookingId,
  }) {
    final key = BookingDocumentsPageRequest(
      tenantId: tenantId,
      companyId: companyId,
      bookingId: bookingId,
    ).cacheKey;
    _cache.remove(key);
    _inFlight.remove(key);
    _emitQa(BookingDocumentsQaEvent.invalidated);
    _notify();
  }

  void invalidateAll({bool emitQa = true}) {
    if (emitQa) _emitQa(BookingDocumentsQaEvent.invalidated);
    _cache.clear();
    _inFlight.clear();
    _notify();
  }

  void resetForTest() {
    _cache.clear();
    _inFlight.clear();
    _listeners.clear();
  }
}

BookingDocumentsPageRepository? _bookingDocumentsPageRepository;

BookingDocumentsPageRepository get bookingDocumentsPageRepository {
  return _bookingDocumentsPageRepository ??= BookingDocumentsPageRepository(
    transport: loadBookingDocumentsPageUncached,
  );
}

void bindBookingDocumentsPageRepositoryForTest(
  BookingDocumentsPageRepository repo,
) {
  _bookingDocumentsPageRepository = repo;
}

void resetBookingDocumentsPageRepositoryForTest() {
  _bookingDocumentsPageRepository?.resetForTest();
}

BookingDocumentsPageTransport loadBookingDocumentsPageUncached =
    _missingBookingDocumentsPageTransport;

Future<Map<String, dynamic>> _missingBookingDocumentsPageTransport({
  required BookingDocumentsPageRequest request,
  required Future<Map<String, String>> Function() headers,
}) {
  throw BookingDocumentsPageException('transport_unbound');
}

/// Collapsed company-list rows never request documents.
bool bookingDocumentsFetchOnListMount() => false;
