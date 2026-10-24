import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/external/active_ride_durable_snapshot.dart';
import 'package:fluxidi_tracking/navigation/external/durable_ride_restore_policy.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  const pricing = <String, dynamic>{
    'start_fee': 7.5,
    'per_km': 1.25,
    'wait_per_min': 1.0,
    'vat_rate': 0.06,
    'vat_mode': 'incl',
    'currency': 'EUR',
  };
  ActiveRideDurableSnapshot snapshot(double km) => ActiveRideDurableSnapshot(
    rideType: 'street',
    bookingId: 'local-ride',
    startedAt: DateTime.utc(2026, 10, 9, 16),
    updatedAt: DateTime.utc(2026, 10, 9, 16, 30),
    ownerDriverId: 'driver-1',
    ownerVehicleId: 'vehicle-1',
    backendConfirmed: false,
    navigationDestination: const ExternalNavigationDestinationPoint(
      latitude: 51.1,
      longitude: 4.2,
      address: 'Destination',
    ),
    meterPricing: pricing,
    trackedDistanceKm: km,
    waitingSeconds: 90,
    isWaiting: true,
    currentOrFixedFare: 7.5 + km * 1.25 + 1.5,
  );
  bool allowed(
    ActiveRideDurableSnapshot s, {
    String driver = 'driver-1',
    String vehicle = 'vehicle-1',
  }) => canRestoreLocalStreetRide(
    isStreet: s.isStreet,
    backendConfirmed: s.backendConfirmed,
    ownerDriverId: s.ownerDriverId ?? '',
    activeDriverId: driver,
    ownerVehicleId: s.ownerVehicleId ?? '',
    activeVehicleId: vehicle,
    tripId: s.tripId ?? '',
    finalizePending: s.finalizePending,
    lifecyclePhase: s.lifecyclePhase,
    meterPricing: s.meterPricing,
  );
  test('cold restore installs navigation target before saved meters, preventing route reload reset', () {
    final source = File('lib/main_parts/driver_home_page_state.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _recoverActiveRideDurableSnapshot()');
    final end = source.indexOf('Future<DirectRideReconcileOutcome> _reconcileDirectBookingOnWorker', start);
    final recovery = source.substring(start, end);
    final install = recovery.indexOf('_installActiveNavTarget(');
    final meter = recovery.indexOf('_kmDriven =');
    expect(install, greaterThanOrEqualTo(0));
    expect(meter, greaterThan(install));
    expect(recovery, contains('_activeBooking = restoredBooking;'));
    expect(recovery, contains('final restoredBooking = localStreet ? null : booking!;'));
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fluxidi-ride-recovery-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => dir.path);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await dir.delete(recursive: true);
  });
  test(
    'process restart reads the same owned manual ride and meter inputs from disk',
    () async {
      await ActiveRideDurableSnapshotStore.save(
        tenantId: 'tenant',
        companyId: 'company',
        snapshot: snapshot(104.114),
      );
      final restored = (await ActiveRideDurableSnapshotStore.load(
        tenantId: 'tenant',
        companyId: 'company',
      ))!;
      expect(allowed(restored), isTrue);
      expect(restored.tripId, isNull);
      expect(restored.backendConfirmed, isFalse);
      expect(restored.navigationDestination!.address, 'Destination');
      expect(restored.isWaiting, isTrue);
      expect(restored.waitingSeconds, 90);
      expect(restored.meterPricing, pricing);
      final fare =
          (restored.meterPricing!['start_fee'] as num) +
          (restored.trackedDistanceKm! *
              (restored.meterPricing!['per_km'] as num)) +
          (restored.waitingSeconds! /
              60 *
              (restored.meterPricing!['wait_per_min'] as num));
      expect(fare, restored.currentOrFixedFare);
      expect(allowed(restored, driver: 'other'), isFalse);
      expect(allowed(restored, vehicle: 'other'), isFalse);
      expect(
        await ActiveRideDurableSnapshotStore.load(
          tenantId: 'tenant',
          companyId: 'other',
        ),
        isNull,
      );
    },
  );
  test(
    'overlapping checkpoints preserve order and clear cannot resurrect a stopped ride',
    () async {
      await Future.wait([
        for (final km in [1.0, 2.0, 3.0])
          ActiveRideDurableSnapshotStore.save(
            tenantId: 'tenant',
            companyId: 'company',
            snapshot: snapshot(km),
          ),
      ]);
      expect(
        (await ActiveRideDurableSnapshotStore.load(
          tenantId: 'tenant',
          companyId: 'company',
        ))!.trackedDistanceKm,
        3,
      );
      await Future.wait([
        ActiveRideDurableSnapshotStore.save(
          tenantId: 'tenant',
          companyId: 'company',
          snapshot: snapshot(4),
        ),
        ActiveRideDurableSnapshotStore.clear(
          tenantId: 'tenant',
          companyId: 'company',
        ),
      ]);
      expect(
        await ActiveRideDurableSnapshotStore.load(
          tenantId: 'tenant',
          companyId: 'company',
        ),
        isNull,
      );
    },
  );
  test('partial crash write leaves last completed checkpoint readable', () async {
    await ActiveRideDurableSnapshotStore.save(
      tenantId: 'tenant',
      companyId: 'company',
      snapshot: snapshot(5),
    );
    await File(
      '${dir.path}/fluxidi/active_ride/tenant_tenant/company_company/${ActiveRideDurableSnapshotStore.fileName}.pending',
    ).writeAsString('{broken');
    expect(
      (await ActiveRideDurableSnapshotStore.load(
        tenantId: 'tenant',
        companyId: 'company',
      ))!.trackedDistanceKm,
      5,
    );
  });
  test(
    'legacy unbound snapshot and server-backed record cannot use local authority',
    () {
      final legacy = ActiveRideDurableSnapshot.fromJson({
        'rideType': 'street',
        'bookingId': 'local-ride',
      });
      expect(allowed(legacy), isFalse);
      for (final changes in [
        <String, dynamic>{'backendConfirmed': true},
        {'tripId': 'server-trip'},
        {'finalizePending': true},
        {'lifecyclePhase': 'completed'},
        {'meterPricing': null},
        {
          'meterPricing': {...pricing, 'per_km': double.infinity},
        },
      ]) {
        expect(
          allowed(
            ActiveRideDurableSnapshot.fromJson({
              ...snapshot(5).toJson(),
              ...changes,
            }),
          ),
          isFalse,
        );
      }
    },
  );
}
