import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fluxidi_tracking/driver/driver_ride_alert_controller.dart';
import 'package:fluxidi_tracking/driver/driver_ride_alert_preferences.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';

void main() {
  testWidgets('An unfinished sound transport never delays cancellation', (
    tester,
  ) async {
    final gate = Completer<void>();
    var stops = 0;
    final owner = Object();
    final c = DriverRideAlertController(
      play: (_) => gate.future,
      stop: () async {
        stops++;
      },
      nowMs: () => 0,
    );
    c.present(owner: owner, identity: 'slow-audio', deadlineMs: 10000);
    await tester.pump();
    final before = stops;
    c.stop(owner: owner);
    expect(c.active, isFalse);
    expect(stops, greaterThan(before));
    gate.complete();
    await tester.pump();
    c.dispose();
  });
  testWidgets('Unexpired identities are not evicted by other proposals', (
    tester,
  ) async {
    var plays = 0;
    final owner = Object();
    final c = DriverRideAlertController(
      play: (_) async {
        plays++;
      },
      stop: () async {},
      nowMs: () => 0,
    );
    for (var i = 0; i < 16; i++) {
      c.present(owner: owner, identity: 'offer-$i', deadlineMs: 10000);
      await tester.pump();
    }
    expect(plays, 16);
    c.present(owner: owner, identity: 'offer-0', deadlineMs: 10000);
    await tester.pump();
    expect(plays, 16);
    c.stop(owner: owner);
    c.dispose();
  });
  testWidgets(
    'One alert per proposal; exact deadline stops even without another poll',
    (tester) async {
      var plays = 0, stops = 0, now = 1000;
      final c = DriverRideAlertController(
        play: (_) async {
          plays++;
        },
        stop: () async {
          stops++;
        },
        nowMs: () => now,
      );
      addTearDown(c.dispose);
      final owner = Object();
      c.present(owner: owner, identity: 'T:C:D:O:1', deadlineMs: 3000);
      await tester.pump();
      expect(plays, 1);
      expect(c.active, isTrue);
      c.present(owner: owner, identity: 'T:C:D:O:1', deadlineMs: 3000);
      await tester.pump();
      expect(plays, 1);
      now = 3000;
      await tester.pump(const Duration(seconds: 2));
      expect(c.active, isFalse);
      expect(stops, greaterThanOrEqualTo(2));
    },
  );
  for (final reason in [
    'accept',
    'decline',
    'withdraw',
    'owner change',
    'background',
    'dispose',
  ]) {
    testWidgets('$reason stops immediately and never repeats sound', (
      tester,
    ) async {
      var plays = 0, stops = 0;
      final owner = Object();
      final c = DriverRideAlertController(
        play: (_) async {
          plays++;
        },
        stop: () async {
          stops++;
        },
        nowMs: () => 0,
      );
      c.present(owner: owner, identity: reason, deadlineMs: 60000);
      await tester.pump();
      expect(plays, 1);
      final before = stops;
      if (reason == 'dispose')
        c.dispose();
      else
        c.stop(owner: owner);
      expect(c.active, isFalse);
      expect(stops, greaterThan(before));
      await tester.pump(const Duration(seconds: 10));
      expect(plays, 1);
      if (reason != 'dispose') c.dispose();
    });
  }
  testWidgets(
    'Expired offers never start; owner handoff cannot be stopped by old host',
    (tester) async {
      var plays = 0;
      final c = DriverRideAlertController(
        play: (_) async {
          plays++;
        },
        stop: () async {},
        nowMs: () => 100,
      );
      addTearDown(c.dispose);
      final old = Object(), next = Object();
      c.present(owner: old, identity: 'expired', deadlineMs: 100);
      await tester.pump();
      expect(plays, 0);
      c.present(owner: old, identity: 'valid', deadlineMs: 60000);
      await tester.pump();
      c.present(owner: next, identity: 'valid', deadlineMs: 60000);
      c.stop(owner: old);
      await tester.pump();
      expect(c.active, isTrue);
      expect(plays, 1);
      c.stop(owner: next);
      expect(c.active, isFalse);
    },
  );
  testWidgets(
    'Rotation/resume same identity stays silent; new version alerts once',
    (tester) async {
      final flashes = <bool>[];
      final c = DriverRideAlertController(
        play: (v) async {
          flashes.add(v);
        },
        stop: () async {},
        nowMs: () => 0,
      );
      addTearDown(c.dispose);
      final owner = Object();
      c.present(owner: owner, identity: 'D:O:1', deadlineMs: 60000);
      await tester.pump();
      c.stop(owner: owner);
      c.present(
        owner: owner,
        identity: 'D:O:1',
        deadlineMs: 60000,
        flashlight: true,
      );
      await tester.pump();
      expect(flashes, [false]);
      expect(c.active, isTrue);
      c.present(
        owner: owner,
        identity: 'D:O:2',
        deadlineMs: 60000,
        flashlight: true,
      );
      await tester.pump();
      expect(flashes, [false, true]);
      c.stop(owner: owner);
      await tester.pump();
    },
  );
  testWidgets('Late queued effect cannot play after invalidation', (
    tester,
  ) async {
    var plays = 0;
    final c = DriverRideAlertController(
      play: (_) async {
        plays++;
      },
      stop: () async {},
      nowMs: () => 0,
    );
    addTearDown(c.dispose);
    final owner = Object();
    c.present(owner: owner, identity: 'late', deadlineMs: 1000);
    c.stop(owner: owner);
    await tester.pump();
    expect(plays, 0);
    expect(c.active, isFalse);
  });
  test(
    'Flashlight defaults off and is isolated by tenant/company/driver',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      ActiveDriverSession actor(
        String driver, {
        String company = 'C',
        String tenant = 'T',
      }) => ActiveDriverSession(
        driverId: driver,
        employeeNumber: '',
        fullName: driver,
        phone: '',
        loggedInAt: '',
        updatedAt: '',
        tenantId: tenant,
        companyId: company,
        driverSessionToken: 'fixture',
        linkMethod: 'public_driver_login',
      );
      final prefs = DriverRideAlertPreferences();
      expect(await prefs.flashlight(actor('A')), isFalse);
      await prefs.setFlashlight(actor('A'), true);
      expect(await prefs.flashlight(actor('A')), isTrue);
      expect(await prefs.flashlight(actor('B')), isFalse);
      expect(await prefs.flashlight(actor('A', company: 'OTHER')), isFalse);
      expect(await prefs.flashlight(actor('A', tenant: 'OTHER')), isFalse);
      await prefs.setFlashlight(actor('A'), false);
      expect(await prefs.flashlight(actor('A')), isFalse);
    },
  );
}
