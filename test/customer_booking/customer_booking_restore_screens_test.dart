import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_flow.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

Widget _app(Widget child, Size size) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: RepaintBoundary(
      key: const Key('restore_capture_root'),
      child: MaterialApp(key: UniqueKey(), home: child),
    ),
  );
}

const _company = CustomerBookingCompany(
  partnerId: 'partner_demo',
  companyName: 'All-in Taxi Christophe Vanroeghem',
  vehicles: <Map<String, dynamic>>[
    <String, dynamic>{
      'vehicle_id': 'vh_premium',
      'vehicle_type': 'sedan',
      'tier': 'premium',
      'seats': 3,
    },
  ],
);

const _profile = CustomerProfile(
  customerId: 'cus_1',
  name: 'Christophe',
  phone: '+32469788891',
  email: 'c@example.com',
  preferredPostcode: '9688',
  companyName: '',
  vatNumber: '',
  billingStreet: 'Koekamerstraat 488A',
  billingPostalCode: '9688',
  billingCity: 'Maarkedal',
  createdAt: '2026-01-01',
  updatedAt: '2026-01-01',
);

CustomerBookingQuoteClient _quotes() {
  return CustomerBookingQuoteClient(
    bookingBaseUrl: 'http://127.0.0.1:8788',
    httpPost: (url, headers, body) async {
      if (url.path.endsWith('/book')) {
        return http.Response(
          jsonEncode(<String, dynamic>{'ok': true, 'bookingId': 'bk_restore_1'}),
          200,
        );
      }
      return http.Response(
        jsonEncode(<String, dynamic>{
          'ok': true,
          'price_available': true,
          'calculator_off': false,
          'request_quote_required': false,
          'price_incl_vat': 48.5,
          'total_price_incl_vat': 48.5,
          'distance_km': 14.2,
          'duration_min': 22,
          'currency': 'EUR',
          'pickup_lat': 50.79,
          'pickup_lon': 3.62,
          'dropoff_lat': 50.901,
          'dropoff_lon': 4.484,
        }),
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
            label: query,
            lat: 50.79,
            lon: 3.62,
            placeType: 'address',
          ),
        ],
      );
    },
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('restore_capture_root')),
  );
  final image = await tester.runAsync(
    () => boundary.toImage(pixelRatio: 1.25),
  );
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  final dir = Directory(
    r'C:\_flutter_work\fluxidi_customer_ops_client_p0\.qa-local\restore-20260917',
  )..createSync(recursive: true);
  File('${dir.path}${Platform.pathSeparator}$name.png').writeAsBytesSync(
    bytes!.buffer.asUint8List(),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required CustomerBookingEntryContext entry,
  CustomerProfile? profile,
}) async {
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    _app(
      CustomerBookingFlow(
        entry: entry,
        language: AppLanguage.nl,
        lookup: _lookup(),
        quoteClient: _quotes(),
        profile: profile,
      ),
      size,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture restored mobile booking screens', (tester) async {
    const phone = Size(390, 844);
    const tabletPortrait = Size(800, 1280);
    const tabletLandscape = Size(1280, 800);

    await _pump(
      tester,
      size: phone,
      profile: _profile,
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        company: _company,
        pickup: CustomerBookingPlace(
          address: 'Koekamerstraat 488A, 9688 Maarkedal',
          latitude: 50.79,
          longitude: 3.62,
        ),
        destination: CustomerBookingPlace(
          address: 'Brussels Airport, Zaventem',
          latitude: 50.901,
          longitude: 4.484,
        ),
      ),
    );
    await _capture(tester, '01_phone_taxi_quote');

    await tester.ensureVisible(find.byKey(kCustomerBookingConfirmKey));
    await tester.tap(find.byKey(kCustomerBookingConfirmKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _capture(tester, '02_phone_taxi_confirmed');

    await _pump(
      tester,
      size: phone,
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.airport,
        company: _company,
      ),
    );
    await _capture(tester, '03_phone_airport_chrome');

    await tester.tap(find.byKey(kCustomerBookingConfirmKey));
    await tester.pump();
    await _capture(tester, '04_phone_airport_missing_fields');

    await _pump(
      tester,
      size: tabletPortrait,
      profile: _profile,
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.airport,
        company: _company,
      ),
    );
    await _capture(tester, '05_tablet_portrait_airport');

    await _pump(
      tester,
      size: tabletLandscape,
      profile: _profile,
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        company: _company,
        pickup: CustomerBookingPlace(
          address: 'Koekamerstraat 488A, 9688 Maarkedal',
          latitude: 50.79,
          longitude: 3.62,
        ),
        destination: CustomerBookingPlace(
          address: 'Brussels Airport, Zaventem',
          latitude: 50.901,
          longitude: 4.484,
        ),
      ),
    );
    await _capture(tester, '06_tablet_landscape_taxi');

    expect(
      File(
        r'C:\_flutter_work\fluxidi_customer_ops_client_p0\.qa-local\restore-20260917\01_phone_taxi_quote.png',
      ).existsSync(),
      isTrue,
    );
  });
}
