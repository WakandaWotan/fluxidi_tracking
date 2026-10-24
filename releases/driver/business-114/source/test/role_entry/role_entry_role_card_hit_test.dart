import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:fluxidi_tracking/main.dart';
import 'package:fluxidi_tracking/nearby/stap3_flow_keys.dart';
import 'package:fluxidi_tracking/role_entry/role_entry_carousel_host.dart';
import 'package:fluxidi_tracking/role_entry/role_entry_role_card.dart';

const Size _kCompactWindowsGold = Size(1100, 700);

const List<String> _channelsToSilence = <String>[
  'plugins.flutter.io/path_provider',
  'plugins.flutter.io/shared_preferences',
  'plugins.flutter.io/flutter_secure_storage',
  'flutter.baseflow.com/geolocator',
  'flutter.baseflow.com/geolocator_android',
  'flutter.baseflow.com/geolocator_updates_android',
  'flutter.baseflow.com/permissions/methods',
  'dev.fluttercommunity.plus/wakelock_plus',
  'dev.fluttercommunity.plus/connectivity',
  'dev.fluttercommunity.plus/connectivity_status',
  'plugins.flutter.io/url_launcher_android',
  'flutter.baseflow.com/image_picker_android',
  'plugins.flutter.io/file_picker',
  'com.llfbandit.app_links/messages',
  'com.llfbandit.app_links/events',
];

void _installChannelMocks(String testRoot) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in _channelsToSilence) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
  }
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => testRoot,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/shared_preferences'),
    (call) async {
      if (call.method == 'getAll') return <String, Object>{};
      return true;
    },
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/flutter_secure_storage'),
    (call) async {
      if (call.method == 'readAll') return <String, String>{};
      return null;
    },
  );
}

void _uninstallChannelMocks() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in _channelsToSilence) {
    messenger.setMockMethodCallHandler(MethodChannel(name), null);
  }
}

class _OfflineHttpClient implements HttpClient {
  @override
  noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    if (invocation.isMethod && name.contains('close')) return null;
    if (invocation.isSetter) return null;
    if (invocation.isMethod) {
      return Future<HttpClientRequest>.error(
        const SocketException('blocked_in_test'),
      );
    }
    return null;
  }
}

class _OfflineHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _OfflineHttpClient();
}

Future<void> _pumpCompactWindowsRoleEntry(WidgetTester tester) async {
  tester.view.physicalSize = _kCompactWindowsGold;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.binding.setSurfaceSize(_kCompactWindowsGold);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    buildFluxidiRootMaterialApp(
      theme: ThemeData.dark(),
      home: const RoleEntryPage(autoAdvanceCarousel: false),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Finder get _customerIntentTitle => find.textContaining(
      RegExp(r'^(Start as customer|Klant starten)$'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await DriverSessionStore.instance.clearNativeDutyOwnership();
  });

  late HttpOverrides? previousOverrides;
  late Directory testRoot;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = _OfflineHttpOverrides();
    testRoot = Directory.systemTemp.createTempSync('p13_role_entry_');
    _installChannelMocks(testRoot.path);
    appLanguageNotifier.value = AppLanguage.en;
    setAppRole(AppRole.driver);
    await CustomerSessionStore.instance.clear();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    _uninstallChannelMocks();
    HttpOverrides.global = previousOverrides;
    if (testRoot.existsSync()) {
      final path = testRoot.resolveSymbolicLinksSync();
      final prefix = '${Directory.systemTemp.resolveSymbolicLinksSync()}${Platform.pathSeparator}p13_role_entry_';
      if (!path.toLowerCase().startsWith(prefix.toLowerCase())) throw StateError('Unsafe test fixture cleanup');
      testRoot.deleteSync(recursive: true);
    }
  });

  test('role entry no longer allocates Stream.periodic inside build', () {
    final source = File(
      '${Directory.current.path}/lib/main_parts/role_entry_page.dart',
    ).readAsStringSync();
    expect(source.contains('Stream<int>.periodic'), isFalse);
    expect(source.contains('RoleEntryCarouselHost'), isTrue);
    expect(source.contains('RoleEntryRoleCard'), isTrue);
    expect(source.contains('IgnorePointer'), isTrue);
    expect(source.contains('kRoleEntryCarouselBackgroundKey'), isTrue);
    expect(source.contains('navigator.mounted'), isTrue);
    expect(source.contains('kRoleEntryCustomerKey'), isFalse);
    expect(source.contains('localQaCustomerSession'), isFalse);
    expect(source.contains('_goCustomer'), isFalse);
    expect(source.contains('_goBusiness'), isTrue);
    expect(source.contains('_goDriver'), isTrue);
    expect(source.contains('kRoleEntryBusinessKey'), isTrue);
    expect(source.contains('kRoleEntryDriverKey'), isTrue);
  });

  testWidgets('carousel host keeps its index across parent rebuilds', (
    tester,
  ) async {
    var hostBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RoleEntryCarouselHost(
          assetCount: 4,
          autoAdvance: false,
          builder: (context, index, advanceBy) {
            hostBuilds += 1;
            return GestureDetector(
              onTap: () => advanceBy(1),
              child: Text('frame-$index'),
            );
          },
        ),
      ),
    );
    expect(find.text('frame-0'), findsOneWidget);
    await tester.tap(find.text('frame-0'));
    await tester.pump();
    expect(find.text('frame-1'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: RoleEntryCarouselHost(
          assetCount: 4,
          autoAdvance: false,
          builder: (context, index, advanceBy) {
            hostBuilds += 1;
            return GestureDetector(
              onTap: () => advanceBy(1),
              child: Text('frame-$index'),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('frame-1'), findsOneWidget);
    expect(hostBuilds, greaterThanOrEqualTo(2));
  });

  testWidgets('role card center, title, image and edges fire the same action', (
    tester,
  ) async {
    var taps = 0;
    const key = Key('isolated_role_card');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 392,
              child: RoleEntryRoleCard(
                key: key,
                title: 'Customer',
                subtitle: 'Book your ride.',
                icon: Icons.person_outline_rounded,
                height: 88,
                onPressed: () => taps += 1,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final card = find.byKey(key);
    final rect = tester.getRect(card);
    expect(rect.width, greaterThanOrEqualTo(48));
    expect(rect.height, greaterThanOrEqualTo(48));

    await tester.tap(card);
    await tester.pump();
    expect(taps, 1);

    await tester.tap(
      find.descendant(of: card, matching: find.text('Customer')),
    );
    await tester.pump();
    expect(taps, 2);

    await tester.tap(
      find.descendant(
        of: card,
        matching: find.byIcon(Icons.person_outline_rounded),
      ),
    );
    await tester.pump();
    expect(taps, 3);

    await tester.tapAt(Offset(rect.left + 3, rect.center.dy));
    await tester.tapAt(Offset(rect.right - 3, rect.center.dy));
    await tester.tapAt(Offset(rect.center.dx, rect.top + 3));
    await tester.tapAt(Offset(rect.center.dx, rect.bottom - 3));
    await tester.pump();
    expect(taps, 7);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 8);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(taps, 9);

    expect(
      tester.getSemantics(card),
      matchesSemantics(
        label: 'Customer',
        isButton: true,
        isEnabled: true,
        isFocusable: true,
        isFocused: true,
        hasTapAction: true,
        hasEnabledState: true,
      ),
    );
  });

  testWidgets(
    'compact Windows Gold: Business/Driver entry has no customer card',
    (tester) async {
      await _pumpCompactWindowsRoleEntry(tester);

      expect(find.byKey(kRoleEntryCustomerKey), findsNothing);
      expect(find.text('Customer'), findsNothing);
      expect(find.text('Book your ride.'), findsNothing);
      expect(_customerIntentTitle, findsNothing);
      expect(find.byKey(kRoleEntryBusinessKey), findsOneWidget);
      expect(find.byKey(kRoleEntryDriverKey), findsOneWidget);
      expect(find.text('Business'), findsOneWidget);
      expect(find.text('Driver'), findsOneWidget);
      expect(find.text('Manage your fleet.'), findsOneWidget);
      expect(find.text('Start and drive rides.'), findsOneWidget);
      expect(find.byKey(roleEntryCarouselIndexKey(0)), findsOneWidget);
      expect(find.text('Choice remembered.'), findsOneWidget);

      final business = tester.getRect(find.byKey(kRoleEntryBusinessKey));
      final driver = tester.getRect(find.byKey(kRoleEntryDriverKey));
      expect(business.width, greaterThanOrEqualTo(48));
      expect(business.height, greaterThanOrEqualTo(48));
      expect(driver.width, greaterThanOrEqualTo(48));
      expect(driver.height, greaterThanOrEqualTo(48));
    },
  );

  testWidgets(
    'compact Windows Gold: background swipe outside cards still advances',
    (tester) async {
      await _pumpCompactWindowsRoleEntry(tester);
      expect(find.byKey(roleEntryCarouselIndexKey(0)), findsOneWidget);

      final card = tester.getRect(find.byKey(kRoleEntryBusinessKey));
      final swipeFrom = Offset(24, card.center.dy);
      expect(card.contains(swipeFrom), isFalse);

      await tester.timedDragFrom(
        swipeFrom,
        const Offset(-320, 0),
        const Duration(milliseconds: 160),
      );
      await tester.pump();
      expect(find.byKey(roleEntryCarouselIndexKey(1)), findsOneWidget);
      expect(_customerIntentTitle, findsNothing);
      expect(find.text('Enter activation code'), findsNothing);
    },
  );

  testWidgets('compact Windows Gold: business card stays on the company path', (
    tester,
  ) async {
    await _pumpCompactWindowsRoleEntry(tester);
    await tester.tap(find.byKey(kRoleEntryBusinessKey));
    for (var i = 0; i < 40; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.text('Enter activation code').evaluate().isNotEmpty ||
          find.text('Activatiecode invoeren').evaluate().isNotEmpty ||
          find.byType(BusinessHomePage).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(_customerIntentTitle, findsNothing);
    expect(
      find.text('Enter activation code').evaluate().isNotEmpty ||
          find.text('Activatiecode invoeren').evaluate().isNotEmpty ||
          find.byType(BusinessHomePage).evaluate().isNotEmpty,
      isTrue,
    );
  });

  testWidgets('compact Windows Gold: driver card opens chauffeur login', (
    tester,
  ) async {
    await _pumpCompactWindowsRoleEntry(tester);
    await tester.tap(find.byKey(kRoleEntryDriverKey));
    for (var i = 0; i < 40; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byType(ChauffeurLoginPage).evaluate().isNotEmpty ||
          find.byType(DriverHomePage).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(_customerIntentTitle, findsNothing);
    expect(find.byKey(kRoleEntryCustomerKey), findsNothing);
    expect(find.byType(ChauffeurLoginPage), findsOneWidget);
    expect(find.byType(DriverHomePage), findsNothing);
  });

  testWidgets('saved driver session enters server gate without requesting code', (
    tester,
  ) async {
    await tester.runAsync(
      () => DriverSessionStore.instance.saveBackendDriverLoginSession(
        tenantId: 'tenant-role-entry',
        companyId: 'company-role-entry',
        driverId: 'drv-role-entry',
        driverName: 'Bewaarde chauffeur',
        companyDisplayName: 'Testbedrijf',
        driverSessionToken: 'stored-session-token',
        expiresInSeconds: 3600,
      ),
    );
    addTearDown(() async {
      var cleared = false;
      DriverSessionStore.instance.clear().then((_) => cleared = true);
      for (var i = 0; i < 40 && !cleared; i++) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      expect(cleared, isTrue, reason: 'Filesystem session cleanup must complete before the fake async zone closes');
    });
    expect(activeDriverSessionNotifier.value, isNotNull);
    expect(
      activeDriverSessionNotifier.value!.isPublicDriverLoginSession,
      isTrue,
    );

    await _pumpCompactWindowsRoleEntry(tester);
    await tester.tap(find.byKey(kRoleEntryDriverKey));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      if (find.byType(DriverSessionGatePage).evaluate().isNotEmpty) break;
    }

    expect(find.byType(DriverSessionGatePage), findsOneWidget);
    expect(find.byType(ChauffeurLoginPage), findsNothing);
    expect(find.byType(DriverHomePage), findsNothing);
    expect(activeDriverSessionNotifier.value, isNotNull);
    expect(activeDriverSessionNotifier.value!.driverId, 'drv-role-entry');
  });

  test('startup validates a stored driver bearer before mounting the dashboard', () {
    final source = File(
      '${Directory.current.path}/lib/main.dart',
    ).readAsStringSync();
    expect(source.contains('_startInDriverHome = true'), isTrue);
    expect(
      source.contains(
        'target=driver_session_gate reason=stored_bearer',
      ),
      isTrue,
    );
    expect(source.contains('const DriverSessionGatePage()'), isTrue);
  });
}
