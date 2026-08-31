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
      expect(
        repo.hasFreshCache(req(booking: 'b-$i')),
        isFalse,
      );
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
    await repo.fetch(request: req(booking: 'b-1'), headers: headers);
    await repo.fetch(request: req(booking: 'b-2'), headers: headers);
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
    await repo.fetch(request: req(booking: 'b-2'), headers: headers);
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

  test('duplicates merge and consumer inject cannot create a second payable', () {
    final merged = mergeBookingDocumentsByFiscalIdentity(<Map<String, dynamic>>[
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
    ]);
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
  });

  test('QA logs never include production identifiers', () {
    expect(formatBookingDocumentsQaLog(BookingDocumentsQaEvent.networkFetch),
        '[BOOKING_DOCUMENTS] booking_documents_network_fetch');
    expect(formatBookingDocumentsQaLog('tenant_secret'),
        '[BOOKING_DOCUMENTS] booking_documents_network_fetch');
  });
}
