import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_customer/api/public_partner_api.dart';
import 'package:fluxidi_customer/app/customer_app_config.dart';
import 'package:fluxidi_customer/app/customer_theme.dart';
import 'package:fluxidi_customer/screens/customer_taxi_search_screen.dart';
import 'package:http/http.dart' as http;

const CustomerAppConfig _config = CustomerAppConfig(
  appName: 'Fluxidi Customer Dev',
  environmentLabel: 'DEV',
  androidApplicationId: 'com.fluxidi.customer.dev',
  deepLinkScheme: 'fluxidicustomerdev',
  deepLinkHost: 'pay',
  deepLinkPath: '/return',
  variant: CustomerAppVariant.fluxidiMarketplace,
  brand: CustomerBrandColors(
    primary: Color(0xFFFFD400),
    accent: Color(0xFFFFD54F),
    background: Color(0xFF07080B),
    surface: Color(0xFF121318),
    card: Color(0xFF171922),
    textSoft: Color(0xFFB8BDC9),
  ),
  publicBookingBaseUrl: 'https://example.invalid',
);

final CustomerAppConfig _whiteLabelConfig = CustomerAppConfig(
  appName: _config.appName,
  environmentLabel: _config.environmentLabel,
  androidApplicationId: _config.androidApplicationId,
  deepLinkScheme: _config.deepLinkScheme,
  deepLinkHost: _config.deepLinkHost,
  deepLinkPath: _config.deepLinkPath,
  variant: CustomerAppVariant.whiteLabelSingleCompany,
  brand: _config.brand,
  publicBookingBaseUrl: _config.publicBookingBaseUrl,
);

/// Fake transport that answers per path and records the requests it saw.
class _FakeApi {
  _FakeApi({
    required this.nearbyBody,
    this.profileBody,
    this.throwOnNearby = false,
  });

  final String nearbyBody;
  final String? profileBody;
  bool throwOnNearby;

  final List<Uri> requests = <Uri>[];

  PublicPartnerApi build() => PublicPartnerApi(
    baseUrl: _config.publicBookingBaseUrl,
    httpGet: (Uri url, {Map<String, String>? headers}) async {
      requests.add(url);
      if (url.path.endsWith('/partners/nearby')) {
        if (throwOnNearby) {
          throw http.ClientException('offline');
        }
        return http.Response(nearbyBody, 200);
      }
      return http.Response(profileBody ?? '{}', 200);
    },
  );
}

String _nearby(List<Map<String, dynamic>> partners) => jsonEncode(
  <String, dynamic>{
    'ok': true,
    'postcode': '9600',
    'count': partners.length,
    'partners': partners,
  },
);

final String _twoPartners = _nearby(<Map<String, dynamic>>[
  <String, dynamic>{
    'partner_id': 'company:t1:c1',
    'company_name': 'Taxi Schorisse',
    'city': 'Maarkedal',
    'postcode': '9680',
    'country_code': 'BE',
    'bookable': true,
  },
  <String, dynamic>{
    'partner_id': 'company:t2:c2',
    'company_name': 'Taxi Ronse',
    'availability_status': 'inactive',
  },
]);

final String _profileBody = jsonEncode(<String, dynamic>{
  'ok': true,
  'profile': <String, dynamic>{
    'company_name': 'Taxi Schorisse',
    'coverage': <String, dynamic>{
      'region_label': 'Vlaamse Ardennen',
      'postcodes': <String>['9600', '9680'],
    },
    'bookable': true,
  },
});

Future<void> _pump(
  WidgetTester tester,
  PublicPartnerApi api, {
  CustomerAppConfig config = _config,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildCustomerTheme(config),
      home: CustomerTaxiSearchScreen(api: api, config: config),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _searchFor(WidgetTester tester, String postcode) async {
  await tester.enterText(
    find.byKey(const Key('taxi_search_postcode_field')),
    postcode,
  );
  await tester.tap(find.byKey(const Key('taxi_search_button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('searching by postcode sends the postcode and lists partners', (
    tester,
  ) async {
    final fake = _FakeApi(nearbyBody: _twoPartners, profileBody: _profileBody);
    await _pump(tester, fake.build());

    await _searchFor(tester, ' 9600 ');

    expect(fake.requests, hasLength(1));
    expect(fake.requests.single.path, '/partners/nearby');
    expect(fake.requests.single.queryParameters, <String, String>{
      'postcode': '9600',
    });

    expect(find.text('Actieve partners in 9600'), findsOneWidget);
    expect(find.text('Taxi Schorisse'), findsOneWidget);
    expect(find.text('Maarkedal · 9680 · BE'), findsOneWidget);
    expect(find.text('Taxi Ronse'), findsOneWidget);

    // Server-stated state only: one active, one inactive. Nothing invented.
    expect(find.byKey(const Key('partner_status_active')), findsOneWidget);
    expect(find.byKey(const Key('partner_status_inactive')), findsOneWidget);
  });

  testWidgets('tapping a result opens that company profile', (tester) async {
    final fake = _FakeApi(nearbyBody: _twoPartners, profileBody: _profileBody);
    await _pump(tester, fake.build());
    await _searchFor(tester, '9600');

    await tester.tap(find.text('Taxi Schorisse'));
    await tester.pumpAndSettle();

    final profileRequest = fake.requests.last;
    expect(profileRequest.path, '/partners/profile');
    expect(profileRequest.queryParameters, <String, String>{
      'partner_id': 'company:t1:c1',
    });

    expect(find.text('Vlaamse Ardennen'), findsOneWidget);
    expect(find.text('9600, 9680'), findsOneWidget);
    // Booking must not look available yet.
    expect(
      find.byKey(const Key('profile_booking_not_connected')),
      findsOneWidget,
    );
  });

  testWidgets('going back keeps the search query and its results', (
    tester,
  ) async {
    final fake = _FakeApi(nearbyBody: _twoPartners, profileBody: _profileBody);
    await _pump(tester, fake.build());
    await _searchFor(tester, '9600');

    await tester.tap(find.text('Taxi Schorisse'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Actieve partners in 9600'), findsOneWidget);
    expect(find.text('Taxi Schorisse'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('taxi_search_postcode_field')))
          .controller
          ?.text,
      '9600',
    );
    // Returning must not trigger another search.
    expect(
      fake.requests.where((uri) => uri.path == '/partners/nearby'),
      hasLength(1),
    );
  });

  testWidgets('the example company is marked in the list and on its profile', (
    tester,
  ) async {
    final fake = _FakeApi(
      nearbyBody: _nearby(<Map<String, dynamic>>[
        <String, dynamic>{
          'partner_id': 'company:t1:c1',
          'company_name': 'Voorbeeld Taxi',
          'bookable': true,
          'example_company': true,
        },
      ]),
      profileBody: jsonEncode(<String, dynamic>{
        'ok': true,
        'profile': <String, dynamic>{
          'company_name': 'Voorbeeld Taxi',
          'bookable': true,
          'example_company': true,
        },
      }),
    );
    await _pump(tester, fake.build());
    await _searchFor(tester, '9600');

    expect(find.byKey(const Key('partner_presentation_badge')), findsOneWidget);
    expect(find.text('Voorbeeldbedrijf'), findsOneWidget);

    await tester.tap(find.text('Voorbeeld Taxi'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile_presentation_badge')), findsOneWidget);
    expect(find.byKey(const Key('profile_presentation_notice')), findsOneWidget);
  });

  testWidgets('an ordinary company shows no example badge', (tester) async {
    final fake = _FakeApi(nearbyBody: _twoPartners, profileBody: _profileBody);
    await _pump(tester, fake.build());
    await _searchFor(tester, '9600');

    expect(find.byKey(const Key('partner_presentation_badge')), findsNothing);
  });

  testWidgets('an empty result explains it instead of showing an empty list', (
    tester,
  ) async {
    final fake = _FakeApi(nearbyBody: _nearby(const <Map<String, dynamic>>[]));
    await _pump(tester, fake.build());

    await _searchFor(tester, '9600');

    expect(find.text('Geen bedrijven gevonden'), findsOneWidget);
    expect(
      find.text('Geen partners gevonden voor postcode of servicegebied 9600.'),
      findsOneWidget,
    );
  });

  testWidgets('a network failure offers retry and then succeeds', (
    tester,
  ) async {
    final fake = _FakeApi(nearbyBody: _twoPartners, throwOnNearby: true);
    await _pump(tester, fake.build());

    await _searchFor(tester, '9600');

    expect(find.text('Geen verbinding'), findsOneWidget);
    expect(find.byKey(const Key('taxi_search_retry')), findsOneWidget);

    fake.throwOnNearby = false;
    await tester.tap(find.byKey(const Key('taxi_search_retry')));
    await tester.pumpAndSettle();

    expect(find.text('Taxi Schorisse'), findsOneWidget);
    expect(find.byKey(const Key('taxi_search_retry')), findsNothing);
  });

  testWidgets('an invalid response is reported, not rendered as results', (
    tester,
  ) async {
    final fake = _FakeApi(nearbyBody: '<html>nope</html>');
    await _pump(tester, fake.build());

    await _searchFor(tester, '9600');

    expect(find.text('Zoeken is niet beschikbaar'), findsOneWidget);
    expect(find.text('Taxi Schorisse'), findsNothing);
  });

  testWidgets('an empty postcode asks for input without calling the API', (
    tester,
  ) async {
    final fake = _FakeApi(nearbyBody: _twoPartners);
    await _pump(tester, fake.build());

    await tester.tap(find.byKey(const Key('taxi_search_button')));
    await tester.pumpAndSettle();

    expect(find.text('Vul eerst een postcode in'), findsOneWidget);
    expect(find.byKey(const Key('taxi_search_retry')), findsNothing);
    expect(fake.requests, isEmpty);
  });

  testWidgets('the white-label variant refuses the platform-wide list', (
    tester,
  ) async {
    final fake = _FakeApi(nearbyBody: _twoPartners);
    await _pump(tester, fake.build(), config: _whiteLabelConfig);

    expect(find.text('Bedrijfsvariant nog niet ondersteund'), findsOneWidget);
    expect(find.byKey(const Key('taxi_search_button')), findsNothing);
    expect(fake.requests, isEmpty);
  });

  testWidgets('an unconfigured base URL names the missing define', (
    tester,
  ) async {
    await _pump(
      tester,
      PublicPartnerApi(
        baseUrl: '',
        httpGet: (Uri url, {Map<String, String>? headers}) async =>
            throw StateError('must not be called'),
      ),
    );

    expect(find.text('API niet geconfigureerd'), findsOneWidget);
    expect(
      find.textContaining(kPublicBookingBaseUrlDefineKey),
      findsOneWidget,
    );
  });
}
