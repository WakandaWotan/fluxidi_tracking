// P3L — accepted booking completion, resume isolation, and theme contrast.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_vault.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_request_history.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_status_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/payment/booking_billing_identity.dart';
import 'package:fluxidi_tracking/payment/booking_payment_options.dart';
import 'package:fluxidi_tracking/payment/payment_booking_selection.dart';
import 'package:fluxidi_tracking/payment/payment_method_catalog.dart';

const String _acceptRef = 'limacc1.dGVzdGl2MTIz.dGVzdGNpcGhlcnRleHQxMjM';
const String _statusRef = 'limqs1.dGVzdGl2MTIz.dGVzdGNpcGhlcnRleHQxMjM';

const BookingPaymentCapability _qrCapable = BookingPaymentCapability(
  paymentOwnerMode: 'manual_only',
  paymentDemoMode: false,
  mollieConnected: false,
  qrTransferAvailable: true,
  publicPaymentOptions: <String>[
    PaymentMethodIds.qrCode,
    PaymentMethodIds.inVehicleCard,
  ],
  countryCode: 'BE',
);

const BookingBillingIdentity _buyer = BookingBillingIdentity(
  legalName: 'Acme Events BV',
  vatNumber: 'BE0123456789',
  street: 'Kerkstraat 12',
  postalCode: '2000',
  city: 'Antwerpen',
  country: 'BE',
  contactEmail: 'facturen@acme.example',
);

LimousineAcceptedQuoteHandoff _handoff({
  String partnerId = 'company:t1:c1',
  String quoteRequestId = 'limq_1',
}) {
  return LimousineAcceptedQuoteHandoff(
    acceptanceReference: _acceptRef,
    quoteRequestId: quoteRequestId,
    quoteRevision: 3,
    termsRevision: 3,
    totalInclVatCents: 60000,
    currency: 'EUR',
    offerId: 'off_1',
    publicPartnerId: partnerId,
    from: 'Gent',
    to: 'Brussel',
    scheduledPickupIso: '2026-08-31T06:00:00Z',
  );
}

LimousineQuoteCreateDraft _draft({String partnerId = 'company:t1:c1'}) {
  return LimousineQuoteCreateDraft(
    publicPartnerId: partnerId,
    offerId: 'off_1',
    journeyType: 'point_to_point',
    from: 'Gent',
    to: 'Brussel',
    scheduledPickupIso: '2026-08-31T06:00:00Z',
    pax: 8,
    bags: 2,
  );
}

LimousineQuoteRequest _request({
  String id = 'limq_1',
  String partnerId = 'company:t1:c1',
  String state = 'accepted',
}) {
  return LimousineQuoteRequest.fromJson(<String, dynamic>{
    'quote_request_id': id,
    'state': state,
    'revision': 3,
    'offer_id': 'off_1',
    'vehicle_id': 'veh_1',
    'public_partner_id': partnerId,
    'journey_type': 'point_to_point',
    'scheduled_pickup_iso': '2026-08-31T06:00:00Z',
    'pax': 8,
    'bags': 2,
    'quotation_available': true,
    'quotation_revision': 1,
    'quotation_total_incl_vat_cents': 60000,
    'quotation_currency': 'EUR',
    'quotation_sent_at': '2026-08-22T10:00:00Z',
    'quotation_expires_at': '2099-01-01T00:00:00Z',
    'acceptance_allowed': state != 'accepted',
    'quote': <String, dynamic>{
      'total_incl_vat_cents': 60000,
      'currency': 'EUR',
      'vat_treatment': 'incl',
      'quoted_at': '2026-08-22T10:00:00Z',
      'expires_at': '2099-01-01T00:00:00Z',
      'terms_revision': 3,
      'public_text': <String, String>{'nl': 'Vaste prijs', 'en': 'Fixed price'},
      'terms': <String, dynamic>{
        'terms_revision': 3,
        'cancellation_deadline_hours': 24,
        'cancellation_penalty_percent': 20,
        'waiting_time_included_minutes': 60,
        'waiting_time_overage_cents_per_minute': 150,
        'no_show_penalty_percent': 100,
        'overtime_cents_per_hour': 10000,
        'customer_obligations': <String, String>{
          'nl': 'Gelieve op tijd aanwezig te zijn.',
          'en': 'Please arrive on time.',
        },
      },
    },
    'fulfilment': <String, dynamic>{'from': 'Gent', 'to': 'Brussel'},
  });
}

LimousineAcceptedBookingCustomer get _customer =>
    const LimousineAcceptedBookingCustomer(
      sessionToken: 'sess_1',
      customerId: 'cust_1',
      name: 'Ada',
      phone: '+32470000000',
      email: 'ada@example.com',
    );

LimousineAcceptedBookingReview _review() {
  return const LimousineAcceptedBookingReview(
    providerName: 'Coachline',
    offerTitle: 'Party Limo',
    serviceClassId: 'stretch_limousine',
    serviceClassLabel: 'Party limo',
    vehicleSupplied: true,
    journeyType: 'point_to_point',
    from: 'Gent',
    to: 'Brussel',
    stops: <String>[],
    scheduledPickupIso: '2026-08-31T06:00:00Z',
    roundtrip: false,
    returnPickupIso: '',
    pax: 8,
    bags: 2,
    acceptedExtras: <Map<String, dynamic>>[],
    includedServices: <Map<String, dynamic>>[],
    mobilisationDisclosure: <String, String>{},
    totalInclVatCents: 60000,
    currency: 'EUR',
    vatTreatment: 'incl',
    termsRevision: 3,
    terms: <String, dynamic>{},
  );
}

class _BookGateway implements LimousineAcceptedBookingGateway {
  int calls = 0;
  Map<String, dynamic>? lastPayload;
  Object? error;
  LimousineAcceptedBookResult result = const LimousineAcceptedBookResult(
    bookingId: 'B-601',
    publicReference: 'FLX-601',
    raw: <String, dynamic>{
      'ok': true,
      'booking_id': 'B-601',
      'public_reference': 'FLX-601',
    },
  );

  @override
  Future<LimousineAcceptedBookResult> book(Map<String, dynamic> payload) async {
    calls += 1;
    lastPayload = payload;
    final thrown = error;
    if (thrown != null) {
      if (thrown is LimousineAcceptedBookException) throw thrown;
      throw Exception('$thrown');
    }
    return result;
  }
}

class _QuoteGateway with LimousineCustomerQuoteGateway {
  @override
  Future<List<LimousineDiscoveredProvider>> discoverNearby({
    String? postcode,
    double? lat,
    double? lng,
    int radiusKm = 20,
  }) async => const [];

  @override
  Future<LimousineProviderDetail> loadProvider(String partnerId) async {
    throw const LimousineCustomerQuoteException(code: 'unused');
  }

  @override
  Future<LimousineQuoteCreateResult> createRequest(
    LimousineQuoteCreateDraft draft,
  ) async {
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

LimousineAcceptedBookingController _booking({
  required _BookGateway gateway,
  LimousineAcceptedQuoteHandoff? handoff,
  LimousineQuoteCreateDraft? draft,
  LimousineQuoteRequest? request,
  LimousineCustomerQuoteController? quoteController,
}) {
  return LimousineAcceptedBookingController(
    handoff: handoff ?? _handoff(),
    draft: draft ?? _draft(),
    request: request ?? _request(),
    entryEnabled: true,
    quoteController: quoteController,
    gateway: gateway,
    initialPaymentCapability: _qrCapable,
    isApplePaymentPlatform: false,
    customerOverride: _customer,
    customerLoader: () async => _customer,
    persister:
        ({
          required response,
          required requestPayload,
          required customer,
        }) async {},
  );
}

Widget _app(Widget child) {
  return MaterialApp(
    theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('1) accepted quote opens checkout without seller warning', (
    tester,
  ) async {
    final quote = LimousineCustomerQuoteController(gateway: _QuoteGateway())
      ..request = _request()
      ..handoff = _handoff();
    var opened = false;
    await tester.pumpWidget(
      _app(
        LimousineCustomerStatusView(
          controller: quote,
          language: AppLanguage.nl,
          palette: paletteForCustomerTheme(CustomerThemeVariant.premiumLight),
          onOpenBookingReview: () => opened = true,
        ),
      ),
    );
    expect(find.byKey(kLimousineAcceptedBookingOpenReviewKey), findsOneWidget);
    expect(
      find.text(
        kLimousineAcceptedBookingErrors[LimousineAcceptedBookingError
                .unauthorizedScope]!
            .nl,
        skipOffstage: false,
      ),
      findsNothing,
    );
    tester
        .widget<FilledButton>(
          find.byKey(kLimousineAcceptedBookingOpenReviewKey),
        )
        .onPressed!();
    await tester.pump();
    expect(opened, isTrue);
    quote.dispose();
  });

  testWidgets('2) real empty-partner ownership still shows warning', (
    tester,
  ) async {
    final gateway = _BookGateway();
    final controller = _booking(
      gateway: gateway,
      handoff: _handoff(partnerId: ''),
      draft: _draft(partnerId: ''),
      request: _request(partnerId: ''),
    );
    controller.setConfirmationAcknowledged(true);
    controller.selectPaymentMethod(PaymentMethodIds.qrCode);
    expect(await controller.confirmBooking(), isFalse);
    expect(gateway.calls, 0);
    expect(controller.error, LimousineAcceptedBookingError.unauthorizedScope);
    await tester.pumpWidget(
      MaterialApp(
        home: LimousineAcceptedBookingPage(
          controller: controller,
          entryEnabled: true,
        ),
      ),
    );
    expect(
      find.text(
        kLimousineAcceptedBookingErrors[LimousineAcceptedBookingError
                .unauthorizedScope]!
            .en,
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    controller.dispose();
  });

  testWidgets(
    '3-10) QR + billing + confirm submits and surfaces success/error',
    (tester) async {
      final gateway = _BookGateway();
      final quote = LimousineCustomerQuoteController(gateway: _QuoteGateway())
        ..handoff = _handoff()
        ..request = _request();
      final controller = _booking(gateway: gateway, quoteController: quote);
      controller.selectPaymentMethod(PaymentMethodIds.qrCode);
      expect(
        controller.paymentSelection?.paymentMethodId,
        PaymentMethodIds.qrCode,
      );
      expect(controller.paymentSelection?.isManualCollection, isTrue);
      expect(controller.paymentSelection?.isMollieCheckout, isFalse);
      controller.setBillingEnabled(true);
      expect(controller.canConfirmBooking, isFalse);
      controller.updateBillingIdentity(_buyer);
      expect(controller.billingIdentityIncomplete, isFalse);
      controller.setConfirmationAcknowledged(true);
      expect(controller.canConfirmBooking, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: LimousineAcceptedBookingPage(
            controller: controller,
            entryEnabled: true,
          ),
        ),
      );
      expect(find.byKey(kLimousineAcceptedBookingPageKey), findsOneWidget);
      expect(
        find.text(
          kLimousineAcceptedBookingErrors[LimousineAcceptedBookingError
                  .unauthorizedScope]!
              .en,
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(await controller.confirmBooking(), isTrue);
      await tester.pump();
      expect(gateway.calls, 1);
      expect(gateway.lastPayload!['payment_method'], PaymentMethodIds.qrCode);
      expect(gateway.lastPayload!['payment_mode'], 'manual');
      expect(gateway.lastPayload!['public_partner_id'], 'company:t1:c1');
      expect(gateway.lastPayload!.containsKey('total_incl_vat_cents'), isFalse);
      expect(gateway.lastPayload!.containsKey('seller'), isFalse);
      expect(controller.phase, LimousineAcceptedBookingPhase.success);
      expect(find.byKey(kLimousineAcceptedBookingSuccessKey), findsOneWidget);
      expect(find.textContaining('FLX-601'), findsOneWidget);
      expect(quote.handoff, isNull);
      controller.dispose();
      quote.dispose();

      final failing = _booking(
        gateway: _BookGateway()
          ..error = const LimousineAcceptedBookException(code: 'network'),
      );
      failing.selectPaymentMethod(PaymentMethodIds.qrCode);
      failing.setConfirmationAcknowledged(true);
      expect(await failing.confirmBooking(), isFalse);
      expect(failing.phase, LimousineAcceptedBookingPhase.failed);
      expect(failing.error, isNotNull);
      failing.dispose();
    },
  );

  test(
    '11) draft/request partner hydrates payload when handoff partner is empty',
    () {
      expect(
        limousineAcceptedBookPreflightError(
          entryEnabled: true,
          handoff: _handoff(partnerId: ''),
          customer: _customer,
          draft: _draft(),
          request: _request(),
        ),
        isNull,
      );
      final payload = limousineAcceptedBookPayload(
        handoff: _handoff(partnerId: ''),
        draft: _draft(),
        customer: _customer,
        payment: BookingPaymentSelection.fromMethodId(PaymentMethodIds.qrCode),
        request: _request(),
      );
      expect(payload['public_partner_id'], 'company:t1:c1');
    },
  );

  test(
    '12-15) stale limacc1 does not hijack another quote; intended resume still works',
    () async {
      final vault = MemoryLimousineAcceptedBookingVault();
      final repo = LimousineAcceptedBookingResumeRepository(vault: vault);
      await repo.persistAccepted(
        handoff: _handoff(quoteRequestId: 'limq_old'),
        draft: _draft(),
        review: _review(),
        customerId: 'cust_1',
        expiresAt: DateTime.utc(2099, 1, 1),
      );
      final other =
          LimousineCustomerQuoteController(
            gateway: _QuoteGateway(),
            resumeRepository: repo,
            customerIdLoader: () async => 'cust_1',
          )..restorePersistedRequest(
            LimousineCustomerRequestRecord(
              quoteRequestId: 'limq_1',
              statusRef: _statusRef,
              state: 'accepted',
              publicPartnerId: 'company:t1:c1',
              from: 'Gent',
              to: 'Brussel',
              scheduledPickupIso: '2026-08-31T06:00:00Z',
              request: _request(),
            ),
          );
      expect(
        await other.restoreAcceptedResumeForQuote(quoteRequestId: 'limq_1'),
        isNull,
      );
      expect(other.handoff, isNull);
      expect(other.restoredFromSecureResume, isFalse);

      final intended = LimousineCustomerQuoteController(
        gateway: _QuoteGateway(),
        resumeRepository: repo,
        customerIdLoader: () async => 'cust_1',
      );
      expect(
        await intended.restoreAcceptedResumeForQuote(
          quoteRequestId: 'limq_old',
        ),
        isNotNull,
      );
      expect(intended.handoff?.quoteRequestId, 'limq_old');
      expect(intended.restoredFromSecureResume, isTrue);
      other.dispose();
      intended.dispose();
    },
  );

  test('16) new showroom quote page skips leftover resume attach', () {
    final quotePage = File(
      'lib/limousine/limousine_customer_quote_page.dart',
    ).readAsStringSync();
    expect(quotePage.contains('startingNewOffer'), isTrue);
    expect(
      quotePage.contains(
        'if (widget.resumeRepository != null && !startingNewOffer)',
      ),
      isTrue,
    );
    final detail = File(
      'lib/limousine/limousine_customer_requests_page.dart',
    ).readAsStringSync();
    expect(detail.contains('restoreAcceptedResumeForQuote'), isTrue);
    expect(detail.contains('didChangeAppLifecycleState'), isTrue);
    expect(detail.contains('openLimousineAcceptedBookingReview'), isFalse);
  });

  testWidgets(
    '17) customer quote detail light/dark contrast uses palette tokens',
    (tester) async {
      Future<void> pumpTheme(CustomerThemeVariant variant) async {
        final palette = paletteForCustomerTheme(variant);
        final quote = LimousineCustomerQuoteController(gateway: _QuoteGateway())
          ..request = _request(state: 'quoted');
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
            home: Theme(
              data: themeForCustomerPalette(
                ThemeData(brightness: Brightness.dark, useMaterial3: true),
                palette,
              ),
              child: Scaffold(
                backgroundColor: palette.background,
                body: SingleChildScrollView(
                  child: LimousineCustomerStatusView(
                    controller: quote,
                    language: AppLanguage.nl,
                    palette: palette,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final requestLabel = tester.widget<Text>(
          find.text(kLimousineCustomerYourRequest.nl),
        );
        final inherited = DefaultTextStyle.of(
          tester.element(find.text(kLimousineCustomerYourRequest.nl)),
        );
        expect(inherited.style.color, palette.textPrimary);
        expect(
          brandSignatureContrastRatio(
            inherited.style.color ?? palette.textPrimary,
            palette.background,
          ),
          greaterThanOrEqualTo(4.5),
        );
        final price = tester.widget<Text>(
          find.byKey(kLimousineCustomerQuoteTotalKey),
        );
        expect(price.style?.color, palette.textPrimary);
        expect(find.byKey(kLimousineCustomerTermsCardKey), findsOneWidget);
        final termsCard = tester.widget<Card>(
          find.byKey(kLimousineCustomerTermsCardKey),
        );
        expect(termsCard.color, palette.surface);
        final termsTitle = tester.widget<Text>(
          find.text(kLimousineCustomerTermsTitle.nl),
        );
        final termsStyle = DefaultTextStyle.of(
          tester.element(find.text(kLimousineCustomerTermsTitle.nl)),
        );
        expect(termsStyle.style.color, palette.textPrimary);
        expect(
          brandSignatureContrastRatio(
            termsStyle.style.color ?? palette.textPrimary,
            termsCard.color ?? palette.surface,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(termsTitle.data, kLimousineCustomerTermsTitle.nl);
        final accept = tester.widget<FilledButton>(
          find.byKey(kLimousineCustomerAcceptKey),
        );
        expect(accept.onPressed, isNull);
        expect(requestLabel.data, kLimousineCustomerYourRequest.nl);
        quote.dispose();
      }

      await pumpTheme(CustomerThemeVariant.premiumLight);
      await pumpTheme(CustomerThemeVariant.nightGold);
    },
  );

  test('18) chauffeur My Rides light/dark ride-card pairing stays readable', () {
    final light = driverRideCardColors(DriverThemeVariant.lightEmerald);
    final dark = driverRideCardColors(DriverThemeVariant.nightGold);
    expect(light.surface, const Color(0xFFF7FAF8));
    expect(
      brandSignatureContrastRatio(light.foreground, light.surface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      brandSignatureContrastRatio(light.muted, light.surface),
      greaterThanOrEqualTo(3.0),
    );
    expect(
      brandSignatureContrastRatio(dark.foreground, dark.surface),
      greaterThanOrEqualTo(4.5),
    );
    final source = File(
      'lib/main_parts/driver_home_page_state.dart',
    ).readAsStringSync();
    expect(source.contains('_driverRideCardSurfaceGradient'), isTrue);
    expect(source.contains('if (!palette.isDark)'), isTrue);
    expect(
      source.contains(
        'if (isLightEmerald) return _lightEmeraldSurfaceGradient();',
      ),
      isTrue,
    );
    expect(
      source.contains(
        'style: const TextStyle(\n                              color: Colors.white,\n                              fontSize: 15.1,',
      ),
      isFalse,
    );
  });
}
