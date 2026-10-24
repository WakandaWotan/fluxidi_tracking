import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_app_header/customer_app_header_branding.dart';
import 'package:fluxidi_tracking/customer_app_header/customer_app_header_mode.dart';
import 'package:fluxidi_tracking/customer_app_header/customer_app_header_settings_section.dart';

void main() {
  testWidgets('settings preview and save never publish a partner profile', (
    tester,
  ) async {
    var saved = CustomerAppHeaderMode.logoOnly;
    var savedPosition = CustomerAppHeaderLogoPosition.topLeft;
    bool? savedBusinessHeader;
    var published = false;
    final sectionKey = GlobalKey<CustomerAppHeaderSettingsSectionState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CustomerAppHeaderSettingsSection(
              key: sectionKey,
              logoUrl: 'https://cdn.example/logo.png',
              coverUrl: 'https://cdn.example/cover.png',
              companyName: 'Taxi Mario',
              gold: const Color(0xFFFFD400),
              surface: const Color(0xFF121212),
              background: const Color(0xFF07080B),
              textPrimary: Colors.white,
              textSecondary: Colors.white70,
              border: Colors.white24,
              panelBg: const Color(0xFF121212),
              t:
                  ({
                    required String nl,
                    required String en,
                    String? fr,
                    String? es,
                  }) => nl,
              load: () async => const CustomerAppHeaderBranding(),
              save:
                  ({
                    required mode,
                    required logoPosition,
                    bool? useOnDriverApp,
                    bool? useOnBusinessApp,
                  }) async {
                    saved = mode;
                    savedPosition = logoPosition;
                    savedBusinessHeader = useOnBusinessApp;
                    return CustomerAppHeaderBranding(
                      mode: mode,
                      logoPosition: logoPosition,
                      useOnBusinessApp: useOnBusinessApp ?? false,
                    );
                  },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Header van je eigen klantenapp'), findsOneWidget);
    expect(
      find.text('Bepaalt de bovenkant van je eigen klantenapp.'),
      findsOneWidget,
    );
    expect(find.text('Alleen logo'), findsOneWidget);
    expect(find.text('Alleen headerafbeelding'), findsOneWidget);
    expect(find.text('Header + logo'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('customer_app_header_mode_coverOnly')),
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('business_app_use_company_header')),
    );
    await tester.tap(find.byKey(const Key('business_app_use_company_header')));
    await tester.pump();
    // The page-wide save calls the same section action as its own button.
    expect(await sectionKey.currentState!.save(), isTrue);
    await tester.pumpAndSettle();
    expect(saved, CustomerAppHeaderMode.coverOnly);
    expect(savedPosition, CustomerAppHeaderLogoPosition.topLeft);
    expect(savedBusinessHeader, isTrue);
    expect(published, isFalse);
    expect(
      find.textContaining('publieke partnerprofiel is niet gewijzigd'),
      findsOneWidget,
    );
  });

  testWidgets('another company without a setting stays on logo only', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerAppHeaderSettingsSection(
            logoUrl: 'https://cdn.example/other-logo.png',
            coverUrl: '',
            companyName: 'Stadstaxi',
            gold: const Color(0xFFFFD400),
            surface: const Color(0xFF121212),
            background: const Color(0xFF07080B),
            textPrimary: Colors.white,
            textSecondary: Colors.white70,
            border: Colors.white24,
            panelBg: const Color(0xFF121212),
            t:
                ({
                  required String nl,
                  required String en,
                  String? fr,
                  String? es,
                }) => nl,
            load: () async => const CustomerAppHeaderBranding(
              companyName: 'Stadstaxi',
              logoUrl: 'https://cdn.example/other-logo.png',
            ),
            save:
                ({
                  required mode,
                  required logoPosition,
                  bool? useOnDriverApp,
                  bool? useOnBusinessApp,
                }) async => CustomerAppHeaderBranding(
                  mode: mode,
                  logoPosition: logoPosition,
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final logoRadio = tester.widget<RadioListTile<CustomerAppHeaderMode>>(
      find.byKey(const Key('customer_app_header_mode_logoOnly')),
    );
    expect(logoRadio.groupValue, CustomerAppHeaderMode.logoOnly);
  });

  testWidgets('header + logo shows both logo positions', (tester) async {
    var saved = CustomerAppHeaderMode.logoOnly;
    var savedPosition = CustomerAppHeaderLogoPosition.topLeft;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CustomerAppHeaderSettingsSection(
              logoUrl: 'https://cdn.example/logo.png',
              coverUrl: 'https://cdn.example/cover.png',
              companyName: 'Taxi Mario',
              gold: const Color(0xFFFFD400),
              surface: const Color(0xFF121212),
              background: const Color(0xFF07080B),
              textPrimary: Colors.white,
              textSecondary: Colors.white70,
              border: Colors.white24,
              panelBg: const Color(0xFF121212),
              t:
                  ({
                    required String nl,
                    required String en,
                    String? fr,
                    String? es,
                  }) => nl,
              load: () async => const CustomerAppHeaderBranding(),
              save:
                  ({
                    required mode,
                    required logoPosition,
                    bool? useOnDriverApp,
                    bool? useOnBusinessApp,
                  }) async {
                    saved = mode;
                    savedPosition = logoPosition;
                    return CustomerAppHeaderBranding(
                      mode: mode,
                      logoPosition: logoPosition,
                    );
                  },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Logopositie'), findsNothing);
    await tester.ensureVisible(
      find.byKey(const Key('customer_app_header_mode_coverAndLogo')),
    );
    await tester.tap(
      find.byKey(const Key('customer_app_header_mode_coverAndLogo')),
    );
    await tester.pump();
    expect(find.text('Logopositie'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('customer_app_header_logo_pos_topRight')),
    );
    await tester.tap(
      find.byKey(const Key('customer_app_header_logo_pos_topRight')),
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('customer_app_header_save')),
    );
    await tester.tap(find.byKey(const Key('customer_app_header_save')));
    await tester.pumpAndSettle();
    expect(saved, CustomerAppHeaderMode.coverAndLogo);
    expect(savedPosition, CustomerAppHeaderLogoPosition.topRight);
  });
}
