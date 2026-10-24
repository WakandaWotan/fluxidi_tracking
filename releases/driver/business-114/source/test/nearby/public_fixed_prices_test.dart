import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/nearby/public_fixed_prices.dart';
import 'package:fluxidi_tracking/nearby/public_fixed_prices_page.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';

Map<String, dynamic> _cityFare({
  String ruleId = 'fx_maarkedal_ronse',
  String name = 'Vast tarief van Maarkedal naar Ronse',
}) {
  return <String, dynamic>{
    'rule_id': ruleId,
    'name': name,
    'kind': 'city_pair',
    'direction': 'one_way',
    'airport_iata': '',
    'origin': <String, dynamic>{
      'type': 'postcode',
      'value': '9688',
      'label': '9688, Maarkedal, Oost-Vlaanderen, België',
      'airport_iata': '',
      'lat': null,
      'lng': null,
    },
    'destination': <String, dynamic>{
      'type': 'zone',
      'value': 'Ronse',
      'label': 'Ronse, Oost-Vlaanderen, België',
      'airport_iata': '',
      'lat': null,
      'lng': null,
    },
    'price_incl_vat': 35,
    'price_ex_vat': 33.02,
    'price_vat': 1.98,
    'vat_rate': 0.06,
    'currency': 'EUR',
    'price_covers': 'ride',
    'tier': 'premium',
    'pax_min': 1,
    'pax_max': 4,
    'bags_max': 99,
    'includes': <String, dynamic>{'wait': true, 'bags': false, 'extras': false},
    'zone_surcharge': 10,
    'rule_version': 2,
  };
}

Map<String, dynamic> _airportFare({String ruleId = 'fx_leuven_bru'}) {
  return <String, dynamic>{
    'rule_id': ruleId,
    'name': 'Leuven stad naar Brussels Airport',
    'kind': 'airport',
    'direction': 'to_airport',
    'airport_iata': 'BRU',
    'origin': <String, dynamic>{
      'type': 'city',
      'value': 'leuven',
      'label': 'Leuven',
      'airport_iata': '',
    },
    'destination': <String, dynamic>{
      'type': 'airport',
      'value': 'BRU',
      'label': 'Brussels Airport (BRU)',
      'airport_iata': 'BRU',
    },
    'price_incl_vat': 85,
    'vat_rate': 0.06,
    'currency': 'EUR',
    'price_covers': 'ride',
    'pax_min': 1,
    'pax_max': 99,
    'bags_max': 99,
    'includes': <String, dynamic>{},
    'rule_version': 1,
  };
}

Map<String, dynamic> _profile(List<Map<String, dynamic>> city,
    List<Map<String, dynamic>> airport) {
  return <String, dynamic>{
    'partner_id': 'company:demo_company_p0:demo_company_p0',
    'company_name': 'Fluxidi Demo Cars',
    'fixed_prices': <String, dynamic>{
      'fallback': 'calculator',
      'airport': airport,
      'city': city,
      'total': city.length + airport.length,
    },
  };
}

void main() {
  group('publicFixedPricesFromProfile', () {
    test('splits airports from villages and cities', () {
      final catalog = publicFixedPricesFromProfile(
        _profile(<Map<String, dynamic>>[_cityFare()], <Map<String, dynamic>>[
          _airportFare(),
        ]),
      );
      expect(catalog.city.single.ruleId, 'fx_maarkedal_ronse');
      expect(catalog.airport.single.ruleId, 'fx_leuven_bru');
      expect(catalog.length, 2);
      expect(catalog.fallback, 'calculator');
    });

    test('a profile without published fares stays empty', () {
      final catalog = publicFixedPricesFromProfile(<String, dynamic>{
        'company_name': 'Fluxidi Demo Cars',
      });
      expect(catalog.isEmpty, isTrue);
    });
  });

  group('fare texts', () {
    final entry = PublicFixedPrice.fromJson(_cityFare())!;

    test('shows the route, the amount and the applicable VAT', () {
      expect(
        publicFixedPriceRouteText(entry),
        '9688, Maarkedal, Oost-Vlaanderen, België → Ronse, Oost-Vlaanderen, België',
      );
      expect(
        publicFixedPriceAmountText(entry, AppLanguage.nl),
        '€ 35,00 incl. 6% btw',
      );
    });

    test('one way, per leg and return read differently', () {
      expect(
        publicFixedPriceScopeLabel(entry, AppLanguage.nl),
        'Enkele rit',
      );
      final bothWays = PublicFixedPrice.fromJson(
        <String, dynamic>{..._cityFare(), 'direction': 'both'},
      )!;
      expect(
        publicFixedPriceScopeLabel(bothWays, AppLanguage.nl),
        'Per ritdeel',
      );
      final roundtrip = PublicFixedPrice.fromJson(
        <String, dynamic>{..._cityFare(), 'price_covers': 'full_assignment'},
      )!;
      expect(
        publicFixedPriceScopeLabel(roundtrip, AppLanguage.nl),
        'Retour inbegrepen',
      );
    });

    test('vehicle and passenger conditions and the area surcharge show up', () {
      final conditions = publicFixedPriceConditionLabels(entry, AppLanguage.nl);
      expect(conditions, contains('Voertuig: Premium'));
      expect(conditions, contains('Tot 4 passagiers'));
      expect(conditions, contains('Wachten inbegrepen'));
      expect(
        publicFixedPriceSurchargeLabels(entry, AppLanguage.nl).single,
        'Gebiedstoeslag € 10,00 buiten het inbegrepen gebied',
      );
    });

    test('airport fares name their direction', () {
      final airport = PublicFixedPrice.fromJson(_airportFare())!;
      expect(
        publicFixedPriceDirectionLabel(airport, AppLanguage.nl),
        'Naar de luchthaven',
      );
      expect(publicFixedPriceDirectionLabel(entry, AppLanguage.nl), '');
    });
  });

  group('search', () {
    test('matches on place, airport code and fare name', () {
      final entries = <PublicFixedPrice>[
        PublicFixedPrice.fromJson(_cityFare())!,
        PublicFixedPrice.fromJson(_airportFare())!,
      ];
      expect(
        publicFixedPricesMatching(entries, 'ronse').single.ruleId,
        'fx_maarkedal_ronse',
      );
      expect(
        publicFixedPricesMatching(entries, 'BRU').single.ruleId,
        'fx_leuven_bru',
      );
      expect(publicFixedPricesMatching(entries, 'maarkedal').length, 1);
      expect(publicFixedPricesMatching(entries, 'antwerpen'), isEmpty);
      expect(publicFixedPricesMatching(entries, '  ').length, 2);
    });
  });

  group('PublicFixedPricesAllPage', () {
    testWidgets('search narrows the list and booking returns the fare', (
      tester,
    ) async {
      PublicFixedPrice? booked;
      await tester.pumpWidget(
        MaterialApp(
          home: PublicFixedPricesAllPage(
            companyName: 'Fluxidi Demo Cars',
            catalog: PublicFixedPriceCatalog(
              airport: <PublicFixedPrice>[
                PublicFixedPrice.fromJson(_airportFare())!,
              ],
              city: <PublicFixedPrice>[
                PublicFixedPrice.fromJson(_cityFare())!,
              ],
              fallback: 'calculator',
            ),
            onBook: (entry) => booked = entry,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(publicFixedPriceTileKey('fx_leuven_bru')), findsOneWidget);
      expect(
        find.byKey(publicFixedPriceTileKey('fx_maarkedal_ronse')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(kPublicFixedPricesSearchKey),
        'ronse',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(publicFixedPriceTileKey('fx_leuven_bru')), findsNothing);

      await tester.tap(
        find.byKey(publicFixedPriceBookKey('fx_maarkedal_ronse')),
      );
      await tester.pumpAndSettle();
      expect(booked?.ruleId, 'fx_maarkedal_ronse');
    });

    testWidgets('a fare stays readable at phone width', (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: PublicFixedPriceTile(
                entry: PublicFixedPrice.fromJson(_cityFare())!,
                language: AppLanguage.nl,
                palette: paletteForCustomerTheme(
                  CustomerThemeVariant.values.first,
                ),
                onBook: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final button = tester.getRect(
        find.byKey(publicFixedPriceBookKey('fx_maarkedal_ronse')),
      );
      expect(button.width, lessThanOrEqualTo(360));
      expect(button.height, greaterThanOrEqualTo(40));
      expect(button.right, lessThanOrEqualTo(360));
    });
  });
}
