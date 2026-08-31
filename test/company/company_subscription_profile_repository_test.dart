import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company/company_subscription_profile_repository.dart';

void main() {
  late DateTime now;
  late int networkCalls;
  late CompanySubscriptionProfileRepository repo;
  BackendSubscriptionProfile profileFor(String tenant, String company) {
    return BackendSubscriptionProfile.fromJson(<String, dynamic>{
      'tenant_id': tenant,
      'company_id': company,
      'plan': 'fluxidi_pro',
      'status': 'active',
      'subscription_status': 'active',
      'features': <String, bool>{'limousine': false},
    });
  }

  setUp(() {
    now = DateTime.utc(2026, 8, 30, 12, 0, 0);
    networkCalls = 0;
    repo = CompanySubscriptionProfileRepository(
      clock: () => now,
      loader: ({String? tenantId, String? companyId}) async {
        networkCalls += 1;
        return profileFor(tenantId ?? '', companyId ?? '');
      },
    );
  });

  test(
    '1. 30 concurrent identical requests → exactly one network call',
    () async {
      final futures = List<Future<BackendSubscriptionProfile>>.generate(
        30,
        (_) => repo.fetch(tenantId: 'co-a', companyId: 'co-a'),
      );
      final results = await Future.wait(futures);
      expect(networkCalls, 1);
      expect(
        results,
        everyElement(
          predicate<BackendSubscriptionProfile>(
            (p) => p.companyId == 'co-a' && p.tenantId == 'co-a',
          ),
        ),
      );
    },
  );

  test('2. repeated calls inside TTL → one total network call', () async {
    await repo.fetch(tenantId: 'co-a', companyId: 'co-a');
    await repo.fetch(tenantId: 'co-a', companyId: 'co-a');
    await repo.fetch(tenantId: 'co-a', companyId: 'co-a');
    expect(networkCalls, 1);
  });

  test('3. widget rebuilds do not refetch', () async {
    Future<BackendSubscriptionProfile>? held;
    String? heldScope;
    Future<BackendSubscriptionProfile> futureForBuild(String scope) {
      if (heldScope != scope || held == null) {
        heldScope = scope;
        held = repo.fetch(tenantId: scope, companyId: scope);
      }
      return held!;
    }

    await futureForBuild('co-a');
    await futureForBuild('co-a');
    await futureForBuild('co-a');
    expect(networkCalls, 1);
    expect(identical(held, futureForBuild('co-a')), isTrue);
  });

  test(
    '4. different company or tenant → separate calls and cached values',
    () async {
      final a = await repo.fetch(tenantId: 'co-a', companyId: 'co-a');
      final b = await repo.fetch(tenantId: 'co-b', companyId: 'co-b');
      expect(networkCalls, 2);
      expect(a.companyId, 'co-a');
      expect(b.companyId, 'co-b');
      expect(a.companyId, isNot(b.companyId));
      await repo.fetch(tenantId: 'co-a', companyId: 'co-a');
      expect(networkCalls, 2);
    },
  );

  test(
    '5. successful subscription mutation invalidates the relevant cache',
    () async {
      await repo.fetch(tenantId: 'co-a', companyId: 'co-a');
      repo.invalidate(tenantId: 'co-a', companyId: 'co-a');
      await repo.fetch(tenantId: 'co-a', companyId: 'co-a');
      expect(networkCalls, 2);
    },
  );

  test('6. manual refresh causes exactly one new request', () async {
    await repo.fetch(tenantId: 'co-a', companyId: 'co-a');
    await repo.fetch(tenantId: 'co-a', companyId: 'co-a', forceRefresh: true);
    expect(networkCalls, 2);
  });

  test('7. failed request is recoverable on the next attempt', () async {
    var shouldFail = true;
    repo = CompanySubscriptionProfileRepository(
      clock: () => now,
      loader: ({String? tenantId, String? companyId}) async {
        networkCalls += 1;
        if (shouldFail) {
          shouldFail = false;
          throw Exception('HTTP 503: unavailable');
        }
        return profileFor(tenantId ?? '', companyId ?? '');
      },
    );
    await expectLater(
      repo.fetch(tenantId: 'co-a', companyId: 'co-a'),
      throwsA(isA<Exception>()),
    );
    expect(networkCalls, 1);
    final recovered = await repo.fetch(tenantId: 'co-a', companyId: 'co-a');
    expect(networkCalls, 2);
    expect(recovered.companyId, 'co-a');
  });

  test(
    '8. sign-out/scope switch cannot expose the previous company profile',
    () async {
      await repo.fetch(tenantId: 'co-old', companyId: 'co-old');
      expect(
        repo.hasFreshCache(tenantId: 'co-old', companyId: 'co-old'),
        isTrue,
      );
      repo.invalidateAll();
      expect(
        repo.hasFreshCache(tenantId: 'co-old', companyId: 'co-old'),
        isFalse,
      );
      final next = await repo.fetch(tenantId: 'co-new', companyId: 'co-new');
      expect(next.companyId, 'co-new');
      expect(next.companyId, isNot('co-old'));
      expect(networkCalls, 2);
    },
  );

  test('TTL is the documented 45s band value', () {
    expect(kCompanySubscriptionProfileTtl, const Duration(seconds: 45));
    expect(kCompanySubscriptionProfileTtl.inSeconds, inInclusiveRange(30, 60));
  });

  test(
    'late in-flight success after invalidate does not restore stale cache',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      repo = CompanySubscriptionProfileRepository(
        clock: () => now,
        loader: ({String? tenantId, String? companyId}) async {
          networkCalls += 1;
          if (!started.isCompleted) started.complete();
          if (!release.isCompleted) await release.future;
          return profileFor(tenantId ?? '', companyId ?? '');
        },
      );
      final pending = repo.fetch(tenantId: 'co-a', companyId: 'co-a');
      await started.future;
      repo.invalidate(tenantId: 'co-a', companyId: 'co-a');
      release.complete();
      await pending;
      expect(repo.hasFreshCache(tenantId: 'co-a', companyId: 'co-a'), isFalse);
      await repo.fetch(tenantId: 'co-a', companyId: 'co-a');
      expect(networkCalls, 2);
    },
  );

  test('QA logging contains no identifiers or profile contents', () async {
    final events = <String>[];
    repo = CompanySubscriptionProfileRepository(
      clock: () => now,
      qaLogEnabled: true,
      qaLog: events.add,
      loader: ({String? tenantId, String? companyId}) async {
        networkCalls += 1;
        return profileFor(tenantId ?? '', companyId ?? '');
      },
    );
    await repo.fetch(tenantId: 'tenant-secret', companyId: 'company-secret');
    await repo.fetch(tenantId: 'tenant-secret', companyId: 'company-secret');
    final first = repo.fetch(
      tenantId: 'tenant-secret',
      companyId: 'company-secret',
      forceRefresh: true,
    );
    final second = repo.fetch(
      tenantId: 'tenant-secret',
      companyId: 'company-secret',
      forceRefresh: true,
    );
    await Future.wait(<Future<BackendSubscriptionProfile>>[first, second]);
    repo.invalidate(tenantId: 'tenant-secret', companyId: 'company-secret');
    expect(events, contains(SubscriptionProfileQaEvent.networkFetch));
    expect(events, contains(SubscriptionProfileQaEvent.cacheHit));
    expect(events, contains(SubscriptionProfileQaEvent.coalesced));
    expect(events, contains(SubscriptionProfileQaEvent.invalidated));
    final lines = events.map(formatSubscriptionProfileQaLog).join('\n');
    expect(lines.contains('tenant-secret'), isFalse);
    expect(lines.contains('company-secret'), isFalse);
    expect(lines.contains('fluxidi_pro'), isFalse);
    expect(lines.contains('Bearer'), isFalse);
    expect(lines.contains('http'), isFalse);
    expect(kFluxidiQaRequestLogging, isFalse);
  });

  test('concurrent manual refresh still shares one network request', () async {
    await repo.fetch(tenantId: 'co-a', companyId: 'co-a');
    final a = repo.fetch(
      tenantId: 'co-a',
      companyId: 'co-a',
      forceRefresh: true,
    );
    final b = repo.fetch(
      tenantId: 'co-a',
      companyId: 'co-a',
      forceRefresh: true,
    );
    await Future.wait(<Future<BackendSubscriptionProfile>>[a, b]);
    expect(networkCalls, 2);
  });
}
