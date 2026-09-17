import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_addresses.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_company_vehicles.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_price_block.dart';
import 'package:fluxidi_tracking/customer_booking/customer_confirmed_location.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/nearby/public_company_presentation.dart';

void main() {
  test('Schorisse and Maarkedal stay equivalent, Ronse does not', () {
    expect(limousineLocalityNamesCompatible('Schorisse', 'Maarkedal'), isTrue);
    expect(limousineLocalityNamesCompatible('Maarkedal', 'Schorisse'), isTrue);
    expect(limousineLocalityNamesCompatible('Schorisse', 'Ronse'), isFalse);
  });

  test('48A Schorisse does not accept 48 Maarkedal as a proven pin', () {
    const query = 'Koekamerstraat 48A, 9688 Schorisse, BE';
    final resolved = limousineResolveOwnedAddress(
      query: query,
      result: const LimousinePlaceLookupResult(
        suggestions: <LimousinePlaceSuggestion>[
          LimousinePlaceSuggestion(
            label: 'Koekamerstraat 48, 9688 Maarkedal, België',
            lat: 50.77205,
            lon: 3.66942,
            placeType: 'address',
            postcode: '9688',
            locality: 'Maarkedal',
          ),
          LimousinePlaceSuggestion(
            label: 'Koekamerstraat - Rue Cocambre 48a, 9600 Ronse, België',
            lat: 50.770403,
            lon: 3.672568,
            placeType: 'address',
            postcode: '9600',
            locality: 'Ronse',
          ),
        ],
      ),
    );
    expect(resolved.value.displayText, query);
    expect(resolved.value.hasCoordinates, isFalse);
    expect(resolved.value.isRouteReady, isFalse);
    expect(resolved.needsConfirm, isTrue);
    expect(resolved.candidate?.postcode, '9688');
    expect(resolved.candidate?.label.contains('Ronse'), isFalse);
  });

  test('confirmed location keys keep house letter and postcode', () {
    expect(
      customerConfirmedLocationKey('Koekamerstraat 48A, 9688 Schorisse, BE'),
      customerConfirmedLocationKey('Koekamerstraat 48A, 9688 Maarkedal'),
    );
    expect(
      customerConfirmedLocationKey('Koekamerstraat 48A, 9688 Schorisse, BE'),
      isNot(customerConfirmedLocationKey('Koekamerstraat 48, 9688 Maarkedal')),
    );
  });

  test('profile text without a pin is not a finished quote address', () {
    final value = customerBookingAddressFromText(
      'Koekamerstraat 48A, 9688 Schorisse, BE',
    );
    expect(value.displayText, contains('48A'));
    expect(value.displayText, contains('Schorisse'));
    expect(value.hasCoordinates, isFalse);
    expect(companyPlanAddressIsQuoteReady(value), isFalse);
  });

  test('quote fingerprint changes when the vehicle changes', () {
    final from = customerBookingAddressFromText(
      'Koekamerstraat 48A, 9688 Schorisse, BE',
      latitude: 50.77205,
      longitude: 3.66942,
    );
    final to = customerBookingAddressFromText(
      'Brussels Airport',
      latitude: 50.901,
      longitude: 4.484,
    );
    const options = CompanyRideOptions(service: 'airport');
    final first = companyPlanQuoteFingerprint(
      from: from,
      to: to,
      pickupLocal: DateTime(2026, 9, 17, 13, 0),
      options: options,
      passengers: 1,
      vehicleId: 'vh_1',
    );
    final next = companyPlanQuoteFingerprint(
      from: from,
      to: to,
      pickupLocal: DateTime(2026, 9, 17, 13, 0),
      options: options,
      passengers: 1,
      vehicleId: 'vh_1786881139131',
    );
    expect(first, isNot(next));
  });

  test('price block uses quote VAT fields and omits route km', () {
    const quote = CompanyPlanQuoteResult(
      fingerprint: 'fp',
      distanceKm: 40.6,
      durationMin: 41,
      priceInclVat: 80.6,
      priceExVat: 66.61,
      currency: 'EUR',
      priceAvailable: true,
    );
    expect(customerBookingQuoteInclVat(quote), 80.6);
    expect(customerBookingQuoteExVat(quote), 66.61);
    expect(formatCompanyPlanQuoteRoute(quote, AppLanguage.nl), contains('km'));
  });

  testWidgets('price block shows incl and excl VAT without route stats', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomerBookingPriceBlock(
            language: AppLanguage.nl,
            loading: false,
            quote: CompanyPlanQuoteResult(
              fingerprint: 'fp',
              distanceKm: 40.6,
              durationMin: 41,
              priceInclVat: 80.6,
              priceExVat: 66.61,
              currency: 'EUR',
              priceAvailable: true,
            ),
            error: null,
            onRetry: _noop,
          ),
        ),
      ),
    );
    expect(find.text('Totaal incl. btw'), findsOneWidget);
    expect(find.text('Excl. btw'), findsOneWidget);
    expect(find.textContaining('40,6'), findsNothing);
    expect(find.textContaining('41 min'), findsNothing);
  });

  test('Fluxidi limousine off hides only limousine offers', () {
    final vehicles = <Map<String, dynamic>>[
      <String, dynamic>{'vehicle_id': 'vh_1', 'name': 'Hoofdwagen'},
      <String, dynamic>{
        'vehicle_id': 'vh_1787058237109',
        'name': 'Party Limo',
        'service_category': 'limousine',
      },
    ];
    final filtered = customerBookingFilterVehiclesForEnabledServices(
      vehicles: vehicles,
      limousineOffered: false,
      limousineVehicleIds: const <String>{'vh_1787058237109'},
    );
    expect(filtered.map((vehicle) => vehicle['vehicle_id']), <String>['vh_1']);
    expect(
      customerBookingFilterVehiclesForEnabledServices(
        vehicles: vehicles,
        limousineOffered: true,
        limousineVehicleIds: const <String>{'vh_1787058237109'},
      ),
      hasLength(2),
    );
  });

  test('street plus locality drops worldwide house-number-only matches', () {
    const query = 'koekamerstraat 48A maarkedal';
    expect(limousineAddressQueryLocality(query)?.toLowerCase(), 'maarkedal');
    expect(limousineMapboxCountryForQuery(query), 'be');
    expect(limousineMapboxCountryForQuery('Champs-Élysées Paris, France'), 'fr');
    final filtered = limousineFilterPlaceSuggestions(query, const [
      LimousinePlaceSuggestion(
        label: '48A, Millbrook, South Australia, Australia',
        placeType: 'address',
        text: '48A',
        locality: 'Millbrook',
      ),
      LimousinePlaceSuggestion(
        label: '48a, Alberta Beach, Canada',
        placeType: 'address',
        text: '48a',
        locality: 'Alberta Beach',
      ),
      LimousinePlaceSuggestion(
        label: 'Koekamerstraat / Rue Cocambre, 9600 Ronse, België',
        placeType: 'address',
        postcode: '9600',
        locality: 'Ronse',
      ),
      LimousinePlaceSuggestion(
        label: 'Koekamerstraat 48A, 9688 Maarkedal, België',
        placeType: 'address',
        postcode: '9688',
        locality: 'Maarkedal',
        lat: 50.772,
        lon: 3.669,
      ),
    ]);
    expect(filtered, hasLength(1));
    expect(filtered.single.label, contains('Maarkedal'));
    expect(filtered.single.label.contains('Ronse'), isFalse);
  });

  test('confirmed 48A plus Kortrijk coords are quote ready', () {
    final from = customerBookingAddressFromText(
      'Koekamerstraat 48A, 9688 Schorisse, BE',
      latitude: 50.77205,
      longitude: 3.66942,
    );
    final to = customerBookingAddressFromText(
      'Kortrijk, West-Vlaanderen, België',
      latitude: 50.828,
      longitude: 3.264,
    );
    expect(from.displayText, contains('48A'));
    expect(from.displayText, contains('Schorisse'));
    expect(companyPlanAddressIsQuoteReady(from), isTrue);
    expect(companyPlanAddressIsQuoteReady(to), isTrue);
    expect(
      companyPlanRouteStatus(
        from: from,
        to: to,
        loading: false,
        quote: const CompanyPlanQuoteResult(
          fingerprint: 'ok',
          distanceKm: 38.5,
          durationMin: 45,
          pickupLat: 50.77205,
          pickupLon: 3.66942,
          dropoffLat: 50.828,
          dropoffLon: 3.264,
        ),
      ),
      CompanyPlanRouteStatus.ready,
    );
  });

  test('unconfirmed pickup asks for confirmation instead of a generic route', () {
    final from = customerBookingAddressFromText(
      'Koekamerstraat 48A, 9688 Schorisse, BE',
    );
    final to = customerBookingAddressFromText(
      'Brussels South Charleroi Airport',
      latitude: 50.459,
      longitude: 4.453,
    );
    expect(
      companyPlanRouteStatus(
        from: from,
        to: to,
        loading: false,
        quote: null,
      ),
      CompanyPlanRouteStatus.confirmPickup,
    );
  });

  test('example presentation does not change the legal company name', () {
    final presentation = publicCompanyPresentationFrom(
      <String, dynamic>{
        'company_name': 'Fluxidi',
        'example_company': true,
      },
      language: AppLanguage.nl,
    );
    expect(presentation.isExample, isTrue);
    expect(presentation.badge, 'Voorbeeldbedrijf');
    expect(presentation.notice, contains('voorbeeldbedrijf van Fluxidi'));
  });

  test('quote ready requires a confirmed pin, not only selected text', () {
    expect(
      companyPlanAddressIsQuoteReady(
        const LimousineAddressValue(
          displayText: 'Koekamerstraat 48A, 9688 Schorisse, BE',
          acceptance: LimousineAddressAcceptance.manualFallback,
        ),
      ),
      isFalse,
    );
  });

  test('late geocode does not wipe a confirmed pin', () {
    final lookup = LimousinePlaceLookup(
      searchOverride: (query, language) async {
        return const LimousinePlaceLookupResult(
          suggestions: <LimousinePlaceSuggestion>[
            LimousinePlaceSuggestion(
              label: 'Koekamerstraat 48, 9688 Maarkedal, België',
              lat: 50.77205,
              lon: 3.66942,
              placeType: 'address',
              postcode: '9688',
              locality: 'Maarkedal',
            ),
          ],
        );
      },
    );
    final controller = LimousineAddressFieldController(
      lookup: lookup,
      fieldId: 'pickup',
    );
    addTearDown(controller.dispose);
    const query = 'Koekamerstraat 48A, 9688 Schorisse, BE';
    controller.acceptCopy(customerBookingAddressFromText(query));
    final resolved = limousineResolveOwnedAddress(
      query: query,
      result: const LimousinePlaceLookupResult(
        suggestions: <LimousinePlaceSuggestion>[
          LimousinePlaceSuggestion(
            label: 'Koekamerstraat 48, 9688 Maarkedal, België',
            lat: 50.77205,
            lon: 3.66942,
            placeType: 'address',
            postcode: '9688',
            locality: 'Maarkedal',
          ),
        ],
      ),
    );
    controller.applyOwnedResolution(resolved);
    expect(controller.locationNeedsConfirm, isTrue);
    expect(controller.value.hasCoordinates, isFalse);
    expect(resolved.candidate?.hasCoordinates, isTrue);
    controller.confirmCandidateLocation();
    expect(controller.locationUserConfirmed, isTrue);
    expect(controller.value.hasCoordinates, isTrue);
    expect(controller.value.displayText, contains('48A'));
    expect(customerBookingPickupNeedsConfirm(controller), isFalse);
    controller.applyOwnedResolution(resolved);
    expect(controller.value.hasCoordinates, isTrue);
    expect(controller.locationUserConfirmed, isTrue);
    expect(controller.value.lat, 50.77205);
  });

  test('selecting a proven house leaves a stale confirm behind', () {
    final lookup = LimousinePlaceLookup(
      searchOverride: (query, language) async =>
          const LimousinePlaceLookupResult(),
    );
    final controller = LimousineAddressFieldController(
      lookup: lookup,
      fieldId: 'pickup',
    );
    addTearDown(controller.dispose);
    controller.applyOwnedResolution(
      limousineResolveOwnedAddress(
        query: 'Koekamerstraat 48A, 9688 Schorisse, BE',
        result: const LimousinePlaceLookupResult(
          suggestions: <LimousinePlaceSuggestion>[
            LimousinePlaceSuggestion(
              label: 'Koekamerstraat 48, 9688 Maarkedal, België',
              lat: 50.77205,
              lon: 3.66942,
              placeType: 'address',
              postcode: '9688',
              locality: 'Maarkedal',
            ),
          ],
        ),
      ),
    );
    expect(customerBookingPickupNeedsConfirm(controller), isTrue);
    controller.selectSuggestion(
      const LimousinePlaceSuggestion(
        label: 'Koekamerstraat 50, 9688 Maarkedal, België',
        lat: 50.7722,
        lon: 3.6696,
        placeType: 'address',
        postcode: '9688',
        locality: 'Maarkedal',
      ),
    );
    expect(controller.locationNeedsConfirm, isFalse);
    expect(controller.locationUserConfirmed, isTrue);
    expect(customerBookingPickupNeedsConfirm(controller), isFalse);
    expect(companyPlanAddressIsQuoteReady(controller.value), isTrue);
  });
}

void _noop() {}
