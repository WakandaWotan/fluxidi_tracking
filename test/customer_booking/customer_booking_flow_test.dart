import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_search.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_plan_airport_cards.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_flow.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
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
    getCurrentPosition: (_) async => const LimousineCurrentLocationFix(
      latitude: 50.85,
      longitude: 4.35,
    ),
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
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    expect(find.byKey(kCustomerBookingGpsFallbackKey), findsOneWidget);
    expect(find.byKey(kCustomerBookingPickupKey), findsOneWidget);
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
    expect(find.text('GPS Straat 12, Brussel'), findsWidgets);
  });

  testWidgets('airport entry opens airport mode with airplane and cards', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      entry: const CustomerBookingEntryContext(kind: CustomerBookingKind.airport),
    );
    expect(find.byKey(kCustomerBookingAirplaneVisualKey), findsOneWidget);
    expect(find.byKey(kCustomerBookingToAirportKey), findsOneWidget);
    expect(find.byKey(kCustomerBookingFromAirportKey), findsOneWidget);
    for (final iata in kCompanyPlanFeaturedAirportIata) {
      expect(find.byKey(customerBookingAirportCardKey(iata)), findsOneWidget);
    }
  });

  testWidgets('Belgian photo card writes the same KJK record as the catalog', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      entry: const CustomerBookingEntryContext(kind: CustomerBookingKind.airport),
    );
    await tester.ensureVisible(find.byKey(customerBookingAirportCardKey('KJK')));
    await tester.tap(find.byKey(customerBookingAirportCardKey('KJK')));
    await tester.pump();
    expect(find.byKey(kCustomerBookingAirportSummaryKey), findsOneWidget);
    expect(find.textContaining('KJK'), findsWidgets);
    expect(find.textContaining(airportByIata('KJK')!.name), findsWidgets);
    expect(find.byKey(kCustomerBookingAirplaneVisualKey), findsOneWidget);
  });

  testWidgets('Andere luchthaven opens country then airport lists', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      entry: const CustomerBookingEntryContext(kind: CustomerBookingKind.airport),
    );
    expect(find.text('Andere luchthaven'), findsOneWidget);
    expect(find.text('Alle luchthavens bekijken'), findsOneWidget);
    await tester.ensureVisible(find.byKey(customerBookingAirportCardKey('other')));
    await tester.tap(find.byKey(customerBookingAirportCardKey('other')));
    await tester.pumpAndSettle();
    expect(find.byKey(kCustomerBookingChooseCountryKey), findsOneWidget);
    expect(find.text('Kies je land'), findsOneWidget);
    expect(find.byKey(kCustomerBookingChooseAirportKey), findsOneWidget);
    expect(find.text('Kies je luchthaven'), findsOneWidget);
    await tester.ensureVisible(find.byKey(customerBookingCountryKey('NL')));
    await tester.tap(find.byKey(customerBookingCountryKey('NL')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(kCustomerBookingAirportSearchKey));
    await tester.enterText(find.byKey(kCustomerBookingAirportSearchKey), 'AMS');
    await tester.pump();
    expect(find.byKey(customerBookingAirportListKey('AMS')), findsOneWidget);
    expect(find.byKey(kCustomerBookingAirplaneVisualKey), findsOneWidget);
  });

  testWidgets('from-airport shows landing hint and hides to-airport late warning', (
    tester,
  ) async {
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
    await tester.ensureVisible(find.byKey(kCustomerBookingLandingHintKey));
    expect(find.byKey(kCustomerBookingLandingHintKey), findsOneWidget);
    expect(find.byKey(kCustomerBookingFlightNumberKey), findsOneWidget);
  });

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
    expect(find.text('Anspachlaan 1, Brussel'), findsWidgets);
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
    expect(find.text('Rogierplein 2, Brussel'), findsWidgets);
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
    expect(find.byKey(kCustomerBookingStreetModeKey), findsOneWidget);
    expect(find.byKey(kCustomerBookingAirportModeKey), findsOneWidget);
    expect(find.byKey(kCustomerBookingCompanyLockKey), findsOneWidget);
    expect(find.byKey(kCustomerBookingAirplaneVisualKey), findsNothing);
    await tester.tap(find.byKey(kCustomerBookingAirportModeKey));
    await tester.pump();
    expect(find.byKey(kCustomerBookingAirplaneVisualKey), findsOneWidget);
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
    await tester.ensureVisible(find.text('Heen en terug met wachten'));
    await tester.tap(find.text('Heen en terug met wachten'));
    await tester.pump();
    expect(find.byKey(customerBookingWaitChipKey(30)), findsOneWidget);
    await tester.tap(find.byKey(kCustomerBookingAddStopKey).first);
    await tester.pump();
    expect(find.byKey(customerBookingStopKey(0)), findsOneWidget);
    expect(find.byKey(kCustomerBookingConfirmKey), findsOneWidget);
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

  testWidgets('calculator off shows price on request without inventing a fare', (
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
  });

  testWidgets('quote errors keep the typed draft and offer retry', (tester) async {
    await _pumpFlow(
      tester,
      size: const Size(800, 1280),
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
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
    final increment = find.byKey(kCustomerBookingPaxIncKey);
    expect(increment, findsOneWidget);
    for (var i = 0; i < 7; i++) {
      tester.widget<IconButton>(increment).onPressed?.call();
      await tester.pump();
    }
    expect(find.textContaining('groter voertuig'), findsOneWidget);
  });

  testWidgets('phone and tablet layouts keep the confirm button', (tester) async {
    for (final size in const <Size>[
      Size(390, 844),
      Size(800, 1280),
    ]) {
      await _pumpFlow(
        tester,
        entry: const CustomerBookingEntryContext(kind: CustomerBookingKind.taxi),
        size: size,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(kCustomerBookingConfirmKey), findsOneWidget);
      if (size.width >= 720) {
        expect(find.byKey(kCustomerBookingWideSplitKey), findsOneWidget);
      } else {
        expect(find.byKey(kCustomerBookingNarrowStackKey), findsOneWidget);
        expect(find.byKey(kCustomerBookingWideSplitKey), findsNothing);
        final map = tester.getRect(find.byKey(kCustomerBookingMapKey));
        final confirm = tester.getRect(find.byKey(kCustomerBookingConfirmKey));
        expect(confirm.top, greaterThanOrEqualTo(map.bottom - 1));
      }
    }
  });

  testWidgets('wide booking layout keeps the map beside the form', (tester) async {
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
    expect(find.byKey(kCustomerBookingWideSplitKey), findsOneWidget);
    final form = tester.getRect(find.byKey(kCustomerBookingFormKey));
    final map = tester.getRect(find.byKey(kCustomerBookingMapKey));
    final confirm = tester.getRect(find.byKey(kCustomerBookingConfirmKey));
    expect(map.left, greaterThan(form.right - 8));
    expect(map.width, greaterThan(480));
    expect(confirm.top, greaterThanOrEqualTo(map.bottom - 1));
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

  testWidgets('scheduled pickup time from home is not replaced by flight time', (
    tester,
  ) async {
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
  });

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
    expect(find.text('Boeking bevestigen'), findsOneWidget);
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
    await tester.tap(find.byKey(kCustomerBookingConfirmKey));
    await tester.pump();
    expect(find.byKey(kCustomerBookingSubmitErrorKey), findsOneWidget);
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
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(kCustomerBookingContactSummaryKey), findsOneWidget);
    await tester.ensureVisible(find.byKey(kCustomerBookingConfirmKey));
    await tester.tap(find.byKey(kCustomerBookingConfirmKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCustomerBookingPaymentPageKey), findsOneWidget);
    expect(books, 0);
    expect(find.byKey(kCustomerBookingPaymentConfirmKey), findsOneWidget);
    await tester.ensureVisible(find.byKey(kCustomerBookingPaymentConfirmKey));
    await tester.tap(find.byKey(kCustomerBookingPaymentConfirmKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(kCustomerBookingSubmitErrorKey), findsNothing);
    expect(find.byKey(kCustomerBookingSuccessKey), findsOneWidget);
    expect(find.textContaining('All-in Taxi Christophe Vanroeghem'), findsWidgets);
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
      ),
    );
    expect(find.byKey(kCustomerBookingAirportChromeKey), findsOneWidget);
    expect(find.byKey(kCustomerBookingToAirportKey), findsOneWidget);
    expect(find.byKey(customerBookingAirportCardKey('BRU')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(kCustomerBookingVehicleHintKey),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Premium'), findsOneWidget);
    expect(find.byKey(customerBookingVehicleKey('vh_premium')), findsOneWidget);
    expect(find.byKey(customerBookingVehicleKey('minivan')), findsNothing);
    final chrome = tester.getRect(find.byKey(kCustomerBookingAirportChromeKey));
    final map = tester.getRect(find.byKey(kCustomerBookingMapKey));
    expect(map.bottom, lessThanOrEqualTo(chrome.top + 1));
  });

  testWidgets('profile address and GPS actions do not overwrite a chosen pickup', (
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
    expect(find.text('Handmatig vertrek 9, Ronse'), findsWidgets);
    expect(find.textContaining('GPS Straat'), findsNothing);
    expect(find.byKey(kCustomerBookingMyAddressKey), findsOneWidget);
    await tester.tap(find.byKey(kCustomerBookingMyAddressKey));
    await tester.pump();
    expect(find.textContaining('Koekamerstraat 488A'), findsWidgets);
  });

  testWidgets('private ride is default and business fields open on both modes', (
    tester,
  ) async {
    for (final kind in const <CustomerBookingKind>[
      CustomerBookingKind.taxi,
      CustomerBookingKind.airport,
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _pumpFlow(
        tester,
        entry: CustomerBookingEntryContext(kind: kind),
      );
      expect(find.byKey(kCustomerBookingPrivateRideKey), findsOneWidget);
      expect(find.byKey(kCustomerBookingBusinessRideKey), findsOneWidget);
      expect(find.text('Particuliere rit'), findsOneWidget);
      expect(find.text('Zakelijke rit'), findsOneWidget);
      expect(find.text('Bedrijfsnaam'), findsNothing);
      final business = find.byKey(kCustomerBookingBusinessRideKey);
      expect(business, findsOneWidget);
      await tester.ensureVisible(business);
      await tester.pump();
      await tester.tap(business);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        find.byKey(bookingBillingFieldKey(BookingBillingFormField.legalName)),
        findsOneWidget,
      );
    }
  });

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
      expect(find.byKey(kCustomerBookingPrivateRideKey), findsOneWidget);
      expect(find.byKey(kCustomerBookingBusinessRideKey), findsOneWidget);
      expect(find.text('Particuliere rit'), findsWidgets);
      expect(find.text('Zakelijke rit'), findsWidgets);
      expect(find.text('Naar de luchthaven'), findsWidgets);
      expect(find.text('Alle luchthavens bekijken'), findsWidgets);
      expect(find.text('Boeking bevestigen'), findsWidgets);
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
    await tester.scrollUntilVisible(
      find.byKey(kCustomerBookingVehiclesNeedRideKey),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(kCustomerBookingVehiclesNeedRideKey), findsOneWidget);
    expect(
      find.text('This company has no bookable vehicle categories for this ride.'),
      findsNothing,
    );
    expect(
      find.text('This company has no suitable vehicles for this ride.'),
      findsNothing,
    );
    expect(find.text('A driver will be assigned soon'), findsNothing);
  });

  testWidgets('Nu and Later sit under Particulier/Zakelijk and expose Datum/Tijd', (
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
    final private = tester.getTopLeft(find.byKey(kCustomerBookingPrivateRideKey));
    final later = tester.getTopLeft(find.byKey(kCustomerBookingLaterKey));
    expect(later.dy, greaterThan(private.dy));
    expect(find.byKey(kCustomerBookingDateKey), findsNothing);
    await tester.tap(find.byKey(kCustomerBookingLaterKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCustomerBookingDateKey), findsOneWidget);
    expect(find.byKey(kCustomerBookingTimeKey), findsOneWidget);
    expect(find.text('Datum'), findsWidgets);
    expect(find.text('Tijd'), findsWidgets);
    expect(find.byKey(customerBookingVehicleKey('vh_tesla')), findsOneWidget);
    expect(find.byKey(customerBookingVehicleKey('vh_cadillac')), findsOneWidget);
    expect(find.text('3 passagiers'), findsOneWidget);
    expect(find.text('4 passagiers'), findsOneWidget);
  });
}
