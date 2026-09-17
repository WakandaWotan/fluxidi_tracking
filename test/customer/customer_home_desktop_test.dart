import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer/customer_home_desktop.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
import 'package:fluxidi_tracking/main.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('fluxidi_customer_desktop_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> pumpHome(WidgetTester tester, Size size) async {
    appLanguageNotifier.value = AppLanguage.nl;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(size);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      buildFluxidiRootMaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const CustomerHomePage(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('wide window uses the approved desktop shell', (tester) async {
    await pumpHome(tester, const Size(1440, 900));
    expect(find.byKey(kCustomerHomeDesktopShellKey), findsOneWidget);
    expect(find.byKey(kCustomerHomeDesktopSidebarKey), findsOneWidget);
    expect(find.byKey(kCustomerHomeNavHomeKey), findsOneWidget);
    expect(find.byKey(kCustomerHomeNavTaxiKey), findsOneWidget);
    expect(find.byKey(kCustomerHomeNavBookingsKey), findsOneWidget);
    expect(find.byKey(kCustomerHomeNavProfileKey), findsOneWidget);
    expect(find.byKey(kCustomerHomeNearbyKey), findsOneWidget);
    expect(find.byKey(kCustomerHomeRadarKey), findsOneWidget);
    expect(find.byKey(kCustomerHomePrivacyKey), findsOneWidget);
    expect(find.byKey(kCustomerHomeNavThemeKey), findsOneWidget);
    expect(find.byKey(kCustomerHomeNavStartKey), findsOneWidget);
    expect(find.byKey(kCustomerHomeSearchRideKey), findsOneWidget);
    expect(find.byKey(kCustomerHomeDesktopDiscoverKey), findsOneWidget);
    expect(find.byKey(kCustomerHomeDesktopScrollKey), findsOneWidget);
    expect(find.byKey(kCustomerHomeNearbyKey), findsOneWidget);
    expect(find.byKey(kCustomerHomeRadarKey), findsOneWidget);
    expect(find.text('Taxi dichtbij'), findsNothing);
    expect(find.text('Christophe'), findsNothing);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byKey(kCustomerHomeTaglineKey), findsOneWidget);
    expect(find.textContaining('Waar brengt je dag je naartoe?'), findsOneWidget);
    expect(find.text('Zoek mijn rit'), findsOneWidget);
    expect(find.text('Ontdek Fluxidi'), findsOneWidget);
    expect(find.text('Taxi'), findsWidgets);
    expect(find.text('Luchthaven'), findsOneWidget);
    expect(find.text('Hotels & B&B'), findsWidgets);
    expect(find.text('Evenementen'), findsWidgets);
    expect(find.text('Zakelijk'), findsWidgets);
    expect(find.text('Limousine'), findsWidgets);
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    tester.view.physicalSize = const Size(1920, 1080);
    await tester.pump();
    expect(find.byKey(kCustomerHomeDesktopShellKey), findsOneWidget);
    expect(find.byKey(kCustomerHomeSearchRideKey), findsOneWidget);
  });

  testWidgets('narrow window keeps the existing mobile home', (tester) async {
    await pumpHome(tester, const Size(390, 844));
    expect(find.byKey(kCustomerHomeDesktopShellKey), findsNothing);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.byKey(kCustomerHomeSearchRideKey), findsNothing);
  });

  testWidgets('desktop search ride opens the taxi booking with typed destination', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1440, 900));
    await tester.enterText(
      find.byKey(kCustomerHomeDropoffKey),
      'Gent Sint-Pietersstation',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(kCustomerHomeSearchRideKey));
    await tester.tap(find.byKey(kCustomerHomeSearchRideKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(kCustomerBookingFlowKey), findsOneWidget);
    expect(find.byKey(kCustomerBookingTitleKey), findsOneWidget);
    expect(find.textContaining('Gent Sint-Pietersstation'), findsWidgets);
  });

  testWidgets('typing a destination keeps the booking panel visible', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1440, 900));
    final before = tester.getSize(
      find.byKey(kCustomerHomeDesktopBookingPanelKey),
    );
    await tester.enterText(find.byKey(kCustomerHomeDropoffKey), 'Gent');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.byKey(kCustomerHomeDesktopBookingPanelKey), findsOneWidget);
    expect(find.byKey(kCustomerHomeDesktopDiscoverKey), findsOneWidget);
    expect(find.text('Ontdek Fluxidi'), findsOneWidget);
    expect(find.byKey(kCustomerHomeSearchRideKey), findsOneWidget);
    final after = tester.getSize(
      find.byKey(kCustomerHomeDesktopBookingPanelKey),
    );
    expect(after.height, lessThan(520));
    expect(after.height, lessThanOrEqualTo(before.height + 200));
    expect(find.text('Gent'), findsWidgets);
  });

  testWidgets('resize keeps typed destination when returning to desktop', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1440, 900));
    await tester.enterText(
      find.byKey(kCustomerHomeDropoffKey),
      'Antwerpen Centraal',
    );
    await tester.pump();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    expect(find.byKey(kCustomerHomeDesktopShellKey), findsNothing);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pump();
    expect(find.byKey(kCustomerHomeDesktopShellKey), findsOneWidget);
    expect(find.text('Antwerpen Centraal'), findsWidgets);
  });
}
