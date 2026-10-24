import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/nearby/public_fixed_prices.dart';
import 'package:fluxidi_tracking/partner_public_profile_page.dart';

Map<String, dynamic> _fare({
  required String ruleId,
  required String name,
  required String kind,
  required String fromLabel,
  required String toLabel,
  required num price,
}) {
  return <String, dynamic>{
    'rule_id': ruleId,
    'name': name,
    'kind': kind,
    'direction': kind == 'airport' ? 'to_airport' : 'one_way',
    'airport_iata': kind == 'airport' ? 'BRU' : '',
    'origin': <String, dynamic>{
      'type': kind == 'airport' ? 'city' : 'postcode',
      'value': fromLabel,
      'label': fromLabel,
      'airport_iata': '',
    },
    'destination': <String, dynamic>{
      'type': kind == 'airport' ? 'airport' : 'zone',
      'value': toLabel,
      'label': toLabel,
      'airport_iata': kind == 'airport' ? 'BRU' : '',
    },
    'price_incl_vat': price,
    'vat_rate': 0.06,
    'currency': 'EUR',
    'price_covers': 'ride',
    'pax_min': 1,
    'pax_max': 4,
    'bags_max': 99,
    'includes': <String, dynamic>{},
    'rule_version': 1,
  };
}

Map<String, dynamic> _profileWith({
  required List<Map<String, dynamic>> airport,
  required List<Map<String, dynamic>> city,
}) {
  return <String, dynamic>{
    'partner_id': 'company:demo_company_p0:demo_company_p0',
    'company_name': 'Fluxidi Demo Cars',
    'is_active': true,
    'profile_enabled': true,
    'coverage': <String, dynamic>{'region_label': 'België'},
    'fixed_prices': <String, dynamic>{
      'fallback': 'calculator',
      'airport': airport,
      'city': city,
      'total': airport.length + city.length,
    },
  };
}

Future<void> _pumpProfile(
  WidgetTester tester,
  Map<String, dynamic> profile, {
  Size size = const Size(900, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  appLanguageNotifier.value = AppLanguage.nl;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        home: PartnerPublicProfilePage(
          partnerId: 'company:demo_company_p0:demo_company_p0',
          companyNameFallback: 'Fluxidi Demo Cars',
          customerHomeBuilder: (_) => const Scaffold(body: Text('home')),
          profileOverride: profile,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('published fares show up under Onze vaste prijzen', (
    tester,
  ) async {
    await _pumpProfile(
      tester,
      _profileWith(
        airport: <Map<String, dynamic>>[
          _fare(
            ruleId: 'fx_leuven_bru',
            name: 'Leuven naar Brussels Airport',
            kind: 'airport',
            fromLabel: 'Leuven',
            toLabel: 'Brussels Airport (BRU)',
            price: 85,
          ),
        ],
        city: <Map<String, dynamic>>[
          _fare(
            ruleId: 'fx_maarkedal_ronse',
            name: 'Vast tarief van Maarkedal naar Ronse',
            kind: 'city_pair',
            fromLabel: '9688, Maarkedal',
            toLabel: 'Ronse',
            price: 35,
          ),
        ],
      ),
    );

    final section = find.byKey(kPublicFixedPricesSectionKey);
    expect(section, findsOneWidget);
    await tester.scrollUntilVisible(section, 300);
    await tester.pumpAndSettle();

    expect(
      find.text(kPublicFixedPricesTitle.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(
      find.text(kPublicFixedPricesAirports.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(
      find.text(kPublicFixedPricesCities.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(find.text('Leuven → Brussels Airport (BRU)'), findsOneWidget);
    expect(find.text('9688, Maarkedal → Ronse'), findsOneWidget);
    expect(find.text('€ 35,00 incl. 6% btw'), findsOneWidget);
    expect(find.text('Enkele rit'), findsWidgets);
    expect(find.text('Naar de luchthaven'), findsOneWidget);
    expect(find.text('Tot 4 passagiers'), findsWidgets);
    expect(
      find.byKey(publicFixedPriceBookKey('fx_maarkedal_ronse')),
      findsOneWidget,
    );
  });

  testWidgets('a long list shows a selection plus Alle vaste prijzen', (
    tester,
  ) async {
    await _pumpProfile(
      tester,
      _profileWith(
        airport: const <Map<String, dynamic>>[],
        city: <Map<String, dynamic>>[
          for (var i = 0; i < 6; i += 1)
            _fare(
              ruleId: 'fx_city_$i',
              name: 'Tarief $i',
              kind: 'city_pair',
              fromLabel: 'Plaats $i',
              toLabel: 'Ronse',
              price: 30 + i,
            ),
        ],
      ),
    );

    final section = find.byKey(kPublicFixedPricesSectionKey);
    await tester.scrollUntilVisible(section, 300);
    await tester.pumpAndSettle();

    expect(find.byKey(publicFixedPriceTileKey('fx_city_0')), findsOneWidget);
    expect(
      find.byKey(publicFixedPriceTileKey('fx_city_2')),
      findsOneWidget,
    );
    expect(find.byKey(publicFixedPriceTileKey('fx_city_5')), findsNothing);

    final allButton = find.byKey(kPublicFixedPricesAllButtonKey);
    expect(allButton, findsOneWidget);
    await tester.tap(allButton);
    await tester.pumpAndSettle();

    expect(find.byKey(kPublicFixedPricesAllPageKey), findsOneWidget);
    expect(find.byKey(kPublicFixedPricesSearchKey), findsOneWidget);
    expect(find.byKey(publicFixedPriceTileKey('fx_city_5')), findsOneWidget);
  });

  testWidgets('a profile without published fares hides the section', (
    tester,
  ) async {
    await _pumpProfile(
      tester,
      _profileWith(
        airport: const <Map<String, dynamic>>[],
        city: const <Map<String, dynamic>>[],
      ),
    );
    expect(find.byKey(kPublicFixedPricesSectionKey), findsNothing);
  });

  testWidgets('the fare stays inside a phone width without overflow', (
    tester,
  ) async {
    await _pumpProfile(
      tester,
      _profileWith(
        airport: const <Map<String, dynamic>>[],
        city: <Map<String, dynamic>>[
          _fare(
            ruleId: 'fx_maarkedal_ronse',
            name: 'Vast tarief van Maarkedal naar Ronse',
            kind: 'city_pair',
            fromLabel: '9688, Maarkedal, Oost-Vlaanderen, België',
            toLabel: 'Ronse, Oost-Vlaanderen, België',
            price: 35,
          ),
        ],
      ),
      size: const Size(360, 800),
    );

    final section = find.byKey(kPublicFixedPricesSectionKey);
    await tester.scrollUntilVisible(section, 300);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final book = tester.getRect(
      find.byKey(publicFixedPriceBookKey('fx_maarkedal_ronse')),
    );
    expect(book.left, greaterThanOrEqualTo(0));
    expect(book.right, lessThanOrEqualTo(360));
    expect(book.height, greaterThanOrEqualTo(40));
  });
}
