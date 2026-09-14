import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/company/company_ops_identity.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';
import 'package:fluxidi_tracking/company/company_settings_page.dart';
import 'package:fluxidi_tracking/widgets/business_theme_selector_sheet.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('fluxidi_ops_theme_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    resetBusinessThemePersistenceLatchForTest();
    companyOpsContextGeneration = 0;
    companyOpsLocalSessionNotifier.value = null;
    companyOpsIdentityNotifier.value = CompanyOpsIdentity.empty;
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    resetBusinessThemePersistenceLatchForTest();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('all existing business themes are selectable presets', () {
    expect(
      BusinessThemeVariant.values,
      containsAll(<BusinessThemeVariant>[
        BusinessThemeVariant.executiveGold,
        BusinessThemeVariant.corporateBlue,
        BusinessThemeVariant.cleanProfessional,
        BusinessThemeVariant.emeraldIvory,
        BusinessThemeVariant.fluxidiNeonRush,
        BusinessThemeVariant.brandSignatureGold,
      ]),
    );
  });

  test('Windows theme apply is readable through the shared store', () async {
    bindBusinessThemeCompanyScope('demo_company_p0');
    await applyBusinessThemePreset(BusinessThemeVariant.corporateBlue);
    expect(businessThemeNotifier.value, BusinessThemeVariant.corporateBlue);
    expect(
      resolveStoredBusinessThemeForCompany('demo_company_p0'),
      BusinessThemeVariant.corporateBlue,
    );
    expect(
      encodeBusinessThemeForCompanyProfile('demo_company_p0')['business_theme_variant'],
      'corporateBlue',
    );
  });

  test('shared-app-route theme write is visible on the Windows scope', () async {
    bindBusinessThemeCompanyScope('demo_company_p0');
    await applyBusinessThemePreset(BusinessThemeVariant.emeraldIvory);
    bindBusinessThemeCompanyScope('demo_company_p0');
    expect(businessThemeNotifier.value, BusinessThemeVariant.emeraldIvory);
    expect(
      paletteForBusinessTheme(businessThemeNotifier.value).accent,
      paletteForBusinessTheme(BusinessThemeVariant.emeraldIvory).accent,
    );
  });

  test('newer company-profile theme wins over a stale local preference', () async {
    bindBusinessThemeCompanyScope('demo_company_p0');
    await applyBusinessThemePreset(BusinessThemeVariant.executiveGold);
    final adopted = await hydrateBusinessThemeFromCompanyProfile(
      companyId: 'demo_company_p0',
      profile: <String, dynamic>{
        'business_theme': <String, dynamic>{
          'variant': 'fluxidiNeonRush',
          'updatedAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 1))
              .toIso8601String(),
        },
      },
    );
    expect(adopted, isTrue);
    expect(businessThemeNotifier.value, BusinessThemeVariant.fluxidiNeonRush);
  });

  test('older company-profile theme does not overwrite a newer local choice', () async {
    bindBusinessThemeCompanyScope('demo_company_p0');
    await applyBusinessThemePreset(BusinessThemeVariant.cleanProfessional);
    final adopted = await hydrateBusinessThemeFromCompanyProfile(
      companyId: 'demo_company_p0',
      profile: <String, dynamic>{
        'business_theme': <String, dynamic>{
          'variant': 'corporateBlue',
          'updatedAt': DateTime.utc(2020, 1, 1).toIso8601String(),
        },
      },
    );
    expect(adopted, isFalse);
    expect(businessThemeNotifier.value, BusinessThemeVariant.cleanProfessional);
  });

  test('missing profile theme does not invent a company override', () async {
    bindBusinessThemeCompanyScope('demo_company_p0');
    await applyBusinessThemePreset(BusinessThemeVariant.corporateBlue);
    final adopted = await hydrateBusinessThemeFromCompanyProfile(
      companyId: 'demo_company_p0',
      profile: <String, dynamic>{'companyName': 'Fluxidi Demo Fleet'},
    );
    expect(adopted, isFalse);
    expect(businessThemeNotifier.value, BusinessThemeVariant.corporateBlue);
  });

  test('company switch isolates theme and identity', () async {
    bindBusinessThemeCompanyScope('demo_company_p0');
    await applyBusinessThemePreset(BusinessThemeVariant.corporateBlue);
    beginCompanyOpsContextClear();
    bindBusinessThemeCompanyScope('demo_company_p1');
    expect(companyOpsLocalSessionNotifier.value, isNull);
    expect(
      resolveStoredBusinessThemeForCompany('demo_company_p0'),
      BusinessThemeVariant.corporateBlue,
    );
    expect(
      resolveStoredBusinessThemeForCompany('demo_company_p1'),
      isNot(BusinessThemeVariant.corporateBlue),
    );
    expect(
      businessThemeNotifier.value,
      resolveStoredBusinessThemeForCompany('demo_company_p1'),
    );
  });

  testWidgets('themed surface follows the live shared preset', (tester) async {
    bindBusinessThemeCompanyScope('demo_company_p0');
    businessThemeNotifier.value = BusinessThemeVariant.corporateBlue;
    businessAppearanceNotifier.value = BusinessThemeVariant.corporateBlue;
    await tester.pumpWidget(
      const MaterialApp(
        home: CompanyOpsThemedSurface(
          child: Scaffold(body: Text('thema')),
        ),
      ),
    );
    await tester.pump();
    final built = tester.element(find.text('thema'));
    expect(
      Theme.of(built).scaffoldBackgroundColor,
      paletteForBusinessTheme(BusinessThemeVariant.corporateBlue).background,
    );
  });

  testWidgets('settings opens the shared theme selector with every variant', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    companyOpsLocalSessionNotifier.value = const CompanyOpsLocalSession(
      companyId: 'demo_company_p0',
      sessionToken: 'tok',
    );
    bindBusinessThemeCompanyScope('demo_company_p0');
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1280, 900)),
        child: MaterialApp(
          home: CompanySettingsPage(
            profileLoader: () async => <String, dynamic>{
              'companyName': 'Fluxidi Demo Fleet',
              'country': 'BE',
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(kCompanySettingsThemeKey), findsOneWidget);
    await tester.tap(find.byKey(kCompanySettingsThemeKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(kBusinessThemeSelectorSheetKey), findsOneWidget);
    for (final variant in BusinessThemeVariant.values) {
      expect(
        find.byKey(Key('business_theme_selector_tile_${variant.name}')),
        findsOneWidget,
      );
    }
    await tester.tap(
      find.byKey(const Key('business_theme_selector_tile_corporateBlue')),
    );
    await tester.pump();
    await tester.tap(find.byKey(kBusinessThemeSelectorApplyKey));
    await tester.pump();
    expect(businessThemeNotifier.value, BusinessThemeVariant.corporateBlue);
  });

  test('theme document carries custom colors and published customer theme', () async {
    bindBusinessThemeCompanyScope('demo_company_p0');
    await applyBusinessThemePreset(BusinessThemeVariant.brandSignatureGold);
    await applyBrandSignaturePalette(
      BrandSignaturePalette.fromColor(const Color(0xFF152044)),
    );
    await saveBusinessPublishedCustomerThemePreference(
      CustomerThemeVariant.nightGold,
    );
    final encoded = encodeBusinessThemeForCompanyProfile('demo_company_p0');
    final nested = encoded['business_theme'] as Map<String, dynamic>;
    expect(encoded['business_theme_variant'], 'brandSignatureGold');
    expect(nested['brandSignaturePalette'], containsPair('hex', '#152044'));
    expect(nested['publishedCustomerTheme'], 'nightGold');
  });

  test('newer profile custom colors win over a stale local palette', () async {
    bindBusinessThemeCompanyScope('demo_company_p0');
    await applyBrandSignaturePalette(
      BrandSignaturePalette.fromColor(const Color(0xFF5A3D18)),
    );
    final adopted = await hydrateBusinessThemeFromCompanyProfile(
      companyId: 'demo_company_p0',
      profile: <String, dynamic>{
        'business_theme': <String, dynamic>{
          'variant': 'brandSignatureGold',
          'updatedAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 2))
              .toIso8601String(),
          'brandSignaturePalette': <String, Object>{
            'argb': const Color(0xFF152044).value,
            'hex': '#152044',
          },
          'publishedCustomerTheme': 'nightGold',
        },
      },
    );
    expect(adopted, isTrue);
    expect(brandSignaturePaletteNotifier.value.hex, '#152044');
    expect(
      businessPublishedCustomerThemeNotifier.value,
      CustomerThemeVariant.nightGold,
    );
  });

  test('demo company p1 no longer forces a midnight palette', () {
    bindBusinessThemeCompanyScope('demo_company_p1');
    expect(
      brandSignaturePaletteNotifier.value.base,
      BrandSignaturePalette.defaults.base,
    );
  });
}
