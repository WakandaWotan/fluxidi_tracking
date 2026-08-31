import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver/trip_history_booking_detail_repository.dart';

void main() {
  late DateTime now;
  late int networkCalls;
  late List<String> requestedIds;
  late TripHistoryBookingDetailRepository repo;

  TripHistoryBookingDetailRequest req({
    String tenant = 't-a',
    String company = 'c-a',
    String driver = 'd-a',
    String booking = 'b-1',
  }) {
    return TripHistoryBookingDetailRequest(
      tenantId: tenant,
      companyId: company,
      driverId: driver,
      bookingId: booking,
    );
  }

  Future<Map<String, String>> headers() async => const <String, String>{
    'Accept': 'application/json',
  };

  setUp(() {
    now = DateTime.utc(2026, 8, 31, 12, 0, 0);
    networkCalls = 0;
    requestedIds = <String>[];
    repo = TripHistoryBookingDetailRepository(
      clock: () => now,
      transport:
          ({
            required TripHistoryBookingDetailRequest request,
            required Future<Map<String, String>> Function() headers,
          }) async {
            networkCalls += 1;
            requestedIds.add(request.bookingId);
            await headers();
            return <String, dynamic>{
              'ok': true,
              'record': <String, dynamic>{'booking_id': request.bookingId},
            };
          },
    );
  });

  test('history sync with 12 rows performs zero automatic detail GETs', () {
    expect(tripHistoryAllowsAutomaticDetailHydration(), isFalse);
    final history = File(
      'lib/main_parts/trip_history_page.dart',
    ).readAsStringSync();
    expect(history.contains('_refreshCanonicalPaymentForItems'), isFalse);
    expect(history.contains('unawaited(_refreshCanonicalPaymentForItems'), isFalse);
    expect(networkCalls, 0);
  });

  test('opening one detail performs at most one GET', () async {
    await repo.fetch(request: req(), headers: headers);
    expect(networkCalls, 1);
    expect(requestedIds, <String>['b-1']);
  });

  test('repeated opening inside TTL performs zero extra GETs', () async {
    await repo.fetch(request: req(), headers: headers);
    await repo.fetch(request: req(), headers: headers);
    expect(networkCalls, 1);
  });

  test('scope and sign-out invalidation drops cached details', () async {
    await repo.fetch(request: req(), headers: headers);
    repo.applyScope(tenantId: 't-b', companyId: 'c-b', driverId: 'd-b');
    expect(repo.hasFreshCache(req()), isFalse);
    await repo.fetch(
      request: req(tenant: 't-b', company: 'c-b', driver: 'd-b'),
      headers: headers,
    );
    expect(networkCalls, 2);
    repo.invalidateAll();
    expect(
      repo.hasFreshCache(req(tenant: 't-b', company: 'c-b', driver: 'd-b')),
      isFalse,
    );
  });

  test('late responses cannot cross tenant/company/driver scope', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    repo = TripHistoryBookingDetailRepository(
      clock: () => now,
      transport:
          ({
            required TripHistoryBookingDetailRequest request,
            required Future<Map<String, String>> Function() headers,
          }) async {
            networkCalls += 1;
            started.complete();
            await release.future;
            return <String, dynamic>{
              'ok': true,
              'record': <String, dynamic>{'booking_id': request.bookingId},
            };
          },
    );
    final pending = repo.fetch(request: req(), headers: headers);
    await started.future;
    repo.applyScope(tenantId: 't-b', companyId: 'c-b', driverId: 'd-b');
    release.complete();
    await expectLater(
      pending,
      throwsA(isA<TripHistoryBookingDetailException>()),
    );
    expect(repo.hasFreshCache(req()), isFalse);
  });
}
