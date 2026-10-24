import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_models.dart';
import 'package:fluxidi_tracking/company/company_booking_detail_page.dart';
import 'package:fluxidi_tracking/company/company_address_field.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_page.dart';
import 'package:fluxidi_tracking/company/company_form_date_time.dart';
import 'package:fluxidi_tracking/company/company_rate_card_hint.dart';
import 'package:fluxidi_tracking/company/company_ride_options_form.dart';
import 'package:fluxidi_tracking/company/company_customer_labels.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

CompanyCustomer _guest() {
  return parseCompanyCustomer(<String, dynamic>{
    'customer_id': 'cus_guest',
    'tenant_id': 'TA',
    'company_id': 'CA',
    'display_name': 'No App Guest',
    'status': 'active',
    'revision': 1,
    'email': '',
    'phone': '+32470000080',
  });
}

Map<String, dynamic> _quoteJson({
  String state = 'draft',
  String email = '',
  int revision = 1,
  int? amountCents,
  String delivery = '',
  bool testSend = false,
  String bookingId = '',
  bool bookingListReady = false,
}) {
  return <String, dynamic>{
    'ok': true,
    'quote': <String, dynamic>{
      'quote_id': 'cqq_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'customer_id': 'cus_guest',
      'state': state,
      'revision': revision,
      'issuer_name': 'Fluxidi Demo Cars',
      'pickup': 'Station',
      'dropoff': 'Airport',
      'start_at': '2026-09-20T09:00:00.000Z',
      'passengers': 2,
      'description': 'Transfer',
      'passenger_name': 'No App Guest',
      'passenger_email': email,
      if (amountCents != null) 'entered_amount_cents': amountCents,
      'currency': 'EUR',
      'vat_treatment': 'incl',
      'valid_until': '2026-09-25T00:00:00.000Z',
      'created_at': '2026-09-10T00:00:00.000Z',
      'updated_at': '2026-09-10T00:00:00.000Z',
      if (delivery.isNotEmpty) 'delivery': delivery,
      'delivery_proven': false,
      'test_send': testSend,
      if (bookingId.isNotEmpty) 'booking_id': bookingId,
      'booking_list_ready': bookingListReady,
    },
    if (delivery.isNotEmpty) 'delivery': delivery,
    'delivery_proven': false,
    if (testSend) 'test_send': true,
  };
}

class _FakeQuoteRepository extends CompanyCustomersRepository {
  _FakeQuoteRepository()
      : super(
          scopeQuery: const <String, String>{
            'tenant_id': 'TA',
            'company_id': 'CA',
          },
          headers: () async => const <String, String>{},
          listTransport: ({
            required path,
            required query,
            required headers,
          }) async =>
              <String, dynamic>{
            'ok': true,
            'items': <dynamic>[],
          },
          sendTransport: ({
            required method,
            required path,
            required query,
            required body,
            required headers,
            idempotencyKey,
          }) async =>
              <String, dynamic>{'ok': true},
        );

  CompanyCustomerQuote? draft;
  CompanyCustomerQuoteWrite? lastWrite;
  int createCalls = 0;
  int updateCalls = 0;
  int sendCalls = 0;

  @override
  Future<CompanyCustomerQuote> createQuote(
    String customerId,
    CompanyCustomerQuoteWrite write, {
    String? idempotencyKey,
  }) async {
    createCalls += 1;
    lastWrite = write;
    draft = parseCompanyCustomerQuote(<String, dynamic>{
      'ok': true,
      'quote': <String, dynamic>{
        ..._quoteJson(
          email: write.passengerEmail,
          revision: 1,
          amountCents: write.enteredAmountCents,
        )['quote'] as Map<String, dynamic>,
        'pickup': write.pickup,
        'dropoff': write.dropoff,
        'start_at': write.startAt,
        'valid_until': write.validUntil,
        'pickup_lat': write.pickupLat,
        'pickup_lon': write.pickupLon,
        'pickup_place_id': write.pickupPlaceId,
        'dropoff_lat': write.dropoffLat,
        'dropoff_lon': write.dropoffLon,
        'dropoff_place_id': write.dropoffPlaceId,
        'passenger_phone': write.passengerPhone,
        'description': write.description,
        'vat_treatment': write.vatTreatment,
        'vat_rate': write.vatRate,
        'currency': write.currency,
        'ride_options': write.rideOptions.toJson(),
      },
    });
    return draft!;
  }

  @override
  Future<CompanyCustomerQuote> updateQuote(
    String quoteId,
    CompanyCustomerQuoteWrite write, {
    required int revision,
  }) async {
    updateCalls += 1;
    lastWrite = write;
    draft = parseCompanyCustomerQuote(<String, dynamic>{
      'ok': true,
      'quote': <String, dynamic>{
        ..._quoteJson(
          email: write.passengerEmail,
          revision: revision,
          amountCents: write.enteredAmountCents,
        )['quote'] as Map<String, dynamic>,
        'pickup': write.pickup,
        'dropoff': write.dropoff,
        'start_at': write.startAt,
        'valid_until': write.validUntil,
        'pickup_lat': write.pickupLat,
        'pickup_lon': write.pickupLon,
        'pickup_place_id': write.pickupPlaceId,
        'dropoff_lat': write.dropoffLat,
        'dropoff_lon': write.dropoffLon,
        'dropoff_place_id': write.dropoffPlaceId,
        'passenger_phone': write.passengerPhone,
        'description': write.description,
        'vat_treatment': write.vatTreatment,
        'vat_rate': write.vatRate,
        'currency': write.currency,
        'ride_options': write.rideOptions.toJson(),
      },
    });
    return draft!;
  }

  @override
  Future<CompanyCustomerQuote> sendQuote(String quoteId) async {
    sendCalls += 1;
    draft = parseCompanyCustomerQuote(
      _quoteJson(
        state: 'sent',
        email: 'guest@p0quote.test',
        amountCents: 8000,
        delivery: 'test_adapter',
        testSend: true,
      ),
    );
    return draft!;
  }

  @override
  Future<CompanyCustomerQuote> getQuote(String quoteId) async {
    return draft ?? parseCompanyCustomerQuote(_quoteJson());
  }

  @override
  Future<List<CompanyCustomerQuote>> listQuotes(String customerId) async {
    return draft == null ? const <CompanyCustomerQuote>[] : <CompanyCustomerQuote>[draft!];
  }
}

CompanyCustomer _guestWithHome() {
  return parseCompanyCustomer(<String, dynamic>{
    'customer_id': 'cus_guest',
    'tenant_id': 'TA',
    'company_id': 'CA',
    'display_name': 'No App Guest',
    'status': 'active',
    'revision': 1,
    'email': '',
    'phone': '+32470000080',
    'addresses': <Map<String, dynamic>>[
      <String, dynamic>{
        'label': 'Thuis',
        'line1': 'Kunstlaan 44',
        'postal_code': '1000',
        'city': 'Brussel',
        'country_code': 'BE',
      },
    ],
  });
}

LimousinePlaceLookup _quoteLookup() {
  return LimousinePlaceLookup(
    searchOverride: (query, language) async {
      final text = query.toLowerCase();
      if (text.contains('kunst')) {
        return const LimousinePlaceLookupResult(
          suggestions: <LimousinePlaceSuggestion>[
            LimousinePlaceSuggestion(
              label: 'Kunstlaan 44, 1000 Brussel, België',
              lat: 50.843,
              lon: 4.368,
              placeId: 'place.kunstlaan',
            ),
          ],
        );
      }
      if (text.contains('centraal') || text.contains('antwerp')) {
        return const LimousinePlaceLookupResult(
          suggestions: <LimousinePlaceSuggestion>[
            LimousinePlaceSuggestion(
              label: 'Antwerpen-Centraal, 2018 Antwerpen, België',
              lat: 51.2172,
              lon: 4.4211,
              placeId: 'place.centraal',
            ),
          ],
        );
      }
      return const LimousinePlaceLookupResult();
    },
  );
}

Future<void> _confirmManualAddress(
  WidgetTester tester, {
  required Key fieldKey,
  required String fieldId,
  required String text,
}) async {
  await tester.ensureVisible(find.byKey(fieldKey));
  await tester.enterText(find.byKey(fieldKey), text);
  await tester.pump(const Duration(milliseconds: 260));
  await tester.pumpAndSettle();
  final manual = find.byKey(limousineAddressManualKey(fieldId));
  expect(manual, findsOneWidget);
  await tester.tap(manual);
  await tester.pump();
}

Future<void> _typeCompanyFormField(
  WidgetTester tester,
  Key key,
  String text,
) async {
  final field = tester.widget<TextField>(find.byKey(key));
  field.controller!.text = text;
  field.onSubmitted?.call(text);
  await tester.pump();
}

Future<void> _pumpQuote(
  WidgetTester tester, {
  required _FakeQuoteRepository repository,
  required Size size,
  CompanyCustomerQuote? existing,
  CompanyCustomer? customer,
  LimousinePlaceLookup? placeLookup,
  DateTime? initialStartAt,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: CompanyCustomerQuotePage(
          key: ValueKey<String>(
            'quote-${size.width}-${existing?.quoteId ?? 'new'}-${initialStartAt?.millisecondsSinceEpoch ?? 0}',
          ),
          repository: repository,
          customer: customer ?? _guest(),
          existing: existing,
          language: AppLanguage.nl,
          issuerName: 'Fluxidi Demo Cars',
          placeLookup: placeLookup,
          initialStartAt: initialStartAt,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('phone and tablet keep quote actions reachable', (tester) async {
    for (final size in <Size>[
      const Size(390, 844),
      const Size(800, 1280),
    ]) {
      final repo = _FakeQuoteRepository();
      await _pumpQuote(tester, repository: repo, size: size);
      expect(find.textContaining('Fluxidi Demo Cars'), findsWidgets);
      expect(find.byKey(kCompanyCustomerQuotePriceKey), findsOneWidget);
      await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteSaveKey));
      await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteSendKey));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('new quote leaves price empty and never falls back to 80 euro', (
    tester,
  ) async {
    final repo = _FakeQuoteRepository();
    await _pumpQuote(tester, repository: repo, size: const Size(390, 844));
    final priceField = tester.widget<TextFormField>(
      find.byKey(kCompanyCustomerQuotePriceKey),
    );
    expect(priceField.controller?.text, isEmpty);
    expect(find.text('80.00'), findsNothing);
    expect(priceField.controller?.text.contains('80'), isFalse);
    await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteSaveKey));
    await tester.tap(find.byKey(kCompanyCustomerQuoteSaveKey));
    await tester.pumpAndSettle();
    expect(repo.createCalls, 1);
    expect(repo.draft?.enteredAmountCents, isNull);
    await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteSendKey));
    await tester.tap(find.byKey(kCompanyCustomerQuoteSendKey));
    await tester.pumpAndSettle();
    expect(repo.sendCalls, 0);
    expect(
      find.text(kCompanyCustomerQuotePriceRequired.of(AppLanguage.nl)),
      findsWidgets,
    );
  });

  testWidgets('explicit 80 euro draft can be saved without email and reopened', (
    tester,
  ) async {
    final repo = _FakeQuoteRepository();
    await _pumpQuote(tester, repository: repo, size: const Size(390, 844));
    await tester.enterText(find.byKey(kCompanyCustomerQuotePriceKey), '80');
    await tester.enterText(find.byKey(kCompanyCustomerQuoteEmailKey), '');
    await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteSaveKey));
    await tester.tap(find.byKey(kCompanyCustomerQuoteSaveKey));
    await tester.pumpAndSettle();
    expect(repo.createCalls, 1);
    expect(repo.draft?.enteredAmountCents, 8000);
    expect(repo.lastWrite?.currency, 'EUR');
    expect(find.byKey(kCompanyCustomerQuoteDraftSavedKey), findsOneWidget);
    expect(find.text(kCompanyCustomerQuoteDraftSaved.of(AppLanguage.nl)), findsOneWidget);
    expect(find.text(kCompanyCustomerQuoteOpen.of(AppLanguage.nl)), findsOneWidget);
    expect(find.byKey(kCompanyCustomerQuoteSendChannelKey), findsOneWidget);
    expect(
      find.textContaining(kCompanyCustomerQuoteSendChannelEmail.of(AppLanguage.nl)),
      findsWidgets,
    );
    expect(
      find.text(kCompanyCustomerQuotePhoneNotChannel.of(AppLanguage.nl)),
      findsOneWidget,
    );

    await _pumpQuote(
      tester,
      repository: repo,
      size: const Size(800, 1280),
      existing: repo.draft,
    );
    expect(find.text('80.00'), findsOneWidget);
    expect(find.textContaining('Fluxidi Demo Cars'), findsWidgets);
    await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteSendKey));
    await tester.tap(find.byKey(kCompanyCustomerQuoteSendKey));
    await tester.pumpAndSettle();
    expect(repo.sendCalls, 0);
    expect(find.text(kCompanyCustomerQuoteEmailRequired.of(AppLanguage.nl)), findsWidgets);

    await tester.enterText(
      find.byKey(kCompanyCustomerQuoteEmailKey),
      'guest@p0quote.test',
    );
    await _confirmManualAddress(
      tester,
      fieldKey: kCompanyCustomerQuotePickupFieldKey,
      fieldId: 'quote_pickup',
      text: 'Station Antwerpen',
    );
    await _confirmManualAddress(
      tester,
      fieldKey: kCompanyCustomerQuoteDropoffFieldKey,
      fieldId: 'quote_dropoff',
      text: 'Brussel Zuid',
    );
    await tester.tap(find.byKey(kCompanyCustomerQuoteReviewKey));
    await tester.pumpAndSettle();
    expect(find.textContaining('EUR 80.00'), findsWidgets);
    expect(find.textContaining('Handmatig adres'), findsWidgets);
    expect(
      find.textContaining(
        '${kCompanyCustomerQuoteSendChannel.of(AppLanguage.nl)}: ${kCompanyCustomerQuoteSendChannelEmail.of(AppLanguage.nl)}',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('guest@p0quote.test'),
      findsWidgets,
    );
    expect(
      find.text(kCompanyCustomerQuotePhoneNotChannel.of(AppLanguage.nl)),
      findsOneWidget,
    );
    await tester.tap(find.byKey(kCompanyCustomerQuoteSendKey));
    await tester.pumpAndSettle();
    expect(repo.sendCalls, 1);
    expect(find.text(kCompanyCustomerQuoteSent.of(AppLanguage.nl)), findsOneWidget);
  });

  testWidgets('accepted quote opens the existing booking from the quote page', (
    tester,
  ) async {
    final repo = _FakeQuoteRepository();
    var opened = '';
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyCustomerQuotePage(
          repository: repo,
          customer: _guest(),
          language: AppLanguage.nl,
          issuerName: 'Fluxidi Demo Cars',
          onOpenBooking: (bookingId) => opened = bookingId,
          existing: parseCompanyCustomerQuote(
            _quoteJson(
              state: 'accepted',
              amountCents: 9500,
              bookingId: 'cqb_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              bookingListReady: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(kCompanyCustomerQuoteViewBooking.of(AppLanguage.nl)), findsOneWidget);
    expect(
      find.text(kCompanyCustomerQuoteAssignmentPending.of(AppLanguage.nl)),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteViewBookingKey));
    await tester.tap(find.byKey(kCompanyCustomerQuoteViewBookingKey));
    await tester.pump();
    expect(opened, 'cqb_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
  });

  testWidgets('quote booking detail pops back to the same quote page', (
    tester,
  ) async {
    final repo = _FakeQuoteRepository();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyCustomerQuotePage(
          repository: repo,
          customer: _guest(),
          language: AppLanguage.nl,
          issuerName: 'Fluxidi Demo Cars',
          existing: parseCompanyCustomerQuote(
            _quoteJson(
              state: 'accepted',
              amountCents: 9500,
              bookingId: 'cqb_ae3b84ee25e4f6505adc0b076192d394',
              bookingListReady: true,
            ),
          ),
          onOpenBooking: (bookingId) {
            final nav = tester.element(find.byType(CompanyCustomerQuotePage));
            openCompanyBookingDetail(
              nav,
              bookingId: bookingId,
              language: AppLanguage.nl,
              openedFrom: CompanyBookingOpenedFrom.quote,
              loader: (id) async => <String, dynamic>{
                'ok': true,
                'status': 'PENDING',
                'record': <String, dynamic>{
                  'booking_id': id,
                  'customer_name': 'Ada Lovelace',
                  'from': 'Brussel-Zuid',
                  'to': 'Antwerpen-Centraal',
                  'quote_id': 'cqq_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                },
              },
              driversLoader: () async => const <Map<String, dynamic>>[],
              vehiclesLoader: () async => const <Map<String, dynamic>>[],
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteViewBookingKey));
    await tester.tap(find.byKey(kCompanyCustomerQuoteViewBookingKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyBookingDetailPageKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaBackToQuoteHintKey), findsOneWidget);
    expect(find.textContaining('Terug gaat naar de offerte'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyCustomerQuotePageKey), findsOneWidget);
    expect(find.byKey(kCompanyBookingDetailPageKey), findsNothing);
    expect(find.byKey(kCompanyCustomerQuoteViewBookingKey), findsOneWidget);
  });

  testWidgets('quote form keeps helpers and ride options outside field frames', (
    tester,
  ) async {
    final repo = _FakeQuoteRepository();
    await _pumpQuote(tester, repository: repo, size: const Size(390, 844));
    expect(find.byKey(kCompanyCustomerQuotePhoneKey), findsOneWidget);
    expect(find.byKey(kCompanyRideServiceKey), findsOneWidget);
    expect(find.byKey(kCompanyTripRouteAddressKey), findsOneWidget);
    expect(find.byKey(kCompanyTripRouteToAirportKey), findsOneWidget);
    expect(find.byKey(kCompanyTripRouteFromAirportKey), findsOneWidget);
    expect(find.byKey(kCompanyTripRouteSwapKey), findsOneWidget);
    expect(find.byKey(kCompanyRideTierKey), findsOneWidget);
    expect(
      find.text(kCompanyCustomerQuoteEmailRequired.of(AppLanguage.nl)),
      findsWidgets,
    );
    expect(
      find.text(kCompanyCustomerQuotePublicDescriptionHint.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(find.textContaining('Toegepast'), findsNothing);
    expect(find.textContaining('Starttarief'), findsNothing);
    expect(find.textContaining('Per km'), findsNothing);
    expect(find.textContaining('Vaste luchthavenprijzen'), findsNothing);
    expect(find.textContaining('Vaste prijs gebruiken'), findsNothing);
    expect(find.byKey(kCompanyCustomerQuoteCurrencyKey), findsOneWidget);
    expect(find.byKey(kCompanyCustomerQuoteIncludedKey), findsOneWidget);
    expect(
      find.text(kCompanyCustomerQuoteVat.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(
      find.text(kCompanyCustomerQuoteValidUntil.of(AppLanguage.nl)),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(kCompanyTripRouteToAirportKey));
    await tester.tap(find.byKey(kCompanyTripRouteToAirportKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAirportSearchFieldKey), findsOneWidget);
    expect(find.byKey(kCompanyRideFlightKey), findsOneWidget);
    expect(find.byKey(kCompanyRideMeetAndGreetKey), findsOneWidget);
    expect(find.byKey(kCompanyRideNameBoardKey), findsOneWidget);
    expect(find.textContaining('Starttarief'), findsNothing);
    expect(find.textContaining('Vaste prijs gebruiken'), findsNothing);
    await tester.ensureVisible(
      find.text(kCompanyCustomerQuoteViewRates.of(AppLanguage.nl)),
    );
    await tester.tap(find.text(kCompanyCustomerQuoteViewRates.of(AppLanguage.nl)));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyInternalRatesPanelKey), findsOneWidget);
    expect(find.textContaining('Starttarief'), findsWidgets);
    expect(
      find.text(kCompanyCustomerQuoteRatesDisclaimer.of(AppLanguage.nl)),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteSaveKey));
    await tester.tap(find.byKey(kCompanyCustomerQuoteSaveKey));
    await tester.pumpAndSettle();
    expect(repo.createCalls, 1);
    expect(repo.lastWrite?.rideOptions.service, 'airport');
    expect(repo.lastWrite?.passengerPhone, '+32470000080');
    expect(tester.takeException(), isNull);
  });

  testWidgets('quote date time is local in the form and ISO only on save', (
    tester,
  ) async {
    final repo = _FakeQuoteRepository();
    await _pumpQuote(
      tester,
      repository: repo,
      size: const Size(390, 844),
      existing: parseCompanyCustomerQuote(_quoteJson()),
    );
    expect(find.textContaining('2026-09-20T'), findsNothing);
    expect(find.textContaining('september 2026'), findsWidgets);
    expect(find.text(kCompanyFormDate.of(AppLanguage.nl)), findsWidgets);
    expect(find.text(kCompanyCustomerQuoteStart.of(AppLanguage.nl)), findsNothing);
    await _typeCompanyFormField(
      tester,
      companyFormDateFieldKey('quote_start'),
      '21/9/2026',
    );
    await _typeCompanyFormField(
      tester,
      companyFormTimeFieldKey('quote_start'),
      '16:30',
    );
    await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteSaveKey));
    await tester.tap(find.byKey(kCompanyCustomerQuoteSaveKey));
    await tester.pumpAndSettle();
    expect(repo.updateCalls, 1);
    expect(repo.lastWrite?.startAt.contains('T'), isTrue);
    expect(companyFormLooksLikeIsoTimestamp(repo.lastWrite!.startAt), isTrue);
    final saved = DateTime.parse(repo.lastWrite!.startAt).toLocal();
    expect(saved.day, 21);
    expect(saved.month, 9);
    expect(saved.hour, 16);
    expect(saved.minute, 30);
  });

  testWidgets(
    'address suggestion and local date survive draft save and reopen',
    (tester) async {
      final repo = _FakeQuoteRepository();
      final lookup = _quoteLookup();
      addTearDown(lookup.dispose);
      await _pumpQuote(
        tester,
        repository: repo,
        size: const Size(390, 844),
        customer: _guestWithHome(),
        placeLookup: lookup,
      );
      expect(find.text(kCompanySavedAddresses.of(AppLanguage.nl)), findsNothing);
      await tester.ensureVisible(find.byKey(kCompanyCustomerQuotePickupFieldKey));
      await tester.enterText(
        find.byKey(kCompanyCustomerQuotePickupFieldKey),
        'Kunstlaan 44 Brussel',
      );
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kunstlaan 44, 1000 Brussel, België').last);
      await tester.pump();
      await tester.enterText(
        find.byKey(kCompanyCustomerQuoteDropoffFieldKey),
        'Antwerpen-Centraal',
      );
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Antwerpen-Centraal, 2018 Antwerpen, België').last);
      await tester.pump();
      await _typeCompanyFormField(
        tester,
        companyFormDateFieldKey('quote_start'),
        '21/9/2026',
      );
      await _typeCompanyFormField(
        tester,
        companyFormTimeFieldKey('quote_start'),
        '16:30',
      );
      await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteSaveKey));
      await tester.tap(find.byKey(kCompanyCustomerQuoteSaveKey));
      await tester.pumpAndSettle();
      expect(repo.lastWrite?.pickupLat, 50.843);
      expect(repo.lastWrite?.pickupPlaceId, 'place.kunstlaan');
      expect(repo.lastWrite?.dropoffLon, 4.4211);
      expect(companyFormLooksLikeIsoTimestamp(repo.lastWrite!.startAt), isTrue);
      final saved = repo.draft!;

      await _pumpQuote(
        tester,
        repository: repo,
        size: const Size(390, 844),
        customer: _guestWithHome(),
        existing: saved,
        placeLookup: lookup,
      );
      expect(find.textContaining('2026-09-21T'), findsNothing);
      expect(find.textContaining('2026-09-20T'), findsNothing);
      expect(find.textContaining('september 2026'), findsWidgets);
      expect(find.textContaining('16:30'), findsWidgets);
      expect(find.text('Kunstlaan 44, 1000 Brussel, België'), findsWidgets);
      expect(find.text('Antwerpen-Centraal, 2018 Antwerpen, België'), findsWidgets);

      await tester.enterText(
        find.byKey(kCompanyCustomerQuotePickupFieldKey),
        'Kunstlaan 44 gewijzigd',
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteSaveKey));
      await tester.tap(find.byKey(kCompanyCustomerQuoteSaveKey));
      await tester.pumpAndSettle();
      expect(repo.lastWrite?.pickup.contains('gewijzigd'), isTrue);
      expect(repo.lastWrite?.pickupLat, isNull);
      expect(repo.lastWrite?.pickupPlaceId, isEmpty);
    },
  );

  testWidgets('review labels selected, manual and incomplete destinations', (
    tester,
  ) async {
    final repo = _FakeQuoteRepository();
    final lookup = _quoteLookup();
    addTearDown(lookup.dispose);
    await _pumpQuote(
      tester,
      repository: repo,
      size: const Size(390, 844),
      placeLookup: lookup,
    );
    await tester.ensureVisible(find.byKey(kCompanyCustomerQuotePickupFieldKey));
    await tester.enterText(
      find.byKey(kCompanyCustomerQuotePickupFieldKey),
      'Kunstlaan 44 Brussel',
    );
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(limousineAddressSuggestionKey('quote_pickup', 0)));
    await tester.pump();
    await tester.enterText(find.byKey(kCompanyCustomerQuoteDropoffFieldKey), 'gent');
    await tester.pump();
    await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteReviewKey));
    await tester.tap(find.byKey(kCompanyCustomerQuoteReviewKey));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteReviewPickupKey));
    expect(
      tester.widget<Text>(find.byKey(kCompanyCustomerQuoteReviewPickupKey)).data,
      contains('Uit voorstel'),
    );
    expect(
      tester.widget<Text>(find.byKey(kCompanyCustomerQuoteReviewDropoffKey)).data,
      contains('Onvolledig adres'),
    );
    expect(find.byKey(kCompanyCustomerQuoteAddressWarningKey), findsOneWidget);
    await tester.enterText(find.byKey(kCompanyCustomerQuotePriceKey), '110');
    await tester.enterText(
      find.byKey(kCompanyCustomerQuoteEmailKey),
      'guest@p0quote.test',
    );
    await tester.tap(find.byKey(kCompanyCustomerQuoteSendKey));
    await tester.pumpAndSettle();
    expect(repo.sendCalls, 0);
    expect(
      find.text(kCompanyCustomerQuoteAddressRequired.of(AppLanguage.nl)),
      findsWidgets,
    );

    await _confirmManualAddress(
      tester,
      fieldKey: kCompanyCustomerQuoteDropoffFieldKey,
      fieldId: 'quote_dropoff',
      text: 'Korenmarkt 1, Gent',
    );
    await tester.tap(find.byKey(kCompanyCustomerQuoteReviewKey));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(kCompanyCustomerQuoteReviewDropoffKey)).data,
      contains('Handmatig adres'),
    );
    expect(find.byKey(kCompanyCustomerQuoteAddressWarningKey), findsNothing);
    await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteSaveKey));
    await tester.tap(find.byKey(kCompanyCustomerQuoteSaveKey));
    await tester.pumpAndSettle();
    expect(repo.lastWrite?.dropoff, 'Korenmarkt 1, Gent');
    expect(repo.lastWrite?.dropoffLat, isNull);
  });

  testWidgets('review shows translated ride options, not raw codes', (
    tester,
  ) async {
    final repo = _FakeQuoteRepository();
    await _pumpQuote(tester, repository: repo, size: const Size(390, 844));
    await tester.ensureVisible(find.byKey(kCompanyRideServiceKey));
    await tester.tap(find.byKey(kCompanyRideServiceKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zakelijk').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kCompanyRideTierKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Premium').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kCompanyRideExtraKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Werktafel (laptop)').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(kCompanyCustomerQuoteDescriptionKey),
      'Transfer Madrid-Gent',
    );
    await tester.pump();
    expect(find.textContaining('Zakelijk · Premium · Werktafel (laptop)'), findsWidgets);
    expect(find.text('business · premium · worktable'), findsNothing);
    expect(find.text(kCompanyCustomerQuoteIncluded.of(AppLanguage.nl)), findsWidgets);
    expect(
      find.text(kCompanyCustomerQuotePriceConditions.of(AppLanguage.nl)),
      findsWidgets,
    );
    await tester.tap(find.byKey(kCompanyCustomerQuoteReviewKey));
    await tester.pumpAndSettle();
    expect(find.textContaining('Zakelijk · Premium · Werktafel (laptop)'), findsWidgets);
    expect(find.textContaining('worktable'), findsNothing);
  });

  testWidgets('excl VAT shows percent, amount and total from settings', (
    tester,
  ) async {
    final repo = _FakeQuoteRepository();
    await _pumpQuote(tester, repository: repo, size: const Size(390, 844));
    await tester.enterText(find.byKey(kCompanyCustomerQuotePriceKey), '110');
    await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteVatFieldKey));
    await tester.tap(find.text(kCompanyCustomerQuoteVatIncl.of(AppLanguage.nl)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(kCompanyCustomerQuoteVatExcl.of(AppLanguage.nl)).last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Btw 6%'), findsWidgets);
    expect(find.textContaining('EUR 6.60'), findsWidgets);
    expect(find.textContaining('Totaal incl. btw EUR 116.60'), findsWidgets);
    expect(find.textContaining('21'), findsNothing);
    await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteSaveKey));
    await tester.tap(find.byKey(kCompanyCustomerQuoteSaveKey));
    await tester.pumpAndSettle();
    expect(repo.lastWrite?.vatTreatment, 'excl');
    expect(repo.lastWrite?.vatRate, 6);
  });

  testWidgets('missing VAT rate is explicit and never invents 21 percent', (
    tester,
  ) async {
    final before = businessSettingsNotifier.value;
    addTearDown(() => businessSettingsNotifier.value = before);
    businessSettingsNotifier.value = before.copyWith(pricingVatRate: 0);
    final repo = _FakeQuoteRepository();
    await _pumpQuote(tester, repository: repo, size: const Size(390, 844));
    await tester.enterText(find.byKey(kCompanyCustomerQuotePriceKey), '110');
    await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteVatFieldKey));
    await tester.tap(find.text(kCompanyCustomerQuoteVatIncl.of(AppLanguage.nl)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(kCompanyCustomerQuoteVatExcl.of(AppLanguage.nl)).last);
    await tester.pumpAndSettle();
    expect(
      find.text(kCompanyCustomerQuoteVatRateMissing.of(AppLanguage.nl)),
      findsWidgets,
    );
    expect(find.textContaining('21'), findsNothing);
    expect(find.textContaining('116.60'), findsNothing);
    await tester.tap(find.byKey(kCompanyCustomerQuoteSaveKey));
    await tester.pumpAndSettle();
    expect(repo.lastWrite?.vatRate, isNull);
  });

  testWidgets('reopened return quote keeps a different return address', (
    tester,
  ) async {
    final raw = _quoteJson(state: 'sent', amountCents: 18000);
    (raw['quote'] as Map<String, dynamic>).addAll(<String, dynamic>{
      'pickup': 'Leuven station, Leuven',
      'dropoff': 'Brussel Centraal, Brussel',
      'return_enabled': true,
      'roundtrip_dispatch_mode': 'split_no_wait',
      'return_pickup_iso': '2026-09-18T16:30:00.000Z',
      'return_from': 'Antwerpen Centraal, Antwerpen',
      'return_to': 'Gent-Sint-Pieters station, Gent',
    });
    await _pumpQuote(
      tester,
      repository: _FakeQuoteRepository(),
      size: const Size(390, 844),
      existing: parseCompanyCustomerQuote(raw),
    );
    expect(find.text('Leuven station, Leuven'), findsWidgets);
    expect(find.text('Brussel Centraal, Brussel'), findsWidgets);
    expect(find.text('Antwerpen Centraal, Antwerpen'), findsNothing);
    expect(find.text('Gent-Sint-Pieters station, Gent'), findsWidgets);
    expect(find.text(kCompanyRoundtripReturnToPlace.of(AppLanguage.nl)), findsOneWidget);
  });

  testWidgets('agenda moment fills quote time', (tester) async {
    await _pumpQuote(
      tester,
      repository: _FakeQuoteRepository(),
      size: const Size(390, 844),
      initialStartAt: DateTime(2026, 9, 14, 10, 0),
    );
    expect(find.text('14 september 2026'), findsWidgets);
    expect(find.text('10:00'), findsWidgets);
  });

  testWidgets('customer-only quote leaves start time empty', (tester) async {
    await _pumpQuote(
      tester,
      repository: _FakeQuoteRepository(),
      size: const Size(390, 844),
    );
    expect(find.text('14 september 2026'), findsNothing);
    final startDate = tester.widget<TextField>(
      find.byKey(companyFormDateFieldKey('quote_start')),
    );
    expect(startDate.controller?.text.trim(), isEmpty);
  });

  testWidgets('airport search and swap keep IATA and clear flight time', (
    tester,
  ) async {
    final repo = _FakeQuoteRepository();
    await _pumpQuote(tester, repository: repo, size: const Size(390, 844));
    await tester.ensureVisible(find.byKey(kCompanyTripRouteToAirportKey));
    await tester.tap(find.byKey(kCompanyTripRouteToAirportKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(kCompanyAirportSearchFieldKey), 'bru');
    await tester.pumpAndSettle();
    expect(find.byKey(companyAirportSuggestionKey('BRU')), findsOneWidget);
    await tester.tap(find.byKey(companyAirportSuggestionKey('BRU')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(kCompanyRideFlightKey), 'SN1234');
    await tester.pump();
    await _typeCompanyFormField(
      tester,
      companyFormDateFieldKey('ride_flight'),
      '20/9/2026',
    );
    await _typeCompanyFormField(
      tester,
      companyFormTimeFieldKey('ride_flight'),
      '14:00',
    );
    await tester.ensureVisible(find.byKey(kCompanyTripRouteSwapKey));
    await tester.tap(find.byKey(kCompanyTripRouteSwapKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyTripRouteFromAirportKey), findsOneWidget);
    expect(find.text(kCompanyCustomerQuoteFlightAtInbound.of(AppLanguage.nl)), findsWidgets);
    expect(find.text('14:00'), findsNothing);
    await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteSaveKey));
    await tester.tap(find.byKey(kCompanyCustomerQuoteSaveKey));
    await tester.pumpAndSettle();
    expect(repo.lastWrite?.rideOptions.airportIata, 'BRU');
    expect(repo.lastWrite?.rideOptions.airportDirection, 'from_airport');
    expect(repo.lastWrite?.rideOptions.flightNumber, 'SN1234');
    expect(repo.lastWrite?.rideOptions.flightAt, isEmpty);
  });

  testWidgets('flight number field stays above sticky quote actions', (
    tester,
  ) async {
    await _pumpQuote(
      tester,
      repository: _FakeQuoteRepository(),
      size: const Size(390, 844),
    );
    await tester.ensureVisible(find.byKey(kCompanyTripRouteToAirportKey));
    await tester.tap(find.byKey(kCompanyTripRouteToAirportKey));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(kCompanyRideFlightKey));
    await tester.pumpAndSettle();
    final flight = tester.getRect(find.byKey(kCompanyRideFlightKey));
    final save = tester.getRect(find.byKey(kCompanyCustomerQuoteSaveKey));
    expect(flight.bottom, lessThanOrEqualTo(save.top));
    await tester.enterText(find.byKey(kCompanyRideFlightKey), 'SN1234');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byKey(kCompanyRideFlightKey)).controller?.text,
      'SN1234',
    );
  });

  testWidgets('save draft recovers after connection error', (tester) async {
    final repo = _OfflineCreateQuoteRepository();
    await _pumpQuote(tester, repository: repo, size: const Size(390, 844));
    await tester.enterText(find.byKey(kCompanyCustomerQuotePriceKey), '80');
    await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteSaveKey));
    await tester.tap(find.byKey(kCompanyCustomerQuoteSaveKey));
    await tester.pumpAndSettle();
    expect(repo.createCalls, 1);
    expect(find.text(kCompanyCustomersOffline.of(AppLanguage.nl)), findsWidgets);
    expect(find.byKey(kCompanyCustomerQuoteRetryKey), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(kCompanyCustomerQuoteSaveKey))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(kCompanyCustomerQuotePriceKey))
          .controller
          ?.text,
      '80',
    );
    await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteRetryKey));
    await tester.tap(find.byKey(kCompanyCustomerQuoteRetryKey));
    await tester.pumpAndSettle();
    expect(repo.createCalls, 2);
    expect(
      tester
          .widget<FilledButton>(find.byKey(kCompanyCustomerQuoteSaveKey))
          .onPressed,
      isNotNull,
    );
  });
}

class _OfflineCreateQuoteRepository extends _FakeQuoteRepository {
  @override
  Future<CompanyCustomerQuote> createQuote(
    String customerId,
    CompanyCustomerQuoteWrite write, {
    String? idempotencyKey,
  }) async {
    createCalls += 1;
    lastWrite = write;
    throw const CompanyCustomerException('transport_failed', offline: true);
  }
}
