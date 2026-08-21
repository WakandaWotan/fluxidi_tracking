import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/airport/airport_catalog.generated.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/airport/airport_selector.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_airport_transfer_fields.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_hotel_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_hotel_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_transfer_endpoint.dart';

AirportCatalogAirport _bru([List<AirportCatalogAirport>? catalog]) {
  return airportByIata('BRU', countryCode: 'BE', airports: catalog)!;
}

AirportCatalogAirport _ams([List<AirportCatalogAirport>? catalog]) {
  return airportByIata('AMS', countryCode: 'NL', airports: catalog)!;
}

LimousinePublishedOffer _offer() {
  return LimousinePublishedOffer.fromJson(<String, dynamic>{
    'offer_id': 'off_1',
    'target_type': 'vehicle',
    'vehicle_id': 'veh_1',
    'service_class_id': 'executive_sedan',
    'title': {'nl': 'Executive', 'en': 'Executive'},
    'description': {'nl': 'Incl. btw', 'en': 'Incl. VAT'},
    'journey_types': ['airport_transfer', 'hotel_transfer', 'point_to_point'],
    'price_presentation': 'quote_required',
    'display_amount_cents': 45000,
    'currency': 'EUR',
    'vehicle': {'passenger_capacity': 3, 'luggage_capacity': 2},
  });
}

LimousineAddressValue _address(String label) => LimousineAddressValue(
  displayText: label,
  canonicalLabel: label,
  lat: 51.05,
  lon: 3.72,
  placeId: 'address.gent',
  acceptance: LimousineAddressAcceptance.selected,
);

LimousineHotelSuggestion _hotelSuggestion() => const LimousineHotelSuggestion(
  name: 'Hotel de Ville',
  formattedAddress: 'Botermarkt 1, 9000 Gent, Belgium',
  latitude: 51.0543,
  longitude: 3.722,
  providerPlaceId: 'poi.hotel.1',
  city: 'Gent',
  postcode: '9000',
  countryCode: 'BE',
);

class _HotelLookup extends LimousineHotelLookup {
  _HotelLookup({this.delay = Duration.zero, this.error = false, this.empty = false})
    : super(
        searchOverride: (query, language) async {
          searches += 1;
          lastQuery = query;
          lastLanguage = language;
          if (delay > Duration.zero) {
            await Future<void>.delayed(delay);
          }
          if (error) {
            return const LimousineHotelLookupResult(hadError: true);
          }
          if (empty) {
            return const LimousineHotelLookupResult();
          }
          return LimousineHotelLookupResult(suggestions: [_hotelSuggestion()]);
        },
      );

  static int searches = 0;
  static String lastQuery = '';
  static String lastLanguage = '';
  final Duration delay;
  final bool error;
  final bool empty;
}

class _Gateway with LimousineCustomerQuoteGateway {
  int createCalls = 0;
  int bookCalls = 0;
  LimousineQuoteCreateDraft? lastDraft;

  @override
  Future<List<LimousineDiscoveredProvider>> discoverNearby({
    String? postcode,
    double? lat,
    double? lng,
    int radiusKm = 20,
  }) async {
    return const [
      LimousineDiscoveredProvider(
        partnerId: 'p1',
        companyName: 'Coachline',
        limousineAvailable: true,
      ),
    ];
  }

  @override
  Future<LimousineProviderDetail> loadProvider(String publicPartnerId) async {
    return LimousineProviderDetail(
      provider: const LimousineDiscoveredProvider(
        partnerId: 'p1',
        companyName: 'Coachline',
        limousineAvailable: true,
      ),
      offers: [_offer()],
    );
  }

  @override
  Future<LimousineQuoteCreateResult> createRequest(
    LimousineQuoteCreateDraft draft,
  ) async {
    createCalls += 1;
    lastDraft = draft;
    return LimousineQuoteCreateResult(
      request: LimousineQuoteRequest.fromJson(<String, dynamic>{
        'quote_request_id': 'limq_1',
        'state': 'requested',
        'revision': 1,
        'offer_id': draft.offerId,
        'journey_type': draft.journeyType,
        'from': draft.from,
        'to': draft.to,
        'scheduled_pickup_iso': draft.scheduledPickupIso,
      }),
    );
  }

  @override
  Future<LimousineBookingRequestResult> createBookingRequest(
    LimousineQuoteCreateDraft draft,
  ) async {
    bookCalls += 1;
    lastDraft = draft;
    return const LimousineBookingRequestResult(bookingId: 'b1');
  }

  @override
  Future<LimousineQuoteRequest> pollStatus(String statusRef) async {
    throw const LimousineCustomerQuoteException(code: 'not_found');
  }

  @override
  Future<LimousineQuoteAcceptResult> accept({
    required String quoteRequestId,
    required int expectedRevision,
    required int termsRevision,
  }) async {
    throw const LimousineCustomerQuoteException(code: 'not_found');
  }
}

Widget _app(Widget child) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: kLimousineSmX400Portrait),
      child: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _HotelLookup.searches = 0;
    _HotelLookup.lastQuery = '';
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
    appLanguageNotifier.value = AppLanguage.nl;
  });

  test('1/2) limousine and airport transport share the same catalog source', () {
    final catalog = publishedAirportCatalog();
    expect(identical(kAirportCatalog, kAirportCatalog), isTrue);
    final generatedIata = kAirportCatalog
        .where(
          (entry) =>
              kSupportedAirportCountryCodes.contains(entry.countryCode) &&
              entry.iata.trim().length == 3,
        )
        .map((entry) => entry.iata)
        .toSet();
    expect(catalog.map((airport) => airport.iata).toSet(), generatedIata);
    expect(catalog, isNotEmpty);
    expect(publishedAirportCountryCodes(catalog).toSet(), kSupportedAirportCountryCodes);
    for (final iata in kRequiredAirportIata) {
      expect(airportByIata(iata, airports: catalog), isNotNull, reason: iata);
    }
    final airportPage = File('lib/airport/airport_page.dart').readAsStringSync();
    final limousinePage = File(
      'lib/limousine/limousine_customer_quote_page.dart',
    ).readAsStringSync();
    expect(airportPage.contains('publishedAirportCatalog()'), isTrue);
    expect(limousinePage.contains('publishedAirportCatalog()'), isTrue);
    expect(airportPage.contains('kAirportCatalog ='), isFalse);
    expect(limousinePage.contains('kAirportCatalog ='), isFalse);
    expect(
      File('lib/airport/airport_catalog_repository.dart').readAsStringSync(),
      contains('kAirportCatalog'),
    );
  });

  test('3/4) airport direction fills destination or pickup as a typed endpoint', () {
    final airport = _bru();
    final other = limousineEndpointFromAddress(_address('Korenmarkt 1, Gent'));
    final toAirport = applyAirportDirection(
      direction: 'to_airport',
      airport: airport,
      other: other,
    );
    expect(toAirport.to?.kind, LimousineTransferEndpointKind.airport);
    expect(toAirport.to?.iataCode, 'BRU');
    expect(toAirport.from?.kind, LimousineTransferEndpointKind.address);
    expect(toAirport.airportDirection, 'to_airport');

    final fromAirport = applyAirportDirection(
      direction: 'from_airport',
      airport: airport,
      other: other,
    );
    expect(fromAirport.from?.kind, LimousineTransferEndpointKind.airport);
    expect(fromAirport.from?.iataCode, 'BRU');
    expect(fromAirport.to?.kind, LimousineTransferEndpointKind.address);
    expect(fromAirport.airportDirection, 'from_airport');
    expect(limousineAirportEndpointIsCanonical(fromAirport.from!), isTrue);
  });

  test('5) country change clears an incompatible airport', () {
    final current = applyAirportDirection(
      direction: 'to_airport',
      airport: _bru(),
      other: limousineEndpointFromAddress(_address('Gent')),
    );
    final cleared = clearIncompatibleAirportOnCountryChange(
      current: current,
      countryCode: 'NL',
    );
    expect(cleared.to?.kind, isNot(LimousineTransferEndpointKind.airport));
    expect(cleared.to?.iataCode, isNull);
    expect(cleared.to?.formattedAddress, isNotEmpty);
  });

  testWidgets('6/7) hotel search opens, debounces, and shows loading/empty/error', (
    tester,
  ) async {
    final lookup = _HotelLookup(delay: const Duration(milliseconds: 40));
    final controller = LimousineHotelFieldController(
      lookup: lookup,
      debounce: const Duration(milliseconds: 40),
    );
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: LimousineHotelField(
            controller: controller,
            label: 'Hotel',
            tokens: LimousineUxTokens.fromSurface(background: Colors.white),
            language: AppLanguage.nl,
          ),
        ),
      ),
    );
    expect(find.byKey(kLimousineHotelFieldKey), findsOneWidget);
    await tester.enterText(find.byKey(kLimousineHotelInputKey), 'Ho');
    await tester.pump();
    expect(_HotelLookup.searches, 0);
    await tester.enterText(find.byKey(kLimousineHotelInputKey), 'Hotel de Ville Gent');
    await tester.pump();
    expect(find.byKey(kLimousineHotelLoadingKey), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 20));
    expect(_HotelLookup.searches, 0);
    await tester.pump(const Duration(milliseconds: 40));
    expect(_HotelLookup.searches, 1);
    await tester.pump(const Duration(milliseconds: 50));
    expect(_HotelLookup.lastQuery, contains('Hotel de Ville'));
    expect(find.byKey(limousineHotelSuggestionKey(0)), findsOneWidget);

    final emptyController = LimousineHotelFieldController(
      lookup: _HotelLookup(empty: true),
      debounce: Duration.zero,
    );
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: LimousineHotelField(
            controller: emptyController,
            label: 'Hotel',
            tokens: LimousineUxTokens.fromSurface(background: Colors.white),
            language: AppLanguage.en,
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(kLimousineHotelInputKey), 'Unknown Inn');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.byKey(kLimousineHotelEmptyKey), findsOneWidget);

    final errorController = LimousineHotelFieldController(
      lookup: _HotelLookup(error: true),
      debounce: Duration.zero,
    );
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: LimousineHotelField(
            controller: errorController,
            label: 'Hotel',
            tokens: LimousineUxTokens.fromSurface(background: Colors.white),
            language: AppLanguage.fr,
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(kLimousineHotelInputKey), 'Hotel Error');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.byKey(kLimousineHotelErrorKey), findsOneWidget);
    controller.dispose();
    emptyController.dispose();
    errorController.dispose();
  });

  test('8) chosen hotel stores name, address, coordinates and provider id', () {
    final endpoint = _hotelSuggestion().toEndpoint();
    expect(endpoint.kind, LimousineTransferEndpointKind.hotel);
    expect(endpoint.hotelName, 'Hotel de Ville');
    expect(endpoint.formattedAddress, contains('Gent'));
    expect(endpoint.latitude, 51.0543);
    expect(endpoint.longitude, 3.722);
    expect(endpoint.providerPlaceId, 'poi.hotel.1');
    expect(endpoint.ratehawkHotelId, isNull);
    expect(limousineHotelEndpointIsUsable(endpoint), isTrue);
  });

  test('9) manual hotel address is marked as fallback', () {
    final manual = limousineManualHotelEndpoint('Korenmarkt 1, 9000 Gent');
    expect(manual.kind, LimousineTransferEndpointKind.hotel);
    expect(manual.manual, isTrue);
    expect(manual.ratehawkHotelId, isNull);
    expect(limousineHotelEndpointIsUsable(manual), isTrue);
  });

  test('10) roundtrip reverses typed endpoints', () {
    final reversed = reverseLimousineEndpoints(
      from: limousineEndpointFromAddress(_address('Gent')),
      to: limousineEndpointFromAirport(_bru()),
    );
    expect(reversed.from.kind, LimousineTransferEndpointKind.airport);
    expect(reversed.from.iataCode, 'BRU');
    expect(reversed.to.kind, LimousineTransferEndpointKind.address);
  });

  test('11) review shows airport and hotel labels', () {
    final airport = limousineEndpointFromAirport(_ams());
    final hotel = _hotelSuggestion().toEndpoint();
    final rows = buildLimousineRequestReviewRows(
      draft: LimousineQuoteCreateDraft(
        journeyType: 'airport_transfer',
        from: 'Gent',
        to: airport.routeText,
        fromEndpoint: limousineEndpointFromAddress(_address('Gent')),
        toEndpoint: airport,
        scheduledPickupIso: '2026-09-01T10:00:00Z',
      ),
      language: AppLanguage.en,
    );
    expect(
      rows.firstWhere((row) => row.id == 'route').value,
      contains('AMS'),
    );
    final hotelRows = buildLimousineRequestReviewRows(
      draft: LimousineQuoteCreateDraft(
        journeyType: 'hotel_transfer',
        from: 'Gent',
        to: hotel.routeText,
        fromEndpoint: limousineEndpointFromAddress(_address('Gent')),
        toEndpoint: hotel,
        scheduledPickupIso: '2026-09-01T10:00:00Z',
      ),
      language: AppLanguage.nl,
    );
    expect(
      hotelRows.firstWhere((row) => row.id == 'route').value,
      contains('Hotel de Ville'),
    );
  });

  test('12/13/15) quote and book payloads keep typed snapshot and cannot override totals', () {
    final draft = LimousineQuoteCreateDraft(
      publicPartnerId: 'p1',
      offerId: 'off_1',
      journeyType: 'airport_transfer',
      from: 'Korenmarkt 1, Gent',
      to: _bru().formattedAddress,
      scheduledPickupIso: '2026-09-01T10:00:00Z',
      airportDirection: 'to_airport',
      fromEndpoint: limousineEndpointFromAddress(_address('Korenmarkt 1, Gent')),
      toEndpoint: limousineEndpointFromAirport(_bru()),
      locale: 'nl',
    );
    final quote = limousineCustomerCreateBody(draft);
    final book = limousineCustomerBookBody(draft);
    expect(quote['from'], isNotEmpty);
    expect(quote['to'], isNotEmpty);
    expect(quote['to_endpoint']['kind'], 'airport');
    expect(quote['to_endpoint']['iata_code'], 'BRU');
    expect(quote['from_endpoint']['kind'], 'address');
    expect(book['service_category'], 'limousine');
    expect(book['to_endpoint']['iata_code'], 'BRU');
    expect(limousineCustomerCreateBodyIsBounded(quote), isTrue);
    expect(limousineCustomerBookBodyIsBounded(book), isTrue);
    for (final body in [quote, book]) {
      expect(body.containsKey('tenant_id'), isFalse);
      expect(body.containsKey('company_id'), isFalse);
      expect(body.containsKey('partner_id'), isFalse);
      expect(body.containsKey('total_incl_vat_cents'), isFalse);
    }
    final frozen = Map<String, dynamic>.from(quote['to_endpoint'] as Map);
    expect(frozen['iata_code'], 'BRU');
    expect(frozen.containsKey('ratehawk_hotel_id'), isTrue);
  });

  test('14) identical drafts stay idempotent', () {
    final draft = LimousineQuoteCreateDraft(
      publicPartnerId: 'p1',
      offerId: 'off_1',
      journeyType: 'hotel_transfer',
      from: 'Gent',
      to: 'Hotel de Ville, Gent',
      scheduledPickupIso: '2026-09-01T10:00:00Z',
      toEndpoint: _hotelSuggestion().toEndpoint(),
      fromEndpoint: limousineEndpointFromAddress(_address('Gent')),
    );
    expect(limousineCustomerCreateBody(draft), limousineCustomerCreateBody(draft));
    expect(limousineCustomerBookBody(draft), limousineCustomerBookBody(draft));
  });

  testWidgets('6) hotel journey opens the hotel searcher on the existing wizard', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LimousineCustomerQuotePage(
          entryEnabled: true,
          gateway: _Gateway(),
          hotelLookup: _HotelLookup(),
          placeLookup: LimousinePlaceLookup(
            searchOverride: (query, language) async {
              return LimousinePlaceLookupResult(
                suggestions: [
                  LimousinePlaceSuggestion(
                    label: query,
                    lat: 51.05,
                    lon: 3.72,
                    placeId: 'address.1',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<InkWell>(
          find.byKey(const ValueKey<String>('limousine_journey_type_hotel_transfer')),
        )
        .onTap!();
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineHotelFieldKey), findsOneWidget);
    expect(find.byKey(kLimousineHotelToDirectionKey), findsOneWidget);
    await tester.enterText(find.byKey(kLimousineHotelInputKey), 'Hotel de Ville Gent');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(_HotelLookup.searches, greaterThan(0));
  });

  testWidgets('airport journey shows shared direction and selector', (tester) async {
    await tester.pumpWidget(
      _app(
        LimousineCustomerQuotePage(
          entryEnabled: true,
          gateway: _Gateway(),
          hotelLookup: _HotelLookup(),
          placeLookup: LimousinePlaceLookup(
            searchOverride: (query, language) async =>
                const LimousinePlaceLookupResult(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<InkWell>(
          find.byKey(
            const ValueKey<String>('limousine_journey_type_airport_transfer'),
          ),
        )
        .onTap!();
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineAirportToDirectionKey), findsOneWidget);
    expect(find.byKey(kLimousineAirportFromDirectionKey), findsOneWidget);
    expect(find.byKey(kSharedAirportCountryDropdownKey), findsOneWidget);
    expect(find.byKey(kSharedAirportAirportDropdownKey), findsOneWidget);
  });

  test('16-19) existing chain stays limousine-only and RateHawk-free', () {
    final hotelLookup = File('lib/limousine/limousine_hotel_lookup.dart').readAsStringSync();
    final endpoint = File('lib/limousine/limousine_transfer_endpoint.dart').readAsStringSync();
    final worker = File(
      'workers/booking/modules/limousine_transfer_endpoint.mjs',
    ).readAsStringSync();
    expect(hotelLookup.contains('RATEHAWK'), isFalse);
    expect(hotelLookup.contains('ratehawk_'), isFalse);
    expect(hotelLookup.contains('kLimousineMapboxSearchHost'), isTrue);
    expect(hotelLookup.contains('searchbox'), isTrue);
    expect(hotelLookup.contains('types=poi'), isFalse);
    expect(endpoint.contains('ratehawk_hotel_id'), isTrue);
    expect(worker.contains('BOOKING_KV'), isFalse);
    expect(worker.contains('CREATE TABLE'), isFalse);
    expect(worker.contains('RATEHAWK_'), isFalse);
    expect(worker.contains('api.ratehawk'), isFalse);
    expect(
      File('lib/limousine/limousine_customer_quote.dart').readAsStringSync(),
      contains("'service_category': 'limousine'"),
    );
    expect(kLimousineCustomerCreateAllowedKeys.contains('from_endpoint'), isTrue);
    expect(kLimousineCustomerForbiddenSubmitKeys.contains('total_incl_vat_cents'), isTrue);
  });

  test('mismatched airport IATA/country is rejected', () {
    final fake = LimousineTransferEndpoint(
      kind: LimousineTransferEndpointKind.airport,
      displayName: 'Not Brussels',
      formattedAddress: 'Somewhere',
      airportName: 'Not Brussels',
      iataCode: 'BRU',
      countryCode: 'NL',
    );
    expect(limousineAirportEndpointIsCanonical(fake), isFalse);
    expect(
      limousineAirportEndpointIsCanonical(limousineEndpointFromAirport(_bru())),
      isTrue,
    );
  });
}
