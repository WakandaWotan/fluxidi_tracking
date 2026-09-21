import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_customer/app/fluxidi_customer_app.dart';
import 'package:fluxidi_customer/deeplinks/customer_deep_link_source.dart';
import 'package:fluxidi_customer/screens/customer_home_screen.dart';
import 'package:fluxidi_customer/screens/customer_profile_screen.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';

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

    Future<double> cardWidth(Size size) async {
      tester.view.physicalSize = size;
      await tester.pumpWidget(const FluxidiCustomerApp());
      await tester.pumpAndSettle();
      final finder = find.byKey(const Key('customer_home_service_airport'));
      await _scrollTo(tester, finder);
      return tester.getSize(finder).width;
    }

    final portrait = await cardWidth(const Size(800, 1280));
    final landscape = await cardWidth(const Size(1280, 800));

    // Portrait shows one wide photo card per service.
    expect(portrait, greaterThan(600));
    // Landscape puts two side by side, so each is roughly half as wide.
    expect(landscape, lessThan(portrait * 0.75));
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
