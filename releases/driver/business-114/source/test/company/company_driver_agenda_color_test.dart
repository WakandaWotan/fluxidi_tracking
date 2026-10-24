import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_color.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_color_chips.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';

List<Map<String, dynamic>> _twentyDrivers() {
  return [
    for (var i = 0; i < 20; i += 1)
      <String, dynamic>{
        'driver_id': 'drv_demo_company_p0_${i + 1}',
        'display_name': i == 0
            ? 'Karel Peeters'
            : i == 1
            ? 'Amira Benali'
            : 'Chauffeur ${i + 1}',
        'agenda_color': i == 19
            ? '#C9A227'
            : kCompanyDriverAgendaColorChoices[i],
        'availability_status': i == 1
            ? 'offline'
            : i == 2
            ? 'busy'
            : 'available',
      },
  ];
}

void main() {
  setUp(resetCompanyDriverAgendaColorCacheForTest);

  test('palette keeps the original six colors and adds twenty standards', () {
    expect(kCompanyDriverAgendaColorChoices, hasLength(20));
    expect(kCompanyDriverAgendaColorChoices.take(6), <String>[
      '#C9A227',
      '#2F6B4F',
      '#3D5A80',
      '#8C2F39',
      '#6B4F2F',
      '#4A4A4A',
    ]);
    expect(companyAgendaColorIsStandard('#c9a227'), isTrue);
    expect(companyAgendaColorIsCustom('#112233'), isTrue);
    expect(companyAgendaColorIsCustom('#C9A227'), isFalse);
  });

  test('usage lists other chauffeurs without blocking reuse', () {
    final usage = companyAgendaColorUsageByHex(
      _twentyDrivers(),
      excludeDriverId: 'drv_demo_company_p0_1',
    );
    expect(companyAgendaColorUsers(usage, '#C9A227'), <String>['Chauffeur 20']);
    expect(
      companyAgendaColorUsedByText(
        companyAgendaColorUsers(usage, '#C9A227'),
        AppLanguage.nl,
      ),
      contains('Chauffeur 20'),
    );
    expect(companyAgendaColorOccupancyShort(<String>['Amira Benali']), 'AB');
  });

  test(
    'saving an agenda color reuses agenda_color and notifies listeners',
    () async {
      final before = companyDriverAgendaColorsTick.value;
      Map<String, dynamic>? saved;
      await saveCompanyDriverAgendaColor(
        driver: <String, dynamic>{
          'driver_id': 'drv_demo_company_p0_1',
          'display_name': 'Karel Peeters',
        },
        color: '#2F6B4F',
        driverUpsert: (driver) async => saved = driver,
      );
      expect(saved?['driver_id'], 'drv_demo_company_p0_1');
      expect(saved?['agenda_color'], '#2F6B4F');
      expect(companyDriverAgendaColorsTick.value, before + 1);
    },
  );

  testWidgets('selected agenda color shows a checkmark', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CompanyDriverAgendaColorChips(
            selected: '#C9A227',
            onSelect: _ignoreColor,
          ),
        ),
      ),
    );
    expect(
      find.byKey(companyDriverAgendaColorCheckKey('#C9A227')),
      findsOneWidget,
    );
    expect(
      find.byKey(companyDriverAgendaColorCheckKey('#2F6B4F')),
      findsNothing,
    );
    expect(
      find.byKey(companyDriverAgendaColorChipKey('#6B2F3F')),
      findsOneWidget,
    );
  });

  testWidgets('agenda color action opens the palette only after tap', (
    tester,
  ) async {
    final drivers = _twentyDrivers();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyDriverAgendaColorAction(
            language: AppLanguage.nl,
            driver: drivers.first,
            driversLoader: () async => drivers,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(kCompanyAgendaColorChange.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(find.byKey(kCompanyDriverAgendaColorPickerKey), findsNothing);
    expect(
      find.byKey(companyDriverAgendaColorChipKey('#2F6B4F')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(companyDriverAgendaColorActionKey('drv_demo_company_p0_1')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyDriverAgendaColorPickerKey), findsOneWidget);
    expect(
      find.byKey(companyDriverAgendaColorCheckKey('#C9A227')),
      findsOneWidget,
    );
    expect(
      find.byKey(companyDriverAgendaColorChipKey('#2F6B4F')),
      findsOneWidget,
    );
    expect(find.text('Karel Peeters'), findsWidgets);
    expect(find.textContaining('Al in gebruik bij'), findsOneWidget);
    expect(
      find.text(kCompanyAgendaColorCustom.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(find.text('Offline'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving a picked agenda color confirms and keeps storage', (
    tester,
  ) async {
    final drivers = _twentyDrivers();
    final before = companyDriverAgendaColorsTick.value;
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyDriverAgendaColorAction(
            language: AppLanguage.en,
            driver: drivers.first,
            driversLoader: () async => drivers,
            driverUpsert: (driver) async {
              drivers[0] = <String, dynamic>{...drivers.first, ...driver};
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(kCompanyAgendaColorChange.of(AppLanguage.en)),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(companyDriverAgendaColorActionKey('drv_demo_company_p0_1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(companyDriverAgendaColorChipKey('#2F6B4F')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(companyDriverAgendaColorCheckKey('#2F6B4F')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(kCompanyDriverAgendaColorSaveKey));
    await tester.pumpAndSettle();
    expect(drivers.first['agenda_color'], '#2F6B4F');
    expect(companyDriverAgendaColorsTick.value, before + 1);
    expect(find.byKey(kCompanyDriverAgendaColorSavedBannerKey), findsOneWidget);
    expect(
      find.text(kCompanyAgendaColorSaved.of(AppLanguage.en)),
      findsOneWidget,
    );
    expect(find.byKey(kCompanyDriverAgendaColorPickerKey), findsNothing);
  });

  testWidgets('custom color saves a hex that is not in the standard grid', (
    tester,
  ) async {
    final drivers = _twentyDrivers();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyDriverAgendaColorAction(
            language: AppLanguage.nl,
            driver: drivers.first,
            driversLoader: () async => drivers,
            driverUpsert: (driver) async {
              drivers[0] = <String, dynamic>{...drivers.first, ...driver};
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(companyDriverAgendaColorActionKey('drv_demo_company_p0_1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kCompanyDriverAgendaCustomColorKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(kCompanyDriverAgendaCustomHexFieldKey),
      '114477',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kCompanyDriverAgendaColorSaveKey));
    await tester.pumpAndSettle();
    expect(drivers.first['agenda_color'], '#114477');
  });

  testWidgets('picker stays readable in existing themes on wide and narrow', (
    tester,
  ) async {
    final drivers = _twentyDrivers();
    addTearDown(() {
      businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
    });
    for (final size in const <Size>[Size(1280, 800), Size(390, 844)]) {
      await tester.binding.setSurfaceSize(size);
      for (final theme in BusinessThemeVariant.values) {
        businessThemeNotifier.value = theme;
        await tester.pumpWidget(
          CompanyOpsThemedSurface(
            child: MaterialApp(
              home: Scaffold(
                body: CompanyDriverAgendaColorPickerDialog(
                  language: AppLanguage.nl,
                  driver: drivers.first,
                  selected: '#C9A227',
                  companyDrivers: drivers,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(kCompanyDriverAgendaColorPreviewKey), findsOneWidget);
        expect(find.text('Karel Peeters'), findsWidgets);
        expect(
          find.text(kCompanyAgendaColorSave.of(AppLanguage.nl)),
          findsOneWidget,
        );
        expect(find.text('Offline'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    }
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}

void _ignoreColor(String color) {}
