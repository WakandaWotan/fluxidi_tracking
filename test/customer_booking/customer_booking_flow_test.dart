import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_search.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_plan_airport_cards.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_flow.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_layout.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_company_vehicles.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote.dart';
import 'package:fluxidi_tracking/payment/booking_billing_identity_form.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_current_location.dart';
import 'package:http/http.dart' as http;

Widget _app(
  Widget child, {
  Size size = const Size(390, 844),
  ThemeData? theme,
}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(theme: theme, home: child),
  );
}

LimousinePlaceLookup _lookup() {
  return LimousinePlaceLookup(
    searchOverride: (query, language) async {
      return LimousinePlaceLookupResult(
        suggestions: [
          LimousinePlaceSuggestion(
            label: query.trim().isEmpty ? 'Rue Test 1, Bruxelles' : query,
            lat: 50.85,
            lon: 4.35,
            placeType: 'address',
          ),
        ],
      );
    },
    reverseOverride: (lat, lon, language) async {
      return LimousinePlaceLookupResult(
        suggestions: [
          LimousinePlaceSuggestion(
            label: 'GPS Straat 12, Brussel',
            lat: lat,
            lon: lon,
            placeType: 'address',
          ),
        ],
      );
    },
  );
}

CustomerBookingQuoteClient _quotes({
  bool calculatorOff = false,
  void Function(String path)? onPost,
  void Function(String path, String body)? onPostBody,
}) {
  return CustomerBookingQuoteClient(
    bookingBaseUrl: 'http://127.0.0.1:8788',
    httpPost: (url, headers, body) async {
      onPost?.call(url.path);
      onPostBody?.call(url.path, body);
      if (url.path.endsWith('/book')) {
        return http.Response(
          jsonEncode(<String, dynamic>{'ok': true, 'bookingId': 'bk_flow_1'}),
          200,
        );
      }
      return http.Response(
        jsonEncode(<String, dynamic>{
          'ok': true,
          'price_available': !calculatorOff,
          'calculator_off': calculatorOff,
          'request_quote_required': calculatorOff,
          'price_incl_vat': calculatorOff ? null : 48.5,
          'total_price_incl_vat': calculatorOff ? null : 48.5,
          'outbound_price_incl_vat': calculatorOff ? null : 28.0,
          'return_price_incl_vat': calculatorOff ? null : 20.5,
          'distance_km': 14.2,
          'duration_min': 22,
          'return_distance_km': 14.1,
          'return_duration_min': 21,
          'currency': 'EUR',
          'pickup_lat': 50.85,
          'pickup_lon': 4.35,
          'dropoff_lat': 50.90,
          'dropoff_lon': 4.48,
        }),
        200,
      );
    },
  );
}

CustomerBookingProfileGet _defaultProfileGet() {
  return (uri) async {
    if (uri.path.contains('availability')) {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'ok': true,
          'vehicles': <Map<String, dynamic>>[
            <String, dynamic>{'vehicle_id': 'vh_1', 'available': true},
            <String, dynamic>{'vehicle_id': 'vh_tesla', 'available': true},
            <String, dynamic>{'vehicle_id': 'vh_cadillac', 'available': true},
            <String, dynamic>{'vehicle_id': 'vh_premium', 'available': true},
            <String, dynamic>{'vehicle_id': 'vh_sedan', 'available': true},
            <String, dynamic>{'vehicle_id': 'vh_van', 'available': true},
          ],
        }),
        200,
      );
    }
    return http.Response('partner_profile_skipped', 404);
  };
}

LimousineCurrentLocationPlatform _gpsDenied() {
  return LimousineCurrentLocationPlatform(
    isLocationServiceEnabled: () async => false,
  );
}

LimousineCurrentLocationPlatform _gpsGranted() {
  return LimousineCurrentLocationPlatform(
    isLocationServiceEnabled: () async => true,
    checkPermission: () async => LimousineLocationPermission.granted,
    requestPermission: () async => LimousineLocationPermission.granted,
    getCurrentPosition: (_) async =>
        const LimousineCurrentLocationFix(latitude: 50.85, longitude: 4.35),
  );
}

Future<void> _pumpFlow(
  WidgetTester tester, {
  required CustomerBookingEntryContext entry,
  Size size = const Size(390, 844),
  bool autoResolveGps = false,
  LimousineCurrentLocationPlatform? gps,
  CustomerBookingQuoteClient? quotes,
  ThemeData? theme,
  CustomerProfile? profile,
  CustomerBookingProfileGet? profileGet,
  AppLanguage language = AppLanguage.nl,
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
        language: language,
        lookup: _lookup(),
        locationPlatform: gps ?? _gpsDenied(),
        quoteClient: quotes ?? _quotes(),
        autoResolveGps: autoResolveGps,
        profile: profile,
        profileGet: profileGet ?? _defaultProfileGet(),
      ),
      size: size,
      theme: theme,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
  if (autoResolveGps) {
    await tester.pump(const Duration(milliseconds: 800));
  }
}

Future<void> _expandSheetIfPresent(WidgetTester tester) async {
  final handle = find.byKey(kCustomerBookingSheetHandleKey);
  if (handle.evaluate().isEmpty) return;
  if (find.byKey(kCustomerBookingSheetKey).evaluate().isEmpty) return;
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

Future<void> _dragSheet(WidgetTester tester, double dy) async {
  final handle = find.byKey(kCustomerBookingSheetHandleKey);
  expect(handle, findsOneWidget);
  await tester.drag(handle, Offset(0, dy));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 40));
}

Finder _treeKey(Key key) => find.byKey(key, skipOffstage: false);

Finder _treeText(String text) => find.text(text, skipOffstage: false);

Future<void> _scrollFormTo(WidgetTester tester, Finder finder) async {
  await _expandSheetIfPresent(tester);
  final formScroll = find.descendant(
    of: _treeKey(kCustomerBookingFormKey),
    matching: find.byType(Scrollable),
  );
  if (formScroll.evaluate().isNotEmpty) {
    await tester.scrollUntilVisible(finder, 280, scrollable: formScroll.first);
  } else if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
  }
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fluxidi_flow_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('ordinary taxi starts in street mode without airplane visual', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      entry: const CustomerBookingEntryContext(kind: CustomerBookingKind.taxi),
      autoResolveGps: true,
      gps: _gpsDenied(),
    );
    expect(find.byKey(kCustomerBookingFlowKey), findsOneWidget);
    expect(find.byKey(kCustomerBookingAirplaneVisualKey), findsNothing);
    expect(_treeKey(kCustomerBookingGpsFallbackKey), findsOneWidget);
    expect(_treeKey(kCustomerBookingPickupKey), findsOneWidget);
    expect(find.textContaining('drv_'), findsNothing);
    expect(find.textContaining('Chauffeurstoewijzing'), findsNothing);
  });

  testWidgets('GPS pickup fills the address when a fix is available', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      entry: const CustomerBookingEntryContext(kind: CustomerBookingKind.taxi),
      autoResolveGps: true,
      gps: _gpsGranted(),
    );
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byKey(kCustomerBookingGpsFallbackKey), findsNothing);
    expect(_treeText('GPS Straat 12, Brussel'), findsWidgets);
  });

  testWidgets('airport entry opens airport mode with airplane and cards', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.airport,
      ),
    );
    expect(_treeKey(kCustomerBookingAirplaneVisualKey), findsOneWidget);
    expect(_treeKey(kCustomerBookingToAirportKey), findsOneWidget);
    expect(_treeKey(kCustomerBookingFromAirportKey), findsOneWidget);
    for (final iata in kCompanyPlanFeaturedAirportIata) {
      expect(_treeKey(customerBookingAirportCardKey(iata)), findsOneWidget);
    }
  });

  testWidgets('Belgian photo card writes the same KJK record as the catalog', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.airport,
      ),
    );
    await _scrollFormTo(tester, _treeKey(customerBookingAirportCardKey('KJK')));
    await tester.tap(find.byKey(customerBookingAirportCardKey('KJK')));
    await tester.pump();
    expect(_treeKey(kCustomerBookingAirportSummaryKey), findsOneWidget);
    expect(find.textContaining('KJK', skipOffstage: false), findsWidgets);
    expect(
      find.textContaining(airportByIata('KJK')!.name, skipOffstage: false),
      findsWidgets,
    );
    expect(_treeKey(kCustomerBookingAirplaneVisualKey), findsOneWidget);
  });

  testWidgets('Andere luchthaven opens country then airport lists', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.airport,
      ),
    );
    expect(find.text('Andere luchthaven'), findsOneWidget);
    expect(find.text('Alle luchthavens bekijken'), findsOneWidget);
    await _scrollFormTo(
      tester,
      _treeKey(customerBookingAirportCardKey('other')),
    );
    await tester.tap(find.byKey(customerBookingAirportCardKey('other')));
    await tester.pumpAndSettle();
    expect(find.byKey(kCustomerBookingChooseCountryKey), findsOneWidget);
    expect(find.text('Kies je land'), findsOneWidget);
    expect(find.byKey(kCustomerBookingChooseAirportKey), findsOneWidget);
    expect(find.text('Kies je luchthaven'), findsOneWidget);
    await _scrollFormTo(tester, _treeKey(customerBookingCountryKey('NL')));
    await tester.tap(find.byKey(customerBookingCountryKey('NL')));
    await tester.pump();
    await _scrollFormTo(tester, _treeKey(kCustomerBookingAirportSearchKey));
    await tester.enterText(find.byKey(kCustomerBookingAirportSearchKey), 'AMS');
    await tester.pump();
    expect(_treeKey(customerBookingAirportListKey('AMS')), findsOneWidget);
    expect(_treeKey(kCustomerBookingAirplaneVisualKey), findsOneWidget);
  });

  testWidgets(
    'from-airport shows landing hint and hides to-airport late warning',
    (tester) async {
      await _pumpFlow(
        tester,
        entry: const CustomerBookingEntryContext(
          kind: CustomerBookingKind.airport,
          toAirport: false,
          airport: AirportCatalogAirport(
            countryCode: 'BE',
            countryName: 'België',
            city: 'Luik',
            name: 'Liège Airport',
            iata: 'LGG',
            latitude: 50.6374,
            longitude: 5.4432,
          ),
        ),
      );
      await _scrollFormTo(tester, _treeKey(kCustomerBookingLandingHintKey));
      expect(find.byKey(kCustomerBookingLandingHintKey), findsOneWidget);
      expect(find.byKey(kCustomerBookingFlightNumberKey), findsOneWidget);
    },
  );

  testWidgets('event context fills the destination once', (tester) async {
    await _pumpFlow(
      tester,
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.event,
        destination: CustomerBookingPlace(
          id: 'evt_1',
          name: 'Jazz Night',
          address: 'Anspachlaan 1, Brussel',
          latitude: 50.85,
          longitude: 4.35,
        ),
      ),
    );
    expect(_treeText('Anspachlaan 1, Brussel'), findsWidgets);
    expect(find.byKey(kCustomerBookingAirplaneVisualKey), findsNothing);
  });

  testWidgets('stay context fills the destination once', (tester) async {
    await _pumpFlow(
      tester,
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.stay,
        destination: CustomerBookingPlace(
          id: 'stay_1',
          name: 'Hotel Nord',
          address: 'Rogierplein 2, Brussel',
          latitude: 50.86,
          longitude: 4.36,
        ),
      ),
    );
    expect(_treeText('Rogierplein 2, Brussel'), findsWidgets);
    expect(find.byKey(kCustomerBookingAirplaneVisualKey), findsNothing);
  });

  testWidgets('business keeps street and airport mode side by side', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.business,
        allowModeToggle: true,
        company: CustomerBookingCompany(
          partnerId: 'demo_company_p0',
          companyName: 'Demo Taxi',
        ),
        lockCompany: true,
      ),
    );
    expect(_treeKey(kCustomerBookingStreetModeKey), findsWidgets);
    expect(_treeKey(kCustomerBookingAirportModeKey), findsWidgets);
    expect(_treeKey(kCustomerBookingCompanyLockKey), findsWidgets);
    expect(find.byKey(kCustomerBookingAirplaneVisualKey), findsNothing);
    await _scrollFormTo(tester, _treeKey(kCustomerBookingAirportModeKey));
    await tester.tap(find.byKey(kCustomerBookingAirportModeKey));
    await tester.pump();
    expect(_treeKey(kCustomerBookingAirplaneVisualKey), findsOneWidget);
  });

  testWidgets('taxi and airport share the phone sheet and mode toggle', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      size: const Size(390, 844),
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        company: CustomerBookingCompany(
          partnerId: 'demo_company_p0',
          companyName: 'Demo Taxi',
        ),
      ),
    );
    expect(find.byKey(kCustomerBookingSheetKey), findsOneWidget);
    expect(_treeKey(kCustomerBookingStreetModeKey), findsWidgets);
    expect(_treeKey(kCustomerBookingAirportModeKey), findsWidgets);
    await _scrollFormTo(tester, _treeKey(kCustomerBookingAirportModeKey));
    await tester.tap(find.byKey(kCustomerBookingAirportModeKey));
    await tester.pump();
    expect(find.byKey(kCustomerBookingSheetKey), findsOneWidget);
    expect(_treeKey(kCustomerBookingAirplaneVisualKey), findsOneWidget);
  });

  testWidgets('phone, tablet portrait and landscape share the map sheet', (
    tester,
  ) async {
    for (final size in const <Size>[
      Size(390, 844),
      Size(430, 932),
      Size(800, 1280),
      Size(1280, 800),
    ]) {
      await _pumpFlow(
        tester,
        size: size,
        entry: const CustomerBookingEntryContext(
          kind: CustomerBookingKind.taxi,
          company: CustomerBookingCompany(
            partnerId: 'demo_company_p0',
            companyName: 'Demo Taxi',
          ),
        ),
      );
      expect(
        find.byKey(kCustomerBookingMapSheetShellKey),
        findsOneWidget,
        reason: '${size.width}x${size.height}',
      );
      expect(find.byKey(kCustomerBookingMapKey), findsOneWidget);
      expect(find.byKey(kCustomerBookingSheetKey), findsOneWidget);
      expect(find.byKey(kCustomerBookingSheetHandleKey), findsOneWidget);
      expect(find.byKey(kCustomerBookingConfirmKey), findsOneWidget);
      expect(find.byKey(kCustomerBookingWideSplitKey), findsNothing);
    }
  });

  testWidgets('taxi and airport keep pickup and return on the same shell', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      size: const Size(800, 1280),
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        company: CustomerBookingCompany(
          partnerId: 'demo_company_p0',
          companyName: 'Demo Taxi',
        ),
        pickup: CustomerBookingPlace(
          address: 'Koekamerstraat 48A, 9688',
          latitude: 50.8039,
          longitude: 3.6308,
        ),
      ),
    );
    expect(find.byKey(kCustomerBookingMapSheetShellKey), findsOneWidget);
    expect(find.textContaining('Koekamerstraat'), findsWidgets);
    await _expandSheetIfPresent(tester);
    final addReturn = find.byKey(kCustomerBookingAddReturnKey);
    if (addReturn.evaluate().isNotEmpty) {
      await tester.ensureVisible(addReturn);
      await tester.tap(addReturn);
      await tester.pump();
    }
    expect(find.byKey(kCustomerBookingReturnDateKey), findsWidgets);
    await _scrollFormTo(tester, _treeKey(kCustomerBookingAirportModeKey));
    await tester.tap(find.byKey(kCustomerBookingAirportModeKey));
    await tester.pump();
    expect(find.byKey(kCustomerBookingMapSheetShellKey), findsOneWidget);
    expect(_treeKey(kCustomerBookingAirplaneVisualKey), findsOneWidget);
    expect(find.textContaining('Koekamerstraat'), findsWidgets);
    await _scrollFormTo(tester, _treeKey(kCustomerBookingStreetModeKey));
    await tester.tap(find.byKey(kCustomerBookingStreetModeKey));
    await tester.pump();
    expect(find.byKey(kCustomerBookingMapSheetShellKey), findsOneWidget);
    expect(find.textContaining('Koekamerstraat'), findsWidgets);
    expect(find.byKey(kCustomerBookingReturnDateKey), findsWidgets);
  });

  testWidgets('confirm stays reachable in every sheet snap', (tester) async {
    await _pumpFlow(
      tester,
      size: const Size(390, 844),
      entry: const CustomerBookingEntryContext(kind: CustomerBookingKind.taxi),
    );
    expect(find.byKey(kCustomerBookingConfirmKey), findsOneWidget);
    await _dragSheet(tester, 240);
    expect(find.byKey(kCustomerBookingConfirmKey), findsOneWidget);
    await _expandSheetIfPresent(tester);
    expect(find.byKey(kCustomerBookingConfirmKey), findsOneWidget);
    final confirm = tester.getRect(find.byKey(kCustomerBookingConfirmKey));
    expect(confirm.bottom, lessThanOrEqualTo(844 + 1));
  });

  testWidgets('company page, link and QR keep the locked company', (
    tester,
  ) async {
    for (final kind in <CustomerBookingKind>[
      CustomerBookingKind.companyPage,
      CustomerBookingKind.bookingLink,
      CustomerBookingKind.qr,
    ]) {
      await _pumpFlow(
        tester,
        entry: CustomerBookingEntryContext(
          kind: kind,
          company: const CustomerBookingCompany(
            partnerId: 'partner_locked',
            companyName: 'Locked Taxi',
          ),
          lockCompany: true,
        ),
      );
      expect(find.text('Locked Taxi'), findsOneWidget);
      expect(find.text('Taxibedrijf zoeken'), findsNothing);
    }
  });

  testWidgets('invalid locked context shows a safe error', (tester) async {
    await _pumpFlow(
      tester,
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.qr,
        lockCompany: true,
      ),
    );
    expect(find.byKey(kCustomerBookingContextErrorKey), findsOneWidget);
    expect(find.byKey(kCustomerBookingConfirmKey), findsNothing);
  });

  testWidgets('return wait chips and a stop sit between pickup and dropoff', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      size: const Size(800, 1280),
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        pickup: CustomerBookingPlace(
          address: 'A Straat 1, Brussel',
          latitude: 50.85,
          longitude: 4.35,
        ),
        destination: CustomerBookingPlace(
          address: 'B Straat 2, Brussel',
          latitude: 50.90,
          longitude: 4.48,
        ),
      ),
    );
    await _expandSheetIfPresent(tester);
    await _scrollFormTo(tester, find.byKey(kCustomerBookingAddReturnKey));
    await tester.tap(find.byKey(kCustomerBookingAddReturnKey));
    await tester.pump();
    await _scrollFormTo(tester, find.byKey(kCustomerBookingReturnWaitKey));
    await tester.tap(find.byKey(kCustomerBookingReturnWaitKey));
    await tester.pump();
    expect(find.byKey(customerBookingWaitChipKey(30)), findsOneWidget);
    await tester.tap(find.byKey(kCustomerBookingAddStopKey).first);
    await tester.pump();
    expect(find.byKey(customerBookingStopKey(0)), findsOneWidget);
    expect(find.byKey(kCustomerBookingConfirmKey), findsOneWidget);
  });

  testWidgets('airport flow hides wait chips that taxi still shows', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      size: const Size(800, 1280),
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.airport,
        pickup: CustomerBookingPlace(
          address: 'A Straat 1, Brussel',
          latitude: 50.85,
          longitude: 4.35,
        ),
        destination: CustomerBookingPlace(
          address: 'Brussels Airport',
          latitude: 50.901,
          longitude: 4.484,
        ),
      ),
    );
    expect(find.text('Heen en terug met wachten'), findsNothing);
    expect(find.byKey(kCustomerBookingReturnWaitKey), findsNothing);
    expect(find.byKey(customerBookingWaitChipKey(30)), findsNothing);
    expect(find.byKey(customerBookingWaitChipKey(90)), findsNothing);
  });

  test('book posts once through the shared customer quote client', () async {
    var books = 0;
    final client = _quotes(
      onPost: (path) {
        if (path.endsWith('/book')) books += 1;
      },
    );
    await client.book(
      body: const <String, dynamic>{'from': 'A', 'to': 'B'},
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        company: CustomerBookingCompany(partnerId: 'demo_company_p0'),
      ),
    );
    expect(books, 1);
    expect(
      customerBookingIdFromResponse({'bookingId': 'bk_flow_1'}),
      'bk_flow_1',
    );
  });

  testWidgets(
    'calculator off shows price on request without inventing a fare',
    (tester) async {
      await _pumpFlow(
        tester,
        size: const Size(800, 1280),
        entry: const CustomerBookingEntryContext(
          kind: CustomerBookingKind.taxi,
          company: CustomerBookingCompany(
            partnerId: 'partner_demo',
            companyName: 'Demo Taxi',
          ),
          pickup: CustomerBookingPlace(
            address: 'A Straat 1, Brussel',
            latitude: 50.85,
            longitude: 4.35,
          ),
          destination: CustomerBookingPlace(
            address: 'B Straat 2, Brussel',
            latitude: 50.90,
            longitude: 4.48,
          ),
        ),
        quotes: _quotes(calculatorOff: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(kCustomerBookingPriceKey), findsOneWidget);
      expect(find.textContaining('Prijs op aanvraag'), findsWidgets);
      expect(find.textContaining('€48'), findsNothing);
    },
  );

  testWidgets('quote errors keep the typed draft and offer retry', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      size: const Size(800, 1280),
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        company: CustomerBookingCompany(
          partnerId: 'partner_demo',
          companyName: 'Demo Taxi',
        ),
        pickup: CustomerBookingPlace(
          address: 'Bewaard vertrek 9, Brussel',
          latitude: 50.85,
          longitude: 4.35,
        ),
        destination: CustomerBookingPlace(
          address: 'Bewaarde bestemming 4, Brussel',
          latitude: 50.90,
          longitude: 4.48,
        ),
      ),
      quotes: CustomerBookingQuoteClient(
        bookingBaseUrl: 'http://127.0.0.1:8788',
        httpPost: (url, headers, body) async {
          return http.Response('{"ok":false,"error":"mapbox_down"}', 503);
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Bewaard vertrek 9, Brussel'), findsWidgets);
    expect(find.text('Bewaarde bestemming 4, Brussel'), findsWidgets);
    expect(find.textContaining('Missing fields'), findsNothing);
    expect(find.textContaining('mapbox_down'), findsNothing);
    expect(find.textContaining('Bad state'), findsNothing);
    await tester.ensureVisible(find.byKey(kCustomerBookingQuoteRetryKey));
    expect(find.byKey(kCustomerBookingQuoteRetryKey), findsOneWidget);
    expect(find.byKey(kCustomerBookingPriceKey), findsNothing);
    expect(find.byKey(kCustomerBookingQuoteRetryKey), findsOneWidget);
  });

  testWidgets('oversized passenger count suggests a larger vehicle type', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      entry: CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        company: CustomerBookingCompany(
          partnerId: 'partner_demo',
          companyName: 'Demo Taxi Maarkedal',
          vehicles: const <Map<String, dynamic>>[
            <String, dynamic>{
              'vehicle_id': 'vh_sedan',
              'vehicle_type': 'sedan',
              'seats': 3,
            },
            <String, dynamic>{
              'vehicle_id': 'vh_van',
              'vehicle_type': 'minivan',
              'seats': 7,
            },
          ],
        ),
      ),
    );
    await _expandSheetIfPresent(tester);
    await tester.tap(find.byKey(kCustomerBookingPaxSummaryKey));
    await tester.pump();
    await _scrollFormTo(tester, _treeKey(kCustomerBookingPaxIncKey));
    final increment = find.byKey(kCustomerBookingPaxIncKey);
    expect(increment, findsOneWidget);
    for (var i = 0; i < 7; i++) {
      tester.widget<IconButton>(increment).onPressed?.call();
      await tester.pump();
    }
    expect(find.textContaining('groter voertuig'), findsOneWidget);
  });

  testWidgets('phone and tablet layouts keep the confirm button', (
    tester,
  ) async {
    for (final size in const <Size>[Size(390, 844), Size(800, 1280)]) {
      await _pumpFlow(
        tester,
        entry: const CustomerBookingEntryContext(
          kind: CustomerBookingKind.taxi,
        ),
        size: size,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(kCustomerBookingConfirmKey), findsOneWidget);
      expect(find.byKey(kCustomerBookingMapSheetShellKey), findsOneWidget);
      expect(find.byKey(kCustomerBookingNarrowStackKey), findsOneWidget);
      expect(find.byKey(kCustomerBookingWideSplitKey), findsNothing);
      expect(find.byKey(kCustomerBookingSheetKey), findsOneWidget);
      expect(find.byKey(kCustomerBookingSheetHandleKey), findsOneWidget);
      expect(find.byKey(kCustomerBookingSheetToggleKey), findsNothing);
      expect(find.text('Waar ophalen?'), findsOneWidget);
      expect(find.text('Waar wil je naartoe?'), findsOneWidget);
      final map = tester.getRect(find.byKey(kCustomerBookingMapKey));
      final sheet = tester.getRect(find.byKey(kCustomerBookingSheetKey));
      final confirm = tester.getRect(find.byKey(kCustomerBookingConfirmKey));
      expect(sheet.top, greaterThan(map.top + 80));
      expect(confirm.top, greaterThan(sheet.top));
    }
  });

  testWidgets('tablet landscape uses the map sheet, not two columns', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      size: const Size(1280, 800),
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        pickup: CustomerBookingPlace(
          address: 'A Straat 1, Brussel',
          latitude: 50.85,
          longitude: 4.35,
        ),
        destination: CustomerBookingPlace(
          address: 'B Straat 2, Brussel',
          latitude: 50.90,
          longitude: 4.48,
        ),
      ),
    );
    expect(find.byKey(kCustomerBookingWideSplitKey), findsNothing);
    expect(find.byKey(kCustomerBookingMapSheetShellKey), findsOneWidget);
    expect(find.byKey(kCustomerBookingSheetKey), findsOneWidget);
    final map = tester.getRect(find.byKey(kCustomerBookingMapKey));
    final sheet = tester.getRect(find.byKey(kCustomerBookingSheetKey));
    final confirm = tester.getRect(find.byKey(kCustomerBookingConfirmKey));
    expect(map.width, greaterThan(480));
    expect(sheet.top, greaterThan(map.top + 40));
    expect(confirm.top, greaterThan(sheet.top));
  });

  testWidgets('public quote posts existing now schedule as date and time', (
    tester,
  ) async {
    String? quoteBody;
    await _pumpFlow(
      tester,
      size: const Size(800, 1280),
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        company: CustomerBookingCompany(
          partnerId: 'partner_demo',
          companyName: 'Demo Taxi',
        ),
        pickup: CustomerBookingPlace(
          address: 'A Straat 1, Brussel',
          latitude: 50.85,
          longitude: 4.35,
        ),
        destination: CustomerBookingPlace(
          address: 'B Straat 2, Brussel',
          latitude: 50.90,
          longitude: 4.48,
        ),
      ),
      quotes: _quotes(
        onPostBody: (path, body) {
          if (path.endsWith('/quote')) quoteBody = body;
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(quoteBody, isNotNull);
    final decoded = jsonDecode(quoteBody!) as Map<String, dynamic>;
    expect(decoded['from'], contains('A Straat 1'));
    expect(decoded['to'], contains('B Straat 2'));
    expect(decoded['date'], isNotEmpty);
    expect(decoded['time'], isNotEmpty);
    expect(decoded.containsKey('flight_at'), isFalse);
  });

  testWidgets('airport route without a company asks to choose a company', (
    tester,
  ) async {
    var quotes = 0;
    await _pumpFlow(
      tester,
      size: const Size(800, 1280),
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.airport,
        pickup: CustomerBookingPlace(
          address: 'Koekamerstraat 48, Maarkedal',
          latitude: 50.77,
          longitude: 3.66,
        ),
        destination: CustomerBookingPlace(
          address: 'Brussels Airport',
          latitude: 50.90,
          longitude: 4.48,
        ),
      ),
      quotes: _quotes(
        onPost: (path) {
          if (path.endsWith('/quote')) quotes += 1;
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(quotes, 0);
    expect(find.textContaining('taxibedrijf'), findsWidgets);
    expect(find.textContaining('offerte kon niet'), findsNothing);
    expect(find.byKey(kCustomerBookingPriceKey), findsNothing);
  });

  testWidgets(
    'scheduled pickup time from home is not replaced by flight time',
    (tester) async {
      await _pumpFlow(
        tester,
        size: const Size(800, 1280),
        entry: CustomerBookingEntryContext(
          kind: CustomerBookingKind.taxi,
          pickup: CustomerBookingPlace(
            address: 'Koekamerstraat 48, Maarkedal',
            latitude: 50.80,
            longitude: 3.63,
            startsAt: DateTime(2026, 9, 16, 9, 45),
          ),
          destination: const CustomerBookingPlace(
            address: 'Brussels Airport',
            latitude: 50.90,
            longitude: 4.48,
          ),
        ),
      );
      expect(find.textContaining('2026-09-16'), findsWidgets);
      expect(find.textContaining('09:45'), findsWidgets);
      expect(find.textContaining('2026-09-16 09:45'), findsNothing);
    },
  );

  testWidgets('large catalog search stays bounded', (tester) async {
    final sw = Stopwatch()..start();
    final matches = searchPublishedAirports('airport', limit: 40);
    sw.stop();
    expect(matches.length, lessThanOrEqualTo(40));
    expect(sw.elapsedMilliseconds, lessThan(250));
    expect(publishedAirportCatalog().length, greaterThanOrEqualTo(173));
  });

  test('light customer theme keeps dark text on cream surfaces', () {
    final palette = paletteForCustomerTheme(CustomerThemeVariant.premiumLight);
    final theme = themeForCustomerPalette(ThemeData.dark(), palette);
    expect(theme.brightness, Brightness.light);
    expect(theme.colorScheme.onSurface.computeLuminance(), lessThan(0.4));
    expect(
      theme.inputDecorationTheme.fillColor!.computeLuminance(),
      greaterThan(0.8),
    );
    expect(
      theme.filledButtonTheme.style!.foregroundColor!
          .resolve(const <WidgetState>{})!
          .computeLuminance(),
      lessThan(0.25),
    );
    expect(
      customerLinkOnBackground(palette).computeLuminance(),
      lessThan(0.35),
    );
  });

  testWidgets('booking flow stays readable under a dark parent theme', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.companyPage,
        company: CustomerBookingCompany(
          partnerId: 'company:demo_company_p0:demo_company_p0',
          companyId: 'demo_company_p0',
          companyName: 'Fluxidi Demo Cars',
        ),
        lockCompany: true,
      ),
      size: const Size(1100, 700),
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(primary: Color(0xFFE5B641)),
      ),
    );
    final pickup = tester.widget<TextField>(
      find.byKey(kCustomerBookingPickupKey),
    );
    expect(
      pickup.decoration?.fillColor?.computeLuminance() ?? 0,
      greaterThan(0.7),
    );
    expect(
      (pickup.style?.color ?? const Color(0xFF182028)).computeLuminance(),
      lessThan(0.4),
    );
    expect(find.text('Fluxidi Demo Cars'), findsOneWidget);
    expect(find.byKey(kCustomerBookingConfirmKey), findsOneWidget);
    expect(find.text('Bevestigen'), findsWidgets);
  });

  testWidgets('confirm explains missing fields and does not post a booking', (
    tester,
  ) async {
    var books = 0;
    await _pumpFlow(
      tester,
      entry: const CustomerBookingEntryContext(kind: CustomerBookingKind.taxi),
      quotes: _quotes(
        onPost: (path) {
          if (path.endsWith('/book')) books += 1;
        },
      ),
    );
    await tester.ensureVisible(find.byKey(kCustomerBookingConfirmKey));
    final confirm = tester.widget<FilledButton>(
      find.byKey(kCustomerBookingConfirmKey),
    );
    expect(confirm.onPressed, isNull);
    expect(find.byKey(kCustomerBookingSuccessKey), findsNothing);
    expect(books, 0);
  });

  testWidgets('confirm posts once and then blocks a second booking', (
    tester,
  ) async {
    var books = 0;
    await _pumpFlow(
      tester,
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        company: CustomerBookingCompany(
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
        ),
        pickup: CustomerBookingPlace(
          address: 'Koekamerstraat 488A, Maarkedal',
          latitude: 50.79,
          longitude: 3.62,
        ),
        destination: CustomerBookingPlace(
          address: 'Brussels Airport, Zaventem',
          latitude: 50.901,
          longitude: 4.484,
        ),
      ),
      quotes: _quotes(
        onPost: (path) {
          if (path.endsWith('/book')) books += 1;
        },
      ),
      profile: CustomerProfile(
        customerId: 'cus_1',
        name: 'Christophe',
        phone: '+32469788891',
        email: 'cvanrokeghem@outlook.com',
        preferredPostcode: '9688',
        companyName: '',
        vatNumber: '',
        billingStreet: 'Koekamerstraat 488A',
        billingPostalCode: '9688',
        billingCity: 'Maarkedal',
        createdAt: '2026-01-01',
        updatedAt: '2026-01-01',
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await _expandSheetIfPresent(tester);
    final vehicle = find.byKey(customerBookingVehicleKey('vh_premium'));
    if (vehicle.evaluate().isNotEmpty) {
      await tester.ensureVisible(vehicle);
      await tester.tap(vehicle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
    }
    expect(_treeKey(kCustomerBookingContactSummaryKey), findsOneWidget);
    await tester.ensureVisible(find.byKey(kCustomerBookingConfirmKey));
    await tester.tap(find.byKey(kCustomerBookingConfirmKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCustomerBookingPaymentPageKey), findsOneWidget);
    expect(books, 0);
    expect(find.byKey(kCustomerBookingPaymentConfirmKey), findsOneWidget);
    await tester.ensureVisible(find.byKey(kCustomerBookingPaymentConfirmKey));
    await tester.tap(find.byKey(kCustomerBookingPaymentConfirmKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(_treeKey(kCustomerBookingSubmitErrorKey), findsNothing);
    expect(_treeKey(kCustomerBookingSuccessKey), findsOneWidget);
    expect(
      find.textContaining('All-in Taxi Christophe Vanroeghem'),
      findsWidgets,
    );
    expect(books, 1);
    await tester.tap(find.byKey(kCustomerBookingConfirmKey));
    await tester.pump();
    expect(books, 1);
  });

  testWidgets('airport map sits above chrome and keeps the company vehicles', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.airport,
        company: CustomerBookingCompany(
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
        ),
        pickup: CustomerBookingPlace(
          address: 'A Straat 1, Brussel',
          latitude: 50.85,
          longitude: 4.35,
        ),
      ),
    );
    expect(_treeKey(kCustomerBookingAirportChromeKey), findsOneWidget);
    expect(_treeKey(kCustomerBookingToAirportKey), findsOneWidget);
    expect(_treeKey(customerBookingAirportCardKey('BRU')), findsOneWidget);
    await _scrollFormTo(tester, _treeKey(customerBookingAirportCardKey('BRU')));
    await tester.tap(find.byKey(customerBookingAirportCardKey('BRU')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await _scrollFormTo(tester, _treeKey(kCustomerBookingVehicleHintKey));
    expect(find.text('Premium', skipOffstage: false), findsOneWidget);
    expect(_treeKey(customerBookingVehicleKey('vh_premium')), findsOneWidget);
    expect(find.byKey(customerBookingVehicleKey('minivan')), findsNothing);
    expect(find.byKey(kCustomerBookingSheetKey), findsOneWidget);
    expect(_treeKey(kCustomerBookingAirportChromeKey), findsOneWidget);
    expect(find.byKey(kCustomerBookingMapKey), findsOneWidget);
    expect(
      tester.getRect(find.byKey(kCustomerBookingMapKey)).height,
      greaterThan(80),
    );
  });

  testWidgets(
    'profile address and GPS actions do not overwrite a chosen pickup',
    (tester) async {
      await _pumpFlow(
        tester,
        autoResolveGps: true,
        gps: _gpsGranted(),
        profile: CustomerProfile(
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
        ),
        entry: const CustomerBookingEntryContext(
          kind: CustomerBookingKind.taxi,
          pickup: CustomerBookingPlace(
            address: 'Handmatig vertrek 9, Ronse',
            latitude: 50.74,
            longitude: 3.60,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));
      expect(_treeText('Handmatig vertrek 9, Ronse'), findsWidgets);
      expect(find.textContaining('GPS Straat'), findsNothing);
      await _scrollFormTo(tester, _treeKey(kCustomerBookingMyAddressKey));
      expect(_treeKey(kCustomerBookingMyAddressKey), findsOneWidget);
      await tester.tap(find.byKey(kCustomerBookingMyAddressKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.textContaining('Koekamerstraat 488A', skipOffstage: false),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'private ride is default and business fields open on both modes',
    (tester) async {
      for (final kind in const <CustomerBookingKind>[
        CustomerBookingKind.taxi,
        CustomerBookingKind.airport,
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await _pumpFlow(tester, entry: CustomerBookingEntryContext(kind: kind));
        await _expandSheetIfPresent(tester);
        expect(_treeKey(kCustomerBookingPrivateRideKey), findsOneWidget);
        expect(_treeKey(kCustomerBookingBusinessRideKey), findsOneWidget);
        expect(_treeText('Particuliere rit'), findsOneWidget);
        expect(_treeText('Zakelijke rit'), findsOneWidget);
        expect(find.text('Bedrijfsnaam'), findsNothing);
        final business = find.byKey(kCustomerBookingBusinessRideKey);
        expect(business, findsOneWidget);
        await _scrollFormTo(tester, business);
        await tester.pump();
        await tester.tap(business);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(
          find.byKey(bookingBillingFieldKey(BookingBillingFormField.legalName)),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets('business details survive payment options and back', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      size: const Size(800, 1280),
      profile: const CustomerProfile(
        customerId: 'cus_1',
        name: 'Christophe',
        phone: '+32469788891',
        email: 'c@example.com',
        preferredPostcode: '9688',
        companyName: 'Flex Demo BV',
        vatNumber: 'BE0123456789',
        billingStreet: 'Koekamerstraat 48A',
        billingPostalCode: '9688',
        billingCity: 'Maarkedal',
        billingCountry: 'BE',
        createdAt: '2026-01-01',
        updatedAt: '2026-01-01',
      ),
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        company: CustomerBookingCompany(
          partnerId: 'partner_demo',
          companyName: 'All-in Taxi',
          vehicles: <Map<String, dynamic>>[
            <String, dynamic>{
              'vehicle_id': 'vh_premium',
              'vehicle_type': 'sedan',
              'tier': 'premium',
              'seats': 3,
            },
          ],
        ),
        pickup: CustomerBookingPlace(
          address: 'Koekamerstraat 48A, Maarkedal',
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
    await tester.pump(const Duration(milliseconds: 600));
    await tester.ensureVisible(find.byKey(kCustomerBookingBusinessRideKey));
    await tester.tap(find.byKey(kCustomerBookingBusinessRideKey));
    await tester.pumpAndSettle();
    expect(find.text('Flex Demo BV'), findsWidgets);
    await tester.ensureVisible(find.byKey(kCustomerBookingConfirmKey));
    await tester.tap(find.byKey(kCustomerBookingConfirmKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCustomerBookingPaymentPageKey), findsOneWidget);
    expect(find.text('Betaalopties'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(kCustomerBookingPaymentPageKey), findsNothing);
    expect(find.text('Flex Demo BV'), findsWidgets);
    expect(find.text('Zakelijke rit'), findsOneWidget);
  });

  testWidgets('switching to private does not send leftover billing fields', (
    tester,
  ) async {
    String? bookBody;
    await _pumpFlow(
      tester,
      size: const Size(800, 1280),
      quotes: _quotes(
        onPostBody: (path, body) {
          if (path.endsWith('/book')) bookBody = body;
        },
      ),
      profile: const CustomerProfile(
        customerId: 'cus_1',
        name: 'Christophe',
        phone: '+32469788891',
        email: 'c@example.com',
        preferredPostcode: '9688',
        companyName: 'Flex Demo BV',
        vatNumber: 'BE0123456789',
        billingStreet: 'Koekamerstraat 48A',
        billingPostalCode: '9688',
        billingCity: 'Maarkedal',
        billingCountry: 'BE',
        createdAt: '2026-01-01',
        updatedAt: '2026-01-01',
      ),
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        company: CustomerBookingCompany(
          partnerId: 'partner_demo',
          companyName: 'All-in Taxi',
          vehicles: <Map<String, dynamic>>[
            <String, dynamic>{
              'vehicle_id': 'vh_premium',
              'vehicle_type': 'sedan',
              'tier': 'premium',
              'seats': 3,
            },
          ],
        ),
        pickup: CustomerBookingPlace(
          address: 'Koekamerstraat 48A, Maarkedal',
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
    await tester.pump(const Duration(milliseconds: 600));
    await tester.ensureVisible(find.byKey(kCustomerBookingBusinessRideKey));
    await tester.tap(find.byKey(kCustomerBookingBusinessRideKey));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(kCustomerBookingPrivateRideKey));
    await tester.tap(find.byKey(kCustomerBookingPrivateRideKey));
    await tester.pumpAndSettle();
    expect(find.text('Bedrijfsnaam'), findsNothing);
    expect(find.byKey(kCustomerBookingContactSummaryKey), findsOneWidget);
    await tester.ensureVisible(find.byKey(kCustomerBookingConfirmKey));
    await tester.tap(find.byKey(kCustomerBookingConfirmKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCustomerBookingPaymentPageKey), findsOneWidget);
    await tester.ensureVisible(find.byKey(kCustomerBookingPaymentConfirmKey));
    await tester.tap(find.byKey(kCustomerBookingPaymentConfirmKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(bookBody, isNotNull);
    final decoded = jsonDecode(bookBody!) as Map<String, dynamic>;
    expect(decoded.containsKey('billing_customer'), isFalse);
    expect(decoded['payment_method'], isNotEmpty);
  });

  testWidgets('readable ride labels stay in tree on phone and tablet', (
    tester,
  ) async {
    for (final size in const <Size>[
      Size(390, 844),
      Size(844, 390),
      Size(800, 1280),
      Size(1280, 800),
    ]) {
      await _pumpFlow(
        tester,
        size: size,
        entry: const CustomerBookingEntryContext(
          kind: CustomerBookingKind.airport,
        ),
      );
      expect(_treeKey(kCustomerBookingPrivateRideKey), findsOneWidget);
      expect(_treeKey(kCustomerBookingBusinessRideKey), findsOneWidget);
      expect(_treeText('Particuliere rit'), findsWidgets);
      expect(_treeText('Zakelijke rit'), findsWidgets);
      expect(_treeText('Naar de luchthaven'), findsWidgets);
      expect(_treeText('Alle luchthavens bekijken'), findsWidgets);
      expect(
        find.byKey(kCustomerBookingConfirmKey, skipOffstage: false),
        findsOneWidget,
      );
    }
  });

  testWidgets('empty destination does not claim the company has no vehicles', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      language: AppLanguage.en,
      profileGet: (uri) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'profile': <String, dynamic>{
              'company_name': 'Fluxidi',
              'vehicles': <Map<String, dynamic>>[],
            },
          }),
          200,
        );
      },
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        company: CustomerBookingCompany(
          partnerId: 'partner_fluxidi',
          companyName: 'Fluxidi',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await _scrollFormTo(tester, _treeKey(kCustomerBookingVehiclesNeedRideKey));
    expect(_treeKey(kCustomerBookingVehiclesNeedRideKey), findsOneWidget);
    expect(
      find.text(
        'This company has no bookable vehicle categories for this ride.',
      ),
      findsNothing,
    );
    expect(
      find.text('This company has no suitable vehicles for this ride.'),
      findsNothing,
    );
    expect(find.text('A driver will be assigned soon'), findsNothing);
  });

  testWidgets(
    'clock row sits under Particulier/Zakelijk and exposes Datum/Tijd',
    (tester) async {
      await _pumpFlow(
        tester,
        entry: const CustomerBookingEntryContext(
          kind: CustomerBookingKind.taxi,
          company: CustomerBookingCompany(
            partnerId: 'partner_demo',
            companyName: 'All-in Taxi',
            vehicles: <Map<String, dynamic>>[
              <String, dynamic>{
                'vehicle_id': 'vh_tesla',
                'name': 'Tesla',
                'vehicle_type': 'sedan',
                'passenger_capacity': 3,
              },
              <String, dynamic>{
                'vehicle_id': 'vh_cadillac',
                'name': 'Cadillac',
                'vehicle_type': 'sedan',
                'passenger_capacity': 4,
              },
            ],
          ),
        ),
      );
      await _expandSheetIfPresent(tester);
      expect(find.byKey(kCustomerBookingNowKey), findsNothing);
      expect(find.byKey(kCustomerBookingLaterKey), findsNothing);
      final private = tester.getTopLeft(
        _treeKey(kCustomerBookingPrivateRideKey),
      );
      final clock = tester.getTopLeft(_treeKey(kCustomerBookingClockRowKey));
      expect(clock.dy, greaterThan(private.dy));
      expect(_treeKey(kCustomerBookingDateKey), findsOneWidget);
      expect(_treeKey(kCustomerBookingTimeKey), findsOneWidget);
      expect(find.text('Datum', skipOffstage: false), findsWidgets);
      expect(find.text('Tijd', skipOffstage: false), findsWidgets);
      expect(_treeKey(kCustomerBookingVehiclesNeedRideKey), findsOneWidget);
      expect(find.byKey(customerBookingVehicleKey('vh_tesla')), findsNothing);
      expect(
        find.byKey(customerBookingVehicleKey('vh_cadillac')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'heen en terug shows return date/time fields and hides faded cars',
    (tester) async {
      await _pumpFlow(
        tester,
        size: const Size(800, 1280),
        entry: const CustomerBookingEntryContext(
          kind: CustomerBookingKind.taxi,
          company: CustomerBookingCompany(
            partnerId: 'partner_demo',
            companyName: 'All-in Taxi',
            vehicles: <Map<String, dynamic>>[
              <String, dynamic>{
                'vehicle_id': 'vh_tesla',
                'name': 'Tesla',
                'vehicle_type': 'sedan',
                'passenger_capacity': 3,
              },
              <String, dynamic>{
                'vehicle_id': 'vh_cadillac',
                'name': 'Cadillac',
                'vehicle_type': 'sedan',
                'passenger_capacity': 4,
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
        ),
        profileGet: (uri) async {
          if (uri.path.contains('availability')) {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'ok': true,
                'vehicles': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'vehicle_id': 'vh_tesla',
                    'available': false,
                    'reason': 'assignment_driver_outside_hours',
                  },
                  <String, dynamic>{
                    'vehicle_id': 'vh_cadillac',
                    'available': true,
                    'driver_id': 'drv_wotan',
                    'driver': <String, dynamic>{
                      'driver_id': 'drv_wotan',
                      'first_name': 'Wotan',
                      'public_photo_url': 'https://example.com/wotan.jpg',
                    },
                  },
                ],
              }),
              200,
            );
          }
          return http.Response('partner_profile_skipped', 404);
        },
      );
      await _expandSheetIfPresent(tester);
      await _scrollFormTo(tester, find.byKey(kCustomerBookingAddReturnKey));
      await tester.tap(find.byKey(kCustomerBookingAddReturnKey));
      await tester.pumpAndSettle();
      expect(find.byKey(kCustomerBookingReturnDateKey), findsOneWidget);
      expect(find.byKey(kCustomerBookingReturnTimeKey), findsOneWidget);
      expect(find.byKey(kCustomerBookingReturnClockRowKey), findsOneWidget);
      final dateRect = tester.getRect(
        find.byKey(kCustomerBookingReturnDateKey),
      );
      final timeRect = tester.getRect(
        find.byKey(kCustomerBookingReturnTimeKey),
      );
      expect((dateRect.width - timeRect.width).abs(), lessThan(12));
      expect((dateRect.top - timeRect.top).abs(), lessThan(4));
      expect(find.text('Datum terugrit'), findsOneWidget);
      expect(find.text('Tijd terugrit'), findsOneWidget);
      expect(find.text('Heenrit'), findsWidgets);
      expect(find.text('Terugrit'), findsWidgets);
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Buiten werkuren'), findsNothing);
      expect(find.text('Overlappende rit'), findsNothing);
      expect(find.byKey(customerBookingVehicleKey('vh_tesla')), findsNothing);
      expect(
        find.byKey(customerBookingVehicleKey('vh_cadillac')),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'phone compact keeps company and vehicle, addresses after expand',
    (tester) async {
      await _pumpFlow(
        tester,
        entry: const CustomerBookingEntryContext(
          kind: CustomerBookingKind.taxi,
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
        ),
      );
      expect(_treeKey(kCustomerBookingCompactSummaryKey), findsOneWidget);
      expect(_treeKey(kCustomerBookingCompanyChooseKey), findsWidgets);
      expect(_treeText('Kies een taxibedrijf'), findsWidgets);
      expect(find.text('Prijs opnieuw berekenen'), findsNothing);
      expect(find.byKey(kCustomerBookingPaxIncKey), findsNothing);
      expect(find.byKey(kCustomerBookingMapPickupChipKey), findsOneWidget);
      expect(find.byKey(kCustomerBookingMapDropoffChipKey), findsOneWidget);
      expect(find.text('Waar ophalen?'), findsOneWidget);
      expect(find.text('Waar wil je naartoe?'), findsOneWidget);
      expect(find.byKey(kCustomerBookingSheetToggleKey), findsNothing);
      expect(find.byKey(kCustomerBookingAddReturnKey), findsWidgets);
      await _expandSheetIfPresent(tester);
      await tester.ensureVisible(find.byKey(kCustomerBookingPaxSummaryKey));
      await tester.tap(find.byKey(kCustomerBookingPaxSummaryKey));
      await tester.pump();
      expect(_treeKey(kCustomerBookingPaxIncKey), findsOneWidget);
    },
  );

  testWidgets('phone sheet grows from compact to full under the header', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      size: const Size(390, 844),
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
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
      ),
    );
    final compact = tester.getRect(find.byKey(kCustomerBookingSheetKey));
    await _dragSheet(tester, -280);
    final expanded = tester.getRect(find.byKey(kCustomerBookingSheetKey));
    expect(expanded.height, greaterThan(compact.height + 80));
    expect(expanded.top, lessThan(compact.top - 80));
    expect(find.byKey(kCustomerBookingSheetToggleKey), findsNothing);
    await _dragSheet(tester, 280);
    final lowered = tester.getRect(find.byKey(kCustomerBookingSheetKey));
    expect(lowered.height, lessThan(expanded.height - 40));
  });

  testWidgets('airport photo card collapses to a changeable selected card', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      size: const Size(800, 1280),
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.airport,
        company: CustomerBookingCompany(
          partnerId: 'partner_demo',
          companyName: 'All-in Taxi',
        ),
        pickup: CustomerBookingPlace(
          address: 'A Straat 1, Brussel',
          latitude: 50.85,
          longitude: 4.35,
        ),
      ),
    );
    await tester.tap(find.byKey(customerBookingAirportCardKey('BRU')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(kCustomerBookingAirportSelectedKey), findsOneWidget);
    expect(find.text('Wijzigen'), findsWidgets);
    expect(find.byKey(customerBookingAirportCardKey('CRL')), findsNothing);
  });

  testWidgets('sheet drag does not start a new quote', (tester) async {
    var quotes = 0;
    await _pumpFlow(
      tester,
      quotes: _quotes(
        onPost: (path) {
          if (path.contains('quote')) quotes += 1;
        },
      ),
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        company: CustomerBookingCompany(
          partnerId: 'partner_demo',
          companyName: 'All-in Taxi',
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
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    final before = quotes;
    final mapBefore = tester.getRect(find.byKey(kCustomerBookingMapKey));
    final insetsBefore = customerBookingMapFitInsets(
      wide: false,
      height: 844,
      sheetExtent:
          tester.getRect(find.byKey(kCustomerBookingSheetKey)).height / 844,
    );
    await _dragSheet(tester, 160);
    await tester.pump(const Duration(milliseconds: 500));
    expect(quotes, before);
    final lowered = tester.getRect(find.byKey(kCustomerBookingSheetKey));
    expect(lowered.height, lessThan(500));
    final insetsAfter = customerBookingMapFitInsets(
      wide: false,
      height: 844,
      sheetExtent: lowered.height / 844,
    );
    expect(insetsAfter.bottom, lessThan(insetsBefore.bottom));
    expect(mapBefore.height, greaterThan(80));
  });

  testWidgets(
    'header has title without Fluxidi logo and missing logo is neutral',
    (tester) async {
      await _pumpFlow(
        tester,
        entry: const CustomerBookingEntryContext(
          kind: CustomerBookingKind.taxi,
          company: CustomerBookingCompany(
            partnerId: 'partner_demo',
            companyName: 'Demo Taxi',
          ),
        ),
      );
      expect(find.byKey(kCustomerBookingTitleKey), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.byType(Image)),
        findsNothing,
      );
      expect(find.byKey(kCustomerBookingCompanyChangeKey), findsNothing);
      expect(
        find.byKey(kCustomerBookingCompanyLogoFallbackKey),
        findsOneWidget,
      );
    },
  );

  testWidgets('company banner uses published media.logo_url with contain', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        company: CustomerBookingCompany(
          partnerId: 'partner_demo',
          companyName: 'Demo Taxi',
        ),
      ),
      profileGet: (uri) async {
        if (uri.path.contains('availability')) {
          return _defaultProfileGet()(uri);
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'company_name': 'Demo Taxi',
            'media': <String, dynamic>{
              'logo_url': 'https://cdn.example/demo-logo.png',
            },
            'vehicles': <Map<String, dynamic>>[
              <String, dynamic>{
                'vehicle_id': 'vh_1',
                'name': 'Sedan',
                'vehicle_type': 'sedan',
                'passenger_capacity': 3,
                'is_active': true,
              },
            ],
          }),
          200,
        );
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byKey(kCustomerBookingCompanyLogoImageKey), findsOneWidget);
    final image = tester.widget<Image>(
      find.byKey(kCustomerBookingCompanyLogoImageKey),
    );
    expect(image.fit, BoxFit.contain);
    expect(image.width, kCustomerBookingCompanyLogoWidth);
    expect(image.height, kCustomerBookingCompanyLogoHeight);
    expect(kCustomerBookingCompanyLogoWidth, inInclusiveRange(100, 120));
    expect(kCustomerBookingCompanyLogoHeight, inInclusiveRange(40, 48));
  });

  testWidgets(
    'map metrics badge sits above the sheet with full duration text',
    (tester) async {
      await _pumpFlow(
        tester,
        entry: const CustomerBookingEntryContext(
          kind: CustomerBookingKind.taxi,
          company: CustomerBookingCompany(
            partnerId: 'partner_demo',
            companyName: 'Demo Taxi',
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
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(kCustomerBookingMetricsBadgeKey), findsOneWidget);
      expect(find.text('22 min · 14,2 km'), findsOneWidget);
      final badge = tester.getRect(find.byKey(kCustomerBookingMetricsBadgeKey));
      final sheet = tester.getRect(find.byKey(kCustomerBookingSheetKey));
      expect(badge.bottom, lessThanOrEqualTo(sheet.top + 4));
      expect(badge.left, lessThan(80));
    },
  );

  testWidgets('phone airport has no arrival margin and one ready-at row', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.airport,
        toAirport: true,
        airport: AirportCatalogAirport(
          countryCode: 'BE',
          countryName: 'België',
          city: 'Brussel',
          name: 'Brussels Airport',
          iata: 'BRU',
          latitude: 50.9014,
          longitude: 4.4844,
        ),
        pickup: CustomerBookingPlace(
          address: 'A Straat 1, Brussel',
          latitude: 50.85,
          longitude: 4.35,
        ),
      ),
    );
    expect(find.byKey(kCustomerBookingArrivalMarginKey), findsNothing);
    expect(find.text('Arrival margin before the flight'), findsNothing);
    expect(find.byKey(kCustomerBookingTaxiReadyAtKey), findsOneWidget);
    expect(find.text('Taxi staat klaar op'), findsOneWidget);
    expect(find.byKey(kCustomerBookingDateKey), findsOneWidget);
    expect(find.byKey(kCustomerBookingTimeKey), findsOneWidget);
    expect(find.byKey(kCustomerBookingFlightDateKey), findsNothing);
    expect(find.text('Vul een bestemming in'), findsNothing);
    expect(find.byKey(kCustomerBookingDropoffKey), findsNothing);
    expect(find.byKey(kCustomerBookingAirportSelectedKey), findsOneWidget);
  });

  testWidgets('incomplete ride hides vehicle and disables confirm', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        company: CustomerBookingCompany(
          partnerId: 'partner_demo',
          companyName: 'All-in Taxi',
          vehicles: <Map<String, dynamic>>[
            <String, dynamic>{
              'vehicle_id': 'vh_old',
              'name': 'Minivan',
              'vehicle_type': 'minivan',
            },
          ],
        ),
      ),
    );
    expect(find.byKey(customerBookingVehicleKey('vh_old')), findsNothing);
    expect(find.text('Minivan'), findsNothing);
    expect(find.byKey(kCustomerBookingPriceKey), findsNothing);
    final confirm = tester.widget<FilledButton>(
      find.byKey(kCustomerBookingConfirmKey),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets('changing destination clears the previous vehicle and price', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        company: CustomerBookingCompany(
          partnerId: 'partner_demo',
          companyName: 'All-in Taxi',
          vehicles: <Map<String, dynamic>>[
            <String, dynamic>{
              'vehicle_id': 'vh_tesla',
              'name': 'Tesla',
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
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.enterText(
      find.byKey(kCustomerBookingDropoffKey),
      'C Straat 9, Antwerpen',
    );
    await tester.pump();
    expect(find.byKey(customerBookingVehicleKey('vh_tesla')), findsNothing);
    expect(find.byKey(kCustomerBookingPriceKey), findsNothing);
  });

  testWidgets('saved profile address fills pickup for a returning customer', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      autoResolveGps: true,
      gps: _gpsGranted(),
      profile: CustomerProfile(
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
      ),
      entry: const CustomerBookingEntryContext(kind: CustomerBookingKind.taxi),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('Koekamerstraat 488A', skipOffstage: false),
      findsWidgets,
    );
  });
}
