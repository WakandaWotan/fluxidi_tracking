// LIMOUSINE-MARKETPLACE-P2D1 — company inbox/detail/respond HTTP client.
// Uses the existing company session + admin explicit scope helpers. Never logs
// tokens, status_ref, acceptance_reference or raw records.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';
import 'limousine_quote_inbox.dart';

abstract class LimousineQuoteInboxGateway {
  Future<LimousineQuoteInboxPageData> list({
    int pageSize = kLimousineQuoteInboxPageDefault,
    String? state,
    String? cursor,
    String? updatedSince,
    String? tenantId,
    String? companyId,
  });

  Future<LimousineQuoteRequest> detail(
    String quoteRequestId, {
    String? tenantId,
    String? companyId,
  });

  Future<LimousineQuoteRespondResult> respond({
    required String quoteRequestId,
    required String action,
    required int expectedRevision,
    Map<String, dynamic>? quote,
    LimousineDeclineDraft? decline,
    String? tenantId,
    String? companyId,
  });
}

class HttpLimousineQuoteInboxGateway implements LimousineQuoteInboxGateway {
  HttpLimousineQuoteInboxGateway({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<http.Response> _get(Uri uri, Map<String, String> headers) {
    final client = _client;
    if (client != null) {
      return client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));
    }
    return http.get(uri, headers: headers).timeout(const Duration(seconds: 12));
  }

  Future<http.Response> _post(
    Uri uri,
    Map<String, String> headers,
    String body,
  ) {
    final client = _client;
    if (client != null) {
      return client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 15));
    }
    return http
        .post(uri, headers: headers, body: body)
        .timeout(const Duration(seconds: 15));
  }

  @override
  Future<LimousineQuoteInboxPageData> list({
    int pageSize = kLimousineQuoteInboxPageDefault,
    String? state,
    String? cursor,
    String? updatedSince,
    String? tenantId,
    String? companyId,
  }) async {
    final bounded = pageSize < 1
        ? kLimousineQuoteInboxPageDefault
        : (pageSize > kLimousineQuoteInboxPageMax
              ? kLimousineQuoteInboxPageMax
              : pageSize);
    final query = <String, String>{
      'page_size': '$bounded',
      if ((state ?? '').trim().isNotEmpty) 'state': state!.trim(),
      if (opaqueLimousineInboxCursor(cursor) != null)
        'cursor': opaqueLimousineInboxCursor(cursor)!,
      if ((updatedSince ?? '').trim().isNotEmpty)
        'updated_since': updatedSince!.trim(),
    };
    final endpoint = adminTenantCompanyScopedUri(
      Uri.parse(
        '${appConfig.bookingBaseUrl}/admin/limousine/quote-requests',
      ).replace(queryParameters: query),
      tenantId: tenantId,
      companyId: companyId,
    );
    final auth = await resolveCompanyOwnerAuthHeaders();
    try {
      final res = await _get(endpoint, auth.headers);
      final map = _decodeMap(res);
      _throwIfFailed(res.statusCode, map);
      return LimousineQuoteInboxPageData.fromJson(map);
    } on LimousineQuoteInboxException {
      rethrow;
    } catch (_) {
      throw const LimousineQuoteInboxException(
        kind: LimousineQuoteInboxErrorKind.network,
        code: 'network',
      );
    }
  }

  @override
  Future<LimousineQuoteRequest> detail(
    String quoteRequestId, {
    String? tenantId,
    String? companyId,
  }) async {
    final id = quoteRequestId.trim();
    if (id.isEmpty) {
      throw const LimousineQuoteInboxException(
        kind: LimousineQuoteInboxErrorKind.notFound,
        code: 'not_found',
      );
    }
    final endpoint = adminTenantCompanyScopedUri(
      Uri.parse(
        '${appConfig.bookingBaseUrl}/admin/limousine/quote-requests/$id',
      ),
      tenantId: tenantId,
      companyId: companyId,
    );
    final auth = await resolveCompanyOwnerAuthHeaders();
    try {
      final res = await _get(endpoint, auth.headers);
      final map = _decodeMap(res);
      _throwIfFailed(res.statusCode, map);
      final record = map['quote_request'];
      if (record is! Map) {
        throw const LimousineQuoteInboxException(
          kind: LimousineQuoteInboxErrorKind.invalid,
          code: 'invalid_response',
        );
      }
      return LimousineQuoteRequest.fromJson(record);
    } on LimousineQuoteInboxException {
      rethrow;
    } catch (_) {
      throw const LimousineQuoteInboxException(
        kind: LimousineQuoteInboxErrorKind.network,
        code: 'network',
      );
    }
  }

  @override
  Future<LimousineQuoteRespondResult> respond({
    required String quoteRequestId,
    required String action,
    required int expectedRevision,
    Map<String, dynamic>? quote,
    LimousineDeclineDraft? decline,
    String? tenantId,
    String? companyId,
  }) async {
    final scope = adminTenantCompanyScope(
      tenantId: tenantId,
      companyId: companyId,
    );
    final body = <String, dynamic>{
      ...scope,
      'quote_request_id': quoteRequestId.trim(),
      'action': action.trim().toLowerCase(),
      'expected_revision': expectedRevision,
    };
    if (action == 'quote' && quote != null) {
      body['quote'] = quote;
    }
    if (action == 'decline' && decline != null) {
      body.addAll(decline.toWorkerBody());
    }
    final endpoint = adminTenantCompanyScopedUri(
      Uri.parse(
        '${appConfig.bookingBaseUrl}/admin/limousine/quote-requests/respond',
      ),
      tenantId: tenantId,
      companyId: companyId,
    );
    final auth = await resolveCompanyOwnerAuthHeaders(json: true);
    try {
      final res = await _post(endpoint, auth.headers, jsonEncode(body));
      final map = _decodeMap(res);
      if (res.statusCode == 409) {
        final current = map['current_revision'] ?? map['currentRevision'];
        throw LimousineQuoteInboxException(
          kind: LimousineQuoteInboxErrorKind.staleRevision,
          code: (map['error'] ?? 'stale_revision').toString(),
          statusCode: 409,
          currentRevision: current is num
              ? current.toInt()
              : int.tryParse('$current'),
        );
      }
      _throwIfFailed(res.statusCode, map);
      final record = map['quote_request'];
      if (record is! Map) {
        throw const LimousineQuoteInboxException(
          kind: LimousineQuoteInboxErrorKind.invalid,
          code: 'invalid_response',
        );
      }
      return LimousineQuoteRespondResult(
        record: LimousineQuoteRequest.fromJson(record),
      );
    } on LimousineQuoteInboxException {
      rethrow;
    } catch (_) {
      throw const LimousineQuoteInboxException(
        kind: LimousineQuoteInboxErrorKind.network,
        code: 'network',
      );
    }
  }

  Map<String, dynamic> _decodeMap(http.Response res) {
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Body is not used beyond a safe error code.
    }
    return <String, dynamic>{};
  }

  void _throwIfFailed(int status, Map<String, dynamic> map) {
    if (status >= 200 && status < 300 && map['ok'] == true) return;
    final error = (map['error'] ?? '').toString().trim();
    final missingRaw = map['missing'];
    final missing = <String>[];
    if (missingRaw is List) {
      for (final item in missingRaw) {
        final text = item.toString().trim();
        if (text.isNotEmpty) missing.add(text);
      }
    }
    if (status == 401 || status == 403) {
      throw LimousineQuoteInboxException(
        kind: LimousineQuoteInboxErrorKind.session,
        code: error.isEmpty ? 'unauthorized' : error,
        statusCode: status,
      );
    }
    if (status == 404 && error == 'manual_quote_gate_off') {
      throw LimousineQuoteInboxException(
        kind: LimousineQuoteInboxErrorKind.gateOff,
        code: error,
        statusCode: status,
      );
    }
    if (status == 404) {
      throw LimousineQuoteInboxException(
        kind: LimousineQuoteInboxErrorKind.notFound,
        code: error.isEmpty ? 'not_found' : error,
        statusCode: status,
      );
    }
    if (status == 409 || error == 'stale_revision') {
      final current = map['current_revision'] ?? map['currentRevision'];
      throw LimousineQuoteInboxException(
        kind: LimousineQuoteInboxErrorKind.staleRevision,
        code: error.isEmpty ? 'stale_revision' : error,
        statusCode: status,
        currentRevision: current is num
            ? current.toInt()
            : int.tryParse('$current'),
      );
    }
    throw LimousineQuoteInboxException(
      kind: status == 400
          ? LimousineQuoteInboxErrorKind.invalid
          : LimousineQuoteInboxErrorKind.unknown,
      code: error.isEmpty ? 'request_failed' : error,
      statusCode: status,
      missing: missing,
    );
  }
}

class LimousineQuoteInboxController {
  LimousineQuoteInboxController({
    required this.gateway,
    this.pageSize = kLimousineQuoteInboxPageDefault,
  });

  final LimousineQuoteInboxGateway gateway;
  final int pageSize;

  int generation = 0;
  LimousineQuoteInboxFilter filter = LimousineQuoteInboxFilter.all;
  List<LimousineQuoteRequest> items = const <LimousineQuoteRequest>[];
  String? nextCursor;
  bool hasMore = false;
  bool loading = false;
  bool loadingMore = false;
  LimousineQuoteInboxException? error;
  LimousineQuoteRequest? detail;
  bool submitting = false;

  List<LimousineQuoteRequest> get visibleItems =>
      items.where((item) => filter.accepts(item.state)).toList(growable: false);

  Future<void> refresh() async {
    final gen = ++generation;
    loading = true;
    error = null;
    try {
      final page = await _loadMatchingPage(cursor: null, gen: gen);
      if (gen != generation) return;
      items = page.items;
      nextCursor = opaqueLimousineInboxCursor(page.nextCursor);
      hasMore = page.hasMore;
    } on LimousineQuoteInboxException catch (e) {
      if (gen != generation) return;
      error = e;
      items = const <LimousineQuoteRequest>[];
      nextCursor = null;
      hasMore = false;
    } finally {
      if (gen == generation) loading = false;
    }
  }

  Future<void> loadMore() async {
    if (loading || loadingMore || !hasMore) return;
    final cursor = opaqueLimousineInboxCursor(nextCursor);
    if (cursor == null) {
      hasMore = false;
      return;
    }
    final gen = generation;
    loadingMore = true;
    try {
      final page = await _loadMatchingPage(cursor: cursor, gen: gen);
      if (gen != generation) return;
      items = mergeLimousineInboxPages(existing: items, incoming: page.items);
      nextCursor = opaqueLimousineInboxCursor(page.nextCursor);
      hasMore = page.hasMore;
    } on LimousineQuoteInboxException catch (e) {
      if (gen != generation) return;
      error = e;
    } finally {
      if (gen == generation) loadingMore = false;
    }
  }

  Future<LimousineQuoteInboxPageData> _loadMatchingPage({
    required String? cursor,
    required int gen,
  }) async {
    var guard = 0;
    String? pageCursor = cursor;
    var accumulated = <LimousineQuoteRequest>[];
    var lastHasMore = false;
    String? lastNext;
    while (guard < 8) {
      if (gen != generation) {
        return LimousineQuoteInboxPageData(
          items: accumulated,
          nextCursor: lastNext,
          hasMore: lastHasMore,
        );
      }
      final page = await gateway.list(
        pageSize: pageSize,
        state: filter.serverState,
        cursor: pageCursor,
      );
      lastHasMore = page.hasMore;
      lastNext = page.nextCursor;
      final matched = page.items
          .where((item) => filter.accepts(item.state))
          .toList();
      accumulated = mergeLimousineInboxPages(
        existing: accumulated,
        incoming: matched,
      );
      if (accumulated.isNotEmpty || !page.hasMore) {
        return LimousineQuoteInboxPageData(
          items: accumulated,
          nextCursor: lastNext,
          hasMore: lastHasMore,
        );
      }
      pageCursor = opaqueLimousineInboxCursor(page.nextCursor);
      if (pageCursor == null) break;
      guard += 1;
    }
    return LimousineQuoteInboxPageData(
      items: accumulated,
      nextCursor: lastNext,
      hasMore: lastHasMore,
    );
  }

  Future<LimousineQuoteRequest?> openDetail(String id) async {
    final gen = generation;
    try {
      final record = await gateway.detail(id);
      if (gen != generation) return detail;
      detail = record;
      _replaceItem(record);
      return record;
    } on LimousineQuoteInboxException catch (e) {
      if (gen != generation) return detail;
      error = e;
      return null;
    }
  }

  Future<LimousineQuoteRespondResult> respond({
    required String action,
    required LimousineQuoteRequest record,
    Map<String, dynamic>? quote,
    LimousineDeclineDraft? decline,
  }) async {
    if (submitting) {
      throw const LimousineQuoteInboxException(
        kind: LimousineQuoteInboxErrorKind.invalid,
        code: 'in_flight',
      );
    }
    final gen = generation;
    submitting = true;
    try {
      final result = await gateway.respond(
        quoteRequestId: record.quoteRequestId,
        action: action,
        expectedRevision: record.revision,
        quote: quote,
        decline: decline,
      );
      if (gen != generation) return result;
      var next = result.record;
      if (next != null) {
        try {
          final fresh = await gateway.detail(next.quoteRequestId);
          if (gen == generation) next = next.mergeAuthoritative(fresh);
        } catch (_) {
          // Respond DTO remains authoritative when detail refresh fails.
        }
        if (gen == generation && next != null) {
          detail = detail == null ? next : detail!.mergeAuthoritative(next);
          _replaceItem(detail ?? next);
        }
      }
      return LimousineQuoteRespondResult(record: next ?? result.record);
    } on LimousineQuoteInboxException catch (e) {
      if (e.kind == LimousineQuoteInboxErrorKind.staleRevision) {
        try {
          final fresh = await gateway.detail(record.quoteRequestId);
          if (gen == generation) {
            detail = fresh;
            _replaceItem(fresh);
          }
        } catch (_) {}
      }
      rethrow;
    } finally {
      if (gen == generation) submitting = false;
    }
  }

  void _replaceItem(LimousineQuoteRequest record) {
    final next = <LimousineQuoteRequest>[];
    var found = false;
    for (final item in items) {
      if (item.quoteRequestId == record.quoteRequestId) {
        next.add(record);
        found = true;
      } else {
        next.add(item);
      }
    }
    if (!found) next.insert(0, record);
    items = next;
  }
}
