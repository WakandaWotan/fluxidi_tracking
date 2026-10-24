import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_app_header/business_company_header.dart';
import 'package:fluxidi_tracking/customer_app_header/customer_app_header_branding.dart';
import 'package:fluxidi_tracking/customer_app_header/customer_app_header_mode.dart';

void main() {
  test('business header only belongs to the active company', () {
    expect(businessHomeUsesCompanyHeader(
      enabled: true,
      profileCompanyId: 'mario',
      activeCompanyId: 'mario',
    ), isTrue);
    expect(businessHomeUsesCompanyHeader(
      enabled: true,
      profileCompanyId: 'mario',
      activeCompanyId: 'other',
    ), isFalse);
    expect(businessHomeUsesCompanyHeader(
      enabled: false,
      profileCompanyId: 'mario',
      activeCompanyId: 'mario',
    ), isFalse);
  });
  test('business flag is independent from the driver header choice', () {
    final branding = CustomerAppHeaderBranding.fromJson(const {
      'customer_app_header_mode': 'header_and_logo',
      'public_logo_url': 'https://cdn.example/logo.png',
      'public_hero_photo_url': 'https://cdn.example/cover.png',
      'business_app_use_company_header': true,
      'driver_app_use_company_header': false,
    });
    expect(branding.useOnBusinessApp, isTrue);
    expect(branding.useOnDriverApp, isFalse);
    expect(branding.mode, CustomerAppHeaderMode.coverAndLogo);
  });

  testWidgets('business header keeps account controls above company media', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: BusinessCompanyHeader(
          branding: CustomerAppHeaderBranding(
            mode: CustomerAppHeaderMode.logoOnly,
            companyName: 'Taxi Mario',
          ),
          trailing: Text('Account en thema'),
          accent: Color(0xFFD6B342),
          surface: Colors.white,
          background: Colors.white,
          textPrimary: Colors.black,
        ),
      ),
    ));
    expect(find.byKey(const Key('business_company_header')), findsOneWidget);
    expect(find.text('Account en thema'), findsOneWidget);
  });
}
