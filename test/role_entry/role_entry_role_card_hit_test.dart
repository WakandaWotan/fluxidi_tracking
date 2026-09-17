import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
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

void _installChannelMocks() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in _channelsToSilence) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
  }
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => Directory.systemTemp.path,
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

bool _customerFlowOpened(WidgetTester tester) {
  return _customerIntentTitle.evaluate().isNotEmpty ||
      find.byType(CustomerOnboardingPage).evaluate().isNotEmpty ||
      find.byType(CustomerHomePage).evaluate().isNotEmpty;
}

List<Object> _drainExceptions(WidgetTester tester) {
  final drained = <Object>[];
  while (true) {
    final exception = tester.takeException();
    if (exception == null) break;
    drained.add(exception);
  }
  return drained;
}

Future<void> _awaitCustomerIntent(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (_customerFlowOpened(tester)) return;
  }
  final rendered = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .where((s) => s.isNotEmpty)
      .take(40)
      .join(' | ');
  fail(
    'Customer flow did not open. role=${appRoleNotifier.value} '
    'exceptions=${_drainExceptions(tester)} Visible text: $rendered',
  );
}

bool _customerCardHasFocus(WidgetTester tester) {
  final focuses = find.descendant(
    of: find.byKey(kRoleEntryCustomerKey),
    matching: find.byType(Focus),
  );
  for (final element in focuses.evaluate()) {
    if (Focus.maybeOf(element)?.hasFocus == true) return true;
  }
  final primary = tester.binding.focusManager.primaryFocus;
  if (primary == null || !primary.hasFocus || primary.context == null) {
    return false;
  }
  return find
      .descendant(
        of: find.byKey(kRoleEntryCustomerKey),
        matching: find.byWidgetPredicate((widget) => identical(widget, primary.context!.widget)),
      )
      .evaluate()
      .isNotEmpty;
}

Future<void> _tabToCustomerCard(WidgetTester tester) async {
  final scope = FocusScope.of(tester.element(find.byType(RoleEntryPage)));
  scope.requestFocus();
  await tester.pump();
  for (var i = 0; i < 24; i++) {
    if (_customerCardHasFocus(tester)) return;
    scope.nextFocus();
    await tester.pump();
    if (_customerCardHasFocus(tester)) return;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  expect(
    _customerCardHasFocus(tester),
    isTrue,
    reason: 'Tab never reached Customer',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpOverrides? previousOverrides;

  setUp(() async {
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = _OfflineHttpOverrides();
    _installChannelMocks();
    appLanguageNotifier.value = AppLanguage.en;
    setAppRole(AppRole.driver);
    await CustomerSessionStore.instance.clear();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    _uninstallChannelMocks();
    HttpOverrides.global = previousOverrides;
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
    expect(
      source.contains('unawaited(\n      _bootstrapCustomerSessionAndMergeBookings'),
      isTrue,
    );
    expect(source.contains('CustomerPhoneRecoveryPage.newCustomerResult'), isTrue);
    expect(source.contains('LocalQaCustomerSessionAccess'), isTrue);
    expect(source.contains('rememberActiveCustomerId'), isTrue);
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
    'compact Windows Gold: customer card opens customer flow, not company',
    (tester) async {
      final companyBefore = CompanySessionStore.instance.hasValidCompanyContext;
      final sessionBefore = activeCompanySessionNotifier.value;
      await _pumpCompactWindowsRoleEntry(tester);

      expect(find.byKey(kRoleEntryCustomerKey), findsOneWidget);
      expect(find.byKey(roleEntryCarouselIndexKey(0)), findsOneWidget);
      expect(find.text('Choice remembered.'), findsOneWidget);

      final card = find.byKey(kRoleEntryCustomerKey);
      final rect = tester.getRect(card);
      expect(rect.width, greaterThanOrEqualTo(48));
      expect(rect.height, greaterThanOrEqualTo(48));

      await tester.tap(card);
      await _awaitCustomerIntent(tester);
      expect(find.text('Enter activation code'), findsNothing);
      expect(find.text('Link company'), findsNothing);
      expect(find.byKey(roleEntryCarouselIndexKey(1)), findsNothing);
      expect(appRoleNotifier.value, AppRole.customer);
      expect(
        CompanySessionStore.instance.hasValidCompanyContext,
        companyBefore,
      );
      expect(activeCompanySessionNotifier.value, sessionBefore);
      expect(find.text('Choice remembered.'), findsOneWidget);
      expect(_customerIntentTitle, findsOneWidget);
      expect(find.byType(BusinessHomePage), findsNothing);
    },
  );

  testWidgets(
    'compact Windows Gold: title and image taps stay on the customer target',
    (tester) async {
      await _pumpCompactWindowsRoleEntry(tester);
      final card = find.byKey(kRoleEntryCustomerKey);

      await tester.tap(
        find.descendant(of: card, matching: find.text('Customer')),
      );
      await _awaitCustomerIntent(tester);
      expect(_customerIntentTitle, findsOneWidget);
      expect(find.byKey(roleEntryCarouselIndexKey(0)), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(
        find.descendant(
          of: card,
          matching: find.byIcon(Icons.person_outline_rounded),
        ),
      );
      await _awaitCustomerIntent(tester);
      expect(_customerIntentTitle, findsOneWidget);
      expect(find.text('Enter activation code'), findsNothing);
    },
  );

  testWidgets('compact Windows Gold: taps near every card edge stay on target', (
    tester,
  ) async {
    await _pumpCompactWindowsRoleEntry(tester);
    final rect = tester.getRect(find.byKey(kRoleEntryCustomerKey));
    final edges = <Offset>[
      Offset(rect.left + 2, rect.center.dy),
      Offset(rect.right - 2, rect.center.dy),
      Offset(rect.center.dx, rect.top + 2),
      Offset(rect.center.dx, rect.bottom - 2),
    ];
    for (final point in edges) {
      await tester.tapAt(point);
      await _awaitCustomerIntent(tester);
      expect(_customerIntentTitle, findsOneWidget);
      expect(find.byKey(roleEntryCarouselIndexKey(0)), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
    }
  });

  testWidgets(
    'compact Windows Gold: background swipe outside cards still advances',
    (tester) async {
      await _pumpCompactWindowsRoleEntry(tester);
      expect(find.byKey(roleEntryCarouselIndexKey(0)), findsOneWidget);

      final card = tester.getRect(find.byKey(kRoleEntryCustomerKey));
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
    },
  );

  testWidgets(
    'compact Windows Gold: Tab / Enter / Space activate the customer card',
    (tester) async {
      await _pumpCompactWindowsRoleEntry(tester);
      await _tabToCustomerCard(tester);

      expect(
        tester.getSemantics(find.byKey(kRoleEntryCustomerKey)),
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

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _awaitCustomerIntent(tester);
      expect(_customerIntentTitle, findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      await _tabToCustomerCard(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _awaitCustomerIntent(tester);
      expect(_customerIntentTitle, findsOneWidget);
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
}
