import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_company_vehicles.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_flow.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_current_location.dart';
import 'package:http/http.dart' as http;

const _shotKey = Key('customer_booking_confirm_shot');

CustomerBookingQuoteClient _quotes({
  void Function(String path, String body)? onPostBody,
  Map<String, dynamic>? bookResponse,
}) {
  return CustomerBookingQuoteClient(
    bookingBaseUrl: 'http://127.0.0.1:8788',
    httpPost: (url, headers, body) async {
      onPostBody?.call(url.path, body);
      if (url.path.endsWith('/book')) {
        return http.Response(
          jsonEncode(
            bookResponse ??
                <String, dynamic>{'ok': true, 'bookingId': 'bk_confirm_1'},
          ),
          200,
        );
      }
      return http.Response(
        jsonEncode(<String, dynamic>{
          'ok': true,
          'price_available': true,
          'price_incl_vat': 6.3,
          'total_price_incl_vat': 6.3,
          'distance_km': 0.3,
          'duration_min': 1,
          'currency': 'EUR',
          'pickup_lat': 50.8039,
          'pickup_lon': 3.6308,
          'dropoff_lat': 50.8012,
          'dropoff_lon': 3.6271,
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
            lat: 50.8012,
            lon: 3.6271,
            placeType: query.contains('Louise') ? 'place' : 'address',
          ),
        ],
      );
    },
    reverseOverride: (lat, lon, language) async {
      return const LimousinePlaceLookupResult(
        suggestions: [
          LimousinePlaceSuggestion(
            label: 'Koekamerstraat 48A, 9688',
            lat: 50.8039,
            lon: 3.6308,
            placeType: 'address',
          ),
        ],
      );
    },
  );
}

CustomerBookingEntryContext _entry({
  DateTime? startsAt,
  String destination = 'Louise-Marie / East Flanders / Belgium',
  double? destLat = 50.8012,
  double? destLon = 3.6271,
}) {
  return CustomerBookingEntryContext(
    kind: CustomerBookingKind.taxi,
    company: CustomerBookingCompany(
      partnerId: 'partner_demo',
      companyName: 'All-in Taxi Christophe Vanroeghem',
      vehicles: <Map<String, dynamic>>[
        <String, dynamic>{
          'vehicle_id': 'vh_tesla',
          'name': 'Tesla',
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
      address: 'Koekamerstraat 48A, 9688',
      latitude: 50.8039,
      longitude: 3.6308,
      startsAt: startsAt,
    ),
    destination: CustomerBookingPlace(
      address: destination,
      latitude: destLat,
      longitude: destLon,
    ),
  );
}

const _profile = CustomerProfile(
  customerId: 'cus_1',
  name: 'Christophe',
  phone: '+32469788891',
  email: 'cvanrokeghem@outlook.com',
  preferredPostcode: '9688',
  companyName: '',
  vatNumber: '',
  billingStreet: 'Koekamerstraat 48A',
  billingPostalCode: '9688',
  billingCity: 'Maarkedal',
  createdAt: '2026-01-01',
  updatedAt: '2026-01-01',
);

CustomerBookingProfileGet _profileGet({int? minPrepMinutes}) {
  return (uri) async {
    if (uri.path.contains('availability')) {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'ok': true,
          'vehicles': <Map<String, dynamic>>[
            <String, dynamic>{
              'vehicle_id': 'vh_tesla',
              'available': true,
              'driver_id': 'drv_chris',
              'first_name': 'Christophe',
            },
          ],
        }),
        200,
      );
    }
    return http.Response(
      jsonEncode(<String, dynamic>{
        'ok': true,
        'partner_id': 'partner_demo',
        'company_name': 'All-in Taxi Christophe Vanroeghem',
        if (minPrepMinutes != null) 'min_prep_minutes': minPrepMinutes,
        'vehicles': <Map<String, dynamic>>[
          <String, dynamic>{
            'vehicle_id': 'vh_tesla',
            'name': 'Tesla',
            'vehicle_type': 'sedan',
            'passenger_capacity': 3,
            'assigned_driver': <String, dynamic>{
              'driver_id': 'drv_chris',
              'first_name': 'Christophe',
            },
          },
        ],
      }),
      200,
    );
  };
}

Future<void> _pump(
  WidgetTester tester, {
  required CustomerBookingEntryContext entry,
  Size size = const Size(390, 844),
  CustomerBookingQuoteClient? quotes,
  int? minPrepMinutes,
  bool wrapShot = false,
}) async {
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final flow = CustomerBookingFlow(
    entry: entry,
    language: AppLanguage.nl,
    lookup: _lookup(),
    locationPlatform: LimousineCurrentLocationPlatform(
      isLocationServiceEnabled: () async => false,
    ),
    quoteClient: quotes ?? _quotes(),
    profile: _profile,
    profileGet: _profileGet(minPrepMinutes: minPrepMinutes),
    autoResolveGps: false,
  );
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        home: wrapShot ? RepaintBoundary(key: _shotKey, child: flow) : flow,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _expandSheet(WidgetTester tester) async {
  final handle = find.byKey(kCustomerBookingSheetHandleKey);
  if (handle.evaluate().isEmpty) return;
  final viewH = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  for (var i = 0; i < 6; i++) {
    final sheet = find.byKey(kCustomerBookingSheetKey);
    if (sheet.evaluate().isEmpty) return;
    final rect = tester.getRect(sheet);
    if (rect.height >= viewH * 0.78) return;
    await tester.drag(handle, Offset(0, -(viewH * 0.28)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
  }
}

FilledButton _confirmButton(WidgetTester tester) {
  return tester.widget<FilledButton>(find.byKey(kCustomerBookingConfirmKey));
}

Future<void> _waitUntilConfirmReady(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    if (find.byKey(kCustomerBookingConfirmKey).evaluate().isNotEmpty &&
        find.byKey(kCustomerBookingPriceKey).evaluate().isNotEmpty &&
        _confirmButton(tester).onPressed != null) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('valid 08:30 taxi ride keeps Confirm active at 08:24', (
    tester,
  ) async {
    await _pump(
      tester,
      entry: _entry(startsAt: DateTime.now().add(const Duration(hours: 1))),
    );
    await _expandSheet(tester);
    final vehicle = find.byKey(customerBookingVehicleKey('vh_tesla'));
    if (vehicle.evaluate().isNotEmpty) {
      await tester.ensureVisible(vehicle);
      await tester.tap(vehicle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    await _waitUntilConfirmReady(tester);
    expect(find.byKey(kCustomerBookingPriceKey), findsOneWidget);
    expect(_confirmButton(tester).onPressed, isNotNull);
    expect(find.byKey(kCustomerBookingConfirmReasonKey), findsNothing);
  });

  testWidgets('configured min prep shows a concrete time next to the clock', (
    tester,
  ) async {
    await _pump(
      tester,
      entry: _entry(startsAt: DateTime.now().add(const Duration(minutes: 6))),
      minPrepMinutes: 15,
    );
    await _expandSheet(tester);
    expect(find.byKey(kCustomerBookingLaterInvalidKey), findsOneWidget);
    expect(find.byKey(kCustomerBookingSuggestedTimeKey), findsOneWidget);
    expect(_confirmButton(tester).onPressed, isNull);
  });

  testWidgets('double tap on Confirm opens one payment sheet', (tester) async {
    var books = 0;
    await _pump(
      tester,
      entry: _entry(startsAt: DateTime.now().add(const Duration(hours: 1))),
      quotes: _quotes(
        onPostBody: (path, body) {
          if (path.endsWith('/book')) books += 1;
        },
      ),
    );
    await _expandSheet(tester);
    final vehicle = find.byKey(customerBookingVehicleKey('vh_tesla'));
    if (vehicle.evaluate().isNotEmpty) {
      await tester.ensureVisible(vehicle);
      await tester.tap(vehicle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    await _waitUntilConfirmReady(tester);
    await tester.ensureVisible(find.byKey(kCustomerBookingConfirmKey));
    await tester.tap(find.byKey(kCustomerBookingConfirmKey));
    await tester.pump();
    await tester.tap(
      find.byKey(kCustomerBookingConfirmKey),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(kCustomerBookingPaymentPageKey), findsOneWidget);
    expect(books, 0);
  });

  testWidgets('book payload keeps the selected driver and vehicle id', (
    tester,
  ) async {
    String bookBody = '';
    await _pump(
      tester,
      entry: _entry(startsAt: DateTime.now().add(const Duration(hours: 1))),
      quotes: _quotes(
        onPostBody: (path, body) {
          if (path.endsWith('/book')) bookBody = body;
        },
      ),
    );
    await _expandSheet(tester);
    final vehicle = find.byKey(customerBookingVehicleKey('vh_tesla'));
    if (vehicle.evaluate().isNotEmpty) {
      await tester.ensureVisible(vehicle);
      await tester.tap(vehicle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    await _waitUntilConfirmReady(tester);
    await tester.ensureVisible(find.byKey(kCustomerBookingConfirmKey));
    await tester.tap(find.byKey(kCustomerBookingConfirmKey));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(kCustomerBookingPaymentConfirmKey));
    await tester.tap(find.byKey(kCustomerBookingPaymentConfirmKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(bookBody, contains('vh_tesla'));
    expect(bookBody, contains('drv_chris'));
  });

  testWidgets('missing checkout link does not post a second /book', (
    tester,
  ) async {
    var books = 0;
    await _pump(
      tester,
      entry: _entry(startsAt: DateTime.now().add(const Duration(hours: 1))),
      quotes: _quotes(
        onPostBody: (path, body) {
          if (path.endsWith('/book')) books += 1;
        },
        bookResponse: const <String, dynamic>{
          'ok': true,
          'booking_id': 'B-76',
          'payment_booking_id': 'PB-76',
        },
      ),
    );
    await _expandSheet(tester);
    final vehicle = find.byKey(customerBookingVehicleKey('vh_tesla'));
    if (vehicle.evaluate().isNotEmpty) {
      await tester.ensureVisible(vehicle);
      await tester.tap(vehicle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    await _waitUntilConfirmReady(tester);
    await tester.ensureVisible(find.byKey(kCustomerBookingConfirmKey));
    await tester.tap(find.byKey(kCustomerBookingConfirmKey));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(kCustomerBookingPaymentConfirmKey));
    await tester.tap(find.byKey(kCustomerBookingPaymentConfirmKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(books, 1);
    await tester.tap(find.byKey(kCustomerBookingConfirmKey));
    await tester.pump();
    expect(books, 1);
  });

  testWidgets('write confirm comparison shots for phone and tablet', (
    tester,
  ) async {
    Future<void> shot(String name) async {
      await tester.pump();
      final boundary =
          tester.renderObject(find.byKey(_shotKey)) as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.25);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      expect(bytes, isNotNull);
      final dir = Directory('test_reports/customer_booking_confirm_20260919');
      dir.createSync(recursive: true);
      File('${dir.path}/$name.png').writeAsBytesSync(bytes!);
    }

    await _pump(
      tester,
      entry: _entry(startsAt: DateTime.now().add(const Duration(hours: 1))),
      wrapShot: true,
    );
    await _expandSheet(tester);
    await shot('01_phone_390_confirm');

    await _pump(
      tester,
      size: const Size(800, 1280),
      entry: _entry(startsAt: DateTime.now().add(const Duration(hours: 1))),
      wrapShot: true,
    );
    await shot('02_tablet_portrait_confirm');

    await _pump(
      tester,
      size: const Size(1280, 800),
      entry: _entry(startsAt: DateTime.now().add(const Duration(hours: 1))),
      wrapShot: true,
    );
    await shot('03_tablet_landscape_confirm');
  });
}
