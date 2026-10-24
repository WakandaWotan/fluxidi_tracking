import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_fixed_price_labels.dart';
import 'package:fluxidi_tracking/company/company_fixed_price_place.dart';
import 'package:fluxidi_tracking/company/company_fixed_price_suggestion.dart';
import 'package:fluxidi_tracking/company/company_fixed_prices_page.dart';
import 'package:fluxidi_tracking/company/company_ops_identity.dart';
import 'package:fluxidi_tracking/company/company_settings_page.dart';

void main() {
  test('Ruien and a Belgian address become a usable place name', () {
    expect(companyFixedPriceLocality('Ruien'), 'Ruien');
    expect(
      companyFixedPriceLocality('Ruien, 9688 Kluisbergen, België'),
      'Ruien',
    );
    expect(companyFixedPricePostcode('Ruien, 9688 Kluisbergen'), '9688');
    expect(
      companyFixedPriceRuleIsAirport(<String, dynamic>{
        'kind': 'city_pair',
        'origin': <String, dynamic>{'type': 'city', 'value': 'Ruien'},
        'destination': <String, dynamic>{'type': 'city', 'value': 'Oudenaarde'},
      }),
      isFalse,
    );
  });

  testWidgets('settings shows both fixed-price entries', (tester) async {
    companyOpsContextGeneration = 1;
    companyOpsLocalSessionNotifier.value = const CompanyOpsLocalSession(
      companyId: 'demo_company_p0',
      sessionToken: 'tok',
    );
    tester.view.physicalSize = const Size(720, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(720, 900)),
        child: MaterialApp(
          home: CompanySettingsPage(
            language: AppLanguage.nl,
            profileLoader: () async => <String, dynamic>{
              'companyName': 'Fluxidi Demo Cars',
              'phone': '+3227110000',
              'email': 'ops@demo.local',
              'country': 'BE',
            },
            profileSaver: (profile) async => profile,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(kCompanySettingsListKey), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanySettingsFixedPricesKey), findsOneWidget);
    expect(find.byKey(kCompanyFixedPricesAirportEntryKey), findsOneWidget);
    expect(find.byKey(kCompanyFixedPricesCityEntryKey), findsOneWidget);
    expect(find.text(kCompanyFixedPricesAirports.of(AppLanguage.nl)), findsOneWidget);
    expect(find.text(kCompanyFixedPricesCities.of(AppLanguage.nl)), findsOneWidget);
    expect(find.textContaining('Worker'), findsNothing);
    expect(find.textContaining('Oude luchthavenlijst'), findsNothing);
  });

  testWidgets('city catalog lists city rules first and keeps add above test', (
    tester,
  ) async {
    var stored = <String, dynamic>{
      'fallback': 'calculator',
      'updated_at': '2026-09-13T12:00:00.000Z',
      'rules': <dynamic>[
        <String, dynamic>{
          'rule_id': 'fx_leuven_bru',
          'name': 'Leuven → BRU',
          'kind': 'airport',
          'airport_iata': 'BRU',
          'enabled': true,
          'price_incl_vat': 85,
          'destination': <String, dynamic>{
            'type': 'airport',
            'airport_iata': 'BRU',
          },
        },
        <String, dynamic>{
          'rule_id': 'fx_leuven_gent',
          'name': 'Leuven → Gent',
          'kind': 'city_pair',
          'enabled': true,
          'price_incl_vat': 95,
          'origin': <String, dynamic>{'type': 'city', 'value': 'Leuven'},
          'destination': <String, dynamic>{'type': 'city', 'value': 'Gent'},
        },
      ],
    };
    tester.view.physicalSize = const Size(720, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(720, 1100)),
        child: MaterialApp(
          home: CompanyFixedPricesPage(
            language: AppLanguage.nl,
            catalog: CompanyFixedPricesCatalog.city,
            loader: () async => stored,
            saver: (doc) async {
              stored = Map<String, dynamic>.from(doc);
              return stored;
            },
            previewer: (payload) async => <String, dynamic>{
              'ok': true,
              'matched': true,
              'snapshot': <String, dynamic>{
                'name': 'Leuven → Gent',
                'fixed_fare_rule_id': 'fx_leuven_gent',
                'total_incl_vat': 95,
              },
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(kCompanyFixedPricesMyList.of(AppLanguage.nl)), findsOneWidget);
    expect(find.byKey(kCompanyFixedPricesAddKey), findsOneWidget);
    expect(find.text('Leuven → Gent'), findsWidgets);
    expect(find.text('Leuven → BRU'), findsNothing);
    expect(find.textContaining('city_pair'), findsNothing);
    expect(find.textContaining('prio'), findsNothing);
    expect(find.textContaining('Worker'), findsNothing);
    final addY = tester.getTopLeft(find.byKey(kCompanyFixedPricesAddKey)).dy;
    final testY = tester.getTopLeft(find.text(kCompanyFixedPricesTestTitle.of(AppLanguage.nl))).dy;
    expect(addY, lessThan(testY));
    await tester.tap(find.byKey(kCompanyFixedPricesAddKey));
    await tester.pumpAndSettle();
    expect(find.text(kCompanyFixedPricesName.of(AppLanguage.nl)), findsOneWidget);
    expect(find.text(kCompanyFixedPricesPlaceCity.of(AppLanguage.nl)), findsWidgets);
    expect(find.text(kCompanyFixedPricesPlaceAirport.of(AppLanguage.nl)), findsNothing);
  });

  testWidgets('route test explains a postcode rule it cannot judge yet', (
    tester,
  ) async {
    Map<String, dynamic>? sent;
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(720, 1600)),
        child: MaterialApp(
          home: CompanyFixedPricesPage(
            language: AppLanguage.nl,
            catalog: CompanyFixedPricesCatalog.city,
            loader: () async => <String, dynamic>{
              'fallback': 'calculator',
              'updated_at': '2026-09-13T12:00:00.000Z',
              'rules': <dynamic>[
                <String, dynamic>{
                  'rule_id': 'fx_maarkedal_ronse',
                  'name': 'Vast tarief van Maarkedal naar Ronse',
                  'kind': 'city_pair',
                  'enabled': true,
                  'price_incl_vat': 35,
                  'origin': <String, dynamic>{
                    'type': 'postcode',
                    'value': '9688',
                    'label': '9688, Maarkedal, Oost-Vlaanderen, België',
                  },
                  'destination': <String, dynamic>{
                    'type': 'zone',
                    'value': 'Ronse',
                  },
                },
              ],
            },
            saver: (doc) async => doc,
            previewer: (payload) async {
              sent = payload;
              return <String, dynamic>{
                'ok': true,
                'matched': false,
                'needs_more_detail': <dynamic>[
                  <String, dynamic>{
                    'rule_id': 'fx_maarkedal_ronse',
                    'name': 'Vast tarief van Maarkedal naar Ronse',
                    'role': 'origin',
                    'place_type': 'postcode',
                    'value': '9688',
                  },
                ],
              };
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(kCompanyFixedPricesPreviewFromKey),
      'Maarkedal, Oost-Vlaanderen, België',
    );
    await tester.enterText(
      find.byKey(kCompanyFixedPricesPreviewToKey),
      'Ronse, Oost-Vlaanderen, België',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(kCompanyFixedPricesPreviewKey));
    await tester.tap(find.byKey(kCompanyFixedPricesPreviewKey));
    await tester.pumpAndSettle();
    expect(sent?['from_postcode'], isNull);
    final shown = tester
        .widget<Text>(find.byKey(kCompanyFixedPricesPreviewTextKey))
        .data!;
    expect(shown, contains('Vast tarief van Maarkedal naar Ronse'));
    expect(shown, contains('9688'));
    expect(shown, contains('vertrek'));
    expect(shown, isNot(contains('Terugval')));
  });

  testWidgets('unsaved rule changes are visible before the route test', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(720, 1600)),
        child: MaterialApp(
          home: CompanyFixedPricesPage(
            language: AppLanguage.nl,
            catalog: CompanyFixedPricesCatalog.city,
            loader: () async => <String, dynamic>{
              'fallback': 'calculator',
              'updated_at': '2026-09-13T12:00:00.000Z',
              'rules': <dynamic>[],
            },
            saver: (doc) async => doc,
            previewer: (_) async => <String, dynamic>{'ok': true},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyFixedPricesUnsavedKey), findsNothing);
    await tester.ensureVisible(
      find.byType(DropdownButtonFormField<String>).first,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(kCompanyFixedPricesFallbackQuote.of(AppLanguage.nl)).last,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyFixedPricesUnsavedKey), findsOneWidget);
    await tester.ensureVisible(find.byKey(kCompanyFixedPricesSaveKey));
    await tester.tap(find.byKey(kCompanyFixedPricesSaveKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyFixedPricesUnsavedKey), findsNothing);
  });

  testWidgets('airport catalog keeps the airport rule and save', (tester) async {
    var stored = <String, dynamic>{
      'fallback': 'calculator',
      'rules': <dynamic>[
        <String, dynamic>{
          'rule_id': 'fx_leuven_bru',
          'name': 'Leuven → BRU',
          'kind': 'airport',
          'enabled': true,
          'priority': 20,
          'price_incl_vat': 85,
          'airport_iata': 'BRU',
          'destination': <String, dynamic>{
            'type': 'airport',
            'airport_iata': 'BRU',
          },
        },
        <String, dynamic>{
          'rule_id': 'fx_leuven_gent',
          'name': 'Leuven → Gent',
          'kind': 'city_pair',
          'enabled': true,
          'price_incl_vat': 95,
        },
      ],
    };
    tester.view.physicalSize = const Size(720, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(720, 1100)),
        child: MaterialApp(
          home: CompanyFixedPricesPage(
            language: AppLanguage.nl,
            catalog: CompanyFixedPricesCatalog.airport,
            loader: () async => stored,
            saver: (doc) async {
              stored = Map<String, dynamic>.from(doc);
              return stored;
            },
            previewer: (payload) async => <String, dynamic>{
              'ok': true,
              'matched': true,
              'snapshot': <String, dynamic>{
                'name': 'Leuven → BRU',
                'fixed_fare_rule_id': 'fx_leuven_bru',
                'total_incl_vat': 85,
                'surcharges': <dynamic>[],
              },
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Leuven → BRU'), findsWidgets);
    expect(find.text('Leuven → Gent'), findsNothing);
    await tester.ensureVisible(find.byKey(kCompanyFixedPricesSaveKey));
    await tester.tap(find.byKey(kCompanyFixedPricesSaveKey));
    await tester.pumpAndSettle();
    expect(
      (stored['rules'] as List).any(
        (item) => item is Map && item['rule_id'] == 'fx_leuven_gent',
      ),
      isTrue,
    );
    await tester.ensureVisible(find.byKey(kCompanyFixedPricesPreviewKey));
    await tester.tap(find.byKey(kCompanyFixedPricesPreviewKey));
    await tester.pumpAndSettle();
    expect(find.textContaining('Leuven → BRU'), findsWidgets);
    expect(find.textContaining('€85'), findsWidgets);
  });

  testWidgets('phone format keeps add and save on screen', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(390, 700)),
        child: MaterialApp(
          home: CompanyFixedPricesPage(
            language: AppLanguage.nl,
            catalog: CompanyFixedPricesCatalog.city,
            loader: () async => <String, dynamic>{
              'fallback': 'calculator',
              'rules': <dynamic>[
                for (var i = 0; i < 8; i++)
                  <String, dynamic>{
                    'rule_id': 'fx_$i',
                    'name': 'Tarief $i',
                    'kind': 'city_pair',
                    'enabled': true,
                    'price_incl_vat': 50 + i,
                  },
              ],
            },
            saver: (doc) async => doc,
            previewer: (_) async => <String, dynamic>{'ok': true},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyFixedPricesAddKey), findsOneWidget);
    expect(
      tester.getRect(find.byKey(kCompanyFixedPricesAddKey)).top,
      lessThan(280),
    );
    expect(find.byKey(kCompanyFixedPricesSaveKey), findsOneWidget);
    expect(
      tester.getRect(find.byKey(kCompanyFixedPricesSaveKey)).bottom,
      lessThanOrEqualTo(700),
    );
  });

  testWidgets('a fare becomes publicly visible and stays that way on save', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    tester.view.physicalSize = const Size(720, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(720, 1400)),
        child: MaterialApp(
          home: CompanyFixedPricesPage(
            language: AppLanguage.nl,
            catalog: CompanyFixedPricesCatalog.city,
            loader: () async => <String, dynamic>{
              'fallback': 'calculator',
              'updated_at': '2026-09-13T12:00:00.000Z',
              'rules': <dynamic>[
                <String, dynamic>{
                  'rule_id': 'fx_maarkedal_ronse',
                  'name': 'Vast tarief van Maarkedal naar Ronse',
                  'kind': 'city_pair',
                  'direction': 'one_way',
                  'enabled': true,
                  'public_visible': false,
                  'price_incl_vat': 35,
                  'origin': <String, dynamic>{
                    'type': 'postcode',
                    'value': '9688',
                    'label': '9688, Maarkedal',
                  },
                  'destination': <String, dynamic>{
                    'type': 'zone',
                    'value': 'Ronse',
                    'label': 'Ronse',
                  },
                },
              ],
            },
            saver: (doc) async {
              saved = Map<String, dynamic>.from(doc);
              return saved!;
            },
            previewer: (_) async => <String, dynamic>{'ok': true},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final toggle = find.byKey(
      companyFixedPricePublicVisibleKey('fx_maarkedal_ronse'),
    );
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(find.byKey(kCompanyFixedPricesUnsavedKey), findsOneWidget);

    await tester.tap(find.byKey(kCompanyFixedPricesSaveKey));
    await tester.pumpAndSettle();

    final rules = (saved?['rules'] as List?)!.cast<Map>();
    expect(rules.single['public_visible'], isTrue);
    expect(rules.single['price_incl_vat'], 35);
    expect(rules.single['direction'], 'one_way');
    expect(find.byKey(kCompanyFixedPricesUnsavedKey), findsNothing);
  });

  testWidgets('suggestion never overwrites a draft amount by itself', (
    tester,
  ) async {
    var applied = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyFixedPriceSuggestion(
            language: AppLanguage.nl,
            from: 'Leuven',
            to: 'BRU',
            airportIata: 'BRU',
            airportDirection: 'to_airport',
            hasManualAmount: true,
            previewer: (payload) async => <String, dynamic>{
              'ok': true,
              'matched': true,
              'snapshot': <String, dynamic>{
                'name': 'Leuven → BRU',
                'fixed_fare_rule_id': 'fx_leuven_bru',
                'total_incl_vat': 85,
                'base_incl_vat': 85,
                'price_covers': 'ride',
              },
            },
            onApply: (_) => applied = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(applied, isFalse);
    expect(find.byKey(kCompanyFixedPriceUseKey), findsNothing);
    await tester.tap(find.text(kCompanyFixedPricesPreview.of(AppLanguage.nl)));
    await tester.pumpAndSettle();
    expect(applied, isFalse);
    await tester.tap(find.byKey(kCompanyFixedPriceUseKey));
    await tester.pumpAndSettle();
    expect(applied, isTrue);
  });

  testWidgets('editor keeps helper text clear of the next field', (
    tester,
  ) async {
    const size = Size(720, 2400);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(1.3),
        ),
        child: MaterialApp(
          home: CompanyFixedPricesPage(
            language: AppLanguage.nl,
            catalog: CompanyFixedPricesCatalog.city,
            loader: () async => <String, dynamic>{
              'fallback': 'calculator',
              'rules': <dynamic>[],
            },
            saver: (doc) async => doc,
            previewer: (_) async => <String, dynamic>{'ok': true},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kCompanyFixedPricesAddKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyFixedPriceEditorKey), findsOneWidget);
    await tester.tap(find.byKey(kCompanyFixedPriceEditorSaveKey));
    await tester.pumpAndSettle();
    expect(find.text('Vul een naam in.'), findsOneWidget);
    final nameError = tester.getRect(find.text('Vul een naam in.'));
    final origin = tester.getRect(
      find.text(kCompanyFixedPricesOrigin.of(AppLanguage.nl)),
    );
    expect(nameError.bottom, lessThanOrEqualTo(origin.top));
    expect(origin.top - nameError.bottom, greaterThanOrEqualTo(16));

    final vatHint = tester.getRect(
      find.text(kCompanyFixedPricesVatHint.of(AppLanguage.nl)),
    );
    final priority = tester.getRect(
      find.text(kCompanyFixedPricesPriority.of(AppLanguage.nl)),
    );
    expect(priority.top - vatHint.bottom, greaterThanOrEqualTo(16));

    final priorityHint = tester.getRect(
      find.text(kCompanyFixedPricesPriorityHint.of(AppLanguage.nl)),
    );
    final covers = tester.getRect(find.text('Prijs geldt voor'));
    expect(covers.top - priorityHint.bottom, greaterThanOrEqualTo(16));

    final includedHint = tester.getRect(
      find.text(kCompanyFixedPricesIncludedAreaHint.of(AppLanguage.nl)),
    );
    final includedKm = tester.getRect(
      find.text('Inbegrepen afstand in km (optioneel)'),
    );
    expect(includedKm.top - includedHint.bottom, greaterThanOrEqualTo(16));

    final last = tester.getRect(find.text('Voertuigklasse'));
    final save = tester.getRect(find.byKey(kCompanyFixedPriceEditorSaveKey));
    expect(last.bottom, lessThanOrEqualTo(save.top));
  });
}
