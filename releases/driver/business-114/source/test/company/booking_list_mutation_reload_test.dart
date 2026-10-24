import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/booking_list_mutation_reload.dart';
import 'package:fluxidi_tracking/company/booking_list_page_repository.dart';

void main() {
  late DateTime now;
  late int networkCalls;
  late List<String> actors;
  late List<int> limits;
  late BookingListPageRepository repo;
  late BookingListMutationReloadCoordinator coordinator;
  late int generation;
  late Map<String, Map<String, dynamic>> responses;

  BookingListPageRequest companyReq({
    String tenant = 'co-a',
    String company = 'co-a',
    String cursor = '',
  }) {
    return BookingListPageRequest(
      actor: BookingListActor.company,
      tenantId: tenant,
      companyId: company,
      historyMode: BookingListHistoryMode.history,
      cursor: cursor,
    );
  }

  BookingListPageRequest driverReq({
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

  Map<String, dynamic> projectedPage(List<String> ids) {
    return <String, dynamic>{
      'ok': true,
      'items': [
        for (final id in ids) <String, dynamic>{'booking_id': id, 'id': id},
      ],
      'count': ids.length,
      'has_more': false,
      'next_cursor': null,
    };
  }

  Future<Map<String, String>> headers() async => const <String, String>{
    'Accept': 'application/json',
  };

  Future<void> visibleDriverReload() {
    return repo.fetch(
      request: driverReq(),
      headers: headers,
      forceRefresh: true,
      reason: BookingListPageReason.mutation,
    );
  }

  void bindCoordinator() {
    coordinator = BookingListMutationReloadCoordinator(
      repository: repo,
      clock: () => now,
      onAdvanceGeneration: () => generation += 1,
    );
  }

  setUp(() {
    now = DateTime.utc(2026, 8, 31, 12, 0, 0);
    networkCalls = 0;
    actors = <String>[];
    limits = <int>[];
    generation = 0;
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
            actors.add(request.actor.name);
            limits.add(limit);
            await headers();
            final hit = responses[request.cacheKey];
            if (hit != null) return hit;
            throw BookingListPageException('missing_fixture');
          },
    );
    bindCoordinator();
  });

  test('chauffeur completion sites use the shared mutation reload helper', () {
    final driver = File(
      'lib/main_parts/driver_home_page_state.dart',
    ).readAsStringSync();
    final helper = File(
      'lib/company/booking_list_mutation_reload.dart',
    ).readAsStringSync();
    expect(
      helper.contains('class BookingListMutationReloadCoordinator'),
      isTrue,
    );
    expect(
      driver.contains('_reloadVisibleDriverBookingsAfterSuccessfulMutation('),
      isTrue,
    );
    expect(driver.contains('shouldSkipLegStatusCall'), isTrue);
    expect(
      '_reloadVisibleDriverBookingsAfterSuccessfulMutation('
          .allMatches(driver)
          .length,
      greaterThanOrEqualTo(4),
    );
    expect(
      driver.contains("trigger: 'planned_stop_bridge_handled_leg'"),
      isFalse,
    );
    expect(driver.contains("trigger: 'status_change_verified'"), isFalse);
    expect(driver.contains("trigger: 'status_change'"), isFalse);
    expect(driver.contains("trigger: 'leg_status_change'"), isFalse);
    expect(driver.contains('kBookingListMutationReloadTrigger'), isTrue);
    expect(driver.contains('BookingListPageReason.mutation'), isTrue);
  });

  test(
    'planned-stop mutation invalidates both actors and fetches once',
    () async {
      responses[driverReq().cacheKey] = projectedPage(<String>['planned']);
      responses[companyReq().cacheKey] = projectedPage(<String>['planned']);
      responses[companyReq(tenant: 'co-b', company: 'co-b').cacheKey] =
          projectedPage(<String>['other']);
      await repo.fetch(request: driverReq(), headers: headers);
      await repo.fetch(request: companyReq(), headers: headers);
      await repo.fetch(
        request: companyReq(tenant: 'co-b', company: 'co-b'),
        headers: headers,
      );
      expect(repo.hasFreshCache(driverReq()), isTrue);
      expect(repo.hasFreshCache(companyReq()), isTrue);
      expect(networkCalls, 3);
      expect(bookingListAllowsAutomaticDrain(), isFalse);

      responses[driverReq().cacheKey] = projectedPage(<String>['remaining']);
      await coordinator.reloadVisibleAfterSuccessfulMutation(
        tenantId: 'co-a',
        companyId: 'co-a',
        mutationKey: 'planned_stop:bk-1',
        reloadVisibleFirstPage: visibleDriverReload,
      );

      expect(generation, 1);
      expect(networkCalls, 4);
      expect(actors.where((name) => name == 'driver').length, 2);
      expect(actors.where((name) => name == 'company').length, 2);
      expect(limits, everyElement(kBookingListProjectedPageSize));
      expect(repo.hasFreshCache(driverReq()), isTrue);
      expect(repo.hasFreshCache(companyReq()), isFalse);
      expect(
        repo.hasFreshCache(companyReq(tenant: 'co-b', company: 'co-b')),
        isTrue,
      );
      final visible = await repo.fetch(request: driverReq(), headers: headers);
      expect(visible.items.single['booking_id'], 'remaining');
      expect(
        visible.items.any((row) => row['booking_id'] == 'planned'),
        isFalse,
      );
      expect(networkCalls, 4);
    },
  );

  test('cross-actor invalidation performs no network I/O', () async {
    responses[driverReq().cacheKey] = projectedPage(<String>['planned']);
    responses[companyReq().cacheKey] = projectedPage(<String>['planned']);
    await repo.fetch(request: driverReq(), headers: headers);
    await repo.fetch(request: companyReq(), headers: headers);
    repo.invalidateBookingListsForAffectedCompany(
      tenantId: 'co-a',
      companyId: 'co-a',
    );
    expect(networkCalls, 2);
    expect(repo.hasFreshCache(driverReq()), isFalse);
    expect(repo.hasFreshCache(companyReq()), isFalse);
  });

  test('cooldown cannot restore a completed row from the old cache', () async {
    responses[driverReq().cacheKey] = projectedPage(<String>['planned']);
    await repo.fetch(request: driverReq(), headers: headers);
    responses[driverReq().cacheKey] = projectedPage(<String>['remaining']);
    await coordinator.reloadVisibleAfterSuccessfulMutation(
      tenantId: 'co-a',
      companyId: 'co-a',
      mutationKey: 'status_change:bk-1',
      reloadVisibleFirstPage: visibleDriverReload,
    );
    final insideCooldown = await repo.fetch(
      request: driverReq(),
      headers: headers,
    );
    expect(insideCooldown.items.single['booking_id'], 'remaining');
    expect(networkCalls, 2);
  });

  test('status_change plus verified coalesce to one visible GET', () async {
    responses[driverReq().cacheKey] = projectedPage(<String>['fresh']);
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
            actors.add(request.actor.name);
            if (!started.isCompleted) started.complete();
            await release.future;
            return projectedPage(<String>['fresh']);
          },
    );
    bindCoordinator();
    final first = coordinator.reloadVisibleAfterSuccessfulMutation(
      tenantId: 'co-a',
      companyId: 'co-a',
      mutationKey: 'status_change:bk-1',
      reloadVisibleFirstPage: visibleDriverReload,
    );
    await started.future;
    final verified = coordinator.reloadVisibleAfterSuccessfulMutation(
      tenantId: 'co-a',
      companyId: 'co-a',
      mutationKey: 'status_change:bk-1',
      reloadVisibleFirstPage: visibleDriverReload,
    );
    release.complete();
    await Future.wait(<Future<void>>[first, verified]);
    expect(networkCalls, 1);
    expect(generation, 1);
    expect(actors, <String>['driver']);
  });

  test(
    'sequential verified fallback after status_change stays one GET',
    () async {
      responses[driverReq().cacheKey] = projectedPage(<String>['remaining']);
      await coordinator.reloadVisibleAfterSuccessfulMutation(
        tenantId: 'co-a',
        companyId: 'co-a',
        mutationKey: 'status_change:bk-1',
        reloadVisibleFirstPage: visibleDriverReload,
      );
      await coordinator.reloadVisibleAfterSuccessfulMutation(
        tenantId: 'co-a',
        companyId: 'co-a',
        mutationKey: 'status_change:bk-1',
        reloadVisibleFirstPage: visibleDriverReload,
      );
      expect(networkCalls, 1);
      expect(generation, 1);
      expect(repo.hasFreshCache(driverReq()), isTrue);
    },
  );

  test('verified-only path still invalidates and reloads once', () async {
    responses[driverReq().cacheKey] = projectedPage(<String>['planned']);
    responses[companyReq().cacheKey] = projectedPage(<String>['planned']);
    await repo.fetch(request: driverReq(), headers: headers);
    await repo.fetch(request: companyReq(), headers: headers);
    responses[driverReq().cacheKey] = projectedPage(<String>['remaining']);
    await coordinator.reloadVisibleAfterSuccessfulMutation(
      tenantId: 'co-a',
      companyId: 'co-a',
      mutationKey: 'status_change_verified:bk-1',
      reloadVisibleFirstPage: visibleDriverReload,
    );
    expect(repo.hasFreshCache(companyReq()), isFalse);
    expect(networkCalls, 3);
    expect(generation, 1);
    expect(actors.last, 'driver');
  });

  test('late pre-mutation response cannot overwrite the new list', () async {
    final started = Completer<void>();
    final release = Completer<void>();
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
            wave += 1;
            if (wave == 1) {
              if (!started.isCompleted) started.complete();
              await release.future;
              return projectedPage(<String>['planned']);
            }
            return projectedPage(<String>['remaining']);
          },
    );
    bindCoordinator();
    final stale = repo.fetch(request: driverReq(), headers: headers);
    await started.future;
    await coordinator.reloadVisibleAfterSuccessfulMutation(
      tenantId: 'co-a',
      companyId: 'co-a',
      mutationKey: 'planned_stop:bk-1',
      reloadVisibleFirstPage: visibleDriverReload,
    );
    release.complete();
    await stale;
    final visible = await repo.fetch(request: driverReq(), headers: headers);
    expect(visible.items.single['booking_id'], 'remaining');
    expect(repo.hasFreshCache(driverReq()), isTrue);
    expect(generation, 1);
  });

  test('manual refresh, TTL and pagination triggers stay distinct', () {
    expect(bookingListRefreshBypassesRepositoryCache('list_manual'), isTrue);
    expect(
      bookingListRefreshBypassesRepositoryCache(
        kBookingListMutationReloadTrigger,
      ),
      isTrue,
    );
    expect(bookingListRefreshBypassesRepositoryCache('periodic_poll'), isFalse);
    expect(bookingListRefreshBypassesRepositoryCache('next_page'), isFalse);
    expect(bookingListRefreshBypassesRepositoryCache('init_boot'), isFalse);
    expect(bookingListAllowsAutomaticDrain(), isFalse);
  });

  test(
    'existing TTL cache hits remain zero-network without mutation',
    () async {
      responses[driverReq().cacheKey] = projectedPage(<String>['planned']);
      await repo.fetch(request: driverReq(), headers: headers);
      await repo.fetch(request: driverReq(), headers: headers);
      expect(networkCalls, 1);
      now = now.add(const Duration(seconds: 46));
      await repo.fetch(request: driverReq(), headers: headers);
      expect(networkCalls, 2);
    },
  );

  test('P0B KPI and subscription-profile fallbacks stay disabled', () {
    final kpi = File(
      'lib/business/business_dashboard_kpi_loading.dart',
    ).readAsStringSync();
    final subscription = File(
      'lib/company/company_subscription_profile_repository.dart',
    ).readAsStringSync();
    expect(
      kpi.contains(
        'bool businessDashboardKpiAllowsAutomaticBookingsListFallback() => false;',
      ),
      isTrue,
    );
    expect(subscription.contains('Duration(seconds: 45)'), isTrue);
    expect(subscription.contains('Duration(seconds: 120)'), isFalse);
  });
}
