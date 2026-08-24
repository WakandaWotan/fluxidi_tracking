import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_external_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_external_quote_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_detail_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_presentation.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_respond_form.dart';
import 'package:fluxidi_tracking/payment/booking_payment_options.dart';
import 'package:fluxidi_tracking/payment/payment_method_catalog.dart';

const String _champagne = '2 flessen champagne';

VehicleProfile _vehicle() {
  return VehicleProfile(
    id: 'veh_limo',
    vehicleName: 'Party Limo',
    brandModel: 'Party Limo',
    licensePlate: '1-TST-001',
    color: 'black',
    passengerCapacity: 8,
    luggageCapacity: 4,
    tierId: 'comfort',
    isActive: true,
    driverId: null,
    companyId: 'company_limo_p3q',
    primaryPhotoRef: '',
    galleryPhotoRefs: const <String>[],
    serviceCategory: 'limousine',
    serviceClassId: 'stretch_limousine',
  );
}

Map<String, dynamic> _offer() {
  return <String, dynamic>{
    'offer_id': 'off_quote',
    'enabled': true,
    'published': true,
    'vehicle_id': 'veh_limo',
    'service_class_id': 'stretch_limousine',
    'target_type': LimousineOfferTarget.vehicle,
    'price_presentation': LimousinePricePresentation.quoteRequired,
    'currency': 'EUR',
  };
}

class _SilentLookup extends LimousinePlaceLookup {
  _SilentLookup()
    : super(
        searchOverride: (query, language) async {
          return const LimousinePlaceLookupResult();
        },
      );
}

class _RecordingGateway implements LimousineExternalQuoteGateway {
  Map<String, dynamic>? lastQuote;
  int createCalls = 0;

  @override
  Future<LimousineExternalQuoteCreateResult> createExternal({
    required LimousineExternalContactSummary contact,
    required LimousineExternalJourneyDraft request,
    required Map<String, dynamic> quote,
    String? tenantId,
    String? companyId,
  }) async {
    createCalls += 1;
    lastQuote = quote;
    return LimousineExternalQuoteCreateResult(
      record: LimousineQuoteRequest.fromJson(<String, dynamic>{
        'quote_request_id': 'limq_notes',
        'state': 'customer_acceptance_required',
        'revision': 1,
        'origin_channel': kLimousineExternalOriginChannel,
        'quote': quote,
      }),
      invitationUrl: 'https://booking.internal/l/i/token',
      contact: contact,
    );
  }

  @override
  Future<LimousineExternalInvitationResult> invitation({
    required String quoteRequestId,
    required String action,
    String? tenantId,
    String? companyId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<LimousineExternalContactSummary> contact({
    required String quoteRequestId,
    String? tenantId,
    String? companyId,
  }) async {
    throw UnimplementedError();
  }
}

class _InboxGateway implements LimousineQuoteInboxGateway {
  _InboxGateway(this.record);

  final LimousineQuoteRequest record;

  @override
  Future<LimousineQuoteInboxPageData> list({
    int pageSize = kLimousineQuoteInboxPageDefault,
    String? state,
    String? cursor,
    String? updatedSince,
    String? tenantId,
    String? companyId,
  }) async {
    return LimousineQuoteInboxPageData(items: <LimousineQuoteRequest>[record]);
  }

  @override
  Future<LimousineQuoteRequest> detail(
    String quoteRequestId, {
    String? tenantId,
    String? companyId,
  }) async {
    return record;
  }

  @override
  Future<LimousineQuoteRespondResult> respond({
    required String quoteRequestId,
    required String action,
    required int expectedRevision,
    Map<String, dynamic>? quote,
    LimousineDeclineDraft? decline,
    String? tenantId,
    String? companyId,
  }) async {
    return LimousineQuoteRespondResult(record: record);
  }

  @override
  Future<Uint8List> fetchQuotationPdf({
    required String quoteRequestId,
    required int revision,
    String? tenantId,
    String? companyId,
  }) async {
    throw UnimplementedError();
  }
}

class _NoopBookGateway implements LimousineAcceptedBookingGateway {
  @override
  Future<LimousineAcceptedBookResult> book(Map<String, dynamic> payload) async {
    return const LimousineAcceptedBookResult(
      bookingId: 'B-1',
      publicReference: 'FLX-1',
      raw: <String, dynamic>{'ok': true},
    );
  }
}

LimousineCompanyQuoteDraft _draft({
  String included = _champagne,
  String mobilisation = 'Vanuit depot',
  String obligations = 'Klaarstaan op de ophaallocatie',
  String important = 'Niet roken',
}) {
  return LimousineCompanyQuoteDraft(
    totalInclVatCents: 100000,
    currency: 'EUR',
    vatTreatment: 'excl',
    vatRate: 0.06,
    expiresAt: '2099-01-01T00:00:00Z',
    cancellationDeadlineHours: 24,
    cancellationPenaltyPercent: 25,
    waitingTimeIncludedMinutes: 15,
    noShowPenaltyPercent: 100,
    overtimeCentsPerHour: 9000,
    includedServices: limousineQuoteIncludedServicesFromFreeText(included),
    mobilisationDisclosure: limousineUntranslatedNoteMap(mobilisation),
    customerObligations: limousineUntranslatedNoteMap(obligations),
    importantInformation: limousineUntranslatedNoteMap(important),
  );
}

LimousineQuoteRequest _quotedRecord({
  String state = 'customer_acceptance_required',
}) {
  final payload = _draft().toWorkerQuote();
  final terms = Map<String, dynamic>.from(payload['terms'] as Map);
  return LimousineQuoteRequest.fromJson(<String, dynamic>{
    'quote_request_id': 'limq_notes',
    'state': state,
    'revision': 3,
    'origin_channel': kLimousineExternalOriginChannel,
    'vehicle_snapshot': <String, dynamic>{'public_name': 'Party Limo'},
    'scheduled_pickup_iso': '2026-10-01T16:00:00Z',
    'fulfilment': <String, dynamic>{
      'from': 'Korenmarkt 1, Gent',
      'to': 'Graslei, Gent',
    },
    'quote': <String, dynamic>{
      ...payload,
      'included_services': terms['included_services'],
      'mobilisation_disclosure': terms['mobilisation_disclosure'],
    },
  });
}

Widget _app(Widget child, {Size size = const Size(430, 1800)}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: child,
    ),
  );
}

Future<void> _fillRequiredJourney(WidgetTester tester) async {
  await tester.enterText(find.byKey(kLimousineExternalContactNameKey), 'Ada');
  await tester.enterText(
    find.byKey(kLimousineExternalContactEmailKey),
    'ada@example.test',
  );
  await tester.enterText(
    find.byKey(kLimousineExternalPickupKey),
    'Korenmarkt 1, Gent',
  );
  await tester.enterText(
    find.byKey(kLimousineExternalDestinationKey),
    'Graslei, Gent',
  );
  await tester.enterText(find.byKey(kLimousineExternalPaxKey), '8');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    appLanguageNotifier.value = AppLanguage.nl;
    businessThemeNotifier.value = BusinessThemeVariant.cleanProfessional;
  });

  test(
    'note labels stay localized and free text is copied, not translated',
    () {
      expect(kLimousineQuoteIncludedServices.nl, 'Inbegrepen diensten');
      expect(kLimousineQuoteIncludedServices.en, 'Included services');
      expect(kLimousineQuoteIncludedServices.fr, 'Services inclus');
      expect(kLimousineQuoteIncludedServices.es, 'Servicios incluidos');
      expect(kLimousineQuoteMobilisation.nl, 'Mobilisatie');
      expect(kLimousineQuoteMobilisation.en, 'Mobilisation');
      expect(kLimousineQuoteMobilisation.fr, 'Mobilisation');
      expect(kLimousineQuoteMobilisation.es, 'Movilización');
      expect(kLimousineQuoteCustomerObligations.nl, 'Klantverplichtingen');
      expect(kLimousineQuoteCustomerObligations.en, 'Customer obligations');
      expect(kLimousineQuoteCustomerObligations.fr, 'Obligations du client');
      expect(kLimousineQuoteCustomerObligations.es, 'Obligaciones del cliente');
      expect(kLimousineQuoteImportantInfo.nl, 'Belangrijke informatie');
      expect(kLimousineQuoteImportantInfo.en, 'Important information');
      expect(kLimousineQuoteImportantInfo.fr, 'Informations importantes');
      expect(kLimousineQuoteImportantInfo.es, 'Información importante');
      final copied = limousineUntranslatedNoteMap(_champagne);
      expect(copied['nl'], _champagne);
      expect(copied['en'], _champagne);
      expect(copied['fr'], _champagne);
      expect(copied['es'], _champagne);
      for (final language in AppLanguage.values) {
        if (language == AppLanguage.de) continue;
        final lines = limousineQuoteCommercialNotesFromDraft(
          _draft(),
          language: language,
        );
        expect(lines.map((line) => line.value), contains(_champagne));
        expect(lines.first.label.of(language), isNot(_champagne));
      }
      expect(
        limousineQuoteCommercialNotesFromDraft(
          const LimousineCompanyQuoteDraft(
            totalInclVatCents: 1,
            currency: 'EUR',
            vatTreatment: 'excl',
          ),
          language: AppLanguage.nl,
        ),
        isEmpty,
      );
    },
  );

  test('submit payload keeps notes in the existing snapshot fields', () {
    final payload = _draft().toWorkerQuote();
    expect(payload['terms']['included_services'], isNotEmpty);
    expect(
      ((payload['terms']['included_services'] as List).first as Map)['label'],
      containsValue(_champagne),
    );
    expect(payload['terms']['mobilisation_disclosure']['en'], 'Vanuit depot');
    expect(
      payload['terms']['customer_obligations']['fr'],
      'Klaarstaan op de ophaallocatie',
    );
    expect(payload['terms']['important_information']['es'], 'Niet roken');
    expect(payload.containsKey('included_services_text'), isFalse);
  });

  testWidgets('editor notes survive Controleer de offerte and send', (
    tester,
  ) async {
    final gateway = _RecordingGateway();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        LimousineExternalQuoteCreatePage(
          gateway: gateway,
          offers: <Map<String, dynamic>>[_offer()],
          vehicles: <VehicleProfile>[_vehicle()],
          placeLookup: _SilentLookup(),
        ),
        size: const Size(800, 2400),
      ),
    );
    await _fillRequiredJourney(tester);
    await tester.scrollUntilVisible(
      find.byKey(kLimousineExternalSubmitKey),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(kLimousineExternalSubmitKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineQuoteEditorPageKey), findsOneWidget);
    await tester.ensureVisible(find.byKey(kLimousineQuoteTotalFieldKey));
    await tester.enterText(find.byKey(kLimousineQuoteTotalFieldKey), '1000');
    await tester.ensureVisible(find.byKey(kLimousineQuoteVatFieldKey));
    await tester.tap(find.byKey(kLimousineQuoteVatFieldKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BTW exclusief').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(kLimousineQuoteIncludedFieldKey));
    await tester.enterText(
      find.byKey(kLimousineQuoteIncludedFieldKey),
      _champagne,
    );
    await tester.enterText(
      find.byKey(kLimousineQuoteMobilisationFieldKey),
      'Vanuit depot',
    );
    await tester.enterText(
      find.byKey(kLimousineQuoteObligationsFieldKey),
      'Klaarstaan op de ophaallocatie',
    );
    await tester.enterText(
      find.byKey(kLimousineQuoteImportantFieldKey),
      'Niet roken',
    );
    await tester.ensureVisible(find.byKey(kLimousineQuoteSubmitKey));
    await tester.tap(find.byKey(kLimousineQuoteSubmitKey));
    await tester.pumpAndSettle();
    expect(find.text('Controleer de offerte'), findsOneWidget);
    expect(find.text('Inbegrepen diensten'), findsWidgets);
    expect(find.text(_champagne), findsWidgets);
    expect(find.text('Mobilisatie'), findsWidgets);
    expect(find.text('Vanuit depot'), findsWidgets);
    expect(find.byKey(kLimousineExternalPreviewIncludedKey), findsOneWidget);
    appLanguageNotifier.value = AppLanguage.en;
    await tester.pumpAndSettle();
    expect(find.text('Included services'), findsWidgets);
    expect(find.text(_champagne), findsWidgets);
    expect(find.text('2 bottles of champagne'), findsNothing);
    await tester.tap(find.byKey(kLimousineExternalPreviewSendKey));
    await tester.pumpAndSettle();
    expect(gateway.createCalls, 1);
    final terms = gateway.lastQuote!['terms'] as Map;
    expect(
      ((terms['included_services'] as List).first as Map)['label']['nl'],
      _champagne,
    );
  });

  testWidgets('empty notes do not render empty sections', (tester) async {
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        LimousineExternalQuoteCreatePage(
          gateway: _RecordingGateway(),
          offers: <Map<String, dynamic>>[_offer()],
          vehicles: <VehicleProfile>[_vehicle()],
          placeLookup: _SilentLookup(),
          quoteDraft: const LimousineCompanyQuoteDraft(
            totalInclVatCents: 100000,
            currency: 'EUR',
            vatTreatment: 'excl',
            vatRate: 0.06,
            expiresAt: '2099-01-01T00:00:00Z',
          ),
        ),
      ),
    );
    await _fillRequiredJourney(tester);
    await tester.scrollUntilVisible(
      find.byKey(kLimousineExternalSubmitKey),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(kLimousineExternalSubmitKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineExternalPreviewIncludedKey), findsNothing);
    expect(find.byKey(kLimousineExternalPreviewMobilisationKey), findsNothing);
    expect(find.byKey(kLimousineExternalPreviewObligationsKey), findsNothing);
    expect(find.byKey(kLimousineExternalPreviewImportantKey), findsNothing);
    expect(find.text('Inbegrepen diensten'), findsNothing);
    expect(find.text('Mobilisatie'), findsNothing);
    expect(find.text('Klantverplichtingen'), findsNothing);
    expect(find.text('Belangrijke informatie'), findsNothing);
  });

  testWidgets('editor seeds persisted notes when editing a draft', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LimousineQuoteEditorPage(
          record: LimousineQuoteRequest.fromJson(<String, dynamic>{
            'quote_request_id': 'limq_seed',
            'state': 'requested',
            'revision': 1,
            'quote': limousineCompanyQuoteDraftEditorSeed(_draft()),
          }),
        ),
      ),
    );
    expect(find.text(_champagne), findsOneWidget);
    expect(find.text('Vanuit depot'), findsOneWidget);
    expect(find.text('Klaarstaan op de ophaallocatie'), findsOneWidget);
    expect(find.text('Niet roken'), findsOneWidget);
  });

  testWidgets('company quote detail shows frozen note text', (tester) async {
    tester.view.physicalSize = const Size(430, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final record = _quotedRecord();
    await tester.pumpWidget(
      _app(
        LimousineQuoteDetailPage(
          quoteRequestId: record.quoteRequestId,
          initial: record,
          gateway: _InboxGateway(record),
        ),
        size: const Size(430, 2200),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(_champagne, skipOffstage: false), findsWidgets);
    expect(find.text('Inbegrepen diensten', skipOffstage: false), findsWidgets);
    expect(find.text('Vanuit depot', skipOffstage: false), findsWidgets);
  });

  testWidgets('accepted customer quote shows the same free text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final request = _quotedRecord(state: 'accepted');
    final controller = LimousineAcceptedBookingController(
      handoff: const LimousineAcceptedQuoteHandoff(
        acceptanceReference: 'limacc1.test',
        quoteRequestId: 'limq_notes',
        quoteRevision: 3,
        termsRevision: 1,
        totalInclVatCents: 106000,
        currency: 'EUR',
        offerId: 'off_quote',
        publicPartnerId: 'company:t1:c1',
        from: 'Gent',
        to: 'Ronse',
        scheduledPickupIso: '2026-10-01T16:00:00Z',
      ),
      draft: const LimousineQuoteCreateDraft(from: 'Gent', to: 'Ronse'),
      request: request,
      entryEnabled: true,
      gateway: _NoopBookGateway(),
      customerOverride: const LimousineAcceptedBookingCustomer(
        sessionToken: 'sess',
        customerId: 'cust',
        name: 'Ada',
        phone: '+32470000000',
        email: 'ada@example.com',
      ),
      initialPaymentCapability: const BookingPaymentCapability(
        paymentOwnerMode: 'manual_only',
        paymentDemoMode: false,
        mollieConnected: false,
        publicPaymentOptions: <String>[PaymentMethodIds.inVehicleCard],
        countryCode: 'BE',
      ),
      isApplePaymentPlatform: false,
    );
    await tester.pumpWidget(
      _app(
        LimousineAcceptedBookingPage(
          controller: controller,
          entryEnabled: true,
        ),
        size: const Size(430, 2200),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(_champagne, skipOffstage: false), findsWidgets);
    expect(find.text('Inbegrepen diensten', skipOffstage: false), findsWidgets);
    expect(find.text('2 bottles of champagne'), findsNothing);
    controller.dispose();
  });
}
