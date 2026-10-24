import '../support/p21_reliable_fixture.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_vehicle_cards.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_airport_fare.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_company_pick.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_company_vehicles.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_flow.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_price_block.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_book_result.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote_wire.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_submit.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_current_location.dart';
import 'package:http/http.dart' as http;

const _crl = AirportCatalogAirport(
  countryCode: 'BE',
  countryName: 'België',
  city: 'Charleroi',
  name: 'Brussels South Charleroi Airport',
  iata: 'CRL',
  latitude: 50.461963,
  longitude: 4.459562,
);

const _zuid = CustomerBookingCompany(
  partnerId: 'partner_zuid',
  companyName: 'Zuid Luchthavenrit',
);

const _noord = CustomerBookingCompany(
  partnerId: 'partner_noord',
  companyName: 'Noord Vaste Prijs',
  vehicles: <Map<String, dynamic>>[
    <String, dynamic>{
      'vehicle_id': 'vh_noord',
      'vehicle_type': 'sedan',
      'tier': 'comfort',
      'seats': 3,
    },
  ],
);

const _zuidPhone = '+32 9 100 00 01';
const _noordPhone = '+32 9 200 00 02';
const _customerPhone = '+32 470 00 00 99';

CustomerBookingEntryContext _airportEntry(CustomerBookingCompany company) {
  return CustomerBookingEntryContext(
    kind: CustomerBookingKind.airport,
    company: company,
    toAirport: true,
    airport: _crl,
    pickup: const CustomerBookingPlace(
      address: 'Koekamerstraat 12, 9688 Schorisse',
      latitude: 50.77205,
      longitude: 3.66942,
    ),
  );
}

Map<String, dynamic> _contactBody({String lead = ''}) {
  return <String, dynamic>{
    'ok': true,
    'request_quote_required': true,
    'reason': 'no_fixed_airport_fare',
    'customer_action': 'contact_company',
    'price_label': 'Prijs op aanvraag',
    'price_incl_vat': 99,
    'total_price_incl_vat': 0,
    'pricing': <String, dynamic>{'total_incl': 99},
    'fixed_price_snapshot': <String, dynamic>{'amount': 99},
    'distance_km': 80,
    'duration_min': 70,
    'currency': 'EUR',
    if (lead.isNotEmpty)
      'conditions': <String, dynamic>{'lead_time': lead}
    else
      'conditions': <String>['lead_time'],
  };
}

Map<String, dynamic> _fixedBody() {
  return <String, dynamic>{
    'ok': true,
    'request_quote_required': false,
    'price_available': true,
    'price_incl_vat': 61.5,
    'total_price_incl_vat': 61.5,
    'distance_km': 80,
    'duration_min': 70,
    'currency': 'EUR',
  };
}

String _partnerOf(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) return '';
  return (decoded['public_partner_id'] ?? '').toString();
}

int _passengersOf(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) return 1;
  final raw = decoded['passengers'];
  if (raw is num) return raw.toInt();
  return int.tryParse('$raw') ?? 1;
}

CustomerBookingQuoteClient _client({
  required Future<http.Response> Function(String path, String body) onPost,
}) {
  return CustomerBookingQuoteClient(
    bookingBaseUrl: 'http://127.0.0.1:8788',
    httpPost: (url, headers, body) => onPost(url.path, body),
  );
}

CustomerBookingProfileGet _profiles({
  Future<void> Function(String partnerId)? beforeProfile,
  bool availabilityEmpty = false,
}) {
  return (uri) async {
    if (uri.path.contains('availability')) {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'ok': true,
          'vehicles': availabilityEmpty
              ? const <Map<String, dynamic>>[]
              : <Map<String, dynamic>>[
                  <String, dynamic>{
                    'vehicle_id': 'vh_noord',
                    'available': true,
                  },
                ],
        }),
        200,
      );
    }
    final partnerId = uri.queryParameters['partner_id'] ?? '';
    if (beforeProfile != null) await beforeProfile(partnerId);
    final phone = partnerId == _noord.partnerId ? _noordPhone : _zuidPhone;
    final email = partnerId == _noord.partnerId
        ? 'boek@noord.example.test'
        : 'boek@zuid.example.test';
    return http.Response(
      jsonEncode(<String, dynamic>{
        'display_name': partnerId == _noord.partnerId
            ? _noord.companyName
            : _zuid.companyName,
        'public_contact': <String, dynamic>{
          'public_phone': phone,
          'booking_email': email,
          'website': 'https://${partnerId}.example.test',
          'phone': _customerPhone,
        },
        'vehicles': <Map<String, dynamic>>[
          <String, dynamic>{
            'vehicle_id': 'vh_noord',
            'vehicle_type': 'sedan',
            'tier': 'comfort',
            'seats': 3,
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
  required CustomerBookingQuoteClient quotes,
  CustomerBookingProfileGet? profileGet,
  CustomerBookingCompanyPicker? companyPicker,
  CustomerProfile? profile,
  bool availabilityEmpty = false,
}) async {
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  tester.view.physicalSize = const Size(800, 1280);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(800, 1280)),
      child: MaterialApp(
        home: CustomerBookingFlow(
          entry: entry,
          language: AppLanguage.nl,
          lookup: LimousinePlaceLookup(
            searchOverride: (query, language) async {
              return const LimousinePlaceLookupResult(
                suggestions: <LimousinePlaceSuggestion>[],
              );
            },
          ),
          locationPlatform: LimousineCurrentLocationPlatform(
            isLocationServiceEnabled: () async => false,
          ),
          quoteClient: quotes,
          reliableChoiceApi: p21UiFixture(entry, profileGet ?? _profiles(availabilityEmpty: availabilityEmpty)),
          autoResolveGps: false,
          profile: profile,
          profileGet:
              profileGet ?? _profiles(availabilityEmpty: availabilityEmpty),
          companyPicker: companyPicker,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  final formScroll = find.descendant(
    of: find.byKey(kCustomerBookingFormKey),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(finder, 240, scrollable: formScroll.first);
  await tester.pump();
}

CustomerProfile _customer() {
  return CustomerProfile(
    customerId: 'cus_fare',
    name: 'Testklant',
    phone: _customerPhone,
    email: 'klant@example.test',
    preferredPostcode: '9688',
    companyName: '',
    vatNumber: '',
    billingStreet: 'Koekamerstraat 12',
    billingPostalCode: '9688',
    billingCity: 'Schorisse',
    createdAt: '2026-01-01',
    updatedAt: '2026-01-01',
  );
}

void main() {

  testWidgets('quote-only offers a fleet preference and copies details without booking', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await _pump(tester, entry: _airportEntry(_zuid), profile: _customer(), availabilityEmpty: true,
      quotes: _client(onPost: (path, body) async => http.Response(jsonEncode(_contactBody()), 200)));
    final preferences = find.byKey(const ValueKey('quote_vehicle_preferences'));
    await _scrollTo(tester, preferences);
    expect(preferences, findsOneWidget);
    final card = find.descendant(of: preferences, matching: find.byType(CustomerBookingVehiclePhotoCard)).first;
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pump();
    expect(tester.widget<CustomerBookingVehiclePhotoCard>(card).selected, isTrue);
    expect(find.byKey(kCustomerBookingConfirmKey), findsNothing);
    await tester.tap(find.byKey(kCustomerBookingAirportContactKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offerteaanvraag kopiëren'));
    await tester.pumpAndSettle();
    expect(copied, contains('Passagiers: 1'));
    expect(copied, contains('Bagage (koffers): 0'));
    expect(copied, contains('Voertuigvoorkeur:'));
    expect(copied, isNot(contains('Voertuigvoorkeur: Geen voorkeur')));
    expect(copied, contains('Koekamerstraat'));
    expect(copied, contains('Charleroi'));
    expect(copied, contains('Testklant'));
    expect(copied, contains('geen bevestigde boeking'));
  });

  test(
    'a stale taxi fare refusal keeps its commercial reason and removes all amounts',
    () {
      final failed = customerBookingBookExceptionFromResponse(
        res: http.Response('{}', 409),
        decoded: <String, dynamic>{
          'ok': false,
          'error': 'request_quote_required',
          'reason': 'taxi_outside_work_area',
        },
      );
      final old = parseCompanyPlanQuote(_fixedBody(), fingerprint: 'old-taxi');
      final quote = customerBookingAirportContactQuote(
        old,
        quoteReason: failed.quoteReason,
      );
      expect(failed.code, 'request_quote_required');
      expect(quote.quoteReason, 'taxi_outside_work_area');
      expect(quote.displayTotalPrice, isNull);
      expect(customerBookingQuoteSupportsConfirm(quote: quote), isFalse);
    },
  );
  test(
    'outside-area taxi contact drops every old amount and blocks confirming',
    () {
      final quote = parseCompanyPlanQuote(<String, dynamic>{
        ..._contactBody(),
        'reason': 'taxi_outside_work_area',
        'price_incl_vat': 128.50,
        'total_price_incl_vat': 128.50,
      }, fingerprint: 'outside-taxi');
      expect(quote.quoteReason, 'taxi_outside_work_area');
      expect(quote.displayTotalPrice, isNull);
      expect(quote.fixedPriceSnapshot, isNull);
      expect(customerBookingQuoteSupportsConfirm(quote: quote), isFalse);
    },
  );

  testWidgets(
    'event taxi outside region shows price on request and company contact',
    (tester) async {
      await _pump(
        tester,
        entry: CustomerBookingEntryContext(
          kind: CustomerBookingKind.event,
          company: _noord,
          pickup: const CustomerBookingPlace(
            address: 'Koekamerstraat 48, 9688 Schorisse',
            latitude: 50.8,
            longitude: 3.6,
          ),
          destination: CustomerBookingPlace(
            address: 'Onderrichtstraat 81, 1000 Brussel',
            latitude: 50.85,
            longitude: 4.35,
            startsAt: DateTime.now().add(const Duration(days: 2)),
          ),
        ),
        quotes: _client(
          onPost: (path, body) async => http.Response(
            jsonEncode(<String, dynamic>{
              ..._contactBody(),
              'reason': 'taxi_outside_work_area',
              'conditions': <String>[],
              'price_incl_vat': 128.50,
              'total_price_incl_vat': 128.50,
            }),
            200,
          ),
        ),
      );
      expect(find.text('Prijs op aanvraag'), findsWidgets);
      expect(find.textContaining('Buiten het werkgebied'), findsOneWidget);
      expect(find.textContaining('luchthavenrit'), findsNothing);
      expect(find.textContaining('128'), findsNothing);
      expect(find.byKey(kCustomerBookingConfirmKey), findsNothing);
      expect(find.text('Contact'), findsOneWidget);
    },
  );

  for (final language in AppLanguage.values) {
    for (final width in [390.0, 800.0]) {
      testWidgets(
        'outside-region copy is translated and fits $language/$width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1280);
          tester.view.devicePixelRatio = 1;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          final quote = parseCompanyPlanQuote(<String, dynamic>{
            ..._contactBody(),
            'reason': 'taxi_outside_work_area',
            'conditions': <String>[],
          }, fingerprint: 'region-copy');
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CustomerBookingPriceBlock(
                    language: language,
                    loading: false,
                    quote: quote,
                    error: null,
                    companyName: 'Voorbeeldbedrijf',
                    onRetry: () {},
                    onAirportContact: () {},
                  ),
                ),
              ),
            ),
          );
          expect(
            find.text(
              customerBookingAirportFareCompactBody(
                language,
                'taxi_outside_work_area',
              ),
            ),
            findsOneWidget,
          );
          expect(find.textContaining('€'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  test('airport contact contract drops stale amounts and keeps lead time', () {
    final quote = parseCompanyPlanQuote(
      _contactBody(lead: 'Minimaal 24 uur vooraf'),
      fingerprint: 'zuid',
    );
    expect(quote.requiresAirportFareContact, isTrue);
    expect(quote.displayTotalPrice, isNull);
    expect(quote.priceInclVat, isNull);
    expect(quote.fixedPriceSnapshot, isNull);
    expect(quote.breakdown, isNull);
    expect(quote.conditionCodes, contains('lead_time'));
    expect(quote.leadTimeLabel, 'Minimaal 24 uur vooraf');
    expect(customerBookingQuoteSupportsConfirm(quote: quote), isFalse);
  });

  test('a zero amount is not kept as an airport fare', () {
    final quote = parseCompanyPlanQuote(<String, dynamic>{
      'ok': true,
      'request_quote_required': true,
      'reason': 'no_fixed_airport_fare',
      'customer_action': 'contact_company',
      'price_incl_vat': 0,
      'total_price_incl_vat': 0,
      'distance_km': 12,
      'duration_min': 20,
    }, fingerprint: 'zero');
    expect(quote.displayTotalPrice, isNull);
    expect(quote.priceAvailable, isFalse);
  });

  test('another company can still return a calculated fare', () {
    final quote = parseCompanyPlanQuote(_fixedBody(), fingerprint: 'noord');
    expect(quote.requiresAirportFareContact, isFalse);
    expect(quote.displayTotalPrice, 61.5);
    expect(customerBookingQuoteSupportsConfirm(quote: quote), isTrue);
  });

  test('calculator-off taxi is not treated as an airport contact quote', () {
    final quote = parseCompanyPlanQuote(<String, dynamic>{
      'ok': true,
      'calculator_off': true,
      'request_quote_required': true,
      'price_incl_vat': null,
      'distance_km': 14.2,
      'duration_min': 22,
    }, fingerprint: 'taxi');
    expect(quote.requiresAirportFareContact, isFalse);
    expect(quote.calculatorOff, isTrue);
    expect(quote.displayTotalPrice, isNull);
  });

  test(
    'quote refusal and booking refusal both become contact, not a fare',
    () async {
      final client = _client(
        onPost: (path, body) async {
          if (path.endsWith('/book')) {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'ok': false,
                'error': 'request_quote_required',
              }),
              409,
            );
          }
          return http.Response(
            jsonEncode(<String, dynamic>{
              'ok': false,
              'error': 'request_quote_required',
              'price_incl_vat': 48,
            }),
            200,
          );
        },
      );
      final quote = await client.quote(
        request: const CompanyPlanQuoteRequest(
          fingerprint: 'refused',
          body: <String, dynamic>{'from': 'A', 'to': 'CRL'},
        ),
        entry: _airportEntry(_zuid),
      );
      expect(quote.requiresAirportFareContact, isTrue);
      expect(quote.displayTotalPrice, isNull);
      expect(
        customerBookingBookIssueFromRaw('request_quote_required'),
        kCustomerBookingIssueRequestQuoteRequired,
      );
      expect(
        customerBookingQuoteIssueFromRaw('route_failed'),
        kCustomerBookingIssueFailed,
      );
    },
  );

  test('public contact ignores a private phone on the same profile', () {
    final contact = customerBookingPublicContactFromProfile(<String, dynamic>{
      'phone': _customerPhone,
      'public_contact': <String, dynamic>{
        'public_phone': _zuidPhone,
        'booking_email': 'boek@zuid.example.test',
        'website': 'https://zuid.example.test',
      },
    });
    expect(contact.phone, _zuidPhone);
    expect(contact.phone.contains('470'), isFalse);
    expect(contact.email, 'boek@zuid.example.test');
  });

  testWidgets('airport contact shows the company notice and no amount', (
    tester,
  ) async {
    await _pump(
      tester,
      entry: _airportEntry(_zuid),
      availabilityEmpty: true,
      quotes: _client(
        onPost: (path, body) async {
          return http.Response(
            jsonEncode(_contactBody(lead: 'Minimaal 24 uur vooraf')),
            200,
          );
        },
      ),
    );
    expect(find.byKey(kCustomerBookingAirportFareNoticeKey), findsOneWidget);
    expect(find.text('Prijs op aanvraag'), findsWidgets);
    expect(find.textContaining('Geen vast luchthaventarief'), findsOneWidget);
    expect(find.textContaining('Zuid Luchthavenrit'), findsWidgets);
    expect(find.text('Contact'), findsOneWidget);
    expect(find.text('Minimaal 24 uur vooraf'), findsOneWidget);
    expect(find.textContaining('€'), findsNothing);
    expect(find.textContaining('99'), findsNothing);
    expect(find.byKey(kCustomerBookingConfirmKey), findsNothing);
    expect(find.byKey(kCustomerBookingNoVehicleAtTimeKey), findsNothing);
    expect(find.byKey(kCustomerBookingSuccessKey), findsNothing);

    await tester.tap(find.byKey(kCustomerBookingAirportContactKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCustomerBookingPublicContactSheetKey), findsOneWidget);
    expect(find.text(_zuidPhone), findsOneWidget);
    expect(find.text('boek@zuid.example.test'), findsOneWidget);
    expect(find.text(_noordPhone), findsNothing);
    expect(find.text(_customerPhone), findsNothing);
  });

  testWidgets('changed input clears the old notice and can restore a fare', (
    tester,
  ) async {
    await _pump(
      tester,
      entry: _airportEntry(_zuid),
      quotes: _client(
        onPost: (path, body) async {
          final priced = _passengersOf(body) > 1;
          return http.Response(
            jsonEncode(priced ? _fixedBody() : _contactBody()),
            200,
          );
        },
      ),
    );
    expect(find.byKey(kCustomerBookingAirportFareBodyKey), findsOneWidget);
    await _scrollTo(tester, find.byKey(kCustomerBookingPaxSummaryKey));
    await tester.tap(find.byKey(kCustomerBookingPaxSummaryKey));
    await tester.pump();
    await _scrollTo(tester, find.byKey(kCustomerBookingPaxIncKey));
    await tester.tap(find.byKey(kCustomerBookingPaxIncKey));
    await tester.pump();
    expect(find.byKey(kCustomerBookingAirportFareBodyKey), findsNothing);
    expect(find.textContaining('€'), findsNothing);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(kCustomerBookingAirportFareBodyKey), findsNothing);
    expect(find.textContaining('61'), findsWidgets);
    expect(find.byKey(kCustomerBookingConfirmKey), findsOneWidget);
  });

  testWidgets(
    'switching company drops the old quote and ignores a late reply',
    (tester) async {
      final zuidQuote = Completer<void>();
      final zuidProfile = Completer<void>();
      await _pump(
        tester,
        entry: _airportEntry(_zuid),
        companyPicker: (context, {required bool airportCapableOnly}) async {
          return _noord;
        },
        profileGet: _profiles(
          beforeProfile: (partnerId) async {
            if (partnerId == _zuid.partnerId) await zuidProfile.future;
          },
        ),
        quotes: _client(
          onPost: (path, body) async {
            if (_partnerOf(body) == _zuid.partnerId) {
              await zuidQuote.future;
              return http.Response(jsonEncode(_contactBody()), 200);
            }
            return http.Response(jsonEncode(_fixedBody()), 200);
          },
        ),
      );
      expect(find.textContaining('Zuid Luchthavenrit'), findsWidgets);
      await tester.ensureVisible(find.byKey(kCustomerBookingChangeCompanyKey));
      await tester.tap(find.byKey(kCustomerBookingChangeCompanyKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.textContaining('Noord Vaste Prijs'), findsWidgets);
      expect(find.textContaining('61'), findsWidgets);
      expect(find.byKey(kCustomerBookingAirportFareBodyKey), findsNothing);
      expect(find.text(_zuidPhone), findsNothing);

      zuidQuote.complete();
      zuidProfile.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Noord Vaste Prijs'), findsWidgets);
      expect(find.textContaining('61'), findsWidgets);
      expect(find.byKey(kCustomerBookingAirportFareBodyKey), findsNothing);
      expect(find.text(_zuidPhone), findsNothing);
      expect(find.textContaining('99'), findsNothing);
    },
  );

  testWidgets('a refused old quote becomes contact for the current company', (
    tester,
  ) async {
    var books = 0;
    await _pump(
      tester,
      entry: _airportEntry(_noord),
      profile: _customer(),
      quotes: _client(
        onPost: (path, body) async {
          if (path.endsWith('/book')) {
            books += 1;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'ok': false,
                'error': 'request_quote_required',
              }),
              409,
            );
          }
          return http.Response(jsonEncode(_fixedBody()), 200);
        },
      ),
    );
    expect(find.textContaining('61'), findsWidgets);
    await _scrollTo(tester, find.byKey(customerBookingVehicleKey('vh_noord')));
    await tester.tap(find.byKey(customerBookingVehicleKey('vh_noord')));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(kCustomerBookingConfirmKey), findsOneWidget);
    await tester.tap(find.byKey(kCustomerBookingConfirmKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCustomerBookingPaymentConfirmKey), findsOneWidget);
    await tester.tap(find.byKey(kCustomerBookingPaymentConfirmKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(books, 1);
    expect(find.byKey(kCustomerBookingSuccessKey), findsNothing);
    expect(find.byKey(kCustomerBookingAirportFareBodyKey), findsOneWidget);
    expect(find.textContaining('Noord Vaste Prijs'), findsWidgets);
    expect(find.textContaining('€'), findsNothing);
    expect(find.textContaining('61'), findsNothing);
    expect(find.byKey(kCustomerBookingConfirmKey), findsNothing);
    await tester.tap(find.byKey(kCustomerBookingAirportContactKey));
    await tester.pumpAndSettle();
    expect(find.text(_noordPhone), findsOneWidget);
    expect(find.text(_zuidPhone), findsNothing);
    expect(find.text(_customerPhone), findsNothing);
  });

  testWidgets('taxi calculator-off and route errors stay separate', (
    tester,
  ) async {
    await _pump(
      tester,
      entry: const CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        company: CustomerBookingCompany(
          partnerId: 'partner_taxi',
          companyName: 'Gewone Taxi',
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
      quotes: _client(
        onPost: (path, body) async {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'ok': true,
              'calculator_off': true,
              'request_quote_required': true,
              'price_incl_vat': null,
              'distance_km': 14.2,
              'duration_min': 22,
              'currency': 'EUR',
            }),
            200,
          );
        },
      ),
    );
    expect(find.textContaining('Prijs op aanvraag'), findsWidgets);
    expect(find.byKey(kCustomerBookingAirportFareBodyKey), findsNothing);
    expect(find.byKey(kCustomerBookingAirportContactKey), findsNothing);
    expect(find.textContaining('€'), findsNothing);
    expect(find.byKey(kCustomerBookingConfirmKey), findsOneWidget);
  });

  testWidgets('a route failure is not shown as price on request', (
    tester,
  ) async {
    await _pump(
      tester,
      entry: _airportEntry(_zuid),
      profile: _customer(),
      quotes: _client(
        onPost: (path, body) async {
          return http.Response(
            jsonEncode(<String, dynamic>{'ok': false, 'error': 'route_failed'}),
            200,
          );
        },
      ),
    );
    expect(find.byKey(kCustomerBookingAirportFareBodyKey), findsNothing);
    expect(find.byKey(kCustomerBookingAirportContactKey), findsNothing);
    expect(
      find.textContaining('De route kon niet worden berekend'),
      findsWidgets,
    );
    expect(find.textContaining('geen vast online tarief'), findsNothing);
  });
}
