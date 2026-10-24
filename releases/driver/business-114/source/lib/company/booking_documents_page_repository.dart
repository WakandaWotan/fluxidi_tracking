// BOOKINGS-DOCUMENTS-BOUND-CLIENT-P0C
//
// Process-wide company booking-documents cache + single-flight.
// Documents are fetched only after an explicit expand/detail/mutation.
// The HTTP envelope is fully materialized before it is cached as healthy.
// Failures are never cached as healthy empty data. Tokens are never stored.
// QA logs never include tenant/company/booking identifiers.

import 'package:fluxidi_tracking/company/booking_documents_presentation.dart';
import 'package:fluxidi_tracking/payment/consumer_sale_presentation.dart';

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

const Set<String> kBookingDocumentsFailureStages = <String>{
  'envelope',
  'row_materialization',
  'presentation',
  'transport',
  'cache',
};

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

String _sanitizeBookingDocumentsToken(String raw) {
  return raw.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
}

String formatBookingDocumentsFailureLog({
  required String stage,
  required Object error,
}) {
  final safeStage = kBookingDocumentsFailureStages.contains(stage)
      ? stage
      : 'unknown';
  final safeType = _sanitizeBookingDocumentsToken(error.runtimeType.toString());
  final rawCode = error is BookingDocumentsPageException ? error.code : '';
  final safeCode = _sanitizeBookingDocumentsToken(rawCode);
  final codePart = safeCode.isEmpty ? '' : ' code=$safeCode';
  return '[BOOKING_DOCUMENTS] fail stage=$safeStage type=$safeType$codePart';
}

void logBookingDocumentsFailure({
  required String stage,
  required Object error,
  void Function(String line)? sink,
}) {
  final line = formatBookingDocumentsFailureLog(stage: stage, error: error);
  if (sink != null) {
    sink(line);
    return;
  }
  // ignore: avoid_print
  print(line);
}

class BookingDocumentsLoadUiState<T> {
  const BookingDocumentsLoadUiState({
    required this.documents,
    required this.error,
    required this.loaded,
    required this.loading,
  });

  final List<T> documents;
  final bool error;
  final bool loaded;
  final bool loading;
}

/// Keep already-visible rows when a refresh fails.
BookingDocumentsLoadUiState<T> bookingDocumentsUiAfterFailedRefresh<T>({
  required List<T> existingDocuments,
  required bool wasLoaded,
}) {
  return BookingDocumentsLoadUiState<T>(
    documents: List<T>.from(existingDocuments),
    error: true,
    loaded: existingDocuments.isNotEmpty || wasLoaded,
    loading: false,
  );
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
    this.omittedRowCount = 0,
    this.raw = const <String, dynamic>{},
  });

  final String cacheKey;
  final List<Map<String, dynamic>> documents;
  final int count;
  final int? activePayableCount;
  final bool reviewRequired;
  final List<String> warnings;
  final int omittedRowCount;
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

String _bookingDocumentsSafeErrorCode(Object? raw) {
  final text = _sanitizeBookingDocumentsToken((raw ?? '').toString());
  return text.isEmpty ? 'invalid_payload' : text;
}

int? _bookingDocumentsReadInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim());
  return null;
}

bool? _bookingDocumentsReadBool(Object? raw) {
  if (raw is bool) return raw;
  return null;
}

String _bookingDocumentsReadText(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final raw = json[key];
    if (raw == null || raw is Map || raw is List) continue;
    final text = raw.toString().trim();
    if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
  }
  return '';
}

Map<String, dynamic>? _bookingDocumentsAsStringKeyMap(Object? raw) {
  if (raw is! Map) return null;
  final out = <String, dynamic>{};
  raw.forEach((key, value) {
    out[key.toString()] = value;
  });
  return out;
}

void _bookingDocumentsAppendSanitizedWarnings(List<String> out, Object? raw) {
  if (raw is! List) return;
  for (final entry in raw) {
    if (entry is Map || entry is List) {
      out.add('warning');
      continue;
    }
    final safe = _sanitizeBookingDocumentsToken(entry.toString());
    if (safe.isNotEmpty) out.add(safe);
  }
}

Map<String, dynamic> _unspecifiedBookingDocumentRow(String identity) {
  return <String, dynamic>{
    'document_id': identity,
    'document_type': 'invoice',
    'document_number': '',
    'proof_reference': '',
    'lifecycle_state': '',
    'document_status': '',
    'issue_timestamp': '',
    'currency': '',
    'content_hash': '',
    'source_booking_id': '',
    'source_leg_id': '',
    'source_leg_type': '',
    'fluxidi_sale_kind': '',
    'invoice_intent': '',
    'created_by_role': '',
    'superseded': false,
    'presentation_label_key': 'invoiceNeutral',
    'fiscal_kind': 'unspecified',
    'fiscal_identity': identity,
    'active_payable_revenue': true,
  };
}

/// Materialize one Worker document row. Returns null only when the row has no
/// safe identity. Recoverable field mismatches become a neutral unspecified
/// invoice — never a silent business-invoice upgrade.
Map<String, dynamic>? materializeBookingDocumentRow(Object? entry) {
  final json = _bookingDocumentsAsStringKeyMap(entry);
  if (json == null) return null;
  final documentId = _bookingDocumentsReadText(json, const [
    'document_id',
    'documentId',
  ]);
  final fiscalIdentity = _bookingDocumentsReadText(json, const [
    'fiscal_identity',
    'fiscalIdentity',
  ]);
  final identity = fiscalIdentity.isNotEmpty ? fiscalIdentity : documentId;
  if (identity.isEmpty) return null;
  try {
    final saleKind = _bookingDocumentsReadText(json, const [
      'fluxidi_sale_kind',
      'fluxidiSaleKind',
      'sale_kind',
      'saleKind',
    ]);
    final documentType = _bookingDocumentsReadText(json, const [
      'document_type',
      'documentType',
    ]);
    final invoiceIntent = _bookingDocumentsReadText(json, const [
      'invoice_intent',
      'invoiceIntent',
    ]);
    final createdByRole = _bookingDocumentsReadText(json, const [
      'created_by_role',
      'createdByRole',
    ]);
    final presentationLabelKey = _bookingDocumentsReadText(json, const [
      'presentation_label_key',
      'presentationLabelKey',
    ]);
    final fiscalKindRaw = _bookingDocumentsReadText(json, const [
      'fiscal_kind',
      'fiscalKind',
    ]);
    final peppol =
        _bookingDocumentsReadBool(json['peppol_applicable']) ??
        _bookingDocumentsReadBool(json['peppolApplicable']);
    final labelKey = consumerOrBusinessDocumentLabelKey(
      saleKind: saleKind,
      documentType: documentType,
      invoiceIntent: invoiceIntent,
      createdByRole: createdByRole,
      peppolApplicable: peppol,
      presentationLabelKey: presentationLabelKey,
      fiscalKind: fiscalKindRaw,
    );
    final kind = resolveDocumentPresentationKind(
      saleKind: saleKind,
      documentType: documentType,
      invoiceIntent: invoiceIntent,
      createdByRole: createdByRole,
      peppolApplicable: peppol,
      presentationLabelKey: presentationLabelKey,
      fiscalKind: fiscalKindRaw,
    );
    final fiscalKind = switch (kind) {
      FluxidiDocumentPresentationKind.consumerSale => 'consumer_sale',
      FluxidiDocumentPresentationKind.businessInvoice => 'business_invoice',
      FluxidiDocumentPresentationKind.creditNote => 'credit_note',
      FluxidiDocumentPresentationKind.invoiceNeutral => 'unspecified',
    };
    final rawExport = json['billit_export'] ?? json['billitExport'];
    final billitExport = rawExport is Map
        ? _bookingDocumentsAsStringKeyMap(rawExport)
        : null;
    return <String, dynamic>{
      'document_id': documentId.isNotEmpty ? documentId : identity,
      'document_type': documentType,
      'document_number': _bookingDocumentsReadText(json, const [
        'document_number',
        'documentNumber',
      ]),
      'proof_reference': _bookingDocumentsReadText(json, const [
        'proof_reference',
        'proofReference',
      ]),
      'lifecycle_state': _bookingDocumentsReadText(json, const [
        'lifecycle_state',
        'lifecycleState',
      ]),
      'document_status': _bookingDocumentsReadText(json, const [
        'document_status',
        'documentStatus',
      ]),
      'issue_timestamp': _bookingDocumentsReadText(json, const [
        'issue_timestamp',
        'issueTimestamp',
      ]),
      'currency': _bookingDocumentsReadText(json, const ['currency']),
      'content_hash': _bookingDocumentsReadText(json, const [
        'content_hash',
        'contentHash',
      ]),
      'source_booking_id': _bookingDocumentsReadText(json, const [
        'source_booking_id',
        'sourceBookingId',
      ]),
      'source_leg_id': _bookingDocumentsReadText(json, const [
        'source_leg_id',
        'sourceLegId',
      ]),
      'source_leg_type': _bookingDocumentsReadText(json, const [
        'source_leg_type',
        'sourceLegType',
      ]),
      'fluxidi_sale_kind': saleKind,
      'peppol_applicable': peppol,
      'invoice_intent': invoiceIntent,
      'created_by_role': createdByRole,
      'superseded': json['superseded'] == true,
      'presentation_label_key': labelKey,
      'fiscal_kind': fiscalKind,
      'fiscal_identity': identity,
      'active_payable_revenue': _bookingDocumentsReadBool(
        json['active_payable_revenue'],
      ),
      if (billitExport != null) 'billit_export': billitExport,
    };
  } catch (_) {
    return _unspecifiedBookingDocumentRow(identity);
  }
}

BookingDocumentsPageResult parseBookingDocumentsPagePayload(
  Map<String, dynamic> decoded, {
  required BookingDocumentsPageRequest request,
}) {
  if (decoded['ok'] != true) {
    throw BookingDocumentsPageException(
      _bookingDocumentsSafeErrorCode(decoded['error']),
    );
  }
  final rawDocs = decoded['documents'];
  if (rawDocs is! List) {
    throw BookingDocumentsPageException('invalid_payload');
  }
  final documents = <Map<String, dynamic>>[];
  final warnings = <String>[];
  _bookingDocumentsAppendSanitizedWarnings(warnings, decoded['warnings']);
  var omittedRowCount = 0;
  for (final entry in rawDocs) {
    final row = materializeBookingDocumentRow(entry);
    if (row == null) {
      omittedRowCount += 1;
      warnings.add('row_omitted');
      continue;
    }
    documents.add(row);
  }
  final localPayable = countActivePayableBookingDocuments(documents);
  final workerPayable = _bookingDocumentsReadInt(
    decoded['active_payable_count'],
  );
  final reviewRequired =
      decoded['review_required'] == true ||
      localPayable > 1 ||
      (workerPayable != null && workerPayable > 1);
  return BookingDocumentsPageResult(
    cacheKey: request.cacheKey,
    documents: List<Map<String, dynamic>>.unmodifiable(documents),
    count: _bookingDocumentsReadInt(decoded['count']) ?? documents.length,
    activePayableCount: workerPayable ?? localPayable,
    reviewRequired: reviewRequired,
    warnings: List<String>.unmodifiable(warnings),
    omittedRowCount: omittedRowCount,
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
      try {
        listener();
      } catch (error) {
        logBookingDocumentsFailure(stage: 'presentation', error: error);
      }
    }
  }

  String _failureStageFor(Object error) {
    if (error is BookingDocumentsPageException &&
        (error.code.startsWith('http_') || error.code == 'transport_unbound')) {
      return 'transport';
    }
    return 'envelope';
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
      } catch (error) {
        if (identical(_inFlight[key], future)) {
          _cache.remove(key);
        }
        logBookingDocumentsFailure(
          stage: _failureStageFor(error),
          error: error,
        );
        rethrow;
      } finally {
        if (identical(_inFlight[key], future)) {
          _inFlight.remove(key);
        }
      }
    });
    _inFlight[key] = future;
    return future;
  }

  BookingDocumentsPageResult? cachedResult(
    BookingDocumentsPageRequest request,
  ) {
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
