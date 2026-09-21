import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_customer/app/customer_routes.dart';
import 'package:fluxidi_customer/app/fluxidi_customer_app.dart';
import 'package:fluxidi_customer/deeplinks/customer_deep_link_source.dart';
import 'package:fluxidi_customer/screens/customer_home_screen.dart';

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

void main() {
  testWidgets('home shows every customer destination', (tester) async {
    await tester.pumpWidget(const FluxidiCustomerApp());
    await tester.pumpAndSettle();

    expect(find.text('Fluxidi Customer Dev'), findsOneWidget);
    for (final destination in kCustomerDestinations) {
      expect(find.text(destination.label), findsOneWidget);
    }
  });

  testWidgets('each destination opens its own not-connected screen', (
    tester,
  ) async {
    await tester.pumpWidget(const FluxidiCustomerApp());
    await tester.pumpAndSettle();

    for (final destination in kCustomerDestinations) {
      await tester.tap(find.text(destination.label));
      await tester.pumpAndSettle();

      if (destination.route == CustomerRoutes.taxi) {
        // Taxi is wired to company search. Without a configured base URL the
        // screen must say so instead of calling anything.
        expect(find.text('API niet geconfigureerd'), findsOneWidget);
      } else {
        expect(
          find.text('Nog niet aangesloten'),
          findsOneWidget,
          reason: 'expected placeholder for ${destination.route}',
        );
      }

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(CustomerHomeScreen), findsOneWidget);
    }
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
      expect(
        find.text('Mijn boekingen'),
        findsOneWidget,
        reason: 'destination missing on ${entry.key}',
      );
    }
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
    expect(find.text('Taxi'), findsOneWidget);
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

  testWidgets('the return screen stays visible on top of a deeper flow', (
    tester,
  ) async {
    // Regression: an imperative push from the link listener ended up on the
    // navigator stack but never became visible on device. The screen is now
    // rendered from app state, so it must show even when another screen was
    // open, and closing it must land back on the start screen.
    final source = _FakeDeepLinkSource();
    addTearDown(source.controller.close);

    await tester.pumpWidget(FluxidiCustomerApp(deepLinkSource: source));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Luchthaven'));
    await tester.pumpAndSettle();
    expect(find.text('Nog niet aangesloten'), findsOneWidget);

    source.controller.add(Uri.parse('fluxidicustomerdev://pay/return'));
    await tester.pumpAndSettle();

    expect(find.text('Je bent terug in de app'), findsOneWidget);
    expect(find.text('Nog niet aangesloten'), findsNothing);

    await tester.tap(find.byKey(const Key('payment_return_close')));
    await tester.pumpAndSettle();

    expect(find.text('Je bent terug in de app'), findsNothing);
    expect(find.byType(CustomerHomeScreen), findsOneWidget);
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
