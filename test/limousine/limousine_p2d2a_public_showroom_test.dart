import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_entry.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_showroom_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_showroom_section.dart';
import 'package:fluxidi_tracking/partner_public_profile_page.dart';
import 'package:http/http.dart' as http;

Map<String, dynamic> _vehicleOffer({
  String id = 'off_veh',
  String presentation = 'quote_required',
  int? cents = 45000,
  String currency = 'EUR',
  Map<String, dynamic>? extraVehicle,
  Map<String, dynamic>? extraOffer,
}) {
  return <String, dynamic>{
    'offer_id': id,
    'target_type': 'vehicle',
    'vehicle_id': 'veh_1',
    'service_class_id': 'executive_sedan',
    'title': {
      'nl': 'Executive',
      'en': 'Executive',
      'fr': 'Executive',
      'es': 'Executive',
    },
    'description': {
      'nl': 'Zwarte sedan',
      'en': 'Black sedan',
      'fr': 'Berline noire',
      'es': 'Sedán negro',
    },
    'price_presentation': presentation,
    if (cents != null) 'display_amount_cents': cents,
    'currency': currency,
    'journey_types': ['point_to_point', 'hourly_package'],
    'included_services': [
      {
        'item_id': 'water',
        'label': {'en': 'Water', 'nl': 'Water'},
      },
    ],
    'paid_extras': [
      {
        'extra_id': 'wait',
        'label': {'en': 'Wait', 'nl': 'Wachten'},
      },
    ],
    'mobilisation': {
      'disclosure': {'en': 'Included', 'nl': 'Inbegrepen'},
    },
    'vehicle': {
      'vehicle_id': 'veh_1',
      'service_class_id': 'executive_sedan',
      'passenger_capacity': 3,
      'luggage_capacity': 2,
      'color': 'Black',
      'photo_url': 'https://cdn.example/car.webp',
      ...?extraVehicle,
    },
    ...?extraOffer,
  };
}

Map<String, dynamic> _classOffer({
  String id = 'off_class',
  String presentation = 'from_price',
}) {
  return <String, dynamic>{
    'offer_id': id,
    'target_type': 'service_class',
    'service_class_id': 'executive_sedan',
    'title': {
      'nl': 'Klasse-arrangement',
      'en': 'Class arrangement',
      'fr': 'Formule classe',
      'es': 'Arreglo de clase',
    },
    'description': {
      'nl': 'Serviceklasse',
      'en': 'Service class',
      'fr': 'Classe de service',
      'es': 'Clase de servicio',
    },
    'price_presentation': presentation,
    'display_amount_cents': 39000,
    'currency': 'EUR',
    'journey_types': ['point_to_point'],
  };
}

Map<String, dynamic> _eligibleProfile({
  List<Map<String, dynamic>>? offers,
  bool available = true,
}) {
  return <String, dynamic>{
    'partner_id': 'p1',
    'company_name': 'Coachline',
    'about_short': 'About Coachline',
    'bookable': true,
    'is_active': true,
    'airport_service_enabled': true,
    'services': ['taxi_vvb', 'airport_transfer'],
    'booking_capabilities': {'online_payments': true},
    'limousine_available': available,
    'limousine_projection': {
      'limousine_available': available,
      'limousine_service_enabled': available,
      'published_offer_count': offers?.length ?? 1,
    },
    'limousine_offers': offers ?? [_vehicleOffer(), _classOffer()],
  };
}

class _CaptureClient extends http.BaseClient {
  int gets = 0;
  final Map<String, dynamic> profile;

  _CaptureClient(this.profile);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    gets += 1;
    final bytes = utf8.encode(jsonEncode({'ok': true, 'profile': profile}));
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([bytes]),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
}

Widget _app(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Widget _pageApp(Widget page) => MaterialApp(home: page);

CustomerThemePalette get _palette =>
    paletteForCustomerTheme(CustomerThemeVariant.premiumLight);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('1) gate off hides the showroom and default entry stays OFF', () {
    expect(LimousineCustomerEntryContract.isVisible, isFalse);
    expect(
      limousinePublicShowroomShouldRender(
        entryEnabled: false,
        profile: _eligibleProfile(),
      ),
      isFalse,
    );
    expect(kLimousinePublicShowroomProfileHttpGets, 1);
  });

  testWidgets('1b) gated-off profile page makes zero added limousine widgets', (
    tester,
  ) async {
    await tester.pumpWidget(
      _pageApp(
        PartnerPublicProfilePage(
          partnerId: 'p1',
          companyNameFallback: 'Coachline',
          customerHomeBuilder: (_) => const SizedBox(),
          limousineShowroomEnabled: false,
          profileOverride: _eligibleProfile(),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousinePublicShowroomSectionKey), findsNothing);
    expect(find.textContaining('Limousines'), findsNothing);
  });

  testWidgets('1c) gate off uses only the existing profile GET', (
    tester,
  ) async {
    final client = _CaptureClient(_eligibleProfile());
    await tester.pumpWidget(
      _pageApp(
        PartnerPublicProfilePage(
          partnerId: 'p1',
          companyNameFallback: 'Coachline',
          customerHomeBuilder: (_) => const SizedBox(),
          limousineShowroomEnabled: false,
          httpClient: client,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(client.gets, kLimousinePublicShowroomProfileHttpGets);
    expect(find.byKey(kLimousinePublicShowroomSectionKey), findsNothing);
  });

  testWidgets('2) valid eligible profile renders the showroom', (tester) async {
    await tester.pumpWidget(
      _app(
        LimousinePublicShowroomSection(
          profile: _eligibleProfile(),
          partnerId: 'p1',
          companyName: 'Coachline',
          language: AppLanguage.en,
          palette: _palette,
        ),
      ),
    );
    expect(find.byKey(kLimousinePublicShowroomSectionKey), findsOneWidget);
    expect(find.text('Limousines and arrangements'), findsOneWidget);
    expect(find.byKey(limousineShowroomCardKey('off_veh')), findsOneWidget);
    expect(find.byKey(limousineShowroomCardKey('off_class')), findsOneWidget);
    expect(
      find.text('The assigned vehicle will match this service class.'),
      findsOneWidget,
    );
    expect(find.byType(Image), findsOneWidget);
  });

  test('3) unpublished/ineligible/no-offer profiles do not render', () {
    expect(
      limousinePublicShowroomShouldRender(
        entryEnabled: true,
        profile: _eligibleProfile(available: false),
      ),
      isFalse,
    );
    expect(
      limousinePublicShowroomShouldRender(
        entryEnabled: true,
        profile: _eligibleProfile(offers: const []),
      ),
      isFalse,
    );
    expect(
      limousinePublicShowroomShouldRender(
        entryEnabled: true,
        profile: <String, dynamic>{
          'company_name': 'Yellow Cab',
          'services': ['taxi_vvb', 'airport_transfer'],
        },
      ),
      isFalse,
    );
  });

  test('4) vehicle offer keeps only safe supplied fields', () {
    final offer = tryParseLimousineShowroomOffer(
      _vehicleOffer(
        extraVehicle: {'license_plate': '1-ABC-234', 'vin': 'WBAXXX'},
      ),
    )!;
    expect(offer.photoUrl, startsWith('https://'));
    expect(offer.passengerCapacity, 3);
    expect(offer.luggageCapacity, 2);
    expect(offer.color, 'Black');
    expect(offer.raw.containsKey('length'), isFalse);
  });

  test('5) class offer never invents a vehicle', () {
    final offer = tryParseLimousineShowroomOffer(_classOffer())!;
    expect(offer.isVehicleTargeted, isFalse);
    expect(offer.photoUrl, isEmpty);
    expect(offer.vehicleId, isEmpty);
  });

  test('6) vehicle-targeted offer takes precedence', () {
    final ranked = collectLimousineShowroomOffers(
      _eligibleProfile(offers: [_classOffer(), _vehicleOffer()]),
    );
    expect(ranked.first.offerId, 'off_veh');
    expect(ranked.first.isVehicleTargeted, isTrue);
  });

  test('7/8) price presentations stay distinct and unavailable has no CTA', () {
    expect(
      limousineShowroomPriceLabel(
        LimousinePublishedOffer.fromJson(
          _vehicleOffer(presentation: 'exact_fixed'),
        ),
        AppLanguage.en,
      ),
      'EUR 450.00',
    );
    expect(
      limousineShowroomPriceLabel(
        LimousinePublishedOffer.fromJson(
          _vehicleOffer(presentation: 'from_price'),
        ),
        AppLanguage.en,
      ),
      startsWith('From '),
    );
    expect(
      limousineShowroomPriceLabel(
        LimousinePublishedOffer.fromJson(
          _vehicleOffer(presentation: 'indicative'),
        ),
        AppLanguage.en,
      ),
      startsWith('Indicative price'),
    );
    expect(
      limousineShowroomPriceLabel(
        LimousinePublishedOffer.fromJson(
          _vehicleOffer(presentation: 'quote_required', cents: null),
        ),
        AppLanguage.en,
      ),
      'Price on request',
    );
    expect(
      limousineShowroomCtaFor(
        LimousinePublishedOffer.fromJson(
          _vehicleOffer(presentation: 'unavailable', cents: null),
        ),
      ),
      LimousineShowroomCta.none,
    );
    expect(
      limousineShowroomCtaFor(
        LimousinePublishedOffer.fromJson(
          _vehicleOffer(presentation: 'exact_fixed'),
        ),
      ),
      LimousineShowroomCta.book,
    );
    expect(
      limousineShowroomCtaFor(LimousinePublishedOffer.fromJson(_classOffer())),
      LimousineShowroomCta.requestQuote,
    );
  });

  test('9) taxi prices are never used as a fallback', () {
    final offer = tryParseLimousineShowroomOffer(
      _vehicleOffer(
        presentation: 'quote_required',
        cents: null,
        extraOffer: {'taxi_price': 12000, 'airport_fixed_fare': 8000},
      ),
    )!;
    expect(
      limousineShowroomPriceLabel(offer, AppLanguage.en),
      'Price on request',
    );
    expect(offer.displayAmountCents, isNull);
  });

  testWidgets('10) private vehicle/company fields stay out of the widgets', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LimousinePublicShowroomSection(
          profile: _eligibleProfile(
            offers: [
              _vehicleOffer(
                extraVehicle: {
                  'license_plate': '1-ABC-234',
                  'vin': 'WBAXXX',
                  'operating_base_address': 'Secret 1',
                },
              ),
            ],
          ),
          partnerId: 'p1',
          companyName: 'Coachline',
          language: AppLanguage.en,
          palette: _palette,
        ),
      ),
    );
    expect(find.textContaining('1-ABC-234'), findsNothing);
    expect(find.textContaining('WBAXXX'), findsNothing);
    expect(find.textContaining('Secret 1'), findsNothing);
    expect(find.textContaining('limousine_entitled'), findsNothing);
  });

  test('11) CTA preselects only partner + offer and does not submit', () {
    final offer = LimousinePublishedOffer.fromJson(_vehicleOffer());
    final gateway = _NoopGateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway);
    controller.applyShowroomSelection(
      publicPartnerId: 'p1',
      offer: offer,
      companyName: 'Coachline',
    );
    expect(controller.draft.publicPartnerId, 'p1');
    expect(controller.draft.offerId, 'off_veh');
    expect(controller.providerOfferLocked, isTrue);
    expect(controller.phase, LimousineCustomerQuotePhase.draft);
    expect(gateway.createCalls, 0);
    expect(gateway.discoverCalls, 0);
    expect(gateway.loadCalls, 0);
    final body = limousineCustomerCreateBody(controller.draft);
    expect(body.containsKey('total_incl_vat_cents'), isFalse);
    expect(body.containsKey('tenant_id'), isFalse);
    expect(body.containsKey('vehicle_id'), isFalse);
    controller.selectOffer(LimousinePublishedOffer.fromJson(_classOffer()));
    expect(controller.draft.offerId, 'off_veh');
    controller.dispose();
  });

  testWidgets('11b) opening P2D2 from the showroom does not submit', (
    tester,
  ) async {
    final gateway = _NoopGateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway);
    var opened = false;
    await tester.pumpWidget(
      _app(
        LimousinePublicShowroomSection(
          profile: _eligibleProfile(offers: [_vehicleOffer()]),
          partnerId: 'p1',
          companyName: 'Coachline',
          language: AppLanguage.en,
          palette: _palette,
          onOpenQuote: (offer) {
            opened = true;
            controller.applyShowroomSelection(
              publicPartnerId: 'p1',
              offer: offer,
            );
          },
        ),
      ),
    );
    final quoteCta = find.byKey(limousineShowroomQuoteCtaKey('off_veh'));
    await tester.ensureVisible(quoteCta);
    await tester.tap(quoteCta);
    await tester.pump();
    expect(opened, isTrue);
    expect(gateway.createCalls, 0);
    expect(controller.draft.offerId, 'off_veh');
    controller.dispose();
  });

  testWidgets('12) profile open uses one GET and the showroom adds none', (
    tester,
  ) async {
    final client = _CaptureClient(_eligibleProfile());
    await tester.pumpWidget(
      _pageApp(
        PartnerPublicProfilePage(
          partnerId: 'p1',
          companyNameFallback: 'Coachline',
          customerHomeBuilder: (_) => const SizedBox(),
          limousineShowroomEnabled: true,
          httpClient: client,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(client.gets, kLimousinePublicShowroomProfileHttpGets);
    expect(find.byKey(kLimousinePublicShowroomSectionKey), findsOneWidget);
    expect(
      File(
        'lib/limousine/limousine_public_showroom.dart',
      ).readAsStringSync().contains('http.get'),
      isFalse,
    );
  });

  test('13) taxi and airport profile sections remain in source', () {
    final source = File(
      'lib/partner_public_profile_page.dart',
    ).readAsStringSync();
    expect(source.contains('_openPartnerBooking'), isTrue);
    expect(source.contains('_openPartnerAirportBooking'), isTrue);
    expect(source.contains('_airportServiceEnabledFromProfile'), isTrue);
    expect(source.contains('LimousinePublicShowroomSection'), isTrue);
    expect(source.contains('_limousineShowroomEnabled'), isTrue);
  });

  testWidgets('13b) taxi CTA remains usable beside the showroom', (
    tester,
  ) async {
    await tester.pumpWidget(
      _pageApp(
        PartnerPublicProfilePage(
          partnerId: 'p1',
          companyNameFallback: 'Coachline',
          customerHomeBuilder: (_) => const SizedBox(),
          limousineShowroomEnabled: true,
          profileOverride: _eligibleProfile(),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousinePublicShowroomSectionKey), findsOneWidget);
    expect(find.byIcon(Icons.local_taxi_outlined), findsWidgets);
    expect(find.byIcon(Icons.flight_takeoff_rounded), findsWidgets);
  });

  test('14) NL/EN/FR/ES showroom labels exist', () {
    for (final language in AppLanguage.values) {
      if (language == AppLanguage.de) continue;
      expect(kLimousineShowroomTitle.of(language).trim(), isNotEmpty);
      expect(kLimousineShowroomPassengers.of(language).trim(), isNotEmpty);
      expect(kLimousineShowroomLuggage.of(language).trim(), isNotEmpty);
      expect(kLimousineShowroomIncluded.of(language).trim(), isNotEmpty);
      expect(kLimousineShowroomExtras.of(language).trim(), isNotEmpty);
      expect(kLimousineShowroomFrom.of(language).trim(), isNotEmpty);
      expect(kLimousineShowroomIndicative.of(language).trim(), isNotEmpty);
      expect(kLimousineShowroomPriceOnRequest.of(language).trim(), isNotEmpty);
      expect(kLimousineShowroomView.of(language).trim(), isNotEmpty);
      expect(kLimousineShowroomRequestQuote.of(language).trim(), isNotEmpty);
      expect(kLimousineShowroomBook.of(language).trim(), isNotEmpty);
    }
  });

  test('15) malformed or unknown offer data fails closed', () {
    expect(tryParseLimousineShowroomOffer({'title': 'x'}), isNull);
    expect(
      tryParseLimousineShowroomOffer(
        _vehicleOffer(presentation: 'mystery_price'),
      ),
      isNull,
    );
    expect(
      tryParseLimousineShowroomOffer(_vehicleOffer(cents: 45000, currency: '')),
      isNull,
    );
    expect(
      tryParseLimousineShowroomOffer({
        ..._vehicleOffer(),
        'vehicle': 'missing',
        'vehicle_id': '',
      }),
      isNull,
    );
    expect(
      tryParseLimousineShowroomOffer(
        _vehicleOffer(extraOffer: {'enabled': false, 'published': true}),
      ),
      isNull,
    );
    expect(
      tryParseLimousineShowroomOffer(
        _vehicleOffer(extraOffer: {'enabled': true, 'published': false}),
      ),
      isNull,
    );
    expect(
      collectLimousineShowroomOffers(
        _eligibleProfile(
          offers: [
            _vehicleOffer(presentation: 'mystery_price'),
            _classOffer(),
          ],
        ),
      ).map((offer) => offer.offerId),
      ['off_class'],
    );
  });

  testWidgets('16) a failed vehicle image keeps the existing placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LimousinePublicShowroomSection(
          profile: _eligibleProfile(
            offers: [
              _vehicleOffer(
                extraVehicle: {'photo_url': 'https://cdn.example/missing.webp'},
              ),
            ],
          ),
          partnerId: 'p1',
          companyName: 'Coachline',
          language: AppLanguage.en,
          palette: _palette,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(kLimousinePublicShowroomSectionKey), findsOneWidget);
    expect(find.byIcon(Icons.directions_car_filled_outlined), findsWidgets);
  });

  test('worker GET profile now includes sanitized showroom fields', () {
    final worker = File(
      'workers/booking/fluxidi_booking_worker.js',
    ).readAsStringSync();
    expect(
      worker.contains('_publicLimousineShowroomFieldsFromStoredProfile'),
      isTrue,
    );
  });

  test('gates remain OFF', () {
    expect(kLimousineMarketplaceCustomerEntryEnabled, isFalse);
    final wrangler = File('workers/booking/wrangler.toml').readAsStringSync();
    expect(wrangler.contains('LIMOUSINE_QUOTE_ENABLED = "0"'), isTrue);
    expect(wrangler.contains('LIMOUSINE_BOOK_ENABLED = "0"'), isTrue);
    expect(wrangler.contains('LIMOUSINE_MANUAL_QUOTE_ENABLED = "0"'), isTrue);
  });
}

class _NoopGateway implements LimousineCustomerQuoteGateway {
  int createCalls = 0;
  int discoverCalls = 0;
  int loadCalls = 0;

  @override
  Future<List<LimousineDiscoveredProvider>> discoverNearby({
    String? postcode,
    double? lat,
    double? lng,
    int radiusKm = 20,
  }) async {
    discoverCalls += 1;
    return const [];
  }

  @override
  Future<LimousineProviderDetail> loadProvider(String partnerId) async {
    loadCalls += 1;
    throw const LimousineCustomerQuoteException(code: 'unused');
  }

  @override
  Future<LimousineQuoteCreateResult> createRequest(
    LimousineQuoteCreateDraft draft,
  ) async {
    createCalls += 1;
    throw const LimousineCustomerQuoteException(code: 'unused');
  }

  @override
  Future<LimousineQuoteRequest> pollStatus(String statusRef) async {
    throw const LimousineCustomerQuoteException(code: 'unused');
  }

  @override
  Future<LimousineQuoteAcceptResult> accept({
    required String quoteRequestId,
    required int expectedRevision,
    required int termsRevision,
  }) async {
    throw const LimousineCustomerQuoteException(code: 'unused');
  }
}
