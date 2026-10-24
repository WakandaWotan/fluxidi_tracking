import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/security/fluxidi_device_biometrics.dart';
import 'package:fluxidi_tracking/security/fluxidi_pin_unlock_page.dart';

class _FakeBiometrics implements FluxidiDeviceBiometrics {
  _FakeBiometrics({required this.available, required this.result});

  final bool available;
  final FluxidiBiometricResult result;
  int calls = 0;
  String? reason;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<FluxidiBiometricResult> authenticate({required String reason}) async {
    calls += 1;
    this.reason = reason;
    return result;
  }
}

Future<void> _pumpLock(
  WidgetTester tester, {
  required FluxidiDeviceBiometrics biometrics,
  required bool setupMode,
  required VoidCallback onUnlocked,
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: FluxidiPinUnlockPage(
        setupMode: setupMode,
        deviceBiometrics: biometrics,
        onUnlocked: onUnlocked,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('enrolled biometrics unlock the business session', (tester) async {
    final biometrics = _FakeBiometrics(
      available: true,
      result: FluxidiBiometricResult.success,
    );
    var unlocked = false;
    await _pumpLock(
      tester,
      biometrics: biometrics,
      setupMode: false,
      onUnlocked: () => unlocked = true,
    );

    expect(find.text('Use device biometrics'), findsOneWidget);
    expect(find.textContaining('Face ID'), findsNothing);
    expect(find.text('Unlock Fluxidi'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('business_biometric_unlock')));
    await tester.tap(find.byKey(const Key('business_biometric_unlock')));
    await tester.pump();

    expect(biometrics.calls, 1);
    expect(biometrics.reason, 'Unlock Fluxidi');
    expect(biometrics.reason!.toLowerCase().contains('face id'), isFalse);
    expect(unlocked, isTrue);
  });

  testWidgets('missing biometrics keep the PIN keypad', (tester) async {
    final biometrics = _FakeBiometrics(
      available: false,
      result: FluxidiBiometricResult.success,
    );
    var unlocked = false;
    await _pumpLock(
      tester,
      biometrics: biometrics,
      setupMode: false,
      onUnlocked: () => unlocked = true,
    );

    expect(find.text('Biometrics not available'), findsOneWidget);
    expect(find.textContaining('Face ID'), findsNothing);
    expect(find.text('0'), findsWidgets);
    expect(find.text('1'), findsWidgets);

    await tester.tap(find.byKey(const Key('business_biometric_unlock')));
    await tester.pump();

    expect(biometrics.calls, 0);
    expect(unlocked, isFalse);
  });

  testWidgets('a canceled biometric prompt stays on the PIN screen', (
    tester,
  ) async {
    final biometrics = _FakeBiometrics(
      available: true,
      result: FluxidiBiometricResult.canceled,
    );
    var unlocked = false;
    await _pumpLock(
      tester,
      biometrics: biometrics,
      setupMode: false,
      onUnlocked: () => unlocked = true,
    );

    await tester.tap(find.byKey(const Key('business_biometric_unlock')));
    await tester.pump();

    expect(biometrics.calls, 1);
    expect(unlocked, isFalse);
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Unlock Fluxidi'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
  });

  testWidgets('PIN setup does not skip the keypad via biometrics', (tester) async {
    final biometrics = _FakeBiometrics(
      available: true,
      result: FluxidiBiometricResult.success,
    );
    var unlocked = false;
    await _pumpLock(
      tester,
      biometrics: biometrics,
      setupMode: true,
      onUnlocked: () => unlocked = true,
    );

    expect(find.text('Biometrics not available'), findsOneWidget);
    expect(find.text('Set your PIN'), findsOneWidget);
    await tester.tap(find.byKey(const Key('business_biometric_unlock')));
    await tester.pump();
    expect(biometrics.calls, 0);
    expect(unlocked, isFalse);
  });
}
