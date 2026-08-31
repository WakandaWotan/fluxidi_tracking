import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/booking_documents_page_repository.dart';
import 'package:fluxidi_tracking/company/booking_documents_presentation.dart';

void main() {
  late DateTime now;
  late int networkCalls;
  late BookingDocumentsPageRepository repo;
  late Map<String, Map<String, dynamic>> responses;

  BookingDocumentsPageRequest req({
    String tenant = 't-a',
    String company = 'c-a',
    String booking = 'b-1',
  }) {
    return BookingDocumentsPageRequest(
      tenantId: tenant,
      companyId: company,
      bookingId: booking,
    );
  }

  Map<String, dynamic> envelope(List<String> ids) {
    return <String, dynamic>{
      'ok': true,
      'documents': [
        for (final id in ids)
          <String, dynamic>{
            'document_id': id,
            'document_type': 'invoice',
            'fluxidi_sale_kind': 'consumer_sale',
            'active_payable_revenue': true,
          },
      ],
      'count': ids.length,
      'active_payable_count': ids.length,
    };
  }

  Future<Map<String, String>> headers() async => const <String, String>{
    'Accept': 'application/json',
  };

  setUp(() {
    now = DateTime.utc(2026, 8, 31, 12, 0, 0);
    networkCalls = 0;
    responses = <String, Map<String, dynamic>>{};
    repo = BookingDocumentsPageRepository(
      clock: () => now,
      transport:
          ({
            required BookingDocumentsPageRequest request,
            required Future<Map<String, String>> Function() headers,
          }) async {
            networkCalls += 1;
            await headers();
            final hit = responses[request.cacheKey];
            if (hit != null) return hit;
            throw BookingDocumentsPageException('missing_fixture');
          },
    );
  });

  test('25 collapsed rows perform zero document GETs', () {
    expect(bookingDocumentsFetchOnListMount(), isFalse);
    expect(networkCalls, 0);
    for (var i = 0; i < 25; i++) {
      expect(repo.hasFreshCache(req(booking: 'b-$i')), isFalse);
    }
    expect(networkCalls, 0);
  });

  test('expand one row performs one GET', () async {
    responses[req().cacheKey] = envelope(<String>['doc-1']);
    await repo.fetch(request: req(), headers: headers);
    expect(networkCalls, 1);
  });

  test('collapse/reopen inside TTL performs zero extra GETs', () async {
    responses[req().cacheKey] = envelope(<String>['doc-1']);
    await repo.fetch(request: req(), headers: headers);
    await repo.fetch(request: req(), headers: headers);
    expect(networkCalls, 1);
  });

  test('concurrent expansion coalesces to one GET', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    repo = BookingDocumentsPageRepository(
      clock: () => now,
      transport:
          ({
            required BookingDocumentsPageRequest request,
            required Future<Map<String, String>> Function() headers,
          }) async {
            networkCalls += 1;
            started.complete();
            await release.future;
            return envelope(<String>['doc-1']);
          },
    );
    final first = repo.fetch(request: req(), headers: headers);
    await started.future;
    final second = repo.fetch(request: req(), headers: headers);
    release.complete();
    await Future.wait(<Future<void>>[first, second]);
    expect(networkCalls, 1);
  });

  test('affected mutation refreshes only that booking', () async {
    responses[req(booking: 'b-1').cacheKey] = envelope(<String>['doc-1']);
    responses[req(booking: 'b-2').cacheKey] = envelope(<String>['doc-2']);
    await repo.fetch(
      request: req(booking: 'b-1'),
      headers: headers,
    );
    await repo.fetch(
      request: req(booking: 'b-2'),
      headers: headers,
    );
    expect(networkCalls, 2);
    repo.invalidateBookingDocuments(
      tenantId: 't-a',
      companyId: 'c-a',
      bookingId: 'b-1',
    );
    await repo.fetch(
      request: req(booking: 'b-1'),
      headers: headers,
      forceRefresh: true,
      reason: BookingDocumentsPageReason.mutation,
    );
    expect(networkCalls, 3);
    await repo.fetch(
      request: req(booking: 'b-2'),
      headers: headers,
    );
    expect(networkCalls, 3);
  });

  test('failures are not cached as healthy empty', () async {
    try {
      await repo.fetch(request: req(), headers: headers);
      fail('expected throw');
    } catch (_) {}
    expect(repo.hasFreshCache(req()), isFalse);
    responses[req().cacheKey] = envelope(<String>['doc-1']);
    await repo.fetch(request: req(), headers: headers);
    expect(networkCalls, 2);
  });

  test(
    'duplicates merge and consumer inject cannot create a second payable',
    () {
      final merged = mergeBookingDocumentsByFiscalIdentity(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'document_id': 'doc-1',
            'fiscal_identity': 'doc-1',
            'fluxidi_sale_kind': 'consumer_sale',
          },
          <String, dynamic>{
            'document_id': 'doc-1',
            'fiscal_identity': 'doc-1',
            'fluxidi_sale_kind': 'consumer_sale',
          },
        ],
      );
      expect(merged.length, 1);
      expect(
        shouldInjectLocalIssuedDocument(
          localDocumentId: 'doc-local',
          localSaleKind: 'business_invoice',
          visibleDocuments: merged,
        ),
        isFalse,
      );
      expect(countActivePayableBookingDocuments(merged), 1);
    },
  );

  test('QA logs never include production identifiers', () {
    expect(
      formatBookingDocumentsQaLog(BookingDocumentsQaEvent.networkFetch),
      '[BOOKING_DOCUMENTS] booking_documents_network_fetch',
    );
    expect(
      formatBookingDocumentsQaLog('tenant_secret'),
      '[BOOKING_DOCUMENTS] booking_documents_network_fetch',
    );
    final failLines = <String>[];
    logBookingDocumentsFailure(
      stage: 'envelope',
      error: BookingDocumentsPageException('invalid_payload'),
      sink: failLines.add,
    );
    logBookingDocumentsFailure(
      stage: 'booking_secret_id',
      error: StateError('tenant=acme booking=pln-1'),
      sink: failLines.add,
    );
    expect(
      failLines.first,
      '[BOOKING_DOCUMENTS] fail stage=envelope type=BookingDocumentsPageException code=invalid_payload',
    );
    expect(failLines.last, contains('stage=unknown'));
    expect(failLines.join('\n'), isNot(contains('tenant')));
    expect(failLines.join('\n'), isNot(contains('booking')));
    expect(failLines.join('\n'), isNot(contains('pln-1')));
    expect(failLines.join('\n'), isNot(contains('acme')));
    expect(failLines.join('\n'), isNot(contains('secret')));
  });

  test('Worker warnings array does not fail materialization', () {
    final decoded = <String, dynamic>{
      'ok': true,
      'documents': <Map<String, dynamic>>[
        <String, dynamic>{
          'document_id': 'doc-1',
          'fluxidi_sale_kind': 'consumer_sale',
          'active_payable_revenue': true,
        },
        <String, dynamic>{'document_id': 'doc-2', 'document_type': 'invoice'},
      ],
      'count': 2,
      'warnings': <dynamic>[],
      'active_payable_count': 2,
      'review_required': true,
    };
    final result = parseBookingDocumentsPagePayload(decoded, request: req());
    expect(result.documents, hasLength(2));
    expect(result.reviewRequired, isTrue);
    expect(result.activePayableCount, 2);
  });

  test('materialization failure is not cached as healthy empty', () async {
    responses[req().cacheKey] = <String, dynamic>{'ok': true, 'count': 1};
    try {
      await repo.fetch(request: req(), headers: headers);
      fail('expected envelope throw');
    } on BookingDocumentsPageException catch (error) {
      expect(error.code, 'invalid_payload');
    }
    expect(repo.hasFreshCache(req()), isFalse);
    expect(repo.cachedResult(req()), isNull);
    responses[req().cacheKey] = envelope(<String>['doc-1']);
    final recovered = await repo.fetch(request: req(), headers: headers);
    expect(recovered.documents, hasLength(1));
    expect(networkCalls, 2);
  });

  test('Retry forceRefresh performs exactly one GET', () async {
    responses[req().cacheKey] = envelope(<String>['doc-1']);
    await repo.fetch(request: req(), headers: headers);
    expect(networkCalls, 1);
    await repo.fetch(
      request: req(),
      headers: headers,
      forceRefresh: true,
      reason: BookingDocumentsPageReason.retry,
    );
    expect(networkCalls, 2);
    await repo.fetch(request: req(), headers: headers);
    expect(networkCalls, 2);
  });

  test('repeated Retry taps coalesce to one GET', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    repo = BookingDocumentsPageRepository(
      clock: () => now,
      transport:
          ({
            required BookingDocumentsPageRequest request,
            required Future<Map<String, String>> Function() headers,
          }) async {
            networkCalls += 1;
            if (!started.isCompleted) started.complete();
            await release.future;
            return envelope(<String>['doc-1']);
          },
    );
    final first = repo.fetch(
      request: req(),
      headers: headers,
      forceRefresh: true,
      reason: BookingDocumentsPageReason.retry,
    );
    await started.future;
    final second = repo.fetch(
      request: req(),
      headers: headers,
      forceRefresh: true,
      reason: BookingDocumentsPageReason.retry,
    );
    release.complete();
    await Future.wait(<Future<void>>[first, second]);
    expect(networkCalls, 1);
  });

  test('sign-out and company change invalidate the documents cache', () async {
    responses[req().cacheKey] = envelope(<String>['doc-1']);
    await repo.fetch(request: req(), headers: headers);
    expect(repo.hasFreshCache(req()), isTrue);
    repo.invalidateAll();
    expect(repo.hasFreshCache(req()), isFalse);
    await repo.fetch(request: req(), headers: headers);
    expect(networkCalls, 2);
    repo.invalidateBookingDocuments(
      tenantId: 't-a',
      companyId: 'c-a',
      bookingId: 'b-1',
    );
    expect(repo.hasFreshCache(req()), isFalse);
  });

  test('existing visible documents survive a failed refresh', () {
    final previous = <Map<String, dynamic>>[
      <String, dynamic>{
        'document_id': 'doc-1',
        'fluxidi_sale_kind': 'consumer_sale',
      },
    ];
    final retained = bookingDocumentsUiAfterFailedRefresh(
      existingDocuments: previous,
      wasLoaded: true,
    );
    expect(retained.documents, hasLength(1));
    expect(retained.documents.single['document_id'], 'doc-1');
    expect(retained.error, isTrue);
    expect(retained.loaded, isTrue);
    expect(retained.loading, isFalse);
  });
}
