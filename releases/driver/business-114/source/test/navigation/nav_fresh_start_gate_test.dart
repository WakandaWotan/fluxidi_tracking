import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/nav_ride_boundary_ownership.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_fresh_start_gate.dart';

void main() {
  group('NAV-LATENCY fresh-start gate (Part B)', () {
    test('fresh fix animates follow', () {
      expect(
        NavFreshStartGate.resolve(ageMs: 0),
        NavFreshStartAction.animateFollow,
      );
      expect(
        NavFreshStartGate.resolve(ageMs: 5000),
        NavFreshStartAction.animateFollow,
      );
      expect(
        NavFreshStartGate.resolve(ageMs: NavFreshStartGate.freshFollowMaxAgeMs),
        NavFreshStartAction.animateFollow,
      );
    });

    test('field-log stale target (284916 ms) never animates follow', () {
      expect(
        NavFreshStartGate.resolve(ageMs: 284916),
        NavFreshStartAction.waitForFix,
      );
      expect(NavFreshStartGate.mayAnimateFollow(ageMs: 284916), isFalse);
    });

    test('bounded stale window is static placeholder only', () {
      expect(
        NavFreshStartGate.resolve(ageMs: 30000),
        NavFreshStartAction.staticPlaceholder,
      );
      expect(NavFreshStartGate.mayAnimateFollow(ageMs: 30000), isFalse);
      expect(
        NavFreshStartGate.resolve(
          ageMs: NavFreshStartGate.stalePlaceholderMaxAgeMs,
        ),
        NavFreshStartAction.staticPlaceholder,
      );
    });

    test('beyond placeholder window waits for a fix', () {
      expect(
        NavFreshStartGate.resolve(
          ageMs: NavFreshStartGate.stalePlaceholderMaxAgeMs + 1,
        ),
        NavFreshStartAction.waitForFix,
      );
    });

    test('null / negative age waits for a fix', () {
      expect(
        NavFreshStartGate.resolve(ageMs: null),
        NavFreshStartAction.waitForFix,
      );
      expect(
        NavFreshStartGate.resolve(ageMs: -1),
        NavFreshStartAction.waitForFix,
      );
    });

    test('just over the fresh threshold stops animating', () {
      expect(
        NavFreshStartGate.mayAnimateFollow(
          ageMs: NavFreshStartGate.freshFollowMaxAgeMs + 1,
        ),
        isFalse,
      );
    });
  });

  group('NAV continuations and fresh route origin', () {
    final now = DateTime.utc(2026, 10, 4, 9, 30);
    const initialOwner = DriverNavigationOperationOwner(
      sessionGeneration: 7,
      cleanupEpoch: 12,
      bookingRowKey: 'B1|OUTBOUND',
    );
    test(
      'STOP, same-booking new leg, disposal and new ride invalidate NAV',
      () {
        bool matches({
          bool mounted = true,
          int session = 7,
          int cleanup = 12,
          String? row = 'B1|OUTBOUND',
        }) => initialOwner.matches(
          mounted: mounted,
          currentSessionGeneration: session,
          currentCleanupEpoch: cleanup,
          currentBookingRowKey: row,
        );
        expect(matches(), isTrue);
        expect(matches(cleanup: 13), isFalse);
        expect(matches(session: 8), isFalse);
        expect(matches(row: 'B1|RETURN'), isFalse);
        expect(matches(row: 'B2|OUTBOUND'), isFalse);
        expect(matches(mounted: false), isFalse);
      },
    );

    test('fresh cached raw fix avoids a second location read', () async {
      final fix = (
        latitude: 50.8,
        longitude: 3.7,
        at: now.subtract(const Duration(seconds: 2)),
      );
      var reads = 0;
      final result = await resolveFreshNavigationPosition(
        cachedPosition: () => fix,
        positionTimestamp: (p) => p.at,
        readFresh: () async {
          reads++;
          return fix;
        },
        operationCurrent: () => true,
        now: () => now,
      );
      expect(result, fix);
      expect(reads, 0);
    });

    test(
      'cached Maarkedal origin is replaced by fresh Sint-Niklaas raw GPS',
      () async {
        final old = (
          latitude: 50.8,
          longitude: 3.7,
          at: now.subtract(const Duration(minutes: 8)),
        );
        final live = (latitude: 51.16, longitude: 4.14, at: now);
        final result = await resolveFreshNavigationPosition(
          cachedPosition: () => old,
          positionTimestamp: (p) => p.at,
          readFresh: () async => live,
          operationCurrent: () => true,
          now: () => now,
        );
        expect(result, live);
        expect(result?.longitude, isNot(old.longitude));
      },
    );

    test('newer raw stream sample wins over delayed one-shot origin', () async {
      final pending =
          Completer<({double latitude, double longitude, DateTime at})>();
      var cached = (
        latitude: 50.8,
        longitude: 3.7,
        at: now.subtract(const Duration(minutes: 8)),
      );
      final result = resolveFreshNavigationPosition(
        cachedPosition: () => cached,
        positionTimestamp: (p) => p.at,
        readFresh: () => pending.future,
        operationCurrent: () => true,
        now: () => now,
      );
      cached = (latitude: 51.161, longitude: 4.141, at: now);
      pending.complete((
        latitude: 51.160,
        longitude: 4.140,
        at: now.subtract(const Duration(seconds: 4)),
      ));
      expect(await result, cached);
    });

    test(
      'late GPS after booking-leg change cannot authorize route or camera',
      () async {
        final pending = Completer<DateTime>();
        var row = 'B1|OUTBOUND';
        final result = resolveFreshNavigationPosition<DateTime>(
          cachedPosition: () => now.subtract(const Duration(minutes: 8)),
          positionTimestamp: (p) => p,
          readFresh: () => pending.future,
          operationCurrent: () => initialOwner.matches(
            mounted: true,
            currentSessionGeneration: 7,
            currentCleanupEpoch: 12,
            currentBookingRowKey: row,
          ),
          now: () => now,
        );
        row = 'B1|RETURN';
        pending.complete(now);
        expect(await result, isNull);
      },
    );

    test('late GPS after STOP cannot authorize route or camera', () async {
      final pending = Completer<DateTime>();
      var cleanup = 12;
      final result = resolveFreshNavigationPosition<DateTime>(
        cachedPosition: () => now.subtract(const Duration(minutes: 8)),
        positionTimestamp: (p) => p,
        readFresh: () => pending.future,
        operationCurrent: () => initialOwner.matches(
          mounted: true,
          currentSessionGeneration: 7,
          currentCleanupEpoch: cleanup,
          currentBookingRowKey: 'B1|OUTBOUND',
        ),
        now: () => now,
      );
      cleanup++;
      pending.complete(now);
      expect(await result, isNull);
    });

    test(
      'failed read still accepts a fresh streaming fix from the same owner',
      () async {
        final pending = Completer<DateTime>();
        var cached = now.subtract(const Duration(minutes: 8));
        final result = resolveFreshNavigationPosition<DateTime>(
          cachedPosition: () => cached,
          positionTimestamp: (p) => p,
          readFresh: () => pending.future,
          operationCurrent: () => true,
          now: () => now,
        );
        cached = now;
        pending.completeError(StateError('GPS timeout'));
        expect(await result, now);
      },
    );

    test(
      'no fresh GPS means no route from an old or future location',
      () async {
        for (final at in [
          now.subtract(const Duration(seconds: 13)),
          now.add(const Duration(seconds: 1)),
        ]) {
          final result = await resolveFreshNavigationPosition<DateTime>(
            cachedPosition: () => at,
            positionTimestamp: (p) => p,
            readFresh: () async => at,
            operationCurrent: () => true,
            now: () => now,
          );
          expect(result, isNull);
        }
      },
    );
  });
}
