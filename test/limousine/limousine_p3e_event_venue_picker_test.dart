import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_airport_transfer_fields.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_event_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_event_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_hotel_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1c_journey.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_transfer_endpoint.dart';

LimousinePublishedOffer _offer({
  List<String> journeyTypes = const ['event_transfer'],
  String presentation = 'quote_required',
}) {
  return LimousinePublishedOffer.fromJson(<String, dynamic>{
    'offer_id': 'off_event',
    'target_type': 'vehicle',
    'vehicle_id': 'veh_1',
    'service_class_id': 'executive_sedan',
    'title': {'nl': 'Event', 'en': 'Event'},
    'description': {'nl': 'Incl. btw', 'en': 'Incl. VAT'},
    'journey_types': journeyTypes,
    'price_presentation': presentation,
    'display_amount_cents': 45000,
    'currency': 'EUR',
    'source_revision': 4,
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

LimousineEventVenueSuggestion _venueSuggestion() =>
    const LimousineEventVenueSuggestion(
      name: 'Flanders Expo',
      formattedAddress: 'Maaltekouter 1, 9051 Gent, Belgium',
      latitude: 51.026,
      longitude: 3.69,
      providerPlaceId: 'poi.venue.1',
      city: 'Gent',
      postcode: '9051',
      countryCode: 'BE',
    );

class _EventLookup extends LimousineEventLookup {
  _EventLookup({
    this.delay = Duration.zero,
    this.error = false,
    this.empty = false,
    this.geocodeHit = true,
  }) : super(
         searchOverride: (query, language) async {
           searches += 1;
           lastQuery = query;
           lastLanguage = language;
           if (delay > Duration.zero) {
             await Future<void>.delayed(delay);
           }
           if (error) {
             return const LimousineEventLookupResult(hadError: true);
           }
           if (empty) {
             return const LimousineEventLookupResult();
           }
           return LimousineEventLookupResult(suggestions: [_venueSuggestion()]);
         },
         manualGeocodeOverride: (query, language) async {
           geocodes += 1;
           if (!geocodeHit) {
             return limousineManualEventEndpoint(query);
           }
           return LimousineTransferEndpoint(
             kind: LimousineTransferEndpointKind.event,
             displayName: query.trim(),
             formattedAddress: '$query, Gent',
             venueName: query.trim(),
             latitude: 51.05,
             longitude: 3.72,
             providerPlaceId: 'address.manual.1',
             city: 'Gent',
             postcode: '9000',
             countryCode: 'BE',
             manual: true,
           );
         },
       );

  static int searches = 0;
  static int geocodes = 0;
  static String lastQuery = '';
  static String lastLanguage = '';
  final Duration delay;
  final bool error;
  final bool empty;
  final bool geocodeHit;
}

class _Gateway with LimousineCustomerQuoteGateway {
  _Gateway({this.offer});

  final LimousinePublishedOffer? offer;
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
      offers: [offer ?? _offer()],
    );
  }

  @override
  Future<LimousineQuoteCreateResult> createRequest(
    LimousineQuoteCreateDraft draft,
  ) async {
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
    _EventLookup.searches = 0;
    _EventLookup.geocodes = 0;
    _EventLookup.lastQuery = '';
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
    appLanguageNotifier.value = AppLanguage.nl;
  });

  test('event venue search uses the existing Mapbox places host', () {
    final uri = limousineMapboxEventPlacesUri(
      query: 'Flanders Expo',
      token: 'tok',
      language: 'nl',
    );
    expect(uri.host, kLimousineMapboxGeocodingV5Host);
    expect(uri.path, contains(kLimousineMapboxGeocodingV5PathPrefix));
    expect(uri.queryParameters['types'], 'poi');
    expect(
      limousineLooksLikeEventVenueCategory('concert_hall stadium expo'),
      isTrue,
    );
  });

  test('Mapbox venue choice is stored in full on the event endpoint', () {
    final endpoint = _venueSuggestion().toEndpoint(eventName: 'Wedding Expo');
    expect(endpoint.kind, LimousineTransferEndpointKind.event);
    expect(endpoint.venueName, 'Flanders Expo');
    expect(endpoint.eventName, 'Wedding Expo');
    expect(endpoint.formattedAddress, contains('Maaltekouter'));
    expect(endpoint.latitude, 51.026);
    expect(endpoint.longitude, 3.69);
    expect(endpoint.providerPlaceId, 'poi.venue.1');
    expect(endpoint.city, 'Gent');
    expect(endpoint.postcode, '9051');
    expect(endpoint.countryCode, 'BE');
    expect(endpoint.manual, isFalse);
    expect(limousineEventEndpointIsUsable(endpoint), isTrue);
    final json = endpoint.toJson();
    expect(json['venue_name'], 'Flanders Expo');
    expect(json['event_name'], 'Wedding Expo');
    expect(json['provider_place_id'], 'poi.venue.1');
  });

  test('manual event location is marked manual and can keep geocoded coords', () {
    final manual = limousineManualEventEndpoint(
      'Tijdelijke festivalweide, Oostende',
      eventName: 'Beach festival',
    );
    expect(manual.kind, LimousineTransferEndpointKind.event);
    expect(manual.manual, isTrue);
    expect(manual.venueName, contains('festivalweide'));
    expect(manual.eventName, 'Beach festival');
    expect(limousineEventEndpointIsUsable(manual), isTrue);
    expect(LimousineTransferEndpointKind.isEvent('venue'), isTrue);
  });

  test('return points stay correctly typed after reverse', () {
    final from = limousineEndpointFromAddress(_address('Korenmarkt 1, Gent'));
    final to = _venueSuggestion().toEndpoint(eventName: 'Gala');
    final reversed = reverseLimousineEndpoints(from: from, to: to);
    expect(reversed.from.kind, LimousineTransferEndpointKind.event);
    expect(reversed.from.venueName, 'Flanders Expo');
    expect(reversed.from.eventName, 'Gala');
    expect(reversed.to.kind, LimousineTransferEndpointKind.address);
  });

  test('quote and book snapshots keep event and venue data', () {
    final draft = LimousineQuoteCreateDraft(
      publicPartnerId: 'p1',
      offerId: 'off_event',
      journeyType: 'event_transfer',
      from: 'Korenmarkt 1, Gent',
      to: 'Flanders Expo, Gent',
      scheduledPickupIso: '2026-09-01T20:00:00Z',
      returnPickupIso: '2026-09-01T23:30:00Z',
      roundtrip: true,
      fromEndpoint: limousineEndpointFromAddress(_address('Korenmarkt 1, Gent')),
      toEndpoint: _venueSuggestion().toEndpoint(eventName: 'Wedding Expo'),
      returnPickupEndpoint: _venueSuggestion().toEndpoint(eventName: 'Wedding Expo'),
      returnDestinationEndpoint: limousineEndpointFromAddress(
        _address('Korenmarkt 1, Gent'),
      ),
      locale: 'nl',
    );
    final quote = limousineCustomerCreateBody(draft);
    final book = limousineCustomerBookBody(draft);
    expect(quote['journey_type'], 'event_transfer');
    expect(quote['from_endpoint']['kind'], 'address');
    expect(quote['to_endpoint']['kind'], 'event');
    expect(quote['to_endpoint']['venue_name'], 'Flanders Expo');
    expect(quote['to_endpoint']['event_name'], 'Wedding Expo');
    expect(quote['to_endpoint']['provider_place_id'], 'poi.venue.1');
    expect(quote['to_endpoint']['city'], 'Gent');
    expect(quote['return_pickup_endpoint']['kind'], 'event');
    expect(quote['return_destination_endpoint']['kind'], 'address');
    expect(book['service_category'], 'limousine');
    expect(book['to_endpoint']['venue_name'], 'Flanders Expo');
    expect(limousineCustomerCreateBodyIsBounded(quote), isTrue);
    expect(limousineCustomerBookBodyIsBounded(book), isTrue);
    for (final body in [quote, book]) {
      expect(body.containsKey('tenant_id'), isFalse);
      expect(body.containsKey('company_id'), isFalse);
      expect(body.containsKey('total_incl_vat_cents'), isFalse);
    }
    final rows = buildLimousineRequestReviewRows(
      draft: draft,
      language: AppLanguage.nl,
    );
    expect(rows.any((row) => row.id == 'event_name' && row.value == 'Wedding Expo'), isTrue);
    expect(rows.firstWhere((row) => row.id == 'route').value, contains('Flanders Expo'));
  });

  test('wait stays fail-closed unless the published offer supports it', () {
    expect(limousinePublishedOfferSupportsReturnWait(_offer()), isFalse);
    expect(
      limousinePublishedOfferSupportsReturnWait(
        LimousinePublishedOffer.fromJson(<String, dynamic>{
          ..._offer().raw,
          'waiting_time_included_minutes': 45,
        }),
      ),
      isTrue,
    );
  });

  testWidgets('event-only offer auto-selects Eventtransfer and opens the venue searcher', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LimousineCustomerQuotePage(
          entryEnabled: true,
          gateway: _Gateway(),
          initialPublicPartnerId: 'p1',
          initialOffer: _offer(),
          eventLookup: _EventLookup(),
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
    expect(find.byKey(kLimousineJourneyTypeScopeSingleKey), findsOneWidget);
    expect(find.byKey(kLimousineEventFieldKey), findsOneWidget);
    expect(find.byKey(kLimousineHotelFieldKey), findsNothing);
    expect(find.byKey(kLimousineAirportToDirectionKey), findsNothing);
    expect(find.text('Gewenste aankomsttijd'), findsOneWidget);
    expect(find.text('Zoek evenementlocatie'), findsOneWidget);
    expect(find.text('Naam evenement'), findsOneWidget);
  });

  testWidgets('multi-type offer shows exactly those types', (tester) async {
    await tester.pumpWidget(
      _app(
        LimousineCustomerQuotePage(
          entryEnabled: true,
          gateway: _Gateway(
            offer: _offer(
              journeyTypes: const ['event_transfer', 'point_to_point'],
            ),
          ),
          initialPublicPartnerId: 'p1',
          initialOffer: _offer(
            journeyTypes: const ['event_transfer', 'point_to_point'],
          ),
          eventLookup: _EventLookup(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineJourneyTypeScopeSingleKey), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('limousine_journey_type_event_transfer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('limousine_journey_type_point_to_point')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('limousine_journey_type_airport_transfer')),
      findsNothing,
    );
  });

  testWidgets('venue search stores the chosen Mapbox place', (tester) async {
    final controller = LimousineEventFieldController(
      lookup: _EventLookup(),
      debounce: Duration.zero,
    );
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: LimousineEventField(
            controller: controller,
            tokens: LimousineUxTokens.fromSurface(background: Colors.white),
            language: AppLanguage.nl,
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(kLimousineEventNameInputKey), 'Wedding Expo');
    await tester.enterText(find.byKey(kLimousineEventInputKey), 'Flanders Expo Gent');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(_EventLookup.searches, 1);
    await tester.tap(find.byKey(limousineEventSuggestionKey(0)));
    await tester.pump();
    expect(controller.selected?.kind, LimousineTransferEndpointKind.event);
    expect(controller.selected?.venueName, 'Flanders Expo');
    expect(controller.selected?.eventName, 'Wedding Expo');
    expect(controller.selected?.providerPlaceId, 'poi.venue.1');
    expect(controller.selected?.manual, isFalse);
    expect(find.byKey(kLimousineEventSelectedCardKey), findsOneWidget);
  });

  testWidgets('manual event location works and is marked manual', (tester) async {
    final controller = LimousineEventFieldController(
      lookup: _EventLookup(empty: true),
      debounce: Duration.zero,
    );
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: LimousineEventField(
            controller: controller,
            tokens: LimousineUxTokens.fromSurface(background: Colors.white),
            language: AppLanguage.nl,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(kLimousineEventInputKey),
      'Tijdelijke festivalweide, Oostende',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.byKey(kLimousineEventManualKey), findsOneWidget);
    await tester.tap(find.byKey(kLimousineEventManualKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(controller.selected?.manual, isTrue);
    expect(controller.selected?.kind, LimousineTransferEndpointKind.event);
    expect(_EventLookup.geocodes, greaterThan(0));
    expect(controller.selected?.latitude, 51.05);
  });
}
