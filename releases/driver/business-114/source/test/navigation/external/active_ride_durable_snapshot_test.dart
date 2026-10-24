// ACTIVE-RIDE-DURABLE-RESTORE-P0-7

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/external/active_ride_durable_snapshot.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('ActiveRideDurableSnapshot', () {
    test('round-trip planned + external session', () {
      final launched = DateTime.utc(2026, 8, 6, 17, 0, 0);
      final snap = ActiveRideDurableSnapshot(
        rideType: 'planned',
        bookingId: '2026-08-165',
        parentBookingId: 'PLN-2026-000384',
        activeLegId: 'leg_1',
        tripId: 'session_abc',
        lifecyclePhase: 'active',
        startedAt: launched,
        updatedAt: launched.add(const Duration(minutes: 12)),
        lastLat: 51.05,
        lastLon: 3.72,
        trackedDistanceKm: 4.2,
        waitingSeconds: 90,
        currentOrFixedFare: 35.40,
        paymentState: null,
        finalizePending: false,
        externalNavSession: ExternalNavigationSession(
          provider: ExternalNavProvider.googleMaps,
          bookingId: '2026-08-165',
          phase: ExternalNavPhase.activeRide,
          destination: const ExternalNavigationDestinationPoint(
            latitude: 50.85,
            longitude: 4.35,
          ),
          launchedAt: launched,
          pipActive: true,
          nativeGuidanceSuppressed: true,
        ),
      );

      final decoded = ActiveRideDurableSnapshot.fromJson(
        Map<String, dynamic>.from(snap.toJson()),
      );
      expect(decoded.rideType, 'planned');
      expect(decoded.isPlanned, isTrue);
      expect(decoded.bookingId, '2026-08-165');
      expect(decoded.tripId, 'session_abc');
      expect(decoded.trackedDistanceKm, 4.2);
      expect(decoded.currentOrFixedFare, 35.40);
      expect(decoded.externalNavSession, isNotNull);
      expect(decoded.externalNavSession!.pipActive, isTrue);
      expect(decoded.externalNavSession!.phase, ExternalNavPhase.activeRide);
    });

    test('street snapshot identity fields', () {
      final snap = ActiveRideDurableSnapshot(
        rideType: 'street',
        bookingId: 'street_1786035880780_1dghte50',
        parentBookingId: 'street_1786035880780_1dghte50',
        tripId: 'trip_ef67352e-3383-494f-87d4-e53f7567c9f4',
        lifecyclePhase: 'active',
        startedAt: DateTime.utc(2026, 8, 6, 17, 4, 40),
        updatedAt: DateTime.utc(2026, 8, 6, 17, 10, 0),
        trackedDistanceKm: 1.1,
        waitingSeconds: 0,
        currentOrFixedFare: 8.5,
        finalizePending: true,
      );
      expect(snap.isStreet, isTrue);
      expect(snap.finalizePending, isTrue);
      final j = snap.toJson();
      expect(j['version'], 2);
      expect(j['rideType'], 'street');
    });

    test('empty booking id rejected by store save guard via fromJson', () {
      final empty = ActiveRideDurableSnapshot.fromJson(<String, dynamic>{
        'rideType': 'planned',
        'bookingId': '  ',
        'lifecyclePhase': 'active',
        'startedAt': '2026-08-06T17:00:00Z',
        'updatedAt': '2026-08-06T17:00:00Z',
      });
      expect(empty.bookingId.trim(), isEmpty);
    });
  });

  group('restore notice', () {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('fluxidi-restore-notice-');
      messenger.setMockMethodCallHandler(channel, (_) async => root.path);
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      final tempRoot = Directory.systemTemp.absolute.path.toLowerCase();
      final testRoot = root.absolute.path.toLowerCase();
      if (testRoot.startsWith('$tempRoot${Platform.pathSeparator}') &&
          root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });

    test(
      'warns once across reloads without deleting the ride snapshot',
      () async {
        final started = DateTime.utc(2026, 10, 1, 12);
        final oldRide = ActiveRideDurableSnapshot(
          rideType: 'street',
          bookingId: 'test-ride-1',
          tripId: 'test-trip-1',
          startedAt: started,
          updatedAt: started,
        );
        await ActiveRideDurableSnapshotStore.save(
          tenantId: 'tenant-1',
          companyId: 'company-1',
          snapshot: oldRide,
        );

        expect(
          await ActiveRideDurableSnapshotStore.claimRestoreNotice(
            tenantId: 'tenant-1',
            companyId: 'company-1',
            snapshot: oldRide,
          ),
          isTrue,
        );
        expect(
          await ActiveRideDurableSnapshotStore.claimRestoreNotice(
            tenantId: 'tenant-1',
            companyId: 'company-1',
            snapshot: oldRide,
          ),
          isFalse,
        );
        expect(
          (await ActiveRideDurableSnapshotStore.load(
            tenantId: 'tenant-1',
            companyId: 'company-1',
          ))?.bookingId,
          'test-ride-1',
        );

        final nextRide = ActiveRideDurableSnapshot(
          rideType: 'street',
          bookingId: 'test-ride-2',
          tripId: 'test-trip-2',
          startedAt: started.add(const Duration(days: 1)),
          updatedAt: started.add(const Duration(days: 1)),
        );
        await ActiveRideDurableSnapshotStore.save(
          tenantId: 'tenant-1',
          companyId: 'company-1',
          snapshot: nextRide,
        );
        expect(
          await ActiveRideDurableSnapshotStore.claimRestoreNotice(
            tenantId: 'tenant-1',
            companyId: 'company-1',
            snapshot: nextRide,
          ),
          isTrue,
        );
      },
    );

    test('concurrent recovery attempts show only one warning', () async {
      final started = DateTime.utc(2026, 10, 1, 12);
      final ride = ActiveRideDurableSnapshot(
        rideType: 'street',
        bookingId: 'test-ride-race',
        startedAt: started,
        updatedAt: started,
      );
      await ActiveRideDurableSnapshotStore.save(
        tenantId: 'tenant-1',
        companyId: 'company-1',
        snapshot: ride,
      );
      final claims = await Future.wait([
        ActiveRideDurableSnapshotStore.claimRestoreNotice(
          tenantId: 'tenant-1',
          companyId: 'company-1',
          snapshot: ride,
        ),
        ActiveRideDurableSnapshotStore.claimRestoreNotice(
          tenantId: 'tenant-1',
          companyId: 'company-1',
          snapshot: ride,
        ),
      ]);
      expect(claims.where((claimed) => claimed), hasLength(1));
    });

    test('an unshown claim can retry without losing the ride', () async {
      final started = DateTime.utc(2026, 10, 1, 12);
      final ride = ActiveRideDurableSnapshot(
        rideType: 'planned',
        bookingId: 'test-ride-unshown',
        tripId: 'test-trip-unshown',
        startedAt: started,
        updatedAt: started,
      );
      await ActiveRideDurableSnapshotStore.save(
        tenantId: 'tenant-1',
        companyId: 'company-1',
        snapshot: ride,
      );
      expect(
        await ActiveRideDurableSnapshotStore.claimRestoreNotice(
          tenantId: 'tenant-1',
          companyId: 'company-1',
          snapshot: ride,
        ),
        isTrue,
      );
      await ActiveRideDurableSnapshotStore.releaseUnshownRestoreNotice(
        tenantId: 'tenant-1',
        companyId: 'company-1',
        snapshot: ride,
      );
      expect(
        (await ActiveRideDurableSnapshotStore.load(
          tenantId: 'tenant-1',
          companyId: 'company-1',
        ))?.bookingId,
        'test-ride-unshown',
      );
      expect(
        await ActiveRideDurableSnapshotStore.claimRestoreNotice(
          tenantId: 'tenant-1',
          companyId: 'company-1',
          snapshot: ride,
        ),
        isTrue,
      );
      expect(
        await ActiveRideDurableSnapshotStore.claimRestoreNotice(
          tenantId: 'tenant-1',
          companyId: 'company-1',
          snapshot: ride,
        ),
        isFalse,
      );
    });

    test('release of an old ride preserves a newer notice', () async {
      final started = DateTime.utc(2026, 10, 1, 12);
      final oldRide = ActiveRideDurableSnapshot(
        rideType: 'planned',
        bookingId: 'test-ride-old',
        startedAt: started,
        updatedAt: started,
      );
      final newRide = ActiveRideDurableSnapshot(
        rideType: 'planned',
        bookingId: 'test-ride-new',
        startedAt: started.add(const Duration(days: 1)),
        updatedAt: started.add(const Duration(days: 1)),
      );
      await ActiveRideDurableSnapshotStore.save(
        tenantId: 'tenant-1',
        companyId: 'company-1',
        snapshot: oldRide,
      );
      expect(
        await ActiveRideDurableSnapshotStore.claimRestoreNotice(
          tenantId: 'tenant-1',
          companyId: 'company-1',
          snapshot: oldRide,
        ),
        isTrue,
      );
      await ActiveRideDurableSnapshotStore.save(
        tenantId: 'tenant-1',
        companyId: 'company-1',
        snapshot: newRide,
      );
      expect(
        await ActiveRideDurableSnapshotStore.claimRestoreNotice(
          tenantId: 'tenant-1',
          companyId: 'company-1',
          snapshot: newRide,
        ),
        isTrue,
      );
      await ActiveRideDurableSnapshotStore.releaseUnshownRestoreNotice(
        tenantId: 'tenant-1',
        companyId: 'company-1',
        snapshot: oldRide,
      );
      expect(
        await ActiveRideDurableSnapshotStore.claimRestoreNotice(
          tenantId: 'tenant-1',
          companyId: 'company-1',
          snapshot: newRide,
        ),
        isFalse,
      );
      expect(
        (await ActiveRideDurableSnapshotStore.load(
          tenantId: 'tenant-1',
          companyId: 'company-1',
        ))?.bookingId,
        'test-ride-new',
      );
    });

    test('a cleared ride cannot show a delayed recovery warning', () async {
      final started = DateTime.utc(2026, 10, 1, 12);
      final ride = ActiveRideDurableSnapshot(
        rideType: 'street',
        bookingId: 'test-ride-cleared',
        startedAt: started,
        updatedAt: started,
      );
      await ActiveRideDurableSnapshotStore.save(
        tenantId: 'tenant-1',
        companyId: 'company-1',
        snapshot: ride,
      );
      await ActiveRideDurableSnapshotStore.clear(
        tenantId: 'tenant-1',
        companyId: 'company-1',
      );
      expect(
        await ActiveRideDurableSnapshotStore.claimRestoreNotice(
          tenantId: 'tenant-1',
          companyId: 'company-1',
          snapshot: ride,
        ),
        isFalse,
      );
    });
  });
}
