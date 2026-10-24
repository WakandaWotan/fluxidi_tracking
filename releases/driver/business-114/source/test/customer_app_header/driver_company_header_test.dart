import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/customer_app_header/customer_app_header_branding.dart';
import 'package:fluxidi_tracking/customer_app_header/customer_app_header_mode.dart';
import 'package:fluxidi_tracking/customer_app_header/customer_app_header_settings_section.dart';
import 'package:fluxidi_tracking/customer_app_header/driver_company_header.dart';
import 'package:fluxidi_tracking/customer_app_header/header_local_cache.dart';

void main() {
  test('Fluxidi QR login rejects the Mario device header and prefers own profile', () {
    expect(driverHomeCompanyName(sessionCompanyId:'fluxidi',deviceCompanyId:'mario',deviceCompanyName:'Taxi Mario',profileCompanyId:'mario',profileCompanyName:'Taxi Mario'),'');
    expect(driverHomeCompanyName(sessionCompanyId:'fluxidi',deviceCompanyId:'mario',deviceCompanyName:'Taxi Mario',profileCompanyId:'fluxidi',profileCompanyName:'Fluxidi'),'Fluxidi');
    expect(driverHomeCompanyName(sessionCompanyId:'mario',deviceCompanyId:'mario',deviceCompanyName:'Taxi Mario',profileCompanyId:'',profileCompanyName:''),'Taxi Mario');
  });
  test('driver header stays off unless this company turned it on', () {
    expect(
      driverHomeUsesCompanyHeader(
        enabled: false,
        sessionCompanyId: 'cmp_a',
        activeCompanyId: 'cmp_a',
      ),
      isFalse,
    );
    expect(
      driverHomeUsesCompanyHeader(
        enabled: true,
        sessionCompanyId: 'cmp_a',
        activeCompanyId: 'cmp_b',
      ),
      isFalse,
    );
    expect(
      driverHomeUsesCompanyHeader(
        enabled: true,
        sessionCompanyId: 'cmp_a',
        activeCompanyId: 'cmp_a',
      ),
      isTrue,
    );
  });

  test('missing flag parses as off and does not invent a company', () {
    final branding = CustomerAppHeaderBranding.fromJson(const {
      'company_name': 'Stadstaxi',
      'public_logo_url': 'https://cdn.example/logo.png',
    });
    expect(branding.useOnDriverApp, isFalse);
    expect(branding.companyName, 'Stadstaxi');
  });

  testWidgets('switch saves the driver-app choice with the header mode', (
    tester,
  ) async {
    bool? savedFlag;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CustomerAppHeaderSettingsSection(
              logoUrl: 'https://cdn.example/logo.png',
              coverUrl: 'https://cdn.example/cover.png',
              companyName: 'Stadstaxi',
              gold: const Color(0xFFFFD400),
              surface: const Color(0xFF121212),
              background: const Color(0xFF07080B),
              textPrimary: Colors.white,
              textSecondary: Colors.white70,
              border: Colors.white24,
              panelBg: const Color(0xFF121212),
              t: ({
                required String nl,
                required String en,
                String? fr,
                String? es,
              }) =>
                  nl,
              load: () async => const CustomerAppHeaderBranding(
                mode: CustomerAppHeaderMode.coverAndLogo,
                logoPosition: CustomerAppHeaderLogoPosition.topRight,
              ),
              save: ({
                required mode,
                required logoPosition,
                bool? useOnDriverApp,
                bool? useOnBusinessApp,
              }) async {
                savedFlag = useOnDriverApp;
                return CustomerAppHeaderBranding(
                  mode: mode,
                  logoPosition: logoPosition,
                  useOnDriverApp: useOnDriverApp ?? false,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tile = tester.widget<SwitchListTile>(
      find.byKey(const Key('driver_app_use_company_header')),
    );
    expect(tile.value, isFalse);
    await tester.ensureVisible(find.byKey(const Key('driver_app_use_company_header')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('driver_app_use_company_header')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('customer_app_header_save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customer_app_header_save')));
    await tester.pumpAndSettle();
    expect(savedFlag, isTrue);
  });

  testWidgets('driver banner keeps controls outside the cover', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverCompanyHeader(
            branding: const CustomerAppHeaderBranding(
              mode: CustomerAppHeaderMode.coverOnly,
              coverUrl: 'https://cdn.example/cover.png',
              companyName: 'Stadstaxi',
              useOnDriverApp: true,
            ),
            trailing: const Text('taal-thema-profiel'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('driver_company_header')), findsOneWidget);
    expect(find.text('taal-thema-profiel'), findsOneWidget);
    final header = tester.getRect(find.byKey(const Key('driver_company_header')));
    final controls = tester.getRect(find.text('taal-thema-profiel'));
    expect(controls.top, greaterThanOrEqualTo(header.top));
    expect(controls.bottom, lessThan(header.bottom));
  });

  testWidgets('a new logo is shown again after an earlier image failed', (
    tester,
  ) async {
    Future<void> pump(String logoUrl) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DriverCompanyHeader(
              branding: CustomerAppHeaderBranding(
                mode: CustomerAppHeaderMode.logoOnly,
                logoUrl: logoUrl,
                companyName: 'Stadstaxi',
                useOnDriverApp: true,
              ),
              trailing: const SizedBox.shrink(),
            ),
          ),
        ),
      );
    }

    await pump('https://cdn.example/broken.png');
    await tester.pump();
    await tester.pump();
    expect(find.text('Stadstaxi'), findsOneWidget);

    await pump('https://cdn.example/fresh.png');
    await tester.pump();
    final image = tester.widget<Image>(find.byKey(const Key('customer_header_logo')));
    expect(image.image, headerImageProvider('https://cdn.example/fresh.png'));
    expect(image.image, isNot(headerImageProvider('https://cdn.example/broken.png')));
  });

  test('reloaded profile flag decides the linked driver header', () {
    final enabled = BackendBusinessProfile.fromJson(const {
      'company_id': 'cmp_a',
      'driver_app_use_company_header': true,
      'public_logo_url': 'https://cdn.example/logo.png',
      'customer_app_header_mode': 'header_and_logo',
    });
    final branding = customerAppHeaderBrandingFromBusinessProfile(enabled);
    expect(branding.useOnDriverApp, isTrue);
    expect(branding.logoUrl, 'https://cdn.example/logo.png');
    expect(
      driverHomeUsesCompanyHeader(
        enabled: branding.useOnDriverApp,
        sessionCompanyId: enabled.companyId,
        activeCompanyId: 'cmp_a',
      ),
      isTrue,
    );

    final disabled = BackendBusinessProfile.fromJson(const {
      'company_id': 'cmp_a',
      'driver_app_use_company_header': false,
      'public_logo_url': 'https://cdn.example/logo.png',
    });
    expect(disabled.driverAppUseCompanyHeader, isFalse);
    expect(
      driverHomeUsesCompanyHeader(
        enabled: customerAppHeaderBrandingFromBusinessProfile(
          disabled,
        ).useOnDriverApp,
        sessionCompanyId: 'cmp_a',
        activeCompanyId: 'cmp_a',
      ),
      isFalse,
    );
  });

  testWidgets('turning the driver header off is saved as false', (tester) async {
    bool? savedFlag;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CustomerAppHeaderSettingsSection(
              logoUrl: 'https://cdn.example/logo.png',
              coverUrl: 'https://cdn.example/cover.png',
              companyName: 'Stadstaxi',
              gold: const Color(0xFFFFD400),
              surface: const Color(0xFF121212),
              background: const Color(0xFF07080B),
              textPrimary: Colors.white,
              textSecondary: Colors.white70,
              border: Colors.white24,
              panelBg: const Color(0xFF121212),
              t: ({
                required String nl,
                required String en,
                String? fr,
                String? es,
              }) =>
                  nl,
              load: () async => const CustomerAppHeaderBranding(
                mode: CustomerAppHeaderMode.logoOnly,
                useOnDriverApp: true,
              ),
              save: ({
                required mode,
                required logoPosition,
                bool? useOnDriverApp,
                bool? useOnBusinessApp,
              }) async {
                savedFlag = useOnDriverApp;
                return CustomerAppHeaderBranding(
                  mode: mode,
                  logoPosition: logoPosition,
                  useOnDriverApp: useOnDriverApp ?? false,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.widget<SwitchListTile>(
      find.byKey(const Key('driver_app_use_company_header')),
    );
    expect(before.value, isTrue);
    await tester.ensureVisible(
      find.byKey(const Key('driver_app_use_company_header')),
    );
    await tester.tap(find.byKey(const Key('driver_app_use_company_header')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('customer_app_header_save')));
    await tester.tap(find.byKey(const Key('customer_app_header_save')));
    await tester.pumpAndSettle();
    expect(savedFlag, isFalse);
  });
}
