import 'package:fluxidi_tracking/customer_app_header/customer_app_header_layout.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_app_header/customer_app_header_branding.dart';
import 'package:fluxidi_tracking/customer_app_header/customer_app_header_mode.dart';
import 'package:fluxidi_tracking/customer_app_header/customer_app_header_view.dart';

final Uint8List _png = Uint8List.fromList(<int>[
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
  0x0A,
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

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required CustomerAppHeaderBranding branding,
  ImageProvider? logo,
  ImageProvider? cover,
}) async {
  tester.view.physicalSize = Size(size.width * 2, size.height * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          backgroundColor: const Color(0xFF07080B),
          body: ListView(
            children: <Widget>[
              CustomerAppHeaderView(
                branding: branding,
                gold: const Color(0xFFFFD400),
                surface: const Color(0xFF121212),
                background: const Color(0xFF07080B),
                textPrimary: Colors.white,
                logoImage: logo,
                coverImage: cover,
                coverAspectRatio: 16 / 5,
                trailing: const SizedBox(
                  key: Key('customer_header_language'),
                  width: 48,
                  height: 48,
                ),
              ),
              const SizedBox(height: 24, child: Text('Waar wil je naartoe?')),
              const SizedBox(height: 48, child: Text('Boek een taxi')),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  final logo = MemoryImage(_png);
  final cover = MemoryImage(_png);

  testWidgets('logo only shows the large logo and keeps booking reachable', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(800, 1280),
      branding: const CustomerAppHeaderBranding(
        companyName: 'Other Taxi',
        logoUrl: 'https://cdn.example/logo.png',
      ),
      logo: logo,
    );
    expect(find.byKey(const Key('customer_header_logo')), findsOneWidget);
    expect(find.byKey(const Key('customer_header_cover')), findsNothing);
    expect(find.text('Boek een taxi'), findsOneWidget);
  });

  testWidgets('cover only hides the standalone logo', (tester) async {
    await _pump(
      tester,
      size: const Size(800, 1280),
      branding: const CustomerAppHeaderBranding(
        mode: CustomerAppHeaderMode.coverOnly,
        companyName: 'Taxi Mario',
        logoUrl: 'https://cdn.example/logo.png',
        coverUrl: 'https://cdn.example/cover.png',
      ),
      logo: logo,
      cover: cover,
    );
    expect(find.byKey(const Key('customer_header_cover')), findsOneWidget);
    expect(find.byKey(const Key('customer_header_logo')), findsNothing);
    expect(find.byKey(const Key('customer_header_language')), findsOneWidget);
    final chipRect = tester.getRect(
      find.byKey(const Key('customer_header_language')),
    );
    final coverRect = tester.getRect(
      find.byKey(const Key('customer_header_cover')),
    );
    expect(chipRect.top, greaterThanOrEqualTo(coverRect.top));
    expect(chipRect.bottom, lessThan(coverRect.bottom));
    expect(
      tester.widget<Image>(find.byKey(const Key('customer_header_cover'))).fit,
      BoxFit.cover,
    );
  });

  testWidgets('header + logo overlays a compact logo on the cover', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(390, 844),
      branding: const CustomerAppHeaderBranding(
        mode: CustomerAppHeaderMode.coverAndLogo,
        companyName: 'Taxi Mario',
        logoUrl: 'https://cdn.example/logo.png',
        coverUrl: 'https://cdn.example/cover.png',
      ),
      logo: logo,
      cover: cover,
    );
    expect(find.byKey(const Key('customer_header_cover')), findsOneWidget);
    expect(find.byKey(const Key('customer_header_logo')), findsOneWidget);
    final coverRect = tester.getRect(
      find.byKey(const Key('customer_header_cover')),
    );
    final logoRect = tester.getRect(
      find.byKey(const Key('customer_header_logo')),
    );
    expect(logoRect.top, greaterThanOrEqualTo(coverRect.top - 1));
    expect(logoRect.bottom, lessThanOrEqualTo(coverRect.bottom + 1));
    expect(logoRect.left, lessThan(coverRect.center.dx));
    expect(
      logoRect.bottom,
      closeTo(coverRect.bottom - kCustomerAppHeaderLogoOverlayInset, 1),
    );
  });

  testWidgets('tablet logo sits at the bottom right over the cover', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(800, 1280),
      branding: const CustomerAppHeaderBranding(
        mode: CustomerAppHeaderMode.coverAndLogo,
        logoPosition: CustomerAppHeaderLogoPosition.topRight,
        companyName: 'Other Company',
        coverUrl: 'https://cdn.example/cover.png',
        logoUrl: 'https://cdn.example/logo.png',
      ),
      logo: logo,
      cover: cover,
    );
    final banner = tester.getRect(
      find.byKey(const Key('customer_header_cover')),
    );
    final mark = tester.getRect(find.byKey(const Key('customer_header_logo')));
    expect(mark.bottom, closeTo(banner.bottom - 10, 1));
    expect(mark.right, closeTo(banner.right - 10, 1));
  });

  testWidgets('missing images fall back to the company name', (tester) async {
    await _pump(
      tester,
      size: const Size(390, 844),
      branding: const CustomerAppHeaderBranding(
        mode: CustomerAppHeaderMode.coverOnly,
        companyName: 'Stadstaxi',
      ),
    );
    expect(
      find.byKey(const Key('customer_header_company_name')),
      findsOneWidget,
    );
    expect(find.text('Stadstaxi'), findsOneWidget);
  });

  testWidgets('phone landscape stays scrollable', (tester) async {
    await _pump(
      tester,
      size: const Size(844, 390),
      branding: const CustomerAppHeaderBranding(
        mode: CustomerAppHeaderMode.coverAndLogo,
        companyName: 'Taxi Mario',
        logoUrl: 'https://cdn.example/logo.png',
        coverUrl: 'https://cdn.example/cover.png',
      ),
      logo: logo,
      cover: cover,
    );
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('Boek een taxi'), findsOneWidget);
    final header = tester.getRect(find.byType(CustomerAppHeaderView));
    expect(header.height, lessThan(300));
  });
}
