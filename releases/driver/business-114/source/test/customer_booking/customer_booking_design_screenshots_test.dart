import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_flow.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_route_geometry.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_current_location.dart';
import 'package:http/http.dart' as http;

const _shotKey = Key('customer_booking_design_shot');

CustomerBookingQuoteClient _quotes() {
  return CustomerBookingQuoteClient(
    bookingBaseUrl: 'http://127.0.0.1:8788',
    httpPost: (url, headers, body) async {
      return http.Response(
        '{"ok":true,"price_available":true,"price_incl_vat":80.6,'
        '"total_price_incl_vat":80.6,"price_ex_vat":66.61,'
        '"distance_km":40.6,"duration_min":41,"currency":"EUR",'
        '"pickup_lat":50.80,"pickup_lon":3.63,'
        '"dropoff_lat":51.05,"dropoff_lon":3.72}',
        200,
      );
    },
  );
}

CustomerBookingRouteGeometryClient _geometry() {
  return CustomerBookingRouteGeometryClient(
    token: 'test-token',
    httpGet: (uri) async {
      return http.Response(
        '{"routes":[{"distance":40600,"duration":2460,"geometry":{"coordinates":'
        '[[3.63,50.80],[3.66,50.85],[3.69,50.92],[3.72,51.05]]}}]}',
        200,
      );
    },
  );
}

LimousinePlaceLookup _lookup() {
  return LimousinePlaceLookup(
    searchOverride: (query, language) async {
      return LimousinePlaceLookupResult(
        suggestions: [
          LimousinePlaceSuggestion(
            label: query.trim().isEmpty
                ? 'Koekamerstraat 48A, Schorisse'
                : query,
            lat: 50.80,
            lon: 3.63,
            placeType: 'address',
          ),
        ],
      );
    },
    reverseOverride: (lat, lon, language) async {
      return const LimousinePlaceLookupResult(
        suggestions: [
          LimousinePlaceSuggestion(
            label: 'Koekamerstraat 48A, Schorisse',
            lat: 50.80,
            lon: 3.63,
            placeType: 'address',
          ),
        ],
      );
    },
  );
}

const taxi = CustomerBookingEntryContext(
  kind: CustomerBookingKind.taxi,
  company: CustomerBookingCompany(
    partnerId: 'partner_demo',
    companyName: 'Fluxidi',
    vehicles: <Map<String, dynamic>>[
      <String, dynamic>{
        'vehicle_id': 'vh_tesla',
        'name': 'Hoofdwagen',
        'vehicle_type': 'sedan',
        'passenger_capacity': 3,
        'assigned_driver': <String, dynamic>{
          'driver_id': 'drv_chris',
          'first_name': 'Christophe',
        },
      },
    ],
  ),
  pickup: CustomerBookingPlace(
    address: 'Koekamerstraat 48A, Schorisse',
    latitude: 50.80,
    longitude: 3.63,
  ),
  destination: CustomerBookingPlace(
    address: 'Gent',
    latitude: 51.05,
    longitude: 3.72,
  ),
);

const airport = CustomerBookingEntryContext(
  kind: CustomerBookingKind.airport,
  company: CustomerBookingCompany(
    partnerId: 'partner_demo',
    companyName: 'Fluxidi',
    vehicles: <Map<String, dynamic>>[
      <String, dynamic>{
        'vehicle_id': 'vh_tesla',
        'name': 'Hoofdwagen',
        'vehicle_type': 'sedan',
        'passenger_capacity': 3,
        'assigned_driver': <String, dynamic>{
          'driver_id': 'drv_chris',
          'first_name': 'Christophe',
        },
      },
    ],
  ),
  pickup: CustomerBookingPlace(
    address: 'Koekamerstraat 48A, Schorisse',
    latitude: 50.80,
    longitude: 3.63,
  ),
);

Future<void> _pumpShot(
  WidgetTester tester, {
  required Size size,
  required CustomerBookingEntryContext entry,
  ThemeData? theme,
  double textScale = 1,
  double keyboard = 0,
  CustomerThemeVariant? variant,
}) async {
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  if (variant != null) {
    customerThemeNotifier.value = variant;
  } else {
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  }
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
        viewInsets: EdgeInsets.only(bottom: keyboard),
      ),
      child: MaterialApp(
        theme: theme ?? ThemeData(useMaterial3: true),
        home: RepaintBoundary(
          key: _shotKey,
          child: CustomerBookingFlow(
            key: ValueKey<String>(
              '${entry.kind.name}-${size.width}x${size.height}-'
              '${variant ?? 'light'}-$textScale-$keyboard',
            ),
            entry: entry,
            lookup: _lookup(),
            locationPlatform: LimousineCurrentLocationPlatform(
              isLocationServiceEnabled: () async => false,
            ),
            quoteClient: _quotes(),
            routeGeometryClient: _geometry(),
            profileGet: (uri) async {
              if (uri.path.contains('availability')) {
                return http.Response(
                  '{"ok":true,"vehicles":[{"vehicle_id":"vh_tesla","available":true}]}',
                  200,
                );
              }
              return http.Response('skipped', 404);
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _writeShot(WidgetTester tester, String name) async {
  await tester.pump();
  final boundary =
      tester.renderObject(find.byKey(_shotKey)) as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.25);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  expect(bytes, isNotNull);
  final dir = Directory('test_reports/customer_booking_flow_20260918');
  dir.createSync(recursive: true);
  File('${dir.path}/$name.png').writeAsBytesSync(bytes!);
}

Future<void> _expandFully(WidgetTester tester) async {
  final handle = find.byKey(kCustomerBookingSheetHandleKey);
  if (handle.evaluate().isEmpty) return;
  final viewH = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  for (var i = 0; i < 5; i++) {
    final sheet = tester.getRect(find.byKey(kCustomerBookingSheetKey));
    if (sheet.height >= viewH * 0.82) {
      return;
    }
    await tester.drag(handle, Offset(0, -(viewH * 0.28)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _setHalf(WidgetTester tester) async {
  final handle = find.byKey(kCustomerBookingSheetHandleKey);
  if (handle.evaluate().isEmpty) return;
  await tester.drag(handle, const Offset(0, 80));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('write phone and tablet shots plus route animation frames', (
    tester,
  ) async {
    await _pumpShot(tester, size: const Size(390, 844), entry: taxi);
    expect(find.byKey(kCustomerBookingSheetKey), findsOneWidget);
    await _writeShot(tester, '01_phone_portrait_compact');

    await _setHalf(tester);
    await _writeShot(tester, '02_phone_portrait_half');

    await _expandFully(tester);
    await _writeShot(tester, '03_phone_portrait_expanded');

    await tester.pump(const Duration(milliseconds: 300));
    await _writeShot(tester, '10_route_draw_300ms');
    await tester.pump(const Duration(milliseconds: 300));
    await _writeShot(tester, '11_route_draw_600ms');
    await tester.pump(const Duration(milliseconds: 300));
    await _writeShot(tester, '12_route_draw_900ms');

    await _pumpShot(tester, size: const Size(844, 390), entry: taxi);
    await _writeShot(tester, '04_phone_landscape_compact');
    if (find.byKey(kCustomerBookingSheetHandleKey).evaluate().isNotEmpty) {
      await _setHalf(tester);
      await _writeShot(tester, '08_phone_landscape_half');
    }

    await _pumpShot(tester, size: const Size(800, 1280), entry: airport);
    expect(find.byKey(kCustomerBookingWideSplitKey), findsNothing);
    expect(find.byKey(kCustomerBookingMapSheetShellKey), findsOneWidget);
    final crl = find.byKey(customerBookingAirportCardKey('CRL'));
    final formScroll = find.descendant(
      of: find.byKey(kCustomerBookingFormKey),
      matching: find.byType(Scrollable),
    );
    if (formScroll.evaluate().isNotEmpty && crl.evaluate().isNotEmpty) {
      await tester.scrollUntilVisible(crl, 240, scrollable: formScroll.first);
    }
    if (crl.evaluate().isNotEmpty) {
      await tester.tap(crl);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
    await _writeShot(tester, '05_tablet_portrait_airport');

    await _pumpShot(tester, size: const Size(1280, 800), entry: airport);
    final crlWide = find.byKey(customerBookingAirportCardKey('CRL'));
    final formScrollWide = find.descendant(
      of: find.byKey(kCustomerBookingFormKey),
      matching: find.byType(Scrollable),
    );
    if (formScrollWide.evaluate().isNotEmpty && crlWide.evaluate().isNotEmpty) {
      await tester.scrollUntilVisible(
        crlWide,
        240,
        scrollable: formScrollWide.first,
      );
    }
    if (crlWide.evaluate().isNotEmpty) {
      await tester.tap(crlWide);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
    await _writeShot(tester, '06_tablet_landscape_airport');

    await _pumpShot(tester, size: const Size(390, 844), entry: airport);
    final crlPhone = find.byKey(customerBookingAirportCardKey('CRL'));
    if (crlPhone.evaluate().isNotEmpty) {
      await tester.tap(crlPhone);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
    await _writeShot(tester, '07_phone_portrait_airport');
    await _expandFully(tester);
    await _writeShot(tester, '09_phone_portrait_airport_expanded');

    await _pumpShot(
      tester,
      size: const Size(390, 844),
      entry: taxi,
      variant: CustomerThemeVariant.nightGold,
    );
    await _writeShot(tester, '14_phone_dark_compact');
    await _expandFully(tester);
    await _writeShot(tester, '15_phone_dark_expanded');

    await _pumpShot(
      tester,
      size: const Size(390, 844),
      entry: taxi,
      textScale: 1.3,
    );
    await _writeShot(tester, '16_phone_large_text');

    await _pumpShot(
      tester,
      size: const Size(390, 844),
      entry: taxi,
      keyboard: 280,
    );
    await _writeShot(tester, '17_phone_keyboard');
  });
}
