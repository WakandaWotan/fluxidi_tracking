import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/driver_management_host_entry.dart';
import 'package:fluxidi_tracking/company/driver_management_read_entry.dart';

void main() {
  test(
    'auth, permissions, snapshot and connection failures are distinguished safely',
    () async {
      for (final entry in {
        401: DriverManagementAccess.signIn,
        403: DriverManagementAccess.forbidden,
        409: DriverManagementAccess.sourceUnavailable,
        404: DriverManagementAccess.hostUnavailable,
        503: DriverManagementAccess.hostUnavailable,
      }.entries) {
        expect(
          await driverManagementReadAccess(
            entry: DriverManagementHostEntry('https://operator.test'),
            companyId: 'own',
            get: (_) async => (
              status: entry.key,
              body: jsonEncode({'private': 'never display upstream body'}),
            ),
            sessionUnchanged: () async => true,
          ),
          entry.value,
        );
      }
    },
  );
  for (final result in DriverManagementAccess.values.where(
    (a) => a != DriverManagementAccess.ready,
  )) {
    testWidgets('$result remains discoverable, blocked and retryable', (
      tester,
    ) async {
      final session = ValueNotifier<Object?>('session');
      var probes = 0, opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DriverManagementReadEntryButton(
              enabled: true,
              session: session,
              label: 'Uitgebreid chauffeurbeheer',
              probe: () async => false,
              accessProbe: () async {
                probes++;
                return result;
              },
              open: () async {
                opens++;
              },
              tooltip: 'Overview',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Uitgebreid chauffeurbeheer'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('driver-management-read-entry')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(
        find.byKey(const ValueKey('driver-management-access-retry')),
      );
      await tester.pump();
      expect(probes, 2);
      expect(opens, 0);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });
  }
  testWidgets(
    'missing login recovers via normal company login and revalidates',
    (tester) async {
      final session = ValueNotifier<Object?>(null);
      var recovered = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DriverManagementReadEntryButton(
              enabled: true,
              session: session,
              label: 'Uitgebreid chauffeurbeheer',
              probe: () async => true,
              recoverSession: () async {
                recovered++;
                session.value = 'genuine-session';
              },
              open: () async {},
              tooltip: 'Overview',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('driver-management-access-retry')),
      );
      await tester.pump();
      expect(recovered, 1);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('driver-management-read-entry')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  for (final width in [320.0, 360.0, 400.0, 800.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('entry fits width $width text scale $scale', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final session = ValueNotifier<Object?>('session');
        var opens = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(26),
                  child: DriverManagementReadEntryButton(
                    enabled: true,
                    session: session,
                    label: 'Uitgebreid chauffeurbeheer',
                    probe: () async => true,
                    open: () async {
                      opens++;
                    },
                    tooltip: 'Overview',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('driver-management-read-entry')),
        );
        await tester.pump();
        expect(opens, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      });
    }
  }
}
