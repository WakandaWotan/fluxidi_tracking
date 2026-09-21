import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_customer_core/fluxidi_customer_core.dart';
import 'package:fluxidi_customer/api/ride_quote_api.dart';
import 'package:fluxidi_customer/app/customer_app_config.dart';
import 'package:fluxidi_customer/app/customer_theme.dart';
import 'package:fluxidi_customer/screens/customer_ride_prepare_screen.dart';
import 'package:fluxidi_customer/widgets/customer_route_map.dart';
import 'package:http/http.dart' as http;

const CustomerBrandColors _brand = CustomerBrandColors(
  primary: Color(0xFFFFD400),
  accent: Color(0xFFFFD54F),
  background: Color(0xFF07080B),
  surface: Color(0xFF121318),
  card: Color(0xFF171922),
  textSoft: Color(0xFFB8BDC9),
);

const CustomerAppConfig _config = CustomerAppConfig(
  appName: 'Fluxidi Customer Dev',
  environmentLabel: 'DEV',
  androidApplicationId: 'com.fluxidi.customer.dev',
  deepLinkScheme: 'fluxidicustomerdev',
  deepLinkHost: 'pay',
  deepLinkPath: '/return',
  variant: CustomerAppVariant.fluxidiMarketplace,
  brand: _brand,
  publicBookingBaseUrl: 'https://example.invalid',
  mapboxToken: 'pk.test-token',
);

const FluxidiPartnerScope _scope = FluxidiPartnerScope(
  partnerId: 'company:t1:c1',
  tenantId: 't1',
  companyId: 'c1',
  companyName: 'Taxi Schorisse',
);

const FluxidiLonLat _ronse = FluxidiLonLat(3.6003, 50.7452);
const FluxidiLonLat _oudenaarde = FluxidiLonLat(3.6089, 50.8492);

/// Two Mapbox answers: one geocoding hit per field, then one route.
class _FakeMapbox {
  _FakeMapbox();

  final List<Uri> geocodeUris = <Uri>[];
  final List<Uri> routeUris = <Uri>[];

  FluxidiAddressSearchClient get search => FluxidiAddressSearchClient(
    token: 'pk.test-token',
    httpGet: (Uri url) async {
      geocodeUris.add(url);
      final wantsDestination = url.path.contains('Oudenaarde');
      return http.Response(
        jsonEncode(<String, dynamic>{
          'features': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': wantsDestination ? 'address.2' : 'address.1',
              'place_name': wantsDestination
                  ? 'Markt 1, 9700 Oudenaarde, België'
                  : 'Grote Markt 12 bus 3, 9600 Ronse, België',
              'place_type': <String>['address'],
              'center': <double>[
                wantsDestination ? _oudenaarde.lon : _ronse.lon,
                wantsDestination ? _oudenaarde.lat : _ronse.lat,
              ],
            },
          ],
        }),
        200,
      );
    },
  );

  FluxidiRouteGeometryClient get route => FluxidiRouteGeometryClient(
    token: 'pk.test-token',
    httpGet: (Uri url) async {
      routeUris.add(url);
      return http.Response(
        jsonEncode(<String, dynamic>{
          'routes': <Map<String, dynamic>>[
            <String, dynamic>{
              'distance': 13200,
              'duration': 1020,
              'geometry': <String, dynamic>{
                'coordinates': <List<double>>[
                  <double>[_ronse.lon, _ronse.lat],
                  <double>[3.6020, 50.7700],
                  <double>[3.6055, 50.8100],
                  <double>[_oudenaarde.lon, _oudenaarde.lat],
                ],
              },
            },
          ],
        }),
        200,
      );
    },
  );
}

RideQuoteApi _stubQuoteApi() => RideQuoteApi(
  baseUrl: _config.publicBookingBaseUrl,
  httpPost: (Uri url, {Map<String, String>? headers, Object? body}) async =>
      http.Response('{"ok":true,"price_incl_vat":29.8}', 200),
  httpGet: (Uri url, {Map<String, String>? headers}) async =>
      http.Response('{"ok":true,"vehicles":[]}', 200),
);

void main() {
  group('camera', () {
    test('fits both endpoints inside the visible area', () {
      const size = Size(800, 1200);
      final camera = customerFitCamera(
        points: <FluxidiLonLat>[_ronse, _oudenaarde],
        size: size,
        contentInsets: const EdgeInsets.only(bottom: 600),
      );

      final pickup = customerProject(_ronse, camera, size);
      final dropoff = customerProject(_oudenaarde, camera, size);

      for (final point in <Offset>[pickup, dropoff]) {
        expect(point.dx, greaterThanOrEqualTo(0));
        expect(point.dx, lessThanOrEqualTo(size.width));
        expect(point.dy, greaterThanOrEqualTo(0));
        // Both must stay above the sheet, in the part of the map still visible.
        expect(point.dy, lessThanOrEqualTo(size.height - 600));
      }
      expect(camera.zoom, greaterThan(kCustomerMapMinZoom));
      expect(camera.zoom, lessThanOrEqualTo(kCustomerMapMaxZoom));
    });

    test('a single point still yields a usable zoom', () {
      final camera = customerFitCamera(
        points: <FluxidiLonLat>[_ronse],
        size: const Size(400, 800),
      );

      expect(camera.zoom, greaterThanOrEqualTo(kCustomerMapMinZoom));
      expect(camera.center.lat, closeTo(_ronse.lat, 0.5));
    });
  });

  testWidgets('the map draws tiles, both markers and the real route', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1200);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCustomerTheme(_config),
        home: CustomerRouteMap(
          token: 'pk.test-token',
          pickup: _ronse,
          dropoff: _oudenaarde,
          route: const <FluxidiLonLat>[
            _ronse,
            FluxidiLonLat(3.6020, 50.7700),
            _oudenaarde,
          ],
          contentInsets: const EdgeInsets.only(bottom: 600),
          config: _config,
        ),
      ),
    );
    await tester.pump();

    // Raster tiles are requested from the Mapbox styles endpoint.
    final tiles = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(tiles, isNotEmpty);
    final urls = tiles
        .map((image) => (image.image as NetworkImage).url)
        .toList();
    expect(
      urls.every(
        (url) =>
            url.startsWith(
              'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/',
            ) &&
            url.contains('access_token='),
      ),
      isTrue,
    );

    // Route line and markers are painted, not faked with text.
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('an empty token shows no tiles at all', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CustomerRouteMap(
          token: '',
          pickup: _ronse,
          dropoff: _oudenaarde,
          route: <FluxidiLonLat>[],
          contentInsets: EdgeInsets.zero,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
  });

  testWidgets('picking suggestions gives coordinates and a real route line', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 3200);

    final mapbox = _FakeMapbox();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCustomerTheme(_config),
        home: CustomerRidePrepareScreen(
          api: _stubQuoteApi(),
          scope: _scope,
          config: _config,
          clock: () => DateTime(2026, 9, 22, 8, 0),
          addressSearch: mapbox.search,
          routeGeometry: mapbox.route,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The map surface is present because a token is configured.
    expect(find.byKey(const Key('ride_map_surface')), findsOneWidget);
    expect(find.byKey(const Key('ride_map_not_connected')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('ride_from_field')),
      'Grote Markt 12 bus 3, 9600 Ronse',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ride_address_suggestions')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ride_suggestion_address.1')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('ride_to_field')),
      'Markt 1, 9700 Oudenaarde',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ride_suggestion_address.2')));
    await tester.pumpAndSettle();

    // Geocoding ran for both fields and the route was fetched once.
    expect(mapbox.geocodeUris.length, greaterThanOrEqualTo(2));
    expect(mapbox.routeUris, hasLength(1));
    expect(
      mapbox.routeUris.single.toString(),
      contains('directions/v5/mapbox/driving/'),
    );
    expect(mapbox.routeUris.single.toString(), contains('geometries=geojson'));

    // The picked labels keep their house number and addition.
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('ride_from_field')))
          .controller
          ?.text,
      'Grote Markt 12 bus 3, 9600 Ronse, België',
    );

    final map = tester.widget<CustomerRouteMap>(
      find.byType(CustomerRouteMap),
    );
    expect(map.pickup, isNotNull);
    expect(map.dropoff, isNotNull);
    expect(map.route.length, 4);
    expect(map.contentInsets.bottom, greaterThan(0));
  });

  testWidgets('without a token the screen says the map is unavailable', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 3200);

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerRidePrepareScreen(
          api: _stubQuoteApi(),
          scope: _scope,
          config: const CustomerAppConfig(
            appName: 'Fluxidi Customer Dev',
            environmentLabel: 'DEV',
            androidApplicationId: 'com.fluxidi.customer.dev',
            deepLinkScheme: 'fluxidicustomerdev',
            deepLinkHost: 'pay',
            deepLinkPath: '/return',
            variant: CustomerAppVariant.fluxidiMarketplace,
            brand: _brand,
            publicBookingBaseUrl: 'https://example.invalid',
            mapboxToken: '',
          ),
          clock: () => DateTime(2026, 9, 22, 8, 0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ride_map_not_connected')), findsOneWidget);
    expect(find.byKey(const Key('ride_map_surface')), findsNothing);
    expect(find.byKey(const Key('ride_lookup_unavailable')), findsOneWidget);
  });
}
