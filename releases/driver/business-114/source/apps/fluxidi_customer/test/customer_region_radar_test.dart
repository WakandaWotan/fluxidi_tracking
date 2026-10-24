import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_customer/app/customer_labels.dart';
import 'package:fluxidi_customer/app/fluxidi_customer_app.dart';
import 'package:fluxidi_customer/region_radar/region_interest_client.dart';
import 'package:fluxidi_customer/region_radar/region_radar_geocode.dart';
import 'package:fluxidi_customer/region_radar/region_radar_map_interest.dart';
import 'package:fluxidi_customer/region_radar/region_radar_own_interest_store.dart';
import 'package:fluxidi_customer/screens/customer_region_radar_screen.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:http/http.dart' as http;

RegionInterestClient _client({
  Map<String, dynamic>? radar,
  Map<String, dynamic>? submit,
  int Function()? onSubmit,
}) {
  return RegionInterestClient(
    baseUrl: 'https://example.test',
    httpGet: (uri) async {
      expect(uri.path, '/region-interest/radar');
      expect(uri.queryParameters['country'], isNotEmpty);
      expect(uri.queryParameters['postcode'], isNotEmpty);
      final postcode = uri.queryParameters['postcode'] ?? '';
      return http.Response(
        jsonEncode(
          radar ??
              <String, dynamic>{
                'ok': true,
                'country': uri.queryParameters['country'],
                'postcode': postcode,
                'count': postcode == '3500' ? 1 : 3,
                'display_count': postcode == '3500' ? '1+' : '3+',
                'status': 'partners_wanted',
              },
        ),
        200,
      );
    },
    httpPost: (uri, {headers, body}) async {
      onSubmit?.call();
      expect(uri.path, '/region-interest');
      final payload = jsonDecode(body! as String) as Map<String, dynamic>;
      expect(payload['source'], 'regio_radar');
      expect(payload['name'], isNotEmpty);
      expect(payload['email'], contains('@'));
      return http.Response(
        jsonEncode(
          submit ??
              <String, dynamic>{
                'ok': true,
                'country': payload['country'],
                'postcode': payload['postcode'],
                'count': 4,
                'display_count': '4+',
                'status': 'partners_wanted',
              },
        ),
        200,
      );
    },
  );
}

const _schorisse = RegionRadarPlace(
  country: 'BE',
  postcode: '9688',
  placeName: 'Schorisse',
  lat: 50.770,
  lon: 3.656,
  label: '9688 · Schorisse',
);

const _hasselt = RegionRadarPlace(
  country: 'BE',
  postcode: '3500',
  placeName: 'Hasselt',
  lat: 50.931,
  lon: 5.338,
  label: '3500 · Hasselt',
);

RegionRadarPlaceLookup _places({
  RegionRadarPlace? Function(String country, String postcode)? resolve,
  Future<RegionRadarPlace?> Function(String country, String postcode)? delayed,
}) {
  return ({
    required String country,
    required String postcode,
    required String language,
  }) async {
    if (delayed != null) return delayed(country, postcode);
    if (resolve != null) return resolve(country, postcode);
    if (postcode == '9688') return _schorisse;
    if (postcode == '3500') return _hasselt;
    return null;
  };
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await Scrollable.ensureVisible(
    tester.element(finder),
    alignment: 0.45,
    duration: Duration.zero,
  );
  await tester.pump();
}

Future<void> _openRadar(
  WidgetTester tester, {
  RegionInterestClient? client,
  RegionRadarPlaceLookup? placeLookup,
  RegionRadarOwnInterestStore? ownInterestStore,
  void Function(double lat, double lon)? onRegionMoved,
  Size size = const Size(390, 844),
}) async {
  addTearDown(tester.view.reset);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    MaterialApp(
      home: CustomerRegionRadarScreen(
        client: client ?? _client(),
        placeLookup: placeLookup ?? _places(),
        ownInterestStore:
            ownInterestStore ?? RegionRadarOwnInterestStore.memory(),
        onRegionMoved: onRegionMoved,
        mapBuilder: (_) => const ColoredBox(
          key: Key('customer_region_radar_map_stub'),
          color: Color(0xFFCCCCCC),
        ),
        profileLoader: () async => null,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _viewPostcode(WidgetTester tester, String postcode) async {
  await _reveal(tester, find.byKey(const Key('customer_region_radar_postcode')));
  await tester.enterText(
    find.byKey(const Key('customer_region_radar_postcode')),
    postcode,
  );
  await _reveal(tester, find.byKey(const Key('customer_region_radar_view')));
  await tester.tap(find.byKey(const Key('customer_region_radar_view')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    setAppLanguage(AppLanguage.nl);
  });

  test('region line uses the server count and never invents 3+', () {
    expect(
      regionRadarSummaryLine(
        country: 'BE',
        postcode: '9688',
        displayCount: '3+',
        regionWord: 'Regio',
        partnersWanted: 'taxibedrijven gezocht',
      ),
      'Regio BE 9688: 3+ (taxibedrijven gezocht).',
    );
    expect(
      regionRadarSummaryLine(
        country: 'BE',
        postcode: '3500',
        displayCount: '1+',
        regionWord: 'Regio',
        partnersWanted: 'taxibedrijven gezocht',
      ),
      'Regio BE 3500: 1+ (taxibedrijven gezocht).',
    );
    expect(
      regionRadarSummaryLine(
        country: 'BE',
        postcode: '9688',
        regionWord: 'Regio',
        partnersWanted: 'taxibedrijven gezocht',
      ),
      'Regio BE 9688',
    );
  });

  test('region geocode keeps 9688 on Schorisse and ignores Hasselt addresses', () {
    final place = pickRegionRadarPlace(
      country: 'BE',
      postcode: '9688',
      features: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'address.1',
          'place_type': <String>['address'],
          'text': '9688',
          'place_name': '9688 Hasseltsesteenweg, Herk-de-Stad, Belgium',
          'center': <double>[5.17, 50.94],
          'context': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'place.1', 'text': 'Herk-de-Stad'},
            <String, dynamic>{'id': 'country.1', 'short_code': 'be'},
          ],
        },
        <String, dynamic>{
          'id': 'postcode.9688',
          'place_type': <String>['postcode'],
          'text': '9688',
          'place_name': '9688, Schorisse, Belgium',
          'center': <double>[3.656, 50.770],
          'context': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'place.2', 'text': 'Schorisse'},
            <String, dynamic>{'id': 'country.2', 'short_code': 'be'},
          ],
        },
      ],
    );
    expect(place, isNotNull);
    expect(place!.postcode, '9688');
    expect(place.placeName, 'Schorisse');
    expect(place.lat, closeTo(50.770, 0.001));
    expect(place.lon, closeTo(3.656, 0.001));
  });

  test('an address-only Hasselt hit is not accepted for 9688', () {
    expect(
      pickRegionRadarPlace(
        country: 'BE',
        postcode: '9688',
        features: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'address.1',
            'place_type': <String>['address'],
            'text': '9688',
            'place_name': '9688, Hasselt, Belgium',
            'center': <double>[5.338, 50.931],
            'context': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'place.1', 'text': 'Hasselt'},
              <String, dynamic>{'id': 'country.1', 'short_code': 'be'},
            ],
          },
        ],
      ),
      isNull,
    );
  });

  test('region interest validation matches the website rules', () {
    String t({
      required String nl,
      required String en,
      required String fr,
      required String es,
      required String de,
    }) => nl;

    expect(
      regionInterestFieldError(
        draft: const RegionInterestDraft(
          country: 'BE',
          postcode: '',
          firstName: 'Ada',
          lastName: 'Lovelace',
          email: 'ada@example.com',
        ),
        translate: t,
      ),
      CustomerText.radarNeedPostcode.nl,
    );
    expect(
      regionInterestFieldError(
        draft: const RegionInterestDraft(
          country: 'BE',
          postcode: '9688',
          firstName: '',
          lastName: 'Lovelace',
          email: 'ada@example.com',
        ),
        translate: t,
      ),
      CustomerText.radarNeedFields.nl,
    );
    expect(
      regionInterestFieldError(
        draft: const RegionInterestDraft(
          country: 'BE',
          postcode: '9688 Schorisse',
          firstName: 'Ada',
          lastName: 'Lovelace',
          email: 'ada@example.com',
        ),
        translate: t,
      ),
      isNull,
    );
  });

  testWidgets('home tile still opens Region Radar', (tester) async {
    await tester.pumpWidget(const FluxidiCustomerApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('customer_home_region_radar')),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('customer_home_region_radar')), findsOneWidget);
  });

  testWidgets('the screen shows the website sections without registering', (
    tester,
  ) async {
    var submits = 0;
    await _openRadar(tester, client: _client(onSubmit: () => submits += 1));

    expect(
      find.text('Interesse per regio · locaties bij benadering'),
      findsOneWidget,
    );
    expect(find.text('Help lokale taxi’s hun eigen omzet terug te winnen.'), findsOneWidget);
    expect(find.text('Lokale bedrijven'), findsOneWidget);
    expect(find.text('Eigen prijzen'), findsOneWidget);
    expect(find.text('Geen ritcommissie'), findsOneWidget);
    expect(find.text('Waar wil je een taxi kunnen boeken?'), findsOneWidget);
    expect(
      find.text('Vul je postcode in om de interesse in jouw regio te bekijken.'),
      findsOneWidget,
    );
    await _reveal(tester, find.text('Laat jouw regio meetellen'));
    expect(find.text('Laat jouw regio meetellen'), findsOneWidget);
    await _reveal(tester, find.text('Ja, ik heb interesse'));
    expect(find.text('Ja, ik heb interesse'), findsOneWidget);
    expect(find.text('Je toont interesse. Je boekt nog geen rit.'), findsOneWidget);
    await _reveal(tester, find.text('Kies je regio'));
    expect(find.text('Kies je regio'), findsOneWidget);
    expect(find.text('Laat je interesse zien'), findsOneWidget);
    expect(find.text('Maak de vraag zichtbaar'), findsOneWidget);
    expect(submits, 0);
  });

  testWidgets('Belgium 9688 shows Schorisse and the matching 3+ count', (
    tester,
  ) async {
    final cameras = <(double, double)>[];
    await _openRadar(tester, onRegionMoved: (lat, lon) => cameras.add((lat, lon)));
    await _viewPostcode(tester, '9688');

    expect(find.byKey(const Key('customer_region_radar_place')), findsOneWidget);
    expect(find.textContaining('9688'), findsWidgets);
    expect(find.textContaining('Schorisse'), findsWidgets);
    expect(find.textContaining('Hasselt'), findsNothing);
    expect(find.byKey(const Key('customer_region_radar_count')), findsOneWidget);
    expect(find.byKey(const Key('customer_region_radar_region_marker')), findsOneWidget);
    expect(find.byKey(const Key('customer_region_radar_selected_marker')), findsNothing);
    expect(find.byKey(const Key('customer_region_radar_own_marker')), findsNothing);
    expect(find.text('3+'), findsWidgets);
    expect(find.textContaining('interesse in deze regio'), findsOneWidget);
    expect(
      find.byKey(const Key('customer_region_radar_region_line')),
      findsOneWidget,
    );
    expect(
      find.text('Regio BE 9688: 3+ (taxibedrijven gezocht).'),
      findsOneWidget,
    );
    expect(find.textContaining('0+'), findsNothing);
    expect(cameras, hasLength(1));
    expect(cameras.single.$1, closeTo(50.770, 0.001));
    expect(cameras.single.$2, closeTo(3.656, 0.001));
  });

  testWidgets('switching postcode replaces the region instead of keeping 9688', (
    tester,
  ) async {
    final cameras = <(double, double)>[];
    await _openRadar(tester, onRegionMoved: (lat, lon) => cameras.add((lat, lon)));
    await _viewPostcode(tester, '9688');
    await _viewPostcode(tester, '3500');

    expect(find.textContaining('3500 · Hasselt'), findsWidgets);
    expect(find.textContaining('Schorisse'), findsNothing);
    expect(find.text('1+'), findsWidgets);
    expect(
      find.text('Regio BE 3500: 1+ (taxibedrijven gezocht).'),
      findsOneWidget,
    );
    expect(find.text('3+'), findsNothing);
    expect(cameras, hasLength(2));
    expect(cameras.last.$1, closeTo(50.931, 0.001));
    expect(cameras.last.$2, closeTo(5.338, 0.001));
  });

  testWidgets('an unknown postcode does not keep the previous region', (
    tester,
  ) async {
    await _openRadar(tester);
    await _viewPostcode(tester, '9688');
    await _viewPostcode(tester, '0001');

    expect(find.byKey(const Key('customer_region_radar_lookup_error')), findsOneWidget);
    expect(find.byKey(const Key('customer_region_radar_place')), findsNothing);
    expect(find.byKey(const Key('customer_region_radar_count')), findsNothing);
    expect(find.textContaining('Schorisse'), findsNothing);
  });

  testWidgets('a slower earlier lookup cannot overwrite a later postcode', (
    tester,
  ) async {
    final first = Completer<RegionRadarPlace?>();
    var calls = 0;
    await _openRadar(
      tester,
      placeLookup: _places(
        delayed: (country, postcode) async {
          calls += 1;
          if (calls == 1) return first.future;
          return _hasselt;
        },
      ),
    );
    await _reveal(tester, find.byKey(const Key('customer_region_radar_postcode')));
    await tester.enterText(
      find.byKey(const Key('customer_region_radar_postcode')),
      '9688',
    );
    await _reveal(tester, find.byKey(const Key('customer_region_radar_view')));
    await tester.tap(find.byKey(const Key('customer_region_radar_view')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('customer_region_radar_postcode')),
      '3500',
    );
    await _reveal(tester, find.byKey(const Key('customer_region_radar_view')));
    await tester.tap(find.byKey(const Key('customer_region_radar_view')));
    await tester.pump();
    first.complete(_schorisse);
    await tester.pumpAndSettle();

    expect(find.textContaining('3500 · Hasselt'), findsWidgets);
    expect(find.textContaining('Schorisse'), findsNothing);
  });

  testWidgets('submit is blocked until the form is complete', (tester) async {
    var submits = 0;
    await _openRadar(tester, client: _client(onSubmit: () => submits += 1));
    await _reveal(tester, find.byKey(const Key('customer_region_radar_submit')));
    await tester.tap(find.byKey(const Key('customer_region_radar_submit')));
    await tester.pump();
    expect(find.byKey(const Key('customer_region_radar_form_error')), findsOneWidget);
    expect(submits, 0);
  });

  testWidgets('a valid submit posts once and then stays disabled', (
    tester,
  ) async {
    var submits = 0;
    await _openRadar(tester, client: _client(onSubmit: () => submits += 1));
    await _reveal(tester, find.byKey(const Key('customer_region_radar_postcode')));
    await tester.enterText(
      find.byKey(const Key('customer_region_radar_postcode')),
      '9688',
    );
    await _reveal(tester, find.byKey(const Key('customer_region_radar_first_name')));
    await tester.enterText(
      find.byKey(const Key('customer_region_radar_first_name')),
      'Ada',
    );
    await tester.enterText(
      find.byKey(const Key('customer_region_radar_last_name')),
      'Lovelace',
    );
    await tester.enterText(
      find.byKey(const Key('customer_region_radar_email')),
      'ada@example.com',
    );
    await _reveal(tester, find.byKey(const Key('customer_region_radar_submit')));
    await tester.tap(find.byKey(const Key('customer_region_radar_submit')));
    await tester.pumpAndSettle();

    expect(submits, 1);
    expect(find.byKey(const Key('customer_region_radar_form_success')), findsOneWidget);
    expect(find.byKey(const Key('customer_region_radar_own_marker')), findsOneWidget);
    await tester.tap(find.byKey(const Key('customer_region_radar_submit')));
    await tester.pump();
    expect(submits, 1);
  });

  testWidgets('tablet landscape puts the map and form side by side', (
    tester,
  ) async {
    await _openRadar(tester, size: const Size(1408, 880));
    final map = tester.getRect(find.text('Waar wil je een taxi kunnen boeken?'));
    final form = tester.getRect(find.text('Laat jouw regio meetellen'));
    expect(form.left, greaterThan(map.right - 1));
    expect((form.top - map.top).abs(), lessThan(24));
  });

  test('map markers stay at one regional position and never invent 3+ dots', () {
    expect(
      regionRadarMapMarkers(
        place: _schorisse,
        snapshot: const RegionRadarSnapshot(
          country: 'BE',
          postcode: '9688',
          count: 3,
          displayCount: '3+',
        ),
        ownInThisRegion: false,
      ).map((marker) => marker.kind),
      <RegionRadarMarkerKind>[RegionRadarMarkerKind.regionGroup],
    );
    expect(
      regionRadarMapMarkers(
        place: _schorisse,
        snapshot: const RegionRadarSnapshot(
          country: 'BE',
          postcode: '9688',
          count: 0,
          displayCount: '0+',
        ),
        ownInThisRegion: false,
      ).map((marker) => marker.kind),
      <RegionRadarMarkerKind>[RegionRadarMarkerKind.selectedRegion],
    );
    expect(
      regionRadarMapMarkers(
        place: _schorisse,
        snapshot: const RegionRadarSnapshot(
          country: 'BE',
          postcode: '9688',
          count: 3,
          displayCount: '3+',
        ),
        ownInThisRegion: true,
      ).map((marker) => (marker.kind, marker.lat, marker.lon)),
      <(RegionRadarMarkerKind, double, double)>[
        (RegionRadarMarkerKind.regionGroup, 50.770, 3.656),
        (RegionRadarMarkerKind.ownInterest, 50.770, 3.656),
      ],
    );
    expect(
      regionRadarMapMarkers(
        snapshot: const RegionRadarSnapshot(
          country: 'BE',
          postcode: '9688',
          count: 3,
          displayCount: '3+',
        ),
        ownInThisRegion: true,
      ),
      isEmpty,
    );
    expect(
      regionRadarInterestedLabel(
        displayCount: '3+',
        interestedWord: 'geïnteresseerden',
      ),
      '3+ geïnteresseerden',
    );
  });

  test('server cells become separate points; 3+ still does not invent three', () {
    final markers = regionRadarMapMarkers(
      place: _schorisse,
      snapshot: const RegionRadarSnapshot(
        country: 'BE',
        postcode: '9688',
        count: 3,
        displayCount: '3+',
        approximateCells: <RegionRadarApproximateCell>[
          RegionRadarApproximateCell(
            lat: 50.770,
            lon: 3.656,
            displayCount: '2+',
            postcode: '9688',
          ),
          RegionRadarApproximateCell(
            lat: 50.810,
            lon: 3.700,
            displayCount: '1+',
            postcode: '9688',
          ),
        ],
      ),
      ownInThisRegion: false,
    );
    expect(markers, hasLength(2));
    expect(
      markers.map((marker) => marker.kind).toSet(),
      <RegionRadarMarkerKind>{RegionRadarMarkerKind.regionGroup},
    );
    expect(clusterRegionRadarMarkers(markers: markers, zoom: 11), hasLength(2));
    expect(clusterRegionRadarMarkers(markers: markers, zoom: 6), hasLength(1));
  });

  testWidgets('tapping the region group keeps the server category 3+', (
    tester,
  ) async {
    await _openRadar(tester);
    await _viewPostcode(tester, '9688');
    await _reveal(tester, find.byKey(const Key('customer_region_radar_region_marker')));
    await tester.tap(find.byKey(const Key('customer_region_radar_region_marker')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customer_region_radar_group_info')), findsOneWidget);
    expect(find.text('9688 · Schorisse'), findsWidgets);
    expect(find.byKey(const Key('customer_region_radar_group_count')), findsOneWidget);
    expect(find.text('3+ geïnteresseerden'), findsOneWidget);
    expect(find.text('Jouw interesse'), findsNothing);
    expect(find.text('Geselecteerde regio'), findsNothing);
  });

  testWidgets('a remembered own registration returns on the same region', (
    tester,
  ) async {
    await _openRadar(
      tester,
      ownInterestStore: RegionRadarOwnInterestStore.memory(<String>['BE|9688']),
    );
    await _viewPostcode(tester, '9688');
    expect(find.byKey(const Key('customer_region_radar_own_marker')), findsOneWidget);
    await _reveal(tester, find.byKey(const Key('customer_region_radar_own_marker')));
    await tester.tap(find.byKey(const Key('customer_region_radar_own_marker')));
    await tester.pumpAndSettle();
    expect(find.text('Jouw interesse'), findsWidgets);
    expect(find.textContaining('9688'), findsWidgets);
    expect(find.textContaining('Schorisse'), findsWidgets);
  });

  testWidgets('a failed submit does not show an own marker', (tester) async {
    await _openRadar(
      tester,
      client: RegionInterestClient(
        baseUrl: 'https://example.test',
        httpGet: (uri) async => http.Response(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'country': 'BE',
            'postcode': '9688',
            'count': 3,
            'display_count': '3+',
            'status': 'partners_wanted',
          }),
          200,
        ),
        httpPost: (uri, {headers, body}) async => http.Response(
          jsonEncode(<String, dynamic>{'ok': false, 'error': 'submit_failed'}),
          400,
        ),
      ),
    );
    await _viewPostcode(tester, '9688');
    await _reveal(tester, find.byKey(const Key('customer_region_radar_first_name')));
    await tester.enterText(
      find.byKey(const Key('customer_region_radar_first_name')),
      'Ada',
    );
    await tester.enterText(
      find.byKey(const Key('customer_region_radar_last_name')),
      'Lovelace',
    );
    await tester.enterText(
      find.byKey(const Key('customer_region_radar_email')),
      'ada@example.com',
    );
    await _reveal(tester, find.byKey(const Key('customer_region_radar_submit')));
    await tester.tap(find.byKey(const Key('customer_region_radar_submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customer_region_radar_form_error')), findsOneWidget);
    expect(find.byKey(const Key('customer_region_radar_own_marker')), findsNothing);
  });

  testWidgets('a postcode without interest shows the selected region only', (
    tester,
  ) async {
    await _openRadar(
      tester,
      client: _client(
        radar: <String, dynamic>{
          'ok': true,
          'country': 'BE',
          'postcode': '9688',
          'count': 0,
          'display_count': '0+',
          'status': 'partners_wanted',
        },
      ),
    );
    await _viewPostcode(tester, '9688');
    expect(find.byKey(const Key('customer_region_radar_selected_marker')), findsOneWidget);
    expect(find.text('Geselecteerde regio'), findsOneWidget);
    expect(find.byKey(const Key('customer_region_radar_region_marker')), findsNothing);
    expect(find.byKey(const Key('customer_region_radar_own_marker')), findsNothing);
    await _reveal(
      tester,
      find.byKey(const Key('customer_region_radar_selected_label')),
    );
    await tester.tap(find.byKey(const Key('customer_region_radar_selected_label')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customer_region_radar_selected_info')), findsOneWidget);
    expect(find.text('Jouw interesse'), findsNothing);
  });

  testWidgets('a filled form is not treated as a confirmed registration', (
    tester,
  ) async {
    await _openRadar(tester);
    await _reveal(tester, find.byKey(const Key('customer_region_radar_first_name')));
    await tester.enterText(
      find.byKey(const Key('customer_region_radar_first_name')),
      'Ada',
    );
    await tester.enterText(
      find.byKey(const Key('customer_region_radar_last_name')),
      'Lovelace',
    );
    await tester.enterText(
      find.byKey(const Key('customer_region_radar_email')),
      'ada@example.com',
    );
    await _viewPostcode(tester, '9688');
    expect(find.byKey(const Key('customer_region_radar_own_marker')), findsNothing);
    expect(find.byKey(const Key('customer_region_radar_region_marker')), findsOneWidget);
  });

  testWidgets('an already registered submit keeps a single own marker', (
    tester,
  ) async {
    await _openRadar(
      tester,
      client: _client(
        submit: <String, dynamic>{
          'ok': true,
          'existed': true,
          'country': 'BE',
          'postcode': '9688',
          'count': 3,
          'display_count': '3+',
          'status': 'partners_wanted',
        },
      ),
    );
    await _viewPostcode(tester, '9688');
    await _reveal(tester, find.byKey(const Key('customer_region_radar_first_name')));
    await tester.enterText(
      find.byKey(const Key('customer_region_radar_first_name')),
      'Ada',
    );
    await tester.enterText(
      find.byKey(const Key('customer_region_radar_last_name')),
      'Lovelace',
    );
    await tester.enterText(
      find.byKey(const Key('customer_region_radar_email')),
      'ada@example.com',
    );
    await _reveal(tester, find.byKey(const Key('customer_region_radar_submit')));
    await tester.tap(find.byKey(const Key('customer_region_radar_submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customer_region_radar_own_marker')), findsOneWidget);
    expect(find.text('Jouw interesse'), findsOneWidget);
    expect(find.byKey(const Key('customer_region_radar_region_marker')), findsOneWidget);
  });
}
