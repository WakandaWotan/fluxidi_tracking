import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_customer_core/fluxidi_customer_core.dart';
import 'package:fluxidi_customer/api/ride_quote_api.dart';
import 'package:fluxidi_customer/app/customer_app_config.dart';
import 'package:fluxidi_customer/app/customer_theme.dart';
import 'package:fluxidi_customer/screens/customer_ride_prepare_screen.dart';
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

const FluxidiPartnerScope _scope = FluxidiPartnerScope(
  partnerId: 'company:t1:c1',
  tenantId: 't1',
  companyId: 'c1',
  companyName: 'Taxi Schorisse',
  sourceLabel: 'customer_partner_profile',
);

const List<Map<String, dynamic>> _profileVehicles = <Map<String, dynamic>>[
  <String, dynamic>{'vehicle_id': 'v1', 'name': 'Mercedes V-Klasse'},
  <String, dynamic>{'vehicle_id': 'v2', 'name': 'Tesla Model Y'},
];

String _quoteBody({
  num total = 35.10,
  num? exVat = 33.11,
  num? vat = 1.99,
  num distanceKm = 13.2,
  int durationMin = 17,
  bool calculatorOff = false,
  num? outbound,
  num? returnPrice,
  num? listedTotal,
}) {
  return jsonEncode(<String, dynamic>{
    'ok': true,
    if (!calculatorOff) 'price_incl_vat': total,
    if (calculatorOff) 'calculator_off': true,
    if (exVat != null) 'price_ex_vat': exVat,
    if (vat != null) 'price_vat': vat,
    'distance_km': distanceKm,
    'duration_min': durationMin,
    'currency': 'EUR',
    'pricing_source': 'route_calc',
    if (outbound != null) 'outbound_price_incl_vat': outbound,
    if (returnPrice != null) 'return_price_incl_vat': returnPrice,
    if (listedTotal != null) 'total_price_incl_vat': listedTotal,
  });
}

String _availabilityBody({
  bool v1Available = true,
  bool v2Available = false,
  int? seats = 6,
  String driverName = 'Jan',
}) {
  return jsonEncode(<String, dynamic>{
    'ok': true,
    'partner_id': 'company:t1:c1',
    'vehicles': <Map<String, dynamic>>[
      <String, dynamic>{
        'vehicle_id': 'v1',
        'available': v1Available,
        'reason': '',
        'driver_id': 'd1',
        if (driverName.isNotEmpty) 'public_display_name': driverName,
        if (seats != null) 'passenger_seats': seats,
      },
      <String, dynamic>{
        'vehicle_id': 'v2',
        'available': v2Available,
        'reason': v2Available ? '' : 'no_driver',
      },
    ],
  });
}

class _FakeRideApi {
  _FakeRideApi({
    String? quote,
    String? availability,
    this.throwOnQuote = false,
  }) : quoteBody = quote ?? _quoteBody(),
       availabilityBody = availability ?? _availabilityBody();

  String quoteBody;
  String availabilityBody;
  bool throwOnQuote;

  final List<Map<String, dynamic>> postedBodies = <Map<String, dynamic>>[];
  final List<Uri> getUris = <Uri>[];

  /// When set, a quote answer waits for this completer.
  Completer<void>? gate;

  RideQuoteApi build() => RideQuoteApi(
    baseUrl: _config.publicBookingBaseUrl,
    httpPost: (Uri url, {Map<String, String>? headers, Object? body}) async {
      postedBodies.add(
        Map<String, dynamic>.from(jsonDecode(body! as String) as Map),
      );
      final pending = gate;
      if (pending != null) await pending.future;
      if (throwOnQuote) throw http.ClientException('offline');
      return http.Response(quoteBody, 200);
    },
    httpGet: (Uri url, {Map<String, String>? headers}) async {
      getUris.add(url);
      return http.Response(availabilityBody, 200);
    },
  );
}

/// Tall viewport so the whole sheet content is built; the dedicated layout test
/// below uses real phone and tablet sizes.
Future<void> _pump(
  WidgetTester tester,
  RideQuoteApi api, {
  Size size = const Size(1000, 3200),
}) async {
  addTearDown(tester.view.reset);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildCustomerTheme(_config),
      home: CustomerRidePrepareScreen(
        api: api,
        scope: _scope,
        profileVehicles: _profileVehicles,
        config: _config,
        clock: () => DateTime(2026, 9, 22, 8, 0),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fillRide(
  WidgetTester tester, {
  String from = 'Grote Markt 12 bus 3, 9600 Ronse',
  String to = 'Markt 1, 9700 Oudenaarde',
}) async {
  await tester.enterText(find.byKey(const Key('ride_from_field')), from);
  await tester.enterText(find.byKey(const Key('ride_to_field')), to);
  await tester.pumpAndSettle();
}

Future<void> _requestPrice(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('ride_request_price')));
  await tester.pumpAndSettle();
}

Future<void> _increment(WidgetTester tester, String stepperKey) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(Key(stepperKey)),
      matching: find.byIcon(Icons.add_circle_outline),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('typing enables the price request and refreshes the summary', (
    tester,
  ) async {
    final fake = _FakeRideApi();
    await _pump(tester, fake.build());

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ride_request_price')))
          .onPressed,
      isNull,
    );
    expect(find.text('Ophaaladres nog niet ingevuld'), findsOneWidget);

    await _fillRide(tester);

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ride_request_price')))
          .onPressed,
      isNotNull,
    );
    expect(find.text('Ophaaladres nog niet ingevuld'), findsNothing);
  });

  testWidgets('the quote request carries partner, addresses and ride data', (
    tester,
  ) async {
    final fake = _FakeRideApi();
    await _pump(tester, fake.build());
    await _fillRide(tester);
    await _increment(tester, 'ride_bags');

    await _requestPrice(tester);

    expect(fake.postedBodies, hasLength(1));
    final body = fake.postedBodies.single;
    // Partner routing, not a company login.
    expect(body['public_partner_id'], 'company:t1:c1');
    expect(body['partner_id'], 'company:t1:c1');
    expect(body['tenant_id'], 't1');
    expect(body['company_id'], 'c1');
    expect(body['entry_kind'], 'taxi');
    // House number and addition survive.
    expect(body['from'], 'Grote Markt 12 bus 3, 9600 Ronse');
    expect(body['to'], 'Markt 1, 9700 Oudenaarde');
    // Now ride: when_now plus a derived date and time, no stale pickup.
    expect(body['when_now'], isTrue);
    expect(body['date'], isNotNull);
    expect(body['time'], isNotNull);
    expect(body['passengers'], 2);
    expect(body['bags'], 1);
    expect(body['return_enabled'], isFalse);

    // Availability is asked for the same partner and passenger count.
    expect(fake.getUris, hasLength(1));
    expect(fake.getUris.single.path, '/partners/availability');
    expect(
      fake.getUris.single.queryParameters['partner_id'],
      'company:t1:c1',
    );
    expect(fake.getUris.single.queryParameters['pax'], '2');
    expect(fake.getUris.single.queryParameters['duration_min'], '17');
  });

  testWidgets('a later pickup is sent as a UTC pickup_iso', (tester) async {
    final fake = _FakeRideApi();
    await _pump(tester, fake.build());
    await _fillRide(tester);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ride_pick_pickup')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); // date picker
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); // time picker
    await tester.pumpAndSettle();

    await _requestPrice(tester);

    final body = fake.postedBodies.single;
    expect(body.containsKey('when_now'), isFalse);
    expect(body['pickup_iso'], isA<String>());
    expect((body['pickup_iso'] as String).endsWith('Z'), isTrue);
    expect(body['date'], isNotNull);
    expect(body['time'], isNotNull);
  });

  testWidgets('a return ride sends the return leg fields', (tester) async {
    final fake = _FakeRideApi(
      quote: _quoteBody(outbound: 30, returnPrice: 28, listedTotal: 58),
    );
    await _pump(tester, fake.build());
    await _fillRide(tester);

    await tester.tap(find.byKey(const Key('ride_return_toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ride_pick_return')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await _requestPrice(tester);

    final body = fake.postedBodies.single;
    expect(body['return_enabled'], isTrue);
    expect(body['return_pickup_iso'], isA<String>());
    expect(body['return_from'], 'Markt 1, 9700 Oudenaarde');
    expect(body['return_to'], 'Grote Markt 12 bus 3, 9600 Ronse');
    expect(body['return_date'], isNotNull);
    expect(body['return_time'], isNotNull);

    expect(find.byKey(const Key('ride_price_return_legs')), findsOneWidget);
    expect(find.textContaining('Heenrit'), findsOneWidget);
    expect(find.textContaining('Terugrit'), findsWidgets);
  });

  testWidgets('the server price, vat split and metrics are shown as sent', (
    tester,
  ) async {
    final fake = _FakeRideApi();
    await _pump(tester, fake.build());
    await _fillRide(tester);
    await _requestPrice(tester);

    expect(find.byKey(const Key('ride_price_quoted')), findsOneWidget);
    expect(find.text('€35,10'), findsOneWidget);
    expect(find.byKey(const Key('ride_price_vat_split')), findsOneWidget);
    expect(find.text('13.2 km · 17 min'), findsOneWidget);
    // A quote is never a booking.
    expect(find.byKey(const Key('ride_not_a_booking')), findsOneWidget);
    expect(find.textContaining('boekingsnummer'), findsNothing);
    expect(find.textContaining('Betalen'), findsNothing);
  });

  testWidgets('vehicle offers use server availability and capacity only', (
    tester,
  ) async {
    final fake = _FakeRideApi(availability: _availabilityBody(seats: 1));
    await _pump(tester, fake.build());
    await _fillRide(tester);
    await _requestPrice(tester);

    expect(find.byKey(const Key('ride_offer_v1')), findsOneWidget);
    expect(find.byKey(const Key('ride_offer_v2')), findsOneWidget);
    expect(find.text('Mercedes V-Klasse'), findsOneWidget);
    // Driver name only because the server published one.
    expect(find.textContaining('Jan'), findsOneWidget);
    // Unavailable vehicle keeps the server reason.
    expect(find.textContaining('no_driver'), findsOneWidget);
    // One seat for two passengers is flagged, never silently accepted.
    expect(find.byKey(const Key('ride_offer_too_small_v1')), findsOneWidget);
  });

  testWidgets('no available vehicle is a clear no-offer state', (tester) async {
    final fake = _FakeRideApi(
      availability: _availabilityBody(v1Available: false, v2Available: false),
    );
    await _pump(tester, fake.build());
    await _fillRide(tester);
    await _requestPrice(tester);

    expect(find.byKey(const Key('ride_price_no_offer')), findsOneWidget);
    expect(find.text('Geen aanbod voor deze rit'), findsOneWidget);
    expect(find.byKey(const Key('ride_price_quoted')), findsNothing);
  });

  testWidgets('calculator_off is shown as no automatic price', (tester) async {
    final fake = _FakeRideApi(quote: _quoteBody(calculatorOff: true));
    await _pump(tester, fake.build());
    await _fillRide(tester);
    await _requestPrice(tester);

    expect(find.byKey(const Key('ride_price_no_offer')), findsOneWidget);
    expect(
      find.textContaining('rekent prijzen niet automatisch'),
      findsOneWidget,
    );
  });

  testWidgets('a network failure offers retry and then succeeds', (
    tester,
  ) async {
    final fake = _FakeRideApi(throwOnQuote: true);
    await _pump(tester, fake.build());
    await _fillRide(tester);
    await _requestPrice(tester);

    expect(find.byKey(const Key('ride_price_failed')), findsOneWidget);

    fake.throwOnQuote = false;
    await tester.tap(find.byKey(const Key('ride_price_retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ride_price_quoted')), findsOneWidget);
  });

  testWidgets('an incomplete address cannot request a price', (tester) async {
    final fake = _FakeRideApi();
    await _pump(tester, fake.build());
    await _fillRide(tester, from: 'Markt', to: 'Oud');

    expect(find.byKey(const Key('ride_price_incomplete')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ride_request_price')))
          .onPressed,
      isNull,
    );
    expect(fake.postedBodies, isEmpty);
  });

  testWidgets('changing a ride input invalidates the previous price', (
    tester,
  ) async {
    final fake = _FakeRideApi();
    await _pump(tester, fake.build());
    await _fillRide(tester);
    await _requestPrice(tester);
    expect(find.byKey(const Key('ride_price_quoted')), findsOneWidget);

    await _increment(tester, 'ride_passengers');

    expect(find.byKey(const Key('ride_price_quoted')), findsNothing);
    expect(find.text('€35,10'), findsNothing);
    expect(find.byKey(const Key('ride_price_incomplete')), findsOneWidget);
  });

  testWidgets('a late answer never overwrites a newer request', (tester) async {
    final fake = _FakeRideApi();
    final api = fake.build();
    await _pump(tester, api);
    await _fillRide(tester);

    // First request is held open.
    final firstGate = Completer<void>();
    fake.gate = firstGate;
    await tester.tap(find.byKey(const Key('ride_request_price')));
    await tester.pump();

    // The customer changes the ride and asks again; this one answers first.
    fake.gate = null;
    fake.quoteBody = _quoteBody(total: 48.40, exVat: null, vat: null);
    await _increment(tester, 'ride_passengers');
    await _requestPrice(tester);
    expect(find.text('€48,40'), findsOneWidget);

    // Now the stale first answer arrives.
    fake.quoteBody = _quoteBody();
    firstGate.complete();
    await tester.pumpAndSettle();

    expect(find.text('€48,40'), findsOneWidget);
    expect(find.text('€35,10'), findsNothing);
  });

  testWidgets('a total that disagrees with its legs is flagged, not shown', (
    tester,
  ) async {
    final fake = _FakeRideApi(
      quote: _quoteBody(outbound: 200, returnPrice: 200, listedTotal: 401),
    );
    await _pump(tester, fake.build());
    await _fillRide(tester);
    await _requestPrice(tester);

    expect(find.byKey(const Key('ride_price_total_drift')), findsOneWidget);
    expect(find.byKey(const Key('ride_price_total')), findsNothing);
  });

  testWidgets('ride data survives returning from the date picker', (
    tester,
  ) async {
    final fake = _FakeRideApi();
    await _pump(tester, fake.build());
    await _fillRide(tester);
    await _increment(tester, 'ride_passengers');

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ride_pick_pickup')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('ride_from_field')))
          .controller
          ?.text,
      'Grote Markt 12 bus 3, 9600 Ronse',
    );
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('the map and sheet shell renders on phone and tablet sizes', (
    tester,
  ) async {
    const sizes = <String, Size>{
      'phone portrait': Size(390, 844),
      'phone landscape': Size(844, 390),
      'tablet portrait': Size(800, 1280),
      'tablet landscape': Size(1280, 800),
    };

    for (final entry in sizes.entries) {
      final fake = _FakeRideApi();
      await _pump(tester, fake.build(), size: entry.value);

      expect(
        tester.takeException(),
        isNull,
        reason: 'overflowed on ${entry.key}',
      );
      expect(
        find.byKey(const Key('ride_map_not_connected')),
        findsOneWidget,
        reason: 'map surface missing on ${entry.key}',
      );
      expect(
        find.byType(DraggableScrollableSheet),
        findsOneWidget,
        reason: 'sheet missing on ${entry.key}',
      );
    }
  });
}
