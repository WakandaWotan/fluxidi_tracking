import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_customer/app/customer_app_config.dart';
import 'package:fluxidi_customer/app/fluxidi_customer_app.dart';
import 'package:fluxidi_customer/deeplinks/customer_deep_link_source.dart';
import 'package:fluxidi_customer/screens/customer_home_screen.dart';
import 'package:fluxidi_customer/screens/customer_profile_screen.dart';
import 'package:fluxidi_customer/widgets/customer_header_bar.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';

/// Link source that never touches a platform channel.
class _FakeDeepLinkSource implements CustomerDeepLinkSource {
  _FakeDeepLinkSource({this.initial});

  final Uri? initial;
  final StreamController<Uri> controller = StreamController<Uri>.broadcast();

  @override
  Future<Uri?> initialLink() async => initial;

  @override
  Stream<Uri> linkStream() => controller.stream;
}

/// Galaxy Tab S10 Lite (SM_X400) landscape, from the connected device:
/// physical 2112×1320, density 240, status bar 45 px, gesture inset 72 px.
void _applyGalaxyTabS10LiteLandscape(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.5;
  tester.view.physicalSize = const Size(2112, 1320);
  tester.view.padding = const FakeViewPadding(top: 30, bottom: 48);
  tester.view.viewPadding = const FakeViewPadding(top: 30, bottom: 48);
}

class _TabletLandscapeHomeMetrics {
  const _TabletLandscapeHomeMetrics({
    required this.viewport,
    required this.safeAreaTop,
    required this.safeAreaBottom,
    required this.shellBody,
    required this.navHeight,
    required this.navTop,
    required this.contentHeight,
    required this.listBottomPadding,
    required this.cardHeight,
    required this.logoHeight,
    required this.radar,
    required this.gapRadarToNav,
  });

  final Size viewport;
  final double safeAreaTop;
  final double safeAreaBottom;
  final double shellBody;
  final double navHeight;
  final double navTop;
  final double contentHeight;
  final double listBottomPadding;
  final double cardHeight;
  final double logoHeight;
  final Rect radar;
  final double gapRadarToNav;

  String toDebugString() {
    return 'tablet-landscape '
        'viewport=${viewport.width}x${viewport.height} '
        'safeArea=($safeAreaTop,$safeAreaBottom) '
        'shellBody=$shellBody nav=$navHeight navTop=$navTop '
        'content=$contentHeight listBottomPad=$listBottomPadding '
        'card=$cardHeight logo=$logoHeight '
        'radarBottom=${radar.bottom} gapRadarToNav=$gapRadarToNav';
  }
}

_TabletLandscapeHomeMetrics _measureTabletLandscapeHome(WidgetTester tester) {
  final viewport =
      tester.view.physicalSize / tester.view.devicePixelRatio;
  final nav = tester.getRect(find.byKey(const Key('customer_bottom_nav')));
  final home = tester.getRect(find.byType(CustomerHomeScreen));
  final radar = tester.getRect(
    find.byKey(const Key('customer_home_region_radar')),
  );
  final card = tester.getSize(
    find.byKey(const Key('customer_home_service_airport')),
  );
  final logo = tester.getSize(find.byKey(const Key('customer_header_logo')));
  final scrollable = find.descendant(
    of: find.byType(CustomerHomeScreen),
    matching: find.byType(Scrollable),
  );
  final scrollTop = scrollable.evaluate().isEmpty
      ? home.top
      : tester.getTopLeft(scrollable.first).dy;

  return _TabletLandscapeHomeMetrics(
    viewport: viewport,
    safeAreaTop: tester.view.padding.top,
    safeAreaBottom: tester.view.padding.bottom,
    shellBody: home.height,
    navHeight: nav.height,
    navTop: nav.top,
    contentHeight: radar.bottom - scrollTop,
    listBottomPadding: nav.top - radar.bottom,
    cardHeight: card.height,
    logoHeight: logo.height,
    radar: radar,
    gapRadarToNav: nav.top - radar.bottom,
  );
}

/// Brings an item of the scrolling page into view before asserting on it.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) return;
  await tester.scrollUntilVisible(
    finder,
    280,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // main() restores the stored language; a widget test pins it instead so the
    // expected labels do not depend on the previous test's choice.
    setAppLanguage(AppLanguage.nl);
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });

  test('header logo uses the left band and stays readable on a phone', () {
    expect(
      headerLogoHeight(
        availableWidth: 560,
        screenWidth: 800,
        screenHeight: 1280,
        barHeight: 56,
      ),
      closeTo(52, 0.1),
    );
    expect(
      headerLogoHeight(
        availableWidth: 980,
        screenWidth: 1280,
        screenHeight: 800,
        barHeight: 56,
      ),
      closeTo(52, 0.1),
    );
    expect(
      headerLogoHeight(
        availableWidth: 190,
        screenWidth: 360,
        screenHeight: 780,
        barHeight: 48,
      ),
      closeTo(40.7, 0.2),
    );
  });

  testWidgets('home shows the destination field and every service', (
    tester,
  ) async {
    await tester.pumpWidget(const FluxidiCustomerApp());
    await tester.pumpAndSettle();

    expect(find.text('Waar wil je naartoe?'), findsOneWidget);
    expect(find.byKey(const Key('customer_home_destination')), findsOneWidget);
    expect(find.byKey(const Key('customer_home_book_taxi')), findsOneWidget);

    for (final key in <String>[
      'customer_home_service_airport',
      'customer_home_service_hotels',
      'customer_home_service_events',
      'customer_home_service_limousine',
      'customer_home_region_radar',
    ]) {
      await _scrollTo(tester, find.byKey(Key(key)));
      expect(find.byKey(Key(key)), findsOneWidget, reason: 'missing $key');
    }
  });

  testWidgets('the bottom bar has Home, Boekingen and Profiel', (tester) async {
    await tester.pumpWidget(const FluxidiCustomerApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('customer_bottom_nav')), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Boekingen'), findsOneWidget);
    expect(find.text('Profiel'), findsOneWidget);
  });

  testWidgets('Spanish updates home cards and the bottom bar immediately', (
    tester,
  ) async {
    await tester.pumpWidget(const FluxidiCustomerApp());
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.byKey(const Key('customer_home_service_airport')));
    expect(find.text('Luchthavenritten'), findsOneWidget);
    expect(find.text('Boekingen'), findsOneWidget);
    expect(find.text('Profiel'), findsOneWidget);

    await tester.tap(find.byKey(const Key('customer_header_language')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customer_language_es')));
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.byKey(const Key('customer_home_service_airport')));
    expect(find.text('Traslados al aeropuerto'), findsOneWidget);
    expect(find.text('Hoteles y B&B'), findsOneWidget);
    expect(find.text('Eventos'), findsOneWidget);
    expect(find.text('Limusina'), findsOneWidget);
    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Reservas'), findsOneWidget);
    expect(find.text('Perfil'), findsOneWidget);
    expect(find.text('Luchthavenritten'), findsNothing);
    expect(find.text('Boekingen'), findsNothing);

    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    expect(find.byType(CustomerProfileScreen), findsOneWidget);
    expect(find.text('Mis datos'), findsWidgets);
    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
    expect(find.text('Traslados al aeropuerto'), findsOneWidget);
  });

  testWidgets('Profiel offers details, bookings, language, theme and account', (
    tester,
  ) async {
    await tester.pumpWidget(const FluxidiCustomerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profiel'));
    await tester.pumpAndSettle();

    expect(find.byType(CustomerProfileScreen), findsOneWidget);
    for (final key in <String>[
      'customer_profile_my_details',
      'customer_profile_my_bookings',
      'customer_profile_language',
      'customer_profile_theme',
      'customer_profile_privacy',
    ]) {
      await _scrollTo(tester, find.byKey(Key(key)));
      expect(find.byKey(Key(key)), findsOneWidget, reason: 'missing $key');
    }
    // These belong in the booking flow, not on the profile page.
    expect(find.text('Zakelijke rit'), findsNothing);
    expect(find.text('Taxi in de buurt'), findsNothing);
  });

  testWidgets('home renders on phone and tablet, portrait and landscape', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;

    const sizes = <String, Size>{
      'phone portrait': Size(390, 844),
      'phone landscape': Size(844, 390),
      'tablet portrait': Size(800, 1280),
      'tablet landscape': Size(1280, 800),
    };

    for (final entry in sizes.entries) {
      tester.view.physicalSize = entry.value;
      await tester.pumpWidget(const FluxidiCustomerApp());
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'layout overflowed on ${entry.key}',
      );
      await _scrollTo(
        tester,
        find.byKey(const Key('customer_home_service_airport')),
      );
      expect(
        find.byKey(const Key('customer_home_service_airport')),
        findsOneWidget,
        reason: 'service card missing on ${entry.key}',
      );
    }
  });

  testWidgets('tablet stacks the service cards in portrait, two up in '
      'landscape', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;

    tester.view.physicalSize = const Size(800, 1280);
    await tester.pumpWidget(const FluxidiCustomerApp());
    await tester.pumpAndSettle();
    final portraitFinder = find.byKey(const Key('customer_home_service_airport'));
    await _scrollTo(tester, portraitFinder);
    final portrait = tester.getSize(portraitFinder);
    expect(portrait.width, greaterThan(600));
    expect(portrait.height, inInclusiveRange(176, 200));
    final portraitLogo = tester.getRect(
      find.byKey(const Key('customer_header_logo')),
    );
    final portraitHeader = tester.getRect(find.byType(CustomerHeaderBar));
    final portraitLanguage = tester.getRect(
      find.byKey(const Key('customer_header_language')),
    );
    expect(portraitLogo.height, closeTo(52, 1));
    expect(portraitLogo.right, lessThan(portraitLanguage.left - 4));
    expect((portraitLogo.left - portraitHeader.left).abs(), lessThan(2));

    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpWidget(const FluxidiCustomerApp());
    await tester.pumpAndSettle();
    final landscape = tester.getSize(
      find.byKey(const Key('customer_home_service_airport')),
    );
    expect(landscape.width, lessThan(portrait.width));
    expect(landscape.width, greaterThan(500));
    final landscapeLogo = tester.getRect(
      find.byKey(const Key('customer_header_logo')),
    );
    final landscapeHeader = tester.getRect(find.byType(CustomerHeaderBar));
    expect(landscapeLogo.height, closeTo(52, 1));
    expect((landscapeLogo.left - landscapeHeader.left).abs(), lessThan(2));
  });

  testWidgets('tablet portrait keeps Region Radar fully above the navigation', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1280);

    await tester.pumpWidget(const FluxidiCustomerApp());
    await tester.pumpAndSettle();

    final nav = tester.getRect(find.byKey(const Key('customer_bottom_nav')));
    final radar = tester.getRect(
      find.byKey(const Key('customer_home_region_radar')),
    );
    final card = tester.getSize(
      find.byKey(const Key('customer_home_service_airport')),
    );
    final logo = tester.getSize(find.byKey(const Key('customer_header_logo')));

    expect(radar.bottom, lessThanOrEqualTo(nav.top - 12));
    expect(nav.top - radar.bottom, inInclusiveRange(12, 24));
    expect(card.width, greaterThan(600));
    expect(card.height, inInclusiveRange(176, 200));
    expect(logo.height, closeTo(52, 1));

    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('customer_home_region_radar')),
      200,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    expect(find.byKey(const Key('customer_home_region_radar')), findsOneWidget);
  });

  testWidgets(
    'phone keeps a readable left-aligned logo clear of the compact chips',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 780);
      await tester.pumpWidget(const FluxidiCustomerApp());
      await tester.pumpAndSettle();

      final logo = tester.getRect(
        find.byKey(const Key('customer_header_logo')),
      );
      final header = tester.getRect(find.byType(CustomerHeaderBar));
      final title = tester.getRect(find.text('Waar wil je naartoe?'));
      final language = tester.getRect(
        find.byKey(const Key('customer_header_language')),
      );
      final theme = tester.getRect(
        find.byKey(const Key('customer_header_palette')),
      );
      expect((logo.left - header.left).abs(), lessThan(2));
      expect((logo.left - title.left).abs(), lessThan(2));
      expect(logo.right, lessThan(language.left - 4));
      expect(theme.right, lessThanOrEqualTo(header.right + 1));
      expect(logo.height, greaterThan(32));
      expect(
        (logo.width / logo.height - kCustomerHeaderLogoAspect).abs(),
        lessThan(0.05),
      );
      expect(find.text('DEV'), findsOneWidget);
    },
  );

  testWidgets('the Play identity hides the DEV badge', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 780);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomerHeaderBar(
            config: CustomerAppConfig(
              appName: 'Fluxidi Klanten',
              environmentLabel: '',
              androidApplicationId: 'com.fluxidi.customer',
              deepLinkScheme: 'fluxidicustomer',
              deepLinkHost: 'pay',
              deepLinkPath: '/return',
              variant: CustomerAppVariant.fluxidiMarketplace,
              brand: CustomerBrandColors(
                primary: Color(0xFFFFD400),
                accent: Color(0xFFFFD54F),
                background: Color(0xFF07080B),
                surface: Color(0xFF121318),
                card: Color(0xFF171922),
                textSoft: Color(0xFFB8BDC9),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DEV'), findsNothing);
    expect(find.byKey(const Key('customer_header_language')), findsOneWidget);
    expect(find.byKey(const Key('customer_header_palette')), findsOneWidget);
    final logo = tester.getRect(find.byKey(const Key('customer_header_logo')));
    final header = tester.getRect(find.byType(CustomerHeaderBar));
    expect((logo.left - header.left).abs(), lessThan(2));
    expect(logo.height, greaterThan(32));
  });

  testWidgets('tablet landscape puts destination and book-taxi side by side '
      'and keeps services plus radar on screen', (tester) async {
    addTearDown(tester.view.reset);
    _applyGalaxyTabS10LiteLandscape(tester);

    await tester.pumpWidget(const FluxidiCustomerApp());
    await tester.pumpAndSettle();

    final destination = tester.getRect(
      find.byKey(const Key('customer_home_destination')),
    );
    final book = tester.getRect(
      find.byKey(const Key('customer_home_book_taxi')),
    );
    expect(book.left, greaterThan(destination.right - 1));
    expect((book.top - destination.top).abs(), lessThan(8));

    for (final key in <String>[
      'customer_home_service_airport',
      'customer_home_service_hotels',
      'customer_home_service_events',
      'customer_home_service_limousine',
      'customer_home_region_radar',
    ]) {
      expect(
        find.byKey(Key(key)),
        findsOneWidget,
        reason: '$key should be on screen without scrolling',
      );
    }

    final metrics = _measureTabletLandscapeHome(tester);
    // ignore: avoid_print
    print(metrics.toDebugString());

    expect(metrics.viewport, const Size(1408, 880));
    expect(metrics.safeAreaTop, 30);
    expect(metrics.safeAreaBottom, 48);
    expect(
      metrics.gapRadarToNav,
      inInclusiveRange(16, 24),
      reason:
          'empty strip under Region Radar: ${metrics.gapRadarToNav.toStringAsFixed(1)}',
    );
    expect(
      metrics.cardHeight,
      greaterThan(180),
      reason: 'photo rows should absorb leftover height, not stay clamped',
    );
    expect(metrics.logoHeight, closeTo(52, 1));
    expect(metrics.navTop, greaterThan(metrics.radar.bottom));

    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('customer_home_region_radar')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('customer_home_region_radar')), findsOneWidget);
  });

  testWidgets('the chosen theme colours the shell, field and navigation', (
    tester,
  ) async {
    addTearDown(() {
      customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
    });
    customerThemeNotifier.value = CustomerThemeVariant.nightGold;
    await tester.pumpWidget(const FluxidiCustomerApp());
    await tester.pumpAndSettle();

    final night = paletteForCustomerTheme(CustomerThemeVariant.nightGold);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, night.background);
    final nav = tester.widget<NavigationBar>(
      find.byKey(const Key('customer_bottom_nav')),
    );
    expect(nav.backgroundColor, night.surface);

    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
    await tester.pumpAndSettle();

    final light = paletteForCustomerTheme(CustomerThemeVariant.premiumLight);
    final lightScaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(lightScaffold.backgroundColor, light.background);
    final lightNav = tester.widget<NavigationBar>(
      find.byKey(const Key('customer_bottom_nav')),
    );
    expect(lightNav.backgroundColor, light.surface);
  });

  testWidgets('home survives a large system text size on a phone', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(const FluxidiCustomerApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Waar wil je naartoe?'), findsOneWidget);
  });

  testWidgets('an incoming own-scheme link opens the neutral return screen', (
    tester,
  ) async {
    final source = _FakeDeepLinkSource();
    addTearDown(source.controller.close);

    await tester.pumpWidget(FluxidiCustomerApp(deepLinkSource: source));
    await tester.pumpAndSettle();

    source.controller.add(Uri.parse('fluxidicustomerdev://pay/return'));
    await tester.pumpAndSettle();

    expect(find.text('Je bent terug in de app'), findsOneWidget);
    expect(find.textContaining('betaald'), findsNothing);
    expect(find.textContaining('geslaagd'), findsNothing);
  });

  testWidgets('a cold-start own-scheme link opens the return screen', (
    tester,
  ) async {
    final source = _FakeDeepLinkSource(
      initial: Uri.parse('fluxidicustomerdev://pay/return?status=paid'),
    );
    addTearDown(source.controller.close);

    await tester.pumpWidget(FluxidiCustomerApp(deepLinkSource: source));
    await tester.pumpAndSettle();

    expect(find.text('Je bent terug in de app'), findsOneWidget);
    expect(find.textContaining('betaald'), findsNothing);
  });

  testWidgets('the existing app\'s link does not navigate anywhere', (
    tester,
  ) async {
    final source = _FakeDeepLinkSource();
    addTearDown(source.controller.close);

    await tester.pumpWidget(FluxidiCustomerApp(deepLinkSource: source));
    await tester.pumpAndSettle();

    source.controller.add(Uri.parse('fluxidi://pay/return?status=paid'));
    await tester.pumpAndSettle();

    expect(find.byType(CustomerHomeScreen), findsOneWidget);
    expect(find.text('Je bent terug in de app'), findsNothing);
  });
}
