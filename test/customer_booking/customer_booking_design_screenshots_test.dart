import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_flow.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_current_location.dart';
import 'package:http/http.dart' as http;

const _shotKey = Key('customer_booking_design_shot');

CustomerBookingQuoteClient _quotes() {
  return CustomerBookingQuoteClient(
    bookingBaseUrl: 'http://127.0.0.1:8788',
    httpPost: (url, headers, body) async {
      return http.Response(
        '{"ok":true,"price_available":true,"price_incl_vat":48.5,'
        '"total_price_incl_vat":48.5,"price_ex_vat":40.08,'
        '"distance_km":14.2,"duration_min":22,"currency":"EUR",'
        '"pickup_lat":50.85,"pickup_lon":4.35,'
        '"dropoff_lat":50.90,"dropoff_lon":4.48}',
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
            label: query.trim().isEmpty ? 'A Straat 1, Brussel' : query,
            lat: 50.85,
            lon: 4.35,
            placeType: 'address',
          ),
        ],
      );
    },
    reverseOverride: (lat, lon, language) async {
      return const LimousinePlaceLookupResult(
        suggestions: [
          LimousinePlaceSuggestion(
            label: 'A Straat 1, Brussel',
            lat: 50.85,
            lon: 4.35,
            placeType: 'address',
          ),
        ],
      );
    },
  );
}

Future<void> _pumpShot(
  WidgetTester tester, {
  required Size size,
  required CustomerBookingEntryContext entry,
  ThemeData? theme,
}) async {
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        theme: theme ?? ThemeData(useMaterial3: true),
        home: RepaintBoundary(
          key: _shotKey,
          child: CustomerBookingFlow(
            entry: entry,
            lookup: _lookup(),
            locationPlatform: LimousineCurrentLocationPlatform(
              isLocationServiceEnabled: () async => false,
            ),
            quoteClient: _quotes(),
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
  final dir = Directory('build/customer_booking_screenshots');
  dir.createSync(recursive: true);
  File('${dir.path}/$name.png').writeAsBytesSync(bytes!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('write phone compact, phone expanded and tablet shots', (
    tester,
  ) async {
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
          },
        ],
      ),
      pickup: CustomerBookingPlace(
        address: 'A Straat 1, Brussel',
        latitude: 50.85,
        longitude: 4.35,
      ),
      destination: CustomerBookingPlace(
        address: 'B Straat 2, Gent',
        latitude: 51.05,
        longitude: 3.72,
      ),
    );
    await _pumpShot(
      tester,
      size: const Size(390, 844),
      entry: taxi,
    );
    expect(find.byKey(kCustomerBookingSheetKey), findsOneWidget);
    await _writeShot(tester, 'phone_compact');

    await tester.tap(find.byKey(kCustomerBookingSheetToggleKey));
    await tester.pumpAndSettle();
    await _writeShot(tester, 'phone_expanded');

    await _pumpShot(
      tester,
      size: const Size(1280, 800),
      entry: const CustomerBookingEntryContext(
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
            },
          ],
        ),
        pickup: CustomerBookingPlace(
          address: 'A Straat 1, Brussel',
          latitude: 50.85,
          longitude: 4.35,
        ),
      ),
    );
    expect(find.byKey(kCustomerBookingWideSplitKey), findsOneWidget);
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
    await _writeShot(tester, 'tablet_airport');

    await _pumpShot(
      tester,
      size: const Size(390, 844),
      entry: taxi,
      theme: ThemeData.dark(useMaterial3: true),
    );
    await _writeShot(tester, 'phone_compact_dark');
  });
}
