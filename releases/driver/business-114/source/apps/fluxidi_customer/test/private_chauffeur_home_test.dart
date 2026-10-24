import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_customer/app/fluxidi_customer_app.dart';
import 'package:fluxidi_customer/screens/customer_home_screen.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/private_chauffeur/private_chauffeur_assets.dart';
import 'package:fluxidi_tracking/private_chauffeur/private_chauffeur_discovery_page.dart';

void main() {
  setUp(() {
    setAppLanguage(AppLanguage.nl);
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });

  testWidgets('Privéchauffeur sits under airport rides and the page scrolls', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;

    const cases = <_HomeCase>[
      _HomeCase('phone', Size(390, 844), kPrivateChauffeurBannerMobile, false),
      _HomeCase(
        'tablet',
        Size(800, 1280),
        kPrivateChauffeurBannerTablet,
        false,
      ),
      _HomeCase('pc', Size(1440, 900), kPrivateChauffeurBannerDesktop, true),
    ];

    for (final item in cases) {
      tester.view.physicalSize = item.size;
      await tester.pumpWidget(const FluxidiCustomerApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: item.name);

      final airport = find.byKey(const Key('customer_home_service_airport'));
      final privateChauffeur = find.byKey(
        const Key('customer_home_service_private_chauffeur'),
      );
      final hotels = find.byKey(const Key('customer_home_service_hotels'));
      final airportRect = tester.getRect(airport);
      final privateRect = tester.getRect(privateChauffeur);
      final hotelsRect = tester.getRect(hotels);

      expect(
        privateRect.top,
        greaterThan(airportRect.bottom - 1),
        reason: item.name,
      );
      expect(
        (privateRect.left - airportRect.left).abs(),
        lessThan(8),
        reason: item.name,
      );
      if (item.wide) {
        expect((hotelsRect.top - airportRect.top).abs(), lessThan(8));
        expect(hotelsRect.left, greaterThan(airportRect.right - 1));
      } else {
        expect(hotelsRect.top, greaterThan(privateRect.bottom - 1));
      }

      final image = tester.widget<Image>(
        find.descendant(of: privateChauffeur, matching: find.byType(Image)),
      );
      expect(
        (image.image as AssetImage).assetName,
        item.asset,
        reason: item.name,
      );
      expect(image.fit, BoxFit.cover);

      final lists = find.descendant(
        of: find.byType(CustomerHomeScreen),
        matching: find.byType(ListView),
      );
      if (lists.evaluate().isNotEmpty) {
        await tester.drag(lists.first, const Offset(0, -700));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull, reason: '${item.name} scroll');
      expect(
        find.byKey(const Key('customer_home_service_limousine')),
        findsOneWidget,
      );
    }
  });

  testWidgets('the private chauffeur card opens company search', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    await tester.pumpWidget(const FluxidiCustomerApp());
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('customer_home_service_private_chauffeur')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(kPrivateChauffeurDiscoveryPageKey), findsOneWidget);
    expect(find.byKey(kPrivateChauffeurNeedPlaceKey), findsOneWidget);
    expect(find.text('Privéchauffeur'), findsWidgets);
    expect(
      find.byKey(const Key('limousine_customer_discovery_page')),
      findsNothing,
    );
  });
}

class _HomeCase {
  const _HomeCase(this.name, this.size, this.asset, this.wide);

  final String name;
  final Size size;
  final String asset;
  final bool wide;
}
