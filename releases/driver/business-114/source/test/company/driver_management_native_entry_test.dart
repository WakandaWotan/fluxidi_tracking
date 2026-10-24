import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fluxidi_tracking/main.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/driver_management_read_entry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    final fixture = Directory(
      'D:/Projecten/outputs/business_native_driver_management_20261012/native-fixture',
    )..createSync(recursive: true);
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => fixture.path,
        );
  });
  for (final width in [320.0, 400.0, 800.0]) {
    testWidgets(
      'Actual company entry opens original in-app environment width $width and preserves legacy route',
      (tester) async {
        expect(
          driverManagementReadVerified,
          isTrue,
          reason: 'Run this test with the exact release define.',
        );
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        appLanguageNotifier.value = AppLanguage.nl;
        driversNotifier.value = [
          const DriverProfile(
            id: 'phone-fixture',
            fullName: 'Een chauffeur met een lange volledige naam',
            employeeNumber: 'fixture',
            phone: '',
            isActive: true,
          ),
        ];
        await tester.pumpWidget(
          const MaterialApp(home: CompanyDriverManagementPage()),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        for (
          var i = 0;
          i < 10 &&
              find
                  .byKey(const ValueKey('native-driver-error'))
                  .evaluate()
                  .isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
        }
        expect(
          find.byKey(const ValueKey('native-driver-management-page')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('native-driver-error')),
          findsOneWidget,
        );
        expect(find.textContaining('Draai je tablet'), findsNothing);
        expect(find.text('Nieuw overzicht'), findsNothing);
        await tester.tap(find.text('Meer herstelopties'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('native-driver-legacy')),
          250,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .first,
        );
        await tester.tap(find.byKey(const ValueKey('native-driver-legacy')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('company-driver-management-title')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('native-driver-management-page')),
          findsNothing,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('native-driver-management-page')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
}
