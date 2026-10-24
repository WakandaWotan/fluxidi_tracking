import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/booking_list_page_repository.dart';

void main() {
  late DateTime now;
  late int networkCalls;
  late List<String> limits;
  late List<String> cursors;
  late BookingListPageRepository repo;
  late Map<String, Map<String, dynamic>> responses;

  BookingListPageRequest companyFirst({
    String tenant = 'co-a',
    String company = 'co-a',
    String cursor = '',
    BookingListHistoryMode historyMode = BookingListHistoryMode.history,
    String filterFingerprint = '',
  }) {
    return BookingListPageRequest(
      actor: BookingListActor.company,
      tenantId: tenant,
      companyId: company,
      historyMode: historyMode,
      cursor: cursor,
      filterFingerprint: filterFingerprint,
    );
  }

  BookingListPageRequest driverFirst({
    String tenant = 'co-a',
    String company = 'co-a',
    String driver = 'drv-a',
    String cursor = '',
  }) {
    return BookingListPageRequest(
      actor: BookingListActor.driver,
      tenantId: tenant,
      companyId: company,
      driverId: driver,
      historyMode: BookingListHistoryMode.active,
      cursor: cursor,
    );
  }

  Map<String, dynamic> projectedPage({
    required List<String> ids,
    bool hasMore = false,
    String? nextCursor,
    int? totalCount,
  }) {
    return <String, dynamic>{
      'ok': true,
      'items': [
        for (final id in ids) <String, dynamic>{'booking_id': id, 'id': id},
      ],
      'count': ids.length,
      'has_more': hasMore,
      'next_cursor': nextCursor,
      if (totalCount != null) 'total_count': totalCount,
    };
  }

  Map<String, dynamic> legacyPage(List<String> ids) {
    return <String, dynamic>{
      'ok': true,
      'items': [
        for (final id in ids) <String, dynamic>{'booking_id': id, 'id': id},
      ],
      'count': ids.length,
    };
  }

  Future<Map<String, String>> headers() async => const <String, String>{
    'Accept': 'application/json',
  };

  setUp(() {
    now = DateTime.utc(2026, 8, 31, 12, 0, 0);
    networkCalls = 0;
    limits = <String>[];
    cursors = <String>[];
    responses = <String, Map<String, dynamic>>{};
    repo = BookingListPageRepository(
      clock: () => now,
      transport:
          ({
            required BookingListPageRequest request,
            required int limit,
            required Future<Map<String, String>> Function() headers,
          }) async {
            networkCalls += 1;
            limits.add('$limit');
            cursors.add(request.cursor);
            await headers();
            final key = '${request.cacheKey}|$limit';
            final hit = responses[key] ?? responses[request.cacheKey];
            if (hit != null) return hit;
            throw BookingListPageException('missing_fixture');
          },
    );
  });

  test('first page requests 25 on the projected contract', () async {
    responses[companyFirst().cacheKey] = projectedPage(
      ids: <String>['b1', 'b2'],
      hasMore: true,
      nextCursor: 'cursor-2',
    );
    final page = await repo.fetch(request: companyFirst(), headers: headers);
    expect(networkCalls, 1);
    expect(limits, <String>['25']);
    expect(page.items.length, 2);
    expect(page.count, 2);
    expect(page.totalCount, isNull);
    expect(page.hasMore, isTrue);
    expect(page.nextCursor, 'cursor-2');
    expect(page.contract, BookingListContractKind.projected);
  });

  test('has_more=true exposes load-more only with a real cursor', () {
    expect(
      bookingListShowsLoadMore(
        contract: BookingListContractKind.projected,
        hasMore: true,
        nextCursor: 'cursor-2',
      ),
      isTrue,
    );
    expect(
      bookingListShowsLoadMore(
        contract: BookingListContractKind.projected,
        hasMore: true,
        nextCursor: '',
      ),
      isFalse,
    );
    expect(
      bookingListShowsLoadMore(
        contract: BookingListContractKind.legacy,
        hasMore: true,
        nextCursor: 'nope',
      ),
      isFalse,
    );
  });

  test('one load-more produces exactly one cursor request', () async {
    responses[companyFirst().cacheKey] = projectedPage(
      ids: <String>['b1'],
      hasMore: true,
      nextCursor: 'cursor-2',
    );
    responses[companyFirst(cursor: 'cursor-2').cacheKey] = projectedPage(
      ids: <String>['b2'],
    );
    await repo.fetch(request: companyFirst(), headers: headers);
    await repo.fetch(
      request: companyFirst(cursor: 'cursor-2'),
      headers: headers,
      reason: BookingListPageReason.nextPage,
    );
    expect(networkCalls, 2);
    expect(cursors, <String>['', 'cursor-2']);
    expect(limits, <String>['25', '25']);
  });

  test('has_more=false produces no further request', () async {
    responses[companyFirst().cacheKey] = projectedPage(ids: <String>['b1']);
    final page = await repo.fetch(request: companyFirst(), headers: headers);
    expect(page.hasMore, isFalse);
    expect(
      bookingListShowsLoadMore(
        contract: page.contract,
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
      ),
      isFalse,
    );
    expect(networkCalls, 1);
  });

  test('multiple pages preserve stable order and drop duplicates', () {
    final merged = mergeBookingListPages(
      previous: <Map<String, dynamic>>[
        <String, dynamic>{'booking_id': 'b1'},
        <String, dynamic>{'booking_id': 'b2', 'leg_id': 'L1'},
      ],
      incoming: <Map<String, dynamic>>[
        <String, dynamic>{'booking_id': 'b2', 'leg_id': 'L1'},
        <String, dynamic>{'booking_id': 'b3'},
      ],
    );
    expect(merged.map(bookingListRowDedupeKey).toList(), <String>[
      'b1',
      'b2:L1',
      'b3',
    ]);
  });

  test('never fabricates has_more from items.length', () {
    final parsed = parseBookingListPagePayload(
      <String, dynamic>{
        'ok': true,
        'items': List<Map<String, dynamic>>.generate(
          25,
          (i) => <String, dynamic>{'booking_id': 'b$i'},
        ),
        'count': 25,
      },
      request: companyFirst(),
      limitUsed: 25,
    );
    expect(parsed.contract, BookingListContractKind.legacy);
    expect(parsed.hasMore, isFalse);
    expect(parsed.nextCursor, isNull);
  });

  test('30 concurrent first-page callers share one network request', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    repo = BookingListPageRepository(
      clock: () => now,
      transport:
          ({
            required BookingListPageRequest request,
            required int limit,
            required Future<Map<String, String>> Function() headers,
          }) async {
            networkCalls += 1;
            if (!started.isCompleted) started.complete();
            await release.future;
            return projectedPage(ids: <String>['b1']);
          },
    );
    final futures = List<Future<BookingListPageResult>>.generate(
      30,
      (_) => repo.fetch(request: companyFirst(), headers: headers),
    );
    await started.future;
    release.complete();
    final results = await Future.wait(futures);
    expect(networkCalls, 1);
    expect(
      results,
      everyElement(
        predicate<BookingListPageResult>((p) => p.items.length == 1),
      ),
    );
  });

  test('30 concurrent cursor callers share one network request', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final req = companyFirst(cursor: 'cursor-2');
    repo = BookingListPageRepository(
      clock: () => now,
      transport:
          ({
            required BookingListPageRequest request,
            required int limit,
            required Future<Map<String, String>> Function() headers,
          }) async {
            networkCalls += 1;
            cursors.add(request.cursor);
            if (!started.isCompleted) started.complete();
            await release.future;
            return projectedPage(ids: <String>['b2']);
          },
    );
    final futures = List<Future<BookingListPageResult>>.generate(
      30,
      (_) => repo.fetch(
        request: req,
        headers: headers,
        reason: BookingListPageReason.nextPage,
      ),
    );
    await started.future;
    release.complete();
    final results = await Future.wait(futures);
    expect(networkCalls, 1);
    expect(cursors, <String>['cursor-2']);
    expect(results.length, 30);
  });

  test('rebuild / route return / tab switch inside TTL → zero extra', () async {
    responses[companyFirst().cacheKey] = projectedPage(ids: <String>['b1']);
    await repo.fetch(request: companyFirst(), headers: headers);
    await repo.fetch(request: companyFirst(), headers: headers);
    await repo.fetch(request: companyFirst(), headers: headers);
    expect(networkCalls, 1);
  });

  test('expiry → one new request', () async {
    responses[companyFirst().cacheKey] = projectedPage(ids: <String>['b1']);
    await repo.fetch(request: companyFirst(), headers: headers);
    now = now.add(const Duration(seconds: 46));
    await repo.fetch(request: companyFirst(), headers: headers);
    expect(networkCalls, 2);
  });

  test('manual refresh → one new request', () async {
    responses[companyFirst().cacheKey] = projectedPage(ids: <String>['b1']);
    await repo.fetch(request: companyFirst(), headers: headers);
    await repo.fetch(
      request: companyFirst(),
      headers: headers,
      forceRefresh: true,
      reason: BookingListPageReason.manualRefresh,
    );
    expect(networkCalls, 2);
  });

  test('company change → separate request', () async {
    responses[companyFirst().cacheKey] = projectedPage(ids: <String>['a']);
    responses[companyFirst(tenant: 'co-b', company: 'co-b').cacheKey] =
        projectedPage(ids: <String>['b']);
    await repo.fetch(request: companyFirst(), headers: headers);
    await repo.fetch(
      request: companyFirst(tenant: 'co-b', company: 'co-b'),
      headers: headers,
    );
    expect(networkCalls, 2);
  });

  test('driver change → separate request', () async {
    responses[driverFirst().cacheKey] = projectedPage(ids: <String>['a']);
    responses[driverFirst(driver: 'drv-b').cacheKey] = projectedPage(
      ids: <String>['b'],
    );
    await repo.fetch(request: driverFirst(), headers: headers);
    await repo.fetch(
      request: driverFirst(driver: 'drv-b'),
      headers: headers,
    );
    expect(networkCalls, 2);
  });

  test('late old-company result is ignored by scope key', () async {
    final oldReq = companyFirst();
    final newReq = companyFirst(tenant: 'co-b', company: 'co-b');
    responses[oldReq.cacheKey] = projectedPage(ids: <String>['old']);
    responses[newReq.cacheKey] = projectedPage(ids: <String>['new']);
    final old = await repo.fetch(request: oldReq, headers: headers);
    final next = await repo.fetch(request: newReq, headers: headers);
    expect(old.scopeKey == next.scopeKey, isFalse);
    expect(next.scopeKey.contains('co-b'), isTrue);
    expect(next.items.single['booking_id'], 'new');
  });

  test('sign-out clears cache', () async {
    responses[companyFirst().cacheKey] = projectedPage(ids: <String>['b1']);
    await repo.fetch(request: companyFirst(), headers: headers);
    expect(repo.hasFreshCache(companyFirst()), isTrue);
    repo.invalidateAll();
    expect(repo.hasFreshCache(companyFirst()), isFalse);
    await repo.fetch(request: companyFirst(), headers: headers);
    expect(networkCalls, 2);
  });

  test('successful mutation invalidates affected scope only', () async {
    responses[companyFirst().cacheKey] = projectedPage(ids: <String>['a']);
    responses[companyFirst(tenant: 'co-b', company: 'co-b').cacheKey] =
        projectedPage(ids: <String>['b']);
    await repo.fetch(request: companyFirst(), headers: headers);
    await repo.fetch(
      request: companyFirst(tenant: 'co-b', company: 'co-b'),
      headers: headers,
    );
    repo.invalidate(tenantId: 'co-a', companyId: 'co-a');
    await repo.fetch(request: companyFirst(), headers: headers);
    await repo.fetch(
      request: companyFirst(tenant: 'co-b', company: 'co-b'),
      headers: headers,
    );
    expect(networkCalls, 3);
  });

  test(
    'legacy missing pagination fields triggers one compatible request',
    () async {
      repo = BookingListPageRepository(
        clock: () => now,
        transport:
            ({
              required BookingListPageRequest request,
              required int limit,
              required Future<Map<String, String>> Function() headers,
            }) async {
              networkCalls += 1;
              limits.add('$limit');
              return legacyPage(
                List<String>.generate(limit == 200 ? 40 : 25, (i) => 'L$i'),
              );
            },
      );
      final page = await repo.fetch(request: companyFirst(), headers: headers);
      expect(limits, <String>['25', '200']);
      expect(page.contract, BookingListContractKind.legacy);
      expect(page.items.length, 40);
      expect(page.hasMore, isFalse);
      expect(page.nextCursor, isNull);
      await repo.fetch(request: companyFirst(), headers: headers);
      expect(networkCalls, 2);
    },
  );

  test('legacy failure is not cached as healthy empty', () async {
    var shouldFail = true;
    repo = BookingListPageRepository(
      clock: () => now,
      transport:
          ({
            required BookingListPageRequest request,
            required int limit,
            required Future<Map<String, String>> Function() headers,
          }) async {
            networkCalls += 1;
            if (shouldFail) {
              shouldFail = false;
              throw BookingListPageException('load_failed');
            }
            return legacyPage(<String>['ok']);
          },
    );
    await expectLater(
      repo.fetch(request: companyFirst(), headers: headers),
      throwsA(isA<BookingListPageException>()),
    );
    expect(repo.hasFreshCache(companyFirst()), isFalse);
    final recovered = await repo.fetch(
      request: companyFirst(),
      headers: headers,
    );
    expect(recovered.items.single['booking_id'], 'ok');
    expect(networkCalls, 3);
  });

  test('refresh performs exactly one first-page request', () async {
    responses[companyFirst().cacheKey] = projectedPage(
      ids: <String>['b1'],
      hasMore: true,
      nextCursor: 'cursor-2',
    );
    await repo.fetch(
      request: companyFirst(),
      headers: headers,
      forceRefresh: true,
      reason: BookingListPageReason.manualRefresh,
    );
    expect(networkCalls, 1);
    expect(cursors, <String>['']);
    expect(limits, <String>['25']);
  });

  test('manual retry requests only the failed cursor', () async {
    responses[companyFirst(cursor: 'cursor-2').cacheKey] = projectedPage(
      ids: <String>['b2'],
    );
    await repo.fetch(
      request: companyFirst(cursor: 'cursor-2'),
      headers: headers,
      reason: BookingListPageReason.nextPage,
    );
    expect(networkCalls, 1);
    expect(cursors, <String>['cursor-2']);
  });

  test('projected Worker response ends the sticky legacy path', () async {
    var wave = 0;
    repo = BookingListPageRepository(
      clock: () => now,
      transport:
          ({
            required BookingListPageRequest request,
            required int limit,
            required Future<Map<String, String>> Function() headers,
          }) async {
            networkCalls += 1;
            limits.add('$limit');
            wave += 1;
            if (wave <= 2) {
              return legacyPage(
                List<String>.generate(limit == 200 ? 40 : 2, (i) => 'L$i'),
              );
            }
            return projectedPage(
              ids: <String>['p1'],
              hasMore: true,
              nextCursor: 'cursor-2',
            );
          },
    );
    final first = await repo.fetch(request: companyFirst(), headers: headers);
    expect(first.contract, BookingListContractKind.legacy);
    expect(limits, <String>['25', '200']);
    now = now.add(const Duration(seconds: 46));
    final upgraded = await repo.fetch(
      request: companyFirst(),
      headers: headers,
    );
    expect(upgraded.contract, BookingListContractKind.projected);
    expect(upgraded.nextCursor, 'cursor-2');
    now = now.add(const Duration(seconds: 46));
    await repo.fetch(request: companyFirst(), headers: headers);
    expect(limits, <String>['25', '200', '200', '25']);
    expect(networkCalls, 4);
  });

  test('no automatic drain-all loop', () {
    expect(bookingListAllowsAutomaticDrain(), isFalse);
  });

  test('25 loaded + total_count 83 stays exact 83 after page 2', () {
    final first = parseBookingListPagePayload(
      projectedPage(
        ids: List<String>.generate(25, (i) => 'b$i'),
        hasMore: true,
        nextCursor: 'cursor-2',
        totalCount: 83,
      ),
      request: companyFirst(),
      limitUsed: 25,
    );
    expect(first.count, 25);
    expect(first.totalCount, 83);
    expect(
      companyBookingFilterDisplayedCount(
        selected: true,
        scopeMatches: true,
        contract: first.contract,
        exactTotal: first.totalCount,
        loadedCount: 25,
      ),
      83,
    );
    final next = parseBookingListPagePayload(
      projectedPage(ids: <String>['b25'], totalCount: 83),
      request: companyFirst(cursor: 'cursor-2'),
      limitUsed: 25,
    );
    expect(
      resolveBookingListExactTotal(
        replaceExactTotal: false,
        incoming: next.totalCount,
        previous: first.totalCount,
      ),
      83,
    );
  });

  test('active total differs from history total and is not reused', () {
    final history = parseBookingListPagePayload(
      projectedPage(ids: <String>['h1'], totalCount: 83),
      request: companyFirst(),
      limitUsed: 25,
    );
    final active = parseBookingListPagePayload(
      projectedPage(ids: <String>['a1'], totalCount: 12),
      request: companyFirst(historyMode: BookingListHistoryMode.active),
      limitUsed: 25,
    );
    expect(history.totalCount, 83);
    expect(active.totalCount, 12);
    expect(history.scopeKey == active.scopeKey, isFalse);
    expect(
      companyBookingFilterDisplayedCount(
        selected: false,
        scopeMatches: true,
        contract: BookingListContractKind.projected,
        exactTotal: 83,
        loadedCount: 4,
      ),
      4,
    );
  });

  test('refresh replaces exact total 83 with 82', () {
    expect(
      resolveBookingListExactTotal(
        replaceExactTotal: true,
        incoming: 82,
        previous: 83,
      ),
      82,
    );
  });

  test('legacy response has no total_count and stays compatible', () {
    final parsed = parseBookingListPagePayload(
      legacyPage(List<String>.generate(40, (i) => 'L$i')),
      request: companyFirst(),
      limitUsed: 200,
    );
    expect(parsed.contract, BookingListContractKind.legacy);
    expect(parsed.totalCount, isNull);
    expect(parsed.count, 40);
    expect(
      companyBookingFilterDisplayedCount(
        selected: true,
        scopeMatches: true,
        contract: parsed.contract,
        exactTotal: parsed.totalCount,
        loadedCount: 40,
      ),
      40,
    );
  });

  test('invalid and negative total_count are ignored', () {
    expect(parseBookingListExactTotal(null), isNull);
    expect(parseBookingListExactTotal(-1), isNull);
    expect(parseBookingListExactTotal(1.5), isNull);
    expect(parseBookingListExactTotal('nope'), isNull);
    expect(parseBookingListExactTotal(true), isNull);
    expect(parseBookingListExactTotal(83), 83);
    expect(parseBookingListExactTotal('83'), 83);
  });

  test('driver projected page does not invent an exact total', () {
    final parsed = parseBookingListPagePayload(
      projectedPage(ids: <String>['d1', 'd2']),
      request: driverFirst(),
      limitUsed: 25,
    );
    expect(parsed.contract, BookingListContractKind.projected);
    expect(parsed.count, 2);
    expect(parsed.totalCount, isNull);
  });

  test(
    'company mutation invalidates company and driver keys, not company B',
    () async {
      final companyA = companyFirst();
      final companyACursor = companyFirst(cursor: 'cursor-2');
      final companyAActive = companyFirst(
        historyMode: BookingListHistoryMode.active,
      );
      final driverA = driverFirst();
      final companyB = companyFirst(tenant: 'co-b', company: 'co-b');
      responses[companyA.cacheKey] = projectedPage(
        ids: <String>['hidden'],
        totalCount: 83,
      );
      responses[companyACursor.cacheKey] = projectedPage(ids: <String>['p2']);
      responses[companyAActive.cacheKey] = projectedPage(ids: <String>['a1']);
      responses[driverA.cacheKey] = projectedPage(ids: <String>['drv']);
      responses[companyB.cacheKey] = projectedPage(ids: <String>['keep']);
      await repo.fetch(request: companyA, headers: headers);
      await repo.fetch(request: companyACursor, headers: headers);
      await repo.fetch(request: companyAActive, headers: headers);
      await repo.fetch(request: driverA, headers: headers);
      await repo.fetch(request: companyB, headers: headers);
      expect(networkCalls, 5);
      repo.invalidateBookingListsForAffectedCompany(
        tenantId: 'co-a',
        companyId: 'co-a',
      );
      expect(repo.hasFreshCache(companyA), isFalse);
      expect(repo.hasFreshCache(companyACursor), isFalse);
      expect(repo.hasFreshCache(companyAActive), isFalse);
      expect(repo.hasFreshCache(driverA), isFalse);
      expect(repo.hasFreshCache(companyB), isTrue);
      responses[companyA.cacheKey] = projectedPage(ids: <String>['fresh']);
      final afterHide = await repo.fetch(request: companyA, headers: headers);
      expect(afterHide.items.single['booking_id'], 'fresh');
      expect(
        afterHide.items.any((row) => row['booking_id'] == 'hidden'),
        isFalse,
      );
      await repo.fetch(request: companyB, headers: headers);
      expect(networkCalls, 6);
    },
  );

  test('cross-actor invalidate does not prefetch the other actor', () async {
    responses[companyFirst().cacheKey] = projectedPage(ids: <String>['c']);
    responses[driverFirst().cacheKey] = projectedPage(ids: <String>['d']);
    await repo.fetch(request: companyFirst(), headers: headers);
    await repo.fetch(request: driverFirst(), headers: headers);
    repo.invalidateBookingListsForAffectedCompany(
      tenantId: 'co-a',
      companyId: 'co-a',
    );
    expect(networkCalls, 2);
    await repo.fetch(request: companyFirst(), headers: headers);
    expect(networkCalls, 3);
    expect(repo.hasFreshCache(driverFirst()), isFalse);
  });

  test('late success after invalidate does not restore the old page', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    repo = BookingListPageRepository(
      clock: () => now,
      transport:
          ({
            required BookingListPageRequest request,
            required int limit,
            required Future<Map<String, String>> Function() headers,
          }) async {
            networkCalls += 1;
            if (!started.isCompleted) started.complete();
            await release.future;
            return projectedPage(ids: <String>['stale']);
          },
    );
    final pending = repo.fetch(request: companyFirst(), headers: headers);
    await started.future;
    repo.invalidateBookingListsForAffectedCompany(
      tenantId: 'co-a',
      companyId: 'co-a',
    );
    release.complete();
    await pending;
    expect(repo.hasFreshCache(companyFirst()), isFalse);
  });

  test('empty tenant/company helper does not wipe another company', () async {
    responses[companyFirst(tenant: 'co-b', company: 'co-b').cacheKey] =
        projectedPage(ids: <String>['keep']);
    await repo.fetch(
      request: companyFirst(tenant: 'co-b', company: 'co-b'),
      headers: headers,
    );
    repo.invalidateBookingListsForAffectedCompany(tenantId: '', companyId: '');
    expect(
      repo.hasFreshCache(companyFirst(tenant: 'co-b', company: 'co-b')),
      isTrue,
    );
  });

  test('QA events stay identifier-free', () {
    expect(
      formatBookingPageQaLog(BookingPageQaEvent.networkFetch),
      '[BOOKING_PAGE] booking_page_network_fetch',
    );
    expect(
      formatBookingPageQaLog('tenantId=secret'),
      '[BOOKING_PAGE] booking_page_network_fetch',
    );
  });
}
