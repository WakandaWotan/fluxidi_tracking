import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/company/company_agenda_calendar.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_customer_labels.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';
import 'package:fluxidi_tracking/company/company_ops_workspace_page.dart'
    show kCompanyAgendaWeekKey, kCompanyCustomerDossierEmptyHintKey;

void main() {
  final variants = <BusinessThemeVariant>[
    BusinessThemeVariant.cleanProfessional,
    BusinessThemeVariant.corporateBlue,
    BusinessThemeVariant.executiveGold,
    BusinessThemeVariant.brandSignatureGold,
  ];

  test('agenda ColorScheme meets text and chrome contrast on light and dark', () {
    for (final variant in variants) {
      final palette = paletteForBusinessTheme(variant);
      final scheme = companyOpsColorScheme(palette);
      final surfaces = <Color>[
        palette.background,
        scheme.surface,
        scheme.surfaceContainerLowest,
        scheme.surfaceContainerLow,
        scheme.surfaceContainerHigh,
        scheme.surfaceContainerHighest,
      ];
      for (final surface in surfaces) {
        expect(
          brandSignatureContrastRatio(scheme.onSurface, surface),
          greaterThanOrEqualTo(kCompanyOpsTextContrastRatio),
          reason: '${variant.name} onSurface on $surface',
        );
      }
      expect(
        brandSignatureContrastRatio(scheme.onPrimary, scheme.primary),
        greaterThanOrEqualTo(kCompanyOpsTextContrastRatio),
        reason: '${variant.name} onPrimary',
      );
      expect(
        brandSignatureContrastRatio(
          scheme.onPrimaryContainer,
          scheme.primaryContainer,
        ),
        greaterThanOrEqualTo(kCompanyOpsTextContrastRatio),
        reason: '${variant.name} today header',
      );
      expect(
        brandSignatureContrastRatio(
          scheme.onSecondaryContainer,
          scheme.secondaryContainer,
        ),
        greaterThanOrEqualTo(kCompanyOpsTextContrastRatio),
        reason: '${variant.name} selected chip',
      );
      expect(
        brandSignatureContrastRatio(scheme.outline, scheme.surface),
        greaterThanOrEqualTo(kCompanyOpsChromeContrastRatio),
        reason: '${variant.name} outline on surface',
      );
      expect(
        brandSignatureContrastRatio(scheme.outline, palette.background),
        greaterThanOrEqualTo(kCompanyOpsChromeContrastRatio),
        reason: '${variant.name} outline on background',
      );
      expect(scheme.secondaryContainer, palette.accent);
      expect(scheme.onSecondaryContainer, palette.textOnAccent);
      final theme = companyOpsMaterialTheme(palette);
      final hint = theme.inputDecorationTheme.hintStyle?.color;
      expect(hint, isNotNull);
      expect(
        brandSignatureContrastRatio(hint!, palette.surfaceAlt),
        greaterThanOrEqualTo(kCompanyOpsTextContrastRatio),
        reason: '${variant.name} search hint on surfaceAlt',
      );
      final outlinedFg = theme.outlinedButtonTheme.style?.foregroundColor
          ?.resolve(const <WidgetState>{});
      expect(outlinedFg, isNotNull);
      expect(
        brandSignatureContrastRatio(outlinedFg!, scheme.surface),
        greaterThanOrEqualTo(kCompanyOpsTextContrastRatio),
        reason: '${variant.name} Today/Pick date on surface',
      );
      final outlinedSide = theme.outlinedButtonTheme.style?.side?.resolve(
        const <WidgetState>{},
      );
      expect(outlinedSide, isNotNull);
      expect(
        brandSignatureContrastRatio(outlinedSide!.color, scheme.surface),
        greaterThanOrEqualTo(kCompanyOpsChromeContrastRatio),
        reason: '${variant.name} outlined control border',
      );
      final thumb = theme.scrollbarTheme.thumbColor?.resolve(
        const <WidgetState>{},
      );
      expect(thumb, isNotNull);
      expect(
        brandSignatureContrastRatio(thumb!, scheme.surface),
        greaterThanOrEqualTo(kCompanyOpsChromeContrastRatio),
        reason: '${variant.name} vertical scrollbar thumb',
      );
    }
  });

  testWidgets(
    'hours, short rides and overlap stay readable after a live theme switch',
    (tester) async {
      businessThemeNotifier.value = BusinessThemeVariant.corporateBlue;
      addTearDown(() {
        businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
      });
      final today = DateUtils.dateOnly(DateTime.now());
      final rides = <CompanyAgendaRide>[
        CompanyAgendaRide(
          bookingId: 'overlap_a',
          customerId: 'cus_a',
          customerName: 'Korte rit',
          fromAddress: 'Maarkedal',
          toAddress: 'Ronse',
          pickupIso: DateTime(
            today.year,
            today.month,
            today.day,
            9,
          ).toUtc().toIso8601String(),
          status: 'CONFIRMED',
          assignedDriverId: 'drv_karel',
          assignedVehicleId: 'vh_1',
          durationUnknown: false,
          durationMin: 20,
        ),
        CompanyAgendaRide(
          bookingId: 'overlap_b',
          customerId: 'cus_b',
          customerName: 'Overlap',
          fromAddress: 'Schorisse',
          toAddress: 'Ronse',
          pickupIso: DateTime(
            today.year,
            today.month,
            today.day,
            9,
            10,
          ).toUtc().toIso8601String(),
          status: 'CONFIRMED',
          assignedDriverId: 'drv_amira',
          assignedVehicleId: 'vh_2',
          durationUnknown: false,
          durationMin: 40,
        ),
      ];
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyOpsThemedSurface(
            child: Scaffold(
              body: CompanyAgendaCalendar(
                period: companyAgendaPeriodFor(
                  view: CompanyAgendaView.week,
                  anchorLocal: today,
                ),
                rides: rides,
                language: AppLanguage.nl,
                drivers: const <Map<String, dynamic>>[
                  <String, dynamic>{
                    'driver_id': 'drv_karel',
                    'display_name': 'Karel Peeters',
                    'agenda_color': '#C9A227',
                  },
                  <String, dynamic>{
                    'driver_id': 'drv_amira',
                    'display_name': 'Amira Benali',
                    'agenda_color': '#3D7EA6',
                  },
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      Future<void> expectReadable(BusinessThemeVariant variant) async {
        final palette = paletteForBusinessTheme(variant);
        final scheme = companyOpsColorScheme(palette);
        expect(Theme.of(tester.element(find.text('08:00'))).colorScheme.surface, scheme.surface);
        final hour = tester.widget<Text>(find.text('08:00'));
        expect(hour.style?.color, scheme.onSurface);
        expect(
          brandSignatureContrastRatio(scheme.onSurface, scheme.surface),
          greaterThanOrEqualTo(kCompanyOpsTextContrastRatio),
        );
        expect(find.byKey(kCompanyAgendaTimeGutterKey), findsOneWidget);
        expect(
          find.byKey(const Key('company_agenda_ride_overlap_a')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('company_agenda_ride_overlap_b')),
          findsOneWidget,
        );
        final header = tester.widget<DecoratedBox>(
          find.byKey(companyAgendaDayHeaderKey(today)),
        );
        final decoration = header.decoration as BoxDecoration;
        expect(decoration.color, scheme.primaryContainer);
      }

      await expectReadable(BusinessThemeVariant.corporateBlue);
      businessThemeNotifier.value = BusinessThemeVariant.cleanProfessional;
      await tester.pump();
      await expectReadable(BusinessThemeVariant.cleanProfessional);
      businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
      await tester.pump();
      await expectReadable(BusinessThemeVariant.executiveGold);
    },
  );

  testWidgets(
    'simulated phone and tablet widths keep week-strip and hour labels',
    (tester) async {
      businessThemeNotifier.value = BusinessThemeVariant.cleanProfessional;
      addTearDown(() {
        businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
      });
      final today = DateUtils.dateOnly(DateTime.now());
      Future<void> pumpPhone(Size size) async {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: size),
              child: CompanyOpsThemedSurface(
                child: Scaffold(
                  body: CompanyAgendaPhoneDayPane(
                    rides: const <CompanyAgendaRide>[],
                    language: AppLanguage.nl,
                    drivers: const <Map<String, dynamic>>[],
                    anchor: today,
                    onSelectDay: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await pumpPhone(const Size(390, 844));
      expect(find.byKey(kCompanyAgendaWeekStripKey), findsOneWidget);
      final selectedChip = tester.widget<ActionChip>(
        find.byKey(companyAgendaWeekStripDayKey(today)),
      );
      expect(
        selectedChip.backgroundColor,
        companyOpsColorScheme(
          paletteForBusinessTheme(BusinessThemeVariant.cleanProfessional),
        ).secondaryContainer,
      );
      await pumpPhone(const Size(768, 1024));
      expect(find.byKey(kCompanyAgendaWeekStripKey), findsOneWidget);

      await tester.binding.setSurfaceSize(const Size(768, 1024));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(768, 1024)),
            child: CompanyOpsThemedSurface(
              child: Scaffold(
                body: CompanyAgendaCalendar(
                  period: companyAgendaPeriodFor(
                    view: CompanyAgendaView.week,
                    anchorLocal: today,
                  ),
                  rides: const <CompanyAgendaRide>[],
                  language: AppLanguage.nl,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('08:00'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets('selected week chip uses accent fill, not a faded wash', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: companyOpsMaterialTheme(
          paletteForBusinessTheme(BusinessThemeVariant.corporateBlue),
        ),
        home: Scaffold(
          body: CompanyOpsSelectableChip(
            key: kCompanyAgendaWeekKey,
            selected: true,
            label: 'Week',
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    final chip = tester.widget<FilterChip>(find.byType(FilterChip));
    expect(
      chip.selectedColor,
      paletteForBusinessTheme(BusinessThemeVariant.corporateBlue).accent,
    );
    expect(chip.selected, isTrue);
  });

  testWidgets(
    'Clean Professional empty dossier stays light with dark text against a dark parent',
    (tester) async {
      businessThemeNotifier.value = BusinessThemeVariant.cleanProfessional;
      addTearDown(() {
        businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
      });
      final scheme = companyOpsCurrentScheme();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: ColoredBox(
            color: scheme.surface,
            child: Center(
              child: Text(
                kCompanyCustomersSelectHint.of(AppLanguage.en),
                key: kCompanyCustomerDossierEmptyHintKey,
                style: TextStyle(color: scheme.onSurface),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(scheme.brightness, Brightness.light);
      final hint = tester.widget<Text>(
        find.byKey(kCompanyCustomerDossierEmptyHintKey),
      );
      expect(hint.style?.color, scheme.onSurface);
      expect(
        brandSignatureContrastRatio(scheme.onSurface, scheme.surface),
        greaterThanOrEqualTo(kCompanyOpsTextContrastRatio),
      );
      expect(
        brandSignatureContrastRatio(
          scheme.onSurface,
          ThemeData.dark().colorScheme.surface,
        ),
        lessThan(kCompanyOpsTextContrastRatio),
      );
    },
  );
}
