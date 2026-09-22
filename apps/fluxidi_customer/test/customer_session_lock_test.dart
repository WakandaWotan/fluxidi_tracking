import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_customer/app/fluxidi_customer_app.dart';
import 'package:fluxidi_customer/deeplinks/customer_deep_link_source.dart';
import 'package:fluxidi_customer/screens/customer_home_screen.dart';
import 'package:fluxidi_customer/security/customer_booking_presence.dart';
import 'package:fluxidi_customer/security/customer_device_unlock.dart';
import 'package:fluxidi_customer/security/customer_secure_session_vault.dart';
import 'package:fluxidi_customer/security/customer_session_lock.dart';
import 'package:fluxidi_customer/security/customer_session_lock_gate.dart';
import 'package:fluxidi_customer/security/customer_session_surface.dart';
import 'package:fluxidi_customer/security/customer_unlock_offer.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';

Future<void> _cycleAppThroughBackground(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
}

class _FakeDeepLinkSource implements CustomerDeepLinkSource {
  final StreamController<Uri> controller = StreamController<Uri>.broadcast();

  @override
  Future<Uri?> initialLink() async => null;

  @override
  Stream<Uri> linkStream() => controller.stream;
}

CustomerSession _session({
  required DateTime expiresAt,
  String token = 'cus_live_token',
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  return CustomerSession(
    customerSessionToken: token,
    expiresAt: expiresAt.toUtc().toIso8601String(),
    customerId: 'cus_1',
    phoneE164: '+32470000000',
    createdAt: now,
    updatedAt: now,
  );
}

String _jsonOf(CustomerSession session) => jsonEncode(session.toJson());

CustomerSessionLock _lock({
  required MemoryCustomerSecureSessionVault vault,
  required FakeCustomerDeviceUnlock unlock,
  required MemoryCustomerSessionSurface surface,
}) {
  return CustomerSessionLock(
    vault: vault,
    unlock: unlock,
    surface: surface,
    bookingPresence: CustomerBookingPresence.instance,
  );
}

void main() {
  setUp(() {
    CustomerBookingPresence.instance.debugReset();
    CustomerSessionLock.debugOverride(null);
  });

  tearDown(() {
    CustomerBookingPresence.instance.debugReset();
    CustomerSessionLock.debugOverride(null);
  });

  test('successful unlock hydrates a still-valid session', () async {
    final vault = MemoryCustomerSecureSessionVault()..unlockEnabled = true;
    final surface = MemoryCustomerSessionSurface();
    final unlock = FakeCustomerDeviceUnlock();
    final lock = _lock(vault: vault, unlock: unlock, surface: surface);
    final session = _session(
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
    );
    await vault.writeSessionJson(_jsonOf(session));
    await lock.restoreAtLaunch();
    expect(lock.isLocked, isTrue);
    expect(surface.peek(), isNull);

    expect(await lock.unlock(reason: 'open'), CustomerUnlockResult.success);
    expect(lock.isLocked, isFalse);
    expect(surface.peek()?.customerSessionToken, session.customerSessionToken);
  });

  test('successful unlock does not restore an expired session', () async {
    final vault = MemoryCustomerSecureSessionVault()..unlockEnabled = true;
    final surface = MemoryCustomerSessionSurface();
    final unlock = FakeCustomerDeviceUnlock();
    final lock = _lock(vault: vault, unlock: unlock, surface: surface);
    final session = _session(
      expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
    );
    await vault.writeSessionJson(_jsonOf(session));

    await lock.restoreAtLaunch();
    expect(lock.isLocked, isFalse);
    expect(vault.sessionJson, isNull);
    expect(surface.peek(), isNull);

    await vault.writeSessionJson(_jsonOf(session));
    await vault.writeUnlockEnabled(true);
    expect(await lock.unlock(reason: 'open'), CustomerUnlockResult.success);
    expect(surface.peek(), isNull);
    expect(vault.sessionJson, isNull);
  });

  test('cancel and failed recognition leave the session locked', () async {
    final vault = MemoryCustomerSecureSessionVault()..unlockEnabled = true;
    final surface = MemoryCustomerSessionSurface();
    final unlock = FakeCustomerDeviceUnlock(
      result: CustomerUnlockResult.canceled,
    );
    final lock = _lock(vault: vault, unlock: unlock, surface: surface);
    final session = _session(
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    await vault.writeSessionJson(_jsonOf(session));
    await lock.restoreAtLaunch();

    expect(await lock.unlock(reason: 'open'), CustomerUnlockResult.canceled);
    expect(lock.isLocked, isTrue);
    expect(surface.peek(), isNull);

    unlock.result = CustomerUnlockResult.failed;
    expect(await lock.unlock(reason: 'open'), CustomerUnlockResult.failed);
    expect(lock.isLocked, isTrue);
    expect(surface.peek(), isNull);
  });

  test('lock is skipped during an open booking', () async {
    final vault = MemoryCustomerSecureSessionVault()..unlockEnabled = true;
    final surface = MemoryCustomerSessionSurface();
    final unlock = FakeCustomerDeviceUnlock();
    final lock = _lock(vault: vault, unlock: unlock, surface: surface);
    final session = _session(
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    await vault.writeSessionJson(_jsonOf(session));
    await lock.restoreAtLaunch();
    await lock.unlock(reason: 'open');

    CustomerBookingPresence.instance.enter();
    expect(await lock.lockIfNeeded(), isFalse);
    expect(lock.isLocked, isFalse);
    expect(surface.peek(), isNotNull);
    CustomerBookingPresence.instance.leave();

    expect(await lock.lockIfNeeded(), isTrue);
    expect(lock.isLocked, isTrue);
    expect(surface.peek(), isNull);
  });

  test('lock is skipped during a payment return', () async {
    final vault = MemoryCustomerSecureSessionVault()..unlockEnabled = true;
    final surface = MemoryCustomerSessionSurface();
    final unlock = FakeCustomerDeviceUnlock();
    final lock = _lock(vault: vault, unlock: unlock, surface: surface);
    final session = _session(
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    await vault.writeSessionJson(_jsonOf(session));
    await lock.restoreAtLaunch();
    await lock.unlock(reason: 'open');
    lock.paymentReturnActive = true;
    expect(await lock.lockIfNeeded(), isFalse);
    expect(lock.isLocked, isFalse);
  });

  test('a device without unlock cannot turn the switch on', () async {
    final vault = MemoryCustomerSecureSessionVault();
    final surface = MemoryCustomerSessionSurface();
    final unlock = FakeCustomerDeviceUnlock(protects: false);
    final lock = _lock(vault: vault, unlock: unlock, surface: surface);
    expect(await lock.canProtectDevice(), isFalse);
    expect(
      await lock.enableAfterAuthentication(reason: 'enable'),
      CustomerUnlockResult.unavailable,
    );
    expect(lock.isEnabled, isFalse);
  });

  test('enable and disable require a successful OS prompt', () async {
    final vault = MemoryCustomerSecureSessionVault();
    final surface = MemoryCustomerSessionSurface();
    final unlock = FakeCustomerDeviceUnlock(
      result: CustomerUnlockResult.canceled,
    );
    final lock = _lock(vault: vault, unlock: unlock, surface: surface);
    surface.remember(
      _session(expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1))),
    );

    expect(
      await lock.enableAfterAuthentication(reason: 'enable'),
      CustomerUnlockResult.canceled,
    );
    expect(lock.isEnabled, isFalse);

    unlock.result = CustomerUnlockResult.success;
    expect(
      await lock.enableAfterAuthentication(reason: 'enable'),
      CustomerUnlockResult.success,
    );
    expect(lock.isEnabled, isTrue);
    expect(vault.unlockEnabled, isTrue);

    unlock.result = CustomerUnlockResult.failed;
    expect(
      await lock.disableAfterAuthentication(reason: 'disable'),
      CustomerUnlockResult.failed,
    );
    expect(lock.isEnabled, isTrue);

    unlock.result = CustomerUnlockResult.success;
    expect(
      await lock.disableAfterAuthentication(reason: 'disable'),
      CustomerUnlockResult.success,
    );
    expect(lock.isEnabled, isFalse);
  });

  testWidgets('offer dialog can enable unlock after sign-in', (tester) async {
    final vault = MemoryCustomerSecureSessionVault();
    final surface = MemoryCustomerSessionSurface()
      ..remember(
        _session(expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1))),
      );
    final unlock = FakeCustomerDeviceUnlock();
    final lock = _lock(vault: vault, unlock: unlock, surface: surface);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              key: const Key('start_offer'),
              onPressed: () => offerCustomerDeviceUnlockAfterSignIn(
                context,
                lock: lock,
              ),
              child: const Text('start'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('start_offer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customer_unlock_offer_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('customer_unlock_offer_enable')));
    await tester.pumpAndSettle();
    expect(lock.isEnabled, isTrue);
    expect(unlock.authenticateCount, 1);
  });

  testWidgets('declining the offer leaves unlock off', (tester) async {
    final vault = MemoryCustomerSecureSessionVault();
    final surface = MemoryCustomerSessionSurface();
    final unlock = FakeCustomerDeviceUnlock();
    final lock = _lock(vault: vault, unlock: unlock, surface: surface);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              key: const Key('start_offer'),
              onPressed: () => offerCustomerDeviceUnlockAfterSignIn(
                context,
                lock: lock,
              ),
              child: const Text('start'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('start_offer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customer_unlock_offer_later')));
    await tester.pumpAndSettle();
    expect(lock.isEnabled, isFalse);
    expect(unlock.authenticateCount, 0);
  });

  test('plaintext session file is deleted after a successful migrate', () async {
    final vault = MemoryCustomerSecureSessionVault();
    final surface = MemoryCustomerSessionSurface();
    final unlock = FakeCustomerDeviceUnlock();
    final lock = _lock(vault: vault, unlock: unlock, surface: surface);
    final session = _session(
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
    );
    surface.fileSession = session;

    await lock.restoreAtLaunch();

    expect(await surface.plaintextFileExists(), isFalse);
    expect(surface.fileSession, isNull);
    expect(vault.sessionJson, isNotNull);
    expect(surface.peek()?.customerSessionToken, session.customerSessionToken);
  });

  test('leftover plaintext is deleted when the vault already has the session', () async {
    final vault = MemoryCustomerSecureSessionVault()..unlockEnabled = true;
    final surface = MemoryCustomerSessionSurface();
    final unlock = FakeCustomerDeviceUnlock();
    final lock = _lock(vault: vault, unlock: unlock, surface: surface);
    final session = _session(
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
    );
    await vault.writeSessionJson(_jsonOf(session));
    surface.fileSession = session;

    await lock.restoreAtLaunch();

    expect(await surface.plaintextFileExists(), isFalse);
    expect(surface.fileSession, isNull);
    expect(surface.peek(), isNull);
    expect(lock.isLocked, isTrue);
  });

  test('an invalid plaintext file is deleted and never migrated', () async {
    final vault = MemoryCustomerSecureSessionVault();
    final surface = MemoryCustomerSessionSurface();
    final unlock = FakeCustomerDeviceUnlock();
    final lock = _lock(vault: vault, unlock: unlock, surface: surface);
    surface.fileSession = _session(
      expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 4)),
    );

    await lock.restoreAtLaunch();

    expect(await surface.plaintextFileExists(), isFalse);
    expect(vault.sessionJson, isNull);
    expect(surface.peek(), isNull);
  });

  test('logout deletes the vault and any leftover plaintext file', () async {
    final vault = MemoryCustomerSecureSessionVault()..unlockEnabled = true;
    final surface = MemoryCustomerSessionSurface();
    final unlock = FakeCustomerDeviceUnlock();
    final lock = _lock(vault: vault, unlock: unlock, surface: surface);
    final session = _session(
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    surface.remember(session);
    surface.fileSession = session;
    await lock.persistCurrentSession();
    expect(await surface.plaintextFileExists(), isFalse);

    surface.fileSession = session;
    await lock.signOut();

    expect(await surface.plaintextFileExists(), isFalse);
    expect(vault.sessionJson, isNull);
    expect(surface.peek(), isNull);
  });

  test('an invalidated session deletes vault and leftover plaintext', () async {
    final vault = MemoryCustomerSecureSessionVault()..unlockEnabled = true;
    final surface = MemoryCustomerSessionSurface();
    final unlock = FakeCustomerDeviceUnlock();
    final lock = _lock(vault: vault, unlock: unlock, surface: surface);
    final expired = _session(
      expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
    );
    await vault.writeSessionJson(_jsonOf(expired));
    surface.fileSession = expired;

    await lock.restoreAtLaunch();

    expect(await surface.plaintextFileExists(), isFalse);
    expect(vault.sessionJson, isNull);
    expect(surface.peek(), isNull);
    expect(lock.isLocked, isFalse);
  });

  test('persistCurrentSession writes the vault then deletes the JSON file', () async {
    final vault = MemoryCustomerSecureSessionVault();
    final surface = MemoryCustomerSessionSurface();
    final unlock = FakeCustomerDeviceUnlock();
    final lock = _lock(vault: vault, unlock: unlock, surface: surface);
    final session = _session(
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 3)),
    );
    surface.remember(session);
    surface.fileSession = session;

    await lock.persistCurrentSession();

    expect(vault.sessionJson, isNotNull);
    expect(await surface.plaintextFileExists(), isFalse);
    expect(surface.peek()?.customerSessionToken, session.customerSessionToken);
  });

  test('a deferred lock is applied after a booking ends', () async {
    final vault = MemoryCustomerSecureSessionVault()..unlockEnabled = true;
    final surface = MemoryCustomerSessionSurface();
    final unlock = FakeCustomerDeviceUnlock();
    final lock = _lock(vault: vault, unlock: unlock, surface: surface);
    final session = _session(
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    await vault.writeSessionJson(_jsonOf(session));
    await lock.restoreAtLaunch();
    await lock.unlock(reason: 'open');

    CustomerBookingPresence.instance.enter();
    expect(await lock.lockIfNeeded(), isFalse);
    expect(lock.hasPendingLock, isTrue);
    expect(lock.isLocked, isFalse);
    expect(surface.peek(), isNotNull);

    CustomerBookingPresence.instance.leave();
    expect(await lock.applyPendingLockIfSafe(), isTrue);
    expect(lock.isLocked, isTrue);
    expect(lock.hasPendingLock, isFalse);
    expect(surface.peek(), isNull);
  });

  test('a deferred lock is applied after a payment return closes', () async {
    final vault = MemoryCustomerSecureSessionVault()..unlockEnabled = true;
    final surface = MemoryCustomerSessionSurface();
    final unlock = FakeCustomerDeviceUnlock();
    final lock = _lock(vault: vault, unlock: unlock, surface: surface);
    final session = _session(
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    await vault.writeSessionJson(_jsonOf(session));
    await lock.restoreAtLaunch();
    await lock.unlock(reason: 'open');

    lock.paymentReturnActive = true;
    expect(await lock.lockIfNeeded(), isFalse);
    expect(lock.hasPendingLock, isTrue);
    expect(lock.isLocked, isFalse);

    lock.paymentReturnActive = false;
    await Future<void>.delayed(Duration.zero);
    expect(lock.isLocked, isTrue);
    expect(surface.peek(), isNull);
  });

  test('a deferred lock is applied after a pushed page is gone', () async {
    final vault = MemoryCustomerSecureSessionVault()..unlockEnabled = true;
    final surface = MemoryCustomerSessionSurface();
    final unlock = FakeCustomerDeviceUnlock();
    final lock = _lock(vault: vault, unlock: unlock, surface: surface);
    final session = _session(
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    await vault.writeSessionJson(_jsonOf(session));
    await lock.restoreAtLaunch();
    await lock.unlock(reason: 'open');

    lock.navigationBusy = true;
    expect(await lock.lockIfNeeded(), isFalse);
    expect(lock.hasPendingLock, isTrue);

    lock.navigationBusy = true;
    expect(await lock.applyPendingLockIfSafe(), isFalse);
    expect(lock.isLocked, isFalse);

    lock.navigationBusy = false;
    await Future<void>.delayed(Duration.zero);
    expect(lock.isLocked, isTrue);
    expect(lock.hasPendingLock, isFalse);
  });

  test('ending a booking applies a pending lock without another request', () async {
    final vault = MemoryCustomerSecureSessionVault()..unlockEnabled = true;
    final surface = MemoryCustomerSessionSurface();
    final unlock = FakeCustomerDeviceUnlock();
    final lock = _lock(vault: vault, unlock: unlock, surface: surface);
    final session = _session(
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    await vault.writeSessionJson(_jsonOf(session));
    await lock.attach();
    await lock.unlock(reason: 'open');

    CustomerBookingPresence.instance.enter();
    expect(await lock.lockIfNeeded(), isFalse);
    CustomerBookingPresence.instance.leave();
    await Future<void>.delayed(Duration.zero);

    expect(lock.isLocked, isTrue);
    expect(surface.peek(), isNull);
    lock.detach();
  });

  testWidgets('lock gate stays up after cancel and retries', (tester) async {
    final vault = MemoryCustomerSecureSessionVault()..unlockEnabled = true;
    final surface = MemoryCustomerSessionSurface();
    final unlock = FakeCustomerDeviceUnlock(
      result: CustomerUnlockResult.canceled,
    );
    final lock = _lock(vault: vault, unlock: unlock, surface: surface);
    final session = _session(
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    await vault.writeSessionJson(_jsonOf(session));
    await lock.restoreAtLaunch();

    await tester.pumpWidget(FluxidiCustomerApp(sessionLock: lock));
    await tester.pump();
    await tester.pump();
    expect(find.byType(CustomerSessionLockGate), findsOneWidget);

    unlock.result = CustomerUnlockResult.success;
    await tester.tap(find.byKey(const Key('customer_unlock_retry')));
    await tester.pumpAndSettle();
    expect(find.byType(CustomerSessionLockGate), findsNothing);
    expect(surface.peek()?.customerId, 'cus_1');
  });

  testWidgets(
    'background lock waits for a pushed page, keeps its input, then locks',
    (tester) async {
      final vault = MemoryCustomerSecureSessionVault()..unlockEnabled = true;
      final surface = MemoryCustomerSessionSurface();
      final unlock = FakeCustomerDeviceUnlock();
      final lock = _lock(vault: vault, unlock: unlock, surface: surface);
      final session = _session(
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );
      await vault.writeSessionJson(_jsonOf(session));
      await lock.attach();
      await lock.unlock(reason: 'open');
      unlock.result = CustomerUnlockResult.canceled;

      await tester.pumpWidget(
        FluxidiCustomerApp(
          sessionLock: lock,
          lockAfterBackground: Duration.zero,
        ),
      );
      await tester.pumpAndSettle();

      final homeContext = tester.element(find.byType(CustomerHomeScreen));
      Navigator.of(homeContext).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(
            body: TextField(
              key: Key('deferred_lock_draft'),
              decoration: InputDecoration(labelText: 'draft'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('deferred_lock_draft')),
        'Koekamerstraat 48A',
      );
      expect(find.text('Koekamerstraat 48A'), findsOneWidget);

      await _cycleAppThroughBackground(tester);

      expect(lock.isLocked, isFalse);
      expect(find.text('Koekamerstraat 48A'), findsOneWidget);
      expect(find.byType(CustomerSessionLockGate), findsNothing);

      Navigator.of(
        tester.element(find.byKey(const Key('deferred_lock_draft'))),
      ).pop();
      await tester.pumpAndSettle();

      expect(lock.isLocked, isTrue);
      expect(find.byType(CustomerSessionLockGate), findsOneWidget);
      expect(find.byType(CustomerHomeScreen), findsOneWidget);
    },
  );

  testWidgets(
    'background lock waits for the payment return then locks after close',
    (tester) async {
      final vault = MemoryCustomerSecureSessionVault()..unlockEnabled = true;
      final surface = MemoryCustomerSessionSurface();
      final unlock = FakeCustomerDeviceUnlock();
      final lock = _lock(vault: vault, unlock: unlock, surface: surface);
      final session = _session(
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );
      await vault.writeSessionJson(_jsonOf(session));
      await lock.attach();
      await lock.unlock(reason: 'open');
      unlock.result = CustomerUnlockResult.canceled;
      final source = _FakeDeepLinkSource();
      addTearDown(source.controller.close);

      await tester.pumpWidget(
        FluxidiCustomerApp(
          sessionLock: lock,
          deepLinkSource: source,
          lockAfterBackground: Duration.zero,
        ),
      );
      await tester.pumpAndSettle();

      source.controller.add(Uri.parse('fluxidicustomerdev://pay/return'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('payment_return_close')), findsOneWidget);

      await _cycleAppThroughBackground(tester);

      expect(lock.isLocked, isFalse);
      expect(find.byKey(const Key('payment_return_close')), findsOneWidget);

      await tester.tap(find.byKey(const Key('payment_return_close')));
      await tester.pumpAndSettle();

      expect(lock.isLocked, isTrue);
      expect(find.byType(CustomerSessionLockGate), findsOneWidget);
      expect(find.byType(CustomerHomeScreen), findsOneWidget);
    },
  );
}
