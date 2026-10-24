import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery.dart';
import 'package:fluxidi_tracking/private_chauffeur/private_chauffeur_capability.dart';
import 'package:fluxidi_tracking/private_chauffeur/private_chauffeur_discovery.dart';
import 'package:fluxidi_tracking/private_chauffeur/private_chauffeur_discovery_api.dart';
import 'package:fluxidi_tracking/private_chauffeur/private_chauffeur_discovery_page.dart';
import 'package:fluxidi_tracking/private_chauffeur/private_chauffeur_selection_page.dart';
import 'package:http/http.dart' as http;

void main() {
  setUp(() => setAppLanguage(AppLanguage.nl));

  test('private_chauffeur is the service code and booking is not ready', () {
    expect(kPrivateChauffeurServiceCode, 'private_chauffeur');
    expect(kPrivateChauffeurBookingContractReady, isFalse);
  });

  test('only an explicit private chauffeur offer is listable', () {
    expect(
      privateChauffeurCardsFromNearbyPartners(<Map<String, dynamic>>[
        _partner(
          id: 'on',
          name: 'Atelier Noord',
          services: ['private_chauffeur'],
        ),
        _partner(
          id: 'off',
          name: 'Uitgeschakeld',
          services: ['private_chauffeur'],
          extra: const <String, dynamic>{'private_chauffeur_enabled': false},
        ),
        _partner(id: 'missing', name: 'Taxi Gent', services: ['taxi']),
        _partner(id: 'limo', name: 'Limousine Gent', services: ['limousine']),
        _partner(
          id: 'flag',
          name: 'Vlag Aan',
          extra: const <String, dynamic>{'private_chauffeur_enabled': true},
        ),
        _partner(
          id: 'inactive',
          name: 'Slapend',
          services: ['private_chauffeur'],
          extra: const <String, dynamic>{'is_active': false},
        ),
        _partner(id: 'bare', name: 'Zonder vlag'),
      ]).map((card) => card.publicPartnerId),
      ['on', 'flag'],
    );
  });

  test('nearby keeps the service code and drops taxi and limousine', () async {
    final client = _ScriptedClient(
      jsonEncode(<String, dynamic>{
        'ok': true,
        'partners': <Map<String, dynamic>>[
          _partner(
            id: 'on',
            name: 'Atelier Noord',
            services: ['private_chauffeur'],
          ),
          _partner(
            id: 'taxi',
            name: 'Taxi Gent',
            services: ['taxi', 'airport_transfer'],
          ),
          _partner(id: 'limo', name: 'Limousine Gent', services: ['limousine']),
        ],
      }),
    );
    final gateway = HttpPrivateChauffeurDiscoveryGateway(
      client: client,
      bookingBaseUrl: 'https://booking.test',
    );

    final unscoped = await gateway.search(const LimousineDiscoveryQuery());
    expect(unscoped.needPlace, isTrue);
    expect(unscoped.cards, isEmpty);
    expect(client.gets, 0);

    final listed = await gateway.search(
      const LimousineDiscoveryQuery(postcode: '9000'),
    );
    expect(client.lastUri?.queryParameters['service'], 'private_chauffeur');
    expect(client.lastUri?.queryParameters['postcode'], '9000');
    expect(client.lastUri.toString(), isNot(contains('service=limousine')));
    expect(listed.cards.map((card) => card.companyName), ['Atelier Noord']);
    expect(listed.cards.single.price.kind, LimousineDiscoveryPriceKind.none);

    final located = await gateway.search(
      const LimousineDiscoveryQuery(lat: 51.05, lng: 3.72),
    );
    expect(located.cards, hasLength(1));
    expect(client.lastUri?.queryParameters['lat'], '51.050000');
    expect(client.lastUri?.queryParameters['lng'], '3.720000');
    expect(client.lastUri?.queryParameters.containsKey('postcode'), isFalse);
  });

  test('a profile without the flag does not open', () async {
    final client = _ScriptedClient(
      jsonEncode(<String, dynamic>{
        'profile': _partner(id: 'taxi', name: 'Taxi Gent', services: ['taxi']),
      }),
    );
    final gateway = HttpPrivateChauffeurDiscoveryGateway(
      client: client,
      bookingBaseUrl: 'https://booking.test',
    );
    expect(await gateway.loadPublicProfile('taxi'), isNull);
    expect(client.lastUri?.path, kPrivateChauffeurProfilePath);
    expect(client.lastUri?.queryParameters['partner_id'], 'taxi');
  });

  testWidgets('search keeps the chosen company and service without booking', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lookup = LimousinePlaceLookup(
      searchOverride: (query, language) async =>
          const LimousinePlaceLookupResult(),
    );
    addTearDown(lookup.dispose);
    final gateway = MemoryPrivateChauffeurDiscoveryGateway(
      searchHandler: (query) async {
        return PrivateChauffeurDiscoveryPageData(
          cards: privateChauffeurCardsFromNearbyPartners(<Map<String, dynamic>>[
            _partner(
              id: 'partner-atelier',
              name: 'Atelier Noord',
              services: const ['private_chauffeur'],
            ),
            _partner(
              id: 'taxi-gent',
              name: 'Taxi Gent',
              services: const ['taxi'],
            ),
            _partner(
              id: 'limo-gent',
              name: 'Limousine Gent',
              services: const ['limousine'],
            ),
          ]),
        );
      },
      profileHandler: (id) async => _partner(
        id: id,
        name: 'Atelier Noord',
        services: const ['private_chauffeur'],
      ),
    );

    await tester.pumpWidget(
      _app(
        PrivateChauffeurDiscoveryPage(gateway: gateway, placeLookup: lookup),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(kPrivateChauffeurNeedPlaceKey), findsOneWidget);
    expect(find.text('Taxi Gent'), findsNothing);
    expect(find.text('Limousine Gent'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('private_chauffeur_place')),
      '9000',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kPrivateChauffeurSearchActionKey));
    await tester.pumpAndSettle();

    expect(find.byKey(kPrivateChauffeurEmptyKey), findsNothing);
    expect(find.text('Atelier Noord'), findsWidgets);
    expect(find.text('Taxi Gent'), findsNothing);
    expect(find.text('Limousine Gent'), findsNothing);
    expect(gateway.bookCalls, 0);
    expect(gateway.createQuoteCalls, 0);
    expect(
      gateway.requestedPaths,
      isNot(contains(kLimousineDiscoveryBookPath)),
    );

    await tester.ensureVisible(
      find.byKey(privateChauffeurChooseKey('partner-atelier')),
    );
    await tester.tap(find.byKey(privateChauffeurChooseKey('partner-atelier')));
    await tester.pumpAndSettle();

    final page = tester.widget<PrivateChauffeurSelectionPage>(
      find.byType(PrivateChauffeurSelectionPage),
    );
    expect(page.selection.publicPartnerId, 'partner-atelier');
    expect(page.selection.companyName, 'Atelier Noord');
    expect(page.selection.serviceCode, kPrivateChauffeurServiceCode);
    expect(find.textContaining('€'), findsNothing);
    expect(find.byKey(const Key('private_chauffeur_book')), findsNothing);
    expect(gateway.bookCalls, 0);
    expect(gateway.createQuoteCalls, 0);
  });

  testWidgets('no matching company shows the empty state', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lookup = LimousinePlaceLookup(
      searchOverride: (query, language) async =>
          const LimousinePlaceLookupResult(),
    );
    addTearDown(lookup.dispose);
    final gateway = MemoryPrivateChauffeurDiscoveryGateway(
      searchHandler: (query) async => PrivateChauffeurDiscoveryPageData(
        cards: privateChauffeurCardsFromNearbyPartners(<Map<String, dynamic>>[
          _partner(
            id: 'taxi-gent',
            name: 'Taxi Gent',
            services: const ['taxi'],
          ),
          _partner(
            id: 'off',
            name: 'Uitgeschakeld',
            services: const ['private_chauffeur'],
            extra: const <String, dynamic>{'privateChauffeurEnabled': false},
          ),
        ]),
      ),
    );

    await tester.pumpWidget(
      _app(
        PrivateChauffeurDiscoveryPage(gateway: gateway, placeLookup: lookup),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('private_chauffeur_place')),
      '9000',
    );
    await tester.tap(find.byKey(kPrivateChauffeurSearchActionKey));
    await tester.pumpAndSettle();

    expect(find.byKey(kPrivateChauffeurEmptyKey), findsOneWidget);
    expect(find.text('Taxi Gent'), findsNothing);
    expect(find.text('Uitgeschakeld'), findsNothing);
    expect(find.textContaining('niet als vervanger'), findsOneWidget);
  });

  testWidgets('a profile that drops the flag does not continue', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lookup = LimousinePlaceLookup(
      searchOverride: (query, language) async =>
          const LimousinePlaceLookupResult(),
    );
    addTearDown(lookup.dispose);
    final gateway = MemoryPrivateChauffeurDiscoveryGateway(
      searchHandler: (query) async => PrivateChauffeurDiscoveryPageData(
        cards: privateChauffeurCardsFromNearbyPartners(<Map<String, dynamic>>[
          _partner(
            id: 'partner-atelier',
            name: 'Atelier Noord',
            services: const ['private_chauffeur'],
          ),
        ]),
      ),
      profileHandler: (id) async =>
          _partner(id: id, name: 'Atelier Noord', services: const ['taxi']),
    );

    await tester.pumpWidget(
      _app(
        PrivateChauffeurDiscoveryPage(gateway: gateway, placeLookup: lookup),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('private_chauffeur_place')),
      '9000',
    );
    await tester.tap(find.byKey(kPrivateChauffeurSearchActionKey));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(privateChauffeurChooseKey('partner-atelier')),
    );
    await tester.tap(find.byKey(privateChauffeurChooseKey('partner-atelier')));
    await tester.pumpAndSettle();

    expect(find.byType(PrivateChauffeurSelectionPage), findsNothing);
    expect(find.byKey(kPrivateChauffeurUnavailableKey), findsOneWidget);
    expect(gateway.bookCalls, 0);
  });
}

Map<String, dynamic> _partner({
  required String id,
  required String name,
  List<String>? services,
  Map<String, dynamic> extra = const <String, dynamic>{},
}) {
  return <String, dynamic>{
    'partner_id': id,
    'company_name': name,
    'is_active': true,
    'subscription_status': 'active',
    'profile_enabled': true,
    if (services != null) 'services': services,
    ...extra,
  };
}

class _ScriptedClient extends http.BaseClient {
  _ScriptedClient(this.body);

  final String body;
  Uri? lastUri;
  int gets = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    gets += 1;
    lastUri = request.url;
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}

Widget _app(Widget home) {
  return MaterialApp(home: home);
}
