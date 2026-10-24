import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/limousine/limousine_brand_logo.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';

final Uint8List _kTinyPng = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

LimousineUxTokens _tokens() {
  return LimousineUxTokens.fromSurface(background: const Color(0xFF1A1408));
}

Widget _host({required Size size, required Widget child}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1408),
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 280, child: child),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'public partner logo sits in the former company-name slot with contain',
    (tester) async {
      await tester.pumpWidget(
        _host(
          size: kLimousineSmX400Portrait,
          child: LimousineDiscoveryCompanyIdentity(
            logoUrl: 'https://cdn.example/partner-logo.png',
            companyName: 'Maison Noire',
            tokens: _tokens(),
            logoImage: MemoryImage(_kTinyPng),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(kLimousineDiscoveryCompanyLogoKey), findsOneWidget);
      expect(
        find.byKey(kLimousineDiscoveryCompanyNameFallbackKey),
        findsNothing,
      );
      expect(find.text('Maison Noire'), findsNothing);
      expect(find.text('Fluxidi'), findsNothing);

      final image = tester.widget<Image>(
        find.byKey(kLimousineDiscoveryCompanyLogoKey),
      );
      expect(image.fit, BoxFit.contain);
      expect(image.alignment, Alignment.centerLeft);

      final logoBox = tester.getRect(
        find.byKey(kLimousineDiscoveryCompanyLogoKey),
      );
      expect(logoBox.height, 52);
      expect(logoBox.width, lessThanOrEqualTo(220));
      expect(logoBox.left, lessThan(8));

      expect(
        find.descendant(
          of: find.byType(LimousineDiscoveryCompanyIdentity),
          matching: find.byType(DecoratedBox),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('missing logo falls back to the real company name', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        size: kLimousinePhonePortrait,
        child: LimousineDiscoveryCompanyIdentity(
          logoUrl: '',
          companyName: 'Atelier Or',
          tokens: _tokens(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(kLimousineDiscoveryCompanyLogoKey), findsNothing);
    expect(
      find.byKey(kLimousineDiscoveryCompanyNameFallbackKey),
      findsOneWidget,
    );
    expect(find.text('Atelier Or'), findsOneWidget);
    expect(find.text('Fluxidi'), findsNothing);
  });

  testWidgets('phone and tablet logo slots stay bounded', (tester) async {
    Future<void> pump(Size size, double height, double maxWidth) async {
      await tester.pumpWidget(
        _host(
          size: size,
          child: LimousineDiscoveryCompanyIdentity(
            logoUrl: 'https://cdn.example/wide-logo.png',
            companyName: 'Maison Noire',
            tokens: _tokens(),
            logoImage: MemoryImage(_kTinyPng),
          ),
        ),
      );
      await tester.pump();
      final box = tester.getRect(find.byKey(kLimousineDiscoveryCompanyLogoKey));
      expect(box.height, height);
      expect(box.width, lessThanOrEqualTo(maxWidth));
      expect(limousineDiscoveryCompanyLogoHeight(size), height);
      expect(limousineDiscoveryCompanyLogoMaxWidth(size), maxWidth);
    }

    await pump(kLimousinePhonePortrait, 40, 160);
    await pump(kLimousineSmX400Portrait, 52, 220);
    await pump(kLimousineTabletLandscape, 52, 220);
  });
}
