import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/driver/driver_session_probe.dart';
import 'package:fluxidi_tracking/driver/driver_session_credentials.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:fluxidi_tracking/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ActiveDriverSession _session({String? vehicleId}) {
  final now = DateTime.now().toUtc().toIso8601String();
  return ActiveDriverSession(
    driverId: 'drv-recovery',
    employeeNumber: 'TEST9',
    fullName: 'Driver Recovery',
    phone: '',
    loggedInAt: now,
    updatedAt: now,
    tenantId: 'tenant-recovery',
    companyId: 'company-recovery',
    assignedVehicleId: vehicleId,
    driverSessionToken: 'test-bearer',
    driverSessionExpiresAtUtc: DateTime.now()
        .toUtc()
        .add(const Duration(days: 1))
        .toIso8601String(),
    linkMethod: 'public_driver_login',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixtureRoot;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    fixtureRoot = Directory.systemTemp.createTempSync(
      'driver-session-recovery-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => fixtureRoot.path,
        );
    activeDriverSessionNotifier.value = null;
  });

  tearDown(() async {
    activeDriverSessionNotifier.value = null;
    await DriverSessionStore.instance.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  test(
    'server probe accepts valid bearer and rejects revoked bearer',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('', requests.length == 1 ? 200 : 401);
      });
      final probe = DriverSessionProbe();
      expect(
        await probe.check(
          bookingBaseUrl: 'https://booking.example',
          token: 'test-bearer',
          client: client,
        ),
        DriverSessionProbeResult.valid,
      );
      expect(
        await probe.check(
          bookingBaseUrl: 'https://booking.example',
          token: 'test-bearer',
          client: client,
        ),
        DriverSessionProbeResult.invalid,
      );
      expect(
        requests.every(
          (r) =>
              r.url.queryParameters['limit'] == '1' &&
              r.headers['Authorization'] == 'Bearer test-bearer',
        ),
        isTrue,
      );
    },
  );

  test('server errors preserve recoverable session', () async {
    final client = MockClient((_) async => http.Response('', 503));
    expect(
      await const DriverSessionProbe().check(
        bookingBaseUrl: 'https://booking.example',
        token: 'test-bearer',
        client: client,
      ),
      DriverSessionProbeResult.unavailable,
    );
  });

  test('secure bearer keys are separate for tenant, company and driver', () {
    final credentials = DriverSessionCredentials();
    expect(
      credentials.keyFor('tenant-a', 'company-a', 'driver-a'),
      isNot(credentials.keyFor('tenant-b', 'company-a', 'driver-a')),
    );
    expect(
      credentials.keyFor('tenant-a', 'company-a', 'driver-a'),
      isNot(credentials.keyFor('tenant-a', 'company-b', 'driver-a')),
    );
    expect(
      credentials.keyFor('tenant-a', 'company-a', 'driver-a'),
      isNot(credentials.keyFor('tenant-a', 'company-a', 'driver-b')),
    );
  });

  testWidgets('dashboard appears only after valid server check', (
    tester,
  ) async {
    activeDriverSessionNotifier.value = _session(vehicleId: 'vh-1');
    await tester.pumpWidget(
      MaterialApp(
        home: DriverSessionGatePage(
          probe: (_) async => DriverSessionProbeResult.valid,
          dashboardBuilder: (_) => const Scaffold(body: Text('dashboard')),
        ),
      ),
    );
    expect(find.text('dashboard'), findsNothing);
    await tester.pump();
    expect(find.text('dashboard'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('dashboard'), findsOneWidget);
  });

  testWidgets('fresh backend login opens immediately, resume rechecks', (
    tester,
  ) async {
    activeDriverSessionNotifier.value = _session();
    var probes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DriverSessionGatePage(
          newlyIssued: true,
          probe: (_) async {
            probes++;
            return DriverSessionProbeResult.valid;
          },
          dashboardBuilder: (_) => const Scaffold(body: Text('dashboard')),
        ),
      ),
    );
    expect(find.text('dashboard'), findsOneWidget);
    expect(probes, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(probes, 1);
    expect(find.text('dashboard'), findsOneWidget);
  });

  testWidgets(
    'explicit sign-in goes online before dashboard; resume never repeats activation',
    (tester) async {
      final session = _session(vehicleId: 'vh-1');
      activeDriverSessionNotifier.value = session;
      var state = 'offline', writes = 0, probes = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              home: DriverSessionGatePage(
                newlyIssued: true,
                activateAfterSignIn: true,
                probe: (_) async {
                  probes++;
                  return DriverSessionProbeResult.valid;
                },
                dashboardBuilder: (_) =>
                    const Scaffold(body: Text('online-dashboard')),
              ),
            ),
          );
          expect(find.text('online-dashboard'), findsNothing);
          for (var i = 0; i < 12; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
          }
          expect(find.text('online-dashboard'), findsOneWidget);
          expect(writes, 1);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
          expect(probes, 1);
          expect(writes, 1);
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((request) async {
          expect(
            request.headers['Authorization'],
            'Bearer ${session.driverSessionToken}',
          );
          final scope = {
            'ok': true,
            'tenant_id': session.tenantId,
            'company_id': session.companyId,
            'driver_id': session.driverId,
            'is_active': true,
            'availability_status': 'available',
          };
          if (request.method == 'POST') {
            expect(request.url.path, '/public/driver/availability');
            writes++;
            state = 'available';
            return http.Response(jsonEncode(scope), 200);
          }
          expect(request.url.hasQuery, isFalse);
          return http.Response(
            jsonEncode({
              ...scope,
              'driver': {
                'driver_id': session.driverId,
                'is_active': true,
                'availability_status': state,
                'assigned_vehicle_id': 'vh-1',
              },
            }),
            200,
          );
        }),
      );
    },
  );

  testWidgets('activation refusal does not expose dashboard or claim online', (
    tester,
  ) async {
    activeDriverSessionNotifier.value = _session(vehicleId: 'vh-1');
    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: DriverSessionGatePage(
            newlyIssued: true,
            activateAfterSignIn: true,
            dashboardBuilder: (_) =>
                const Scaffold(body: Text('must-stay-covered')),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('must-stay-covered'), findsNothing);
      expect(
        find.textContaining('Online zetten is nog niet bevestigd'),
        findsOneWidget,
      );
      expect(activeDriverSessionNotifier.value, isNotNull);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((_) async => http.Response('{"ok":false}', 403)));
  });

  testWidgets('unavailable check offers retry without discarding session', (
    tester,
  ) async {
    activeDriverSessionNotifier.value = _session();
    var checks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DriverSessionGatePage(
          probe: (_) async => ++checks == 1
              ? DriverSessionProbeResult.unavailable
              : DriverSessionProbeResult.valid,
          dashboardBuilder: (_) => const Scaffold(body: Text('dashboard')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Opnieuw proberen'), findsOneWidget);
    expect(activeDriverSessionNotifier.value, isNotNull);
    await tester.tap(find.text('Opnieuw proberen'));
    await tester.pump();
    expect(find.text('dashboard'), findsOneWidget);
  });

  testWidgets('revoked bearer returns to code login', (tester) async {
    activeDriverSessionNotifier.value = _session();
    // Revocation clears real files and serialized native ownership. Run the
    // operation in the real async zone rather than retaining a FakeAsync queue.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: DriverSessionGatePage(
            probe: (_) async => DriverSessionProbeResult.invalid,
            dashboardBuilder: (_) => const Scaffold(body: Text('dashboard')),
          ),
        ),
      );
      for (
        var i = 0;
        i < 100 && activeDriverSessionNotifier.value != null;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(find.text('dashboard'), findsNothing);
    expect(activeDriverSessionNotifier.value, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test('standalone JSON contains no bearer after save', () async {
    await DriverSessionStore.instance.saveBackendDriverLoginSession(
      tenantId: 'tenant-recovery',
      companyId: 'company-recovery',
      driverId: 'drv-recovery',
      driverName: 'Driver Recovery',
      companyDisplayName: 'Test Company',
      driverSessionToken: 'test-bearer',
      expiresInSeconds: 3600,
    );
    final path =
        '${fixtureRoot.path}${Platform.pathSeparator}'
        'driver_session${Platform.pathSeparator}tenant_tenant-recovery'
        '${Platform.pathSeparator}company_company-recovery'
        '${Platform.pathSeparator}active_driver_session_v1.json';
    final file = File(path);
    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), isNot(contains('test-bearer')));
    activeDriverSessionNotifier.value = null;
    await DriverSessionStore.instance.bootstrap(
      const <DriverProfile>[],
      useStandaloneScopePointer: true,
    );
    expect(activeDriverSessionNotifier.value?.driverId, 'drv-recovery');
    expect(
      activeDriverSessionNotifier.value?.driverSessionToken,
      'test-bearer',
    );
    await DriverSessionStore.instance.clear();
    expect(await file.exists(), isFalse);
    expect(
      await DriverSessionCredentials().read(
        'tenant-recovery',
        'company-recovery',
        'drv-recovery',
      ),
      isNull,
    );
  });

  test('expired stored bearer is not restored', () async {
    await DriverSessionStore.instance.saveBackendDriverLoginSession(
      tenantId: 'tenant-recovery',
      companyId: 'company-recovery',
      driverId: 'drv-recovery',
      driverName: 'Driver Recovery',
      companyDisplayName: 'Test Company',
      driverSessionToken: 'expired-bearer',
      expiresAtUtc: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
    );
    activeDriverSessionNotifier.value = null;
    await DriverSessionStore.instance.bootstrap(
      const <DriverProfile>[],
      useStandaloneScopePointer: true,
    );
    expect(activeDriverSessionNotifier.value, isNull);
  });

  test(
    'expired pairing challenge does not expire a valid driver bearer',
    () async {
      final now = DateTime.now().toUtc();
      await DriverSessionStore.instance.saveVerifiedDriverPairingSession(
        tenantId: 'tenant-recovery',
        companyId: 'company-recovery',
        companyCode: 'RECOVERY',
        driverId: 'drv-recovery',
        driverName: 'Driver Recovery',
        employeeNumber: 'TEST9',
        driverSessionToken: 'pairing-bearer',
        driverSessionExpiresAtUtc: now.add(const Duration(days: 1)),
        issuedAt: now.subtract(const Duration(hours: 2)),
        expiresAt: now.subtract(const Duration(hours: 1)),
      );
      activeDriverSessionNotifier.value = null;
      await DriverSessionStore.instance.bootstrap(
        const <DriverProfile>[],
        useStandaloneScopePointer: true,
      );
      expect(activeDriverSessionNotifier.value?.driverId, 'drv-recovery');
      expect(
        activeDriverSessionNotifier.value?.driverSessionToken,
        'pairing-bearer',
      );
    },
  );

  test(
    'assigned vehicle is not rejected because another shift driver is shown',
    () {
      final oldVehicles = vehiclesNotifier.value;
      final oldDrivers = driversNotifier.value;
      addTearDown(() {
        vehiclesNotifier.value = oldVehicles;
        driversNotifier.value = oldDrivers;
      });
      vehiclesNotifier.value = <VehicleProfile>[
        const VehicleProfile(
          id: 'vh-1',
          vehicleName: 'Toyota Corolla 1',
          brandModel: 'Toyota Corolla',
          licensePlate: '',
          color: '',
          passengerCapacity: 4,
          luggageCapacity: 3,
          tierId: 'taxi',
          isActive: true,
          driverId: 'drv-other-shift',
          companyId: 'company-recovery',
          primaryPhotoRef: '',
          galleryPhotoRefs: <String>[],
        ),
      ];
      driversNotifier.value = <DriverProfile>[
        const DriverProfile(
          id: 'drv-recovery',
          fullName: 'Driver Recovery',
          employeeNumber: 'RECOVERY',
          phone: '',
          isActive: true,
          companyId: 'company-recovery',
        ),
      ];
      expect(
        standaloneDriverSessionOperationalBlockReason(
          driverId: 'drv-recovery',
          assignedVehicleId: 'vh-1',
          tenantId: 'tenant-recovery',
          companyId: 'company-recovery',
          activeCompanyId: 'company-recovery',
          drivers: driversNotifier.value,
        ),
        isNull,
      );
      expect(
        standaloneDriverSessionOperationalBlockReason(
          driverId: 'drv-recovery',
          assignedVehicleId: null,
          tenantId: 'tenant-recovery',
          companyId: 'company-recovery',
          activeCompanyId: 'company-recovery',
          drivers: driversNotifier.value,
        ),
        'no_vehicle_assigned',
      );
      vehiclesNotifier.value = <VehicleProfile>[
        vehiclesNotifier.value.single.copyWith(isActive: false),
      ];
      expect(
        standaloneDriverSessionOperationalBlockReason(
          driverId: 'drv-recovery',
          assignedVehicleId: 'vh-1',
          tenantId: 'tenant-recovery',
          companyId: 'company-recovery',
          activeCompanyId: 'company-recovery',
          drivers: driversNotifier.value,
        ),
        'no_vehicle_assigned',
      );
      vehiclesNotifier.value = <VehicleProfile>[
        vehiclesNotifier.value.single.copyWith(
          companyId: 'another-company',
          isActive: false,
        ),
      ];
      expect(
        standaloneDriverSessionOperationalBlockReason(
          driverId: 'drv-recovery',
          assignedVehicleId: 'vh-1',
          tenantId: 'tenant-recovery',
          companyId: 'company-recovery',
          activeCompanyId: 'company-recovery',
          drivers: driversNotifier.value,
        ),
        isNull,
      );
    },
  );
}
